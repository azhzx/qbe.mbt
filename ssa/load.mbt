///|
// Load elimination - corresponds to load.c in QBE.
// Requires: fillrpo, fillpreds, ssa (phiins/renblk), fillalias already run.
// Redundantly loaded or stored values are replaced by copies/extensions via a
// recursive `def` that searches backward for a definition of the requested
// byte slice, recording new instructions/phis in an insertion log that is
// applied (sorted) at the end.

///|
priv enum LocType {
  LRoot // right above the original load
  LLoad // inserting a load is allowed
  LNoLoad // only scalar operations allowed
} derive(Eq)

///|
priv struct Loc {
  mut kind : LocType
  mut off : Int32
  mut blk : Int32 // block id
}

///|
priv struct Slice {
  r : @types.Ref
  mut off : Int32 // C SlotL.off: byte offset into the slice's base
  mut sz : Int32
  cls : @types.Class
}

///|
priv struct Insert {
  isphi : Bool
  num : Int32
  bid : Int32
  rpo_id : Int32 // RPO index of bid (the key the reference sorts inserts on)
  off : Int32
  ins : @types.Ins
  phi_m : Slice
  phi_p : @types.Phi
}

///|
priv struct LoadState {
  fn_ : @types.Fn
  mut inum : Int32
  ilog : Array[Insert]
  mut nlog : Int32
}

///|
// MASK(w) in C: (BIT(8*w-1)*2-1); all low 8*w bits set (works for w == 8).
fn mask_of(w : Int32) -> UInt64 {
  let one : UInt64 = 1
  (one << (8 * w - 1)) * 2 - 1
}

///|
// Append an instruction to the insertion log (C iins).
fn iins(
  st : LoadState,
  cls : @types.Class,
  op : @types.Op,
  a0 : @types.Ref,
  a1 : @types.Ref,
  l : Loc,
) -> @types.Ref {
  let to = st.fn_.new_tmp("ld", cls)
  let ins = @types.Ins::new(op, cls, @types.Ref::tmp(to), a0, a1)
  st.ilog.push(Insert::{
    isphi: false,
    num: st.inum,
    bid: l.blk,
    rpo_id: st.fn_.blks[l.blk].rpo_id,
    off: l.off,
    ins,
    phi_m: Slice::{ r: @types.Ref::none(), off: 0, sz: 0, cls: @types.Kw, },
    phi_p: @types.Phi::new(@types.Ref::none(), @types.Kw),
  })
  st.inum = st.inum + 1
  st.nlog = st.nlog + 1
  @types.Ref::tmp(to)
}

///|
// Cast a ref to a class, inserting a cast instruction if needed (C cast).
fn cast(
  st : LoadState,
  r : @types.Ref,
  cls : @types.Class,
  l : Loc,
) -> @types.Ref {
  if !r.is_tmp() {
    return r
  }
  let cls0 = st.fn_.tmps[r.tmp_val()].cls
  if cls0 == cls || (cls == @types.Kw && cls0 == @types.Kl) {
    return r
  }
  let mut r0 = r
  if cls0.wide() < cls.wide() {
    // Widening: a float source reinterprets to a word first, then zero-extends
    // to a long, and a double target reinterprets again.
    if cls0 == @types.Ks {
      r0 = iins(st, @types.Kw, @types.Cast, r0, @types.Ref::none(), l)
    }
    r0 = iins(st, @types.Kl, @types.Extuw, r0, @types.Ref::none(), l)
    if cls == @types.Kd {
      r0 = iins(st, @types.Kd, @types.Cast, r0, @types.Ref::none(), l)
    }
  } else {
    // Same width or narrowing.
    if cls0 == @types.Kd && cls != @types.Kl {
      r0 = iins(st, @types.Kl, @types.Cast, r0, @types.Ref::none(), l)
    }
    if cls0 != @types.Kd || cls != @types.Kw {
      r0 = iins(st, cls, @types.Cast, r0, @types.Ref::none(), l)
    }
  }
  r0
}

///|
// Apply a mask to a ref, inserting an and instruction (C mask).
fn mask(
  st : LoadState,
  r : @types.Ref,
  cls : @types.Class,
  msk : UInt64,
  l : Loc,
) -> @types.Ref {
  let r = cast(st, r, cls, l)
  let c = st.fn_.get_con(msk.reinterpret_as_int64())
  iins(st, cls, @types.And, r, @types.Ref::con(c), l)
}

///|
// Emit a load of the slice masked by msk (C load).
fn load(st : LoadState, sl : Slice, msk : UInt64, l : Loc) -> @types.Ref {
  let ld = match sl.sz {
    1 => @types.Loadub
    2 => @types.Loaduh
    4 => @types.Loaduw
    _ => @types.Load
  }
  let all = msk == mask_of(sl.sz)
  let cls = if all { sl.cls } else if sl.sz > 4 { @types.Kl } else { @types.Kw }
  let mut r = sl.r
  // sl.r might not be live here, but its alias base ref will be.
  if r.is_tmp() {
    let a = st.fn_.tmps[r.tmp_val()].alias_info
    match a.kind {
      @types.ALoc | @types.AEsc | @types.AUnk => {
        r = a.base
        if a.offset != 0 {
          let r1 = st.fn_.get_con(a.offset)
          r = iins(st, @types.Kl, @types.Add, r, @types.Ref::con(r1), l)
        }
      }
      @types.ACon | @types.ASym => {
        let c = st.fn_.add_con(@types.Con::{
          kind: @types.CAddr,
          label: a.label,
          bits: @types.ConBits::{ i: a.offset, d: 0.0, s: 0.0, },
          flt: 0,
          is_local: false,
        })
        r = @types.Ref::con(c)
      }
      _ => ()
    }
  }
  r = iins(st, cls, ld, r, @types.Ref::none(), l)
  if !all {
    r = mask(st, r, cls, msk, l)
  }
  r
}

///|
// Whether writing to ref r kills the slice sl (C killsl).
fn killsl(st : LoadState, r : @types.Ref, sl : Slice) -> Bool {
  if !sl.r.is_tmp() {
    return false
  }
  let a = st.fn_.tmps[sl.r.tmp_val()].alias_info
  match a.kind {
    @types.ALoc | @types.AEsc | @types.AUnk => a.base.eq(r)
    @types.ACon | @types.ASym => false
    _ => false
  }
}

///|
// Undo the current def attempt and either report failure (ref_none) or,
// when a load is allowed at il, emit a fresh load (C goto Load).
fn load_abort(
  st : LoadState,
  sl : Slice,
  msk : UInt64,
  il : Loc,
  oldl : Int32,
  oldt : Int32,
) -> @types.Ref {
  st.fn_.tmps.truncate(oldt)
  st.ilog.truncate(oldl)
  st.nlog = oldl
  if il.kind != LocType::LLoad {
    @types.Ref::none()
  } else {
    load(st, sl, msk, il)
  }
}

///|
// Whether block b dominates block c (C cfg.c dom).
fn dominates(fn_ : @types.Fn, b : Int32, c : Int32) -> Bool {
  let mut c = c
  while c >= 0 && fn_.blks[c].rpo_id > fn_.blks[b].rpo_id {
    c = fn_.blks[c].idom
  }
  c == b
}

///|
// Returns a ref containing the contents of the slice, with all bits zeroed in
// the result where the mask has zeroes (C def). Returns ref_none on failure.
fn def(
  st : LoadState,
  sl : Slice,
  msk : UInt64,
  b : Int32,
  i : Int32,
  il : Loc,
) -> @types.Ref {
  // C load.c def(): "invariants: -1- b dominates il->blk; so we can use
  // temporaries of b in il->blk". The reference asserts it; this port used to
  // walk on, and the resulting insert could be placed in a block that does not
  // dominate its use (hiredis read.c, ffc_digit_comp).
  if !dominates(st.fn_, b, il.blk) {
    abort(
      "loadopt: block @\{st.fn_.blks[b].name} does not dominate " +
      "@\{st.fn_.blks[il.blk].name} (def invariant 1)",
    )
  }
  let oldl = st.nlog
  let oldt = st.fn_.tmps.length()
  let b_ins = st.fn_.blks[b].ins
  let mut ii = if i < 0 { b_ins.length() } else { i }
  let cls = if sl.sz > 4 { @types.Kl } else { @types.Kw }
  let msks = mask_of(sl.sz)

  while ii > 0 {
    ii = ii - 1
    let ins = b_ins[ii]
    if killsl(st, ins.to, sl) ||
      (ins.op == @types.Call && @cfg.escapes(sl.r, st.fn_)) {
      return load_abort(st, sl, msk, il, oldl, oldt)
    }
    let mut ld = false
    let mut sz = 0
    let mut r1 = @types.Ref::none()
    let mut r = @types.Ref::none()
    let mut is_blit = false
    let mut blit_src = @types.Ref::none()
    if ins.op.is_load() {
      ld = true
      sz = loadsz(ins)
      r1 = ins.arg1
      r = ins.to
    } else if ins.op.is_store() {
      sz = storesz(ins)
      r1 = ins.arg2
      r = ins.arg1
    } else if ins.op == @types.Blit1 {
      // A blit is a pair: blit0 holds the two addresses, blit1 the size
      // (C load.c def's Oblit1 case). It stores into the second operand the
      // bytes found at the first one, so it is scanned as a store there.
      is_blit = true
      let s = ins.arg1.rint_val()
      sz = if s < 0 { -s } else { s }
      if ii == 0 {
        continue
      }
      let b0 = b_ins[ii - 1]
      blit_src = b0.arg1
      r1 = b0.arg2
      ii = ii - 1
    } else {
      continue
    }
    let (res, off64) = @cfg.check_alias(sl.r, sl.off, sl.sz, r1, sz, st.fn_)
    match res {
      @cfg.MayAlias =>
        if ld {
          continue
        } else {
          return load_abort(st, sl, msk, il, oldl, oldt)
        }
      @cfg.NoAlias => continue
      @cfg.MustAlias => {
        let mut off = off64.to_int()
        let mut msk1 : UInt64 = 0
        let mut op : @types.Op = @types.Oxxx
        // For a blit the aliasing range is the source slice: narrow it to the
        // part that reaches the address we are looking for.
        let mut sl1 = sl
        if is_blit {
          sl1 = Slice::{ r: blit_src, off: 0, sz: sl.sz, cls: sl.cls, }
          if off >= 0 {
            sl1.off = off
            sz = sz - off
            off = 0
          } else {
            sl1.off = 0
            sl1.sz = sl1.sz + off
          }
          if sz > sl1.sz {
            sz = sl1.sz
          }
          sl1.sz = sz
        }
        if off < 0 {
          off = -off
          msk1 = (mask_of(sz) << (8 * off)) & msks
          op = @types.Shl
        } else {
          msk1 = (mask_of(sz) >> (8 * off)) & msks
          op = @types.Shr
        }
        if (msk1 & msk) == 0 {
          continue
        }
        if is_blit {
          // Fetch what the blit wrote: read the source bytes.
          r = def(st, sl1, mask_of(sz), b, ii, il)
          if r.is_none() {
            return load_abort(st, sl, msk, il, oldl, oldt)
          }
        }
        let mut r = r
        if off != 0 {
          let cls1 = if op == @types.Shr && off + sl.sz > 4 {
            @types.Kl
          } else {
            cls
          }
          r = cast(st, r, cls1, il)
          let rc = st.fn_.get_con((8 * off).to_int64())
          r = iins(st, cls1, op, r, @types.Ref::con(rc), il)
        }
        if (msk1 & msk) != msk1 || off + sz < sl.sz {
          r = mask(st, r, cls, msk1 & msk, il)
        }
        if (msk & (mask_of(8) ^ msk1)) != 0 {
          let r2 = def(st, sl, msk & (mask_of(8) ^ msk1), b, ii, il)
          if r2.is_none() {
            return load_abort(st, sl, msk, il, oldl, oldt)
          }
          r = iins(st, cls, @types.Or, r, r2, il)
        }
        if msk == msks {
          r = cast(st, r, sl.cls, il)
        }
        return r
      }
    }
  }

  // Reuse an existing phi for this slice in this block
  for ist in st.ilog {
    if ist.isphi &&
      ist.bid == b &&
      ist.phi_m.r.eq(sl.r) &&
      ist.phi_m.off == sl.off &&
      ist.phi_m.sz == sl.sz {
      let mut r = ist.phi_p.to
      if msk != msks {
        r = mask(st, r, cls, msk, il)
      } else {
        r = cast(st, r, sl.cls, il)
      }
      return r
    }
  }

  // A phi in this block defining the slot makes backward search unsafe
  for p in st.fn_.blks[b].phi {
    if killsl(st, p.to, sl) {
      return load_abort(st, sl, msk, il, oldl, oldt)
    }
  }

  let npred = st.fn_.blks[b].npred
  if npred == 0 {
    return load_abort(st, sl, msk, il, oldl, oldt)
  }
  if npred == 1 {
    let bp = st.fn_.blks[b].pred[0]
    // C load.c: "l = *il" is a value copy. Loc is a struct here, so a plain
    // alias would let the l.kind write below clobber the caller's loc.
    let l = Loc::{ kind: il.kind, off: il.off, blk: il.blk, }
    if st.fn_.blks[bp].jmp.s2 >= 0 {
      l.kind = LocType::LNoLoad
    }
    let r1 = def(st, sl, msk, bp, -1, l)
    if r1.is_none() {
      return load_abort(st, sl, msk, il, oldl, oldt)
    }
    return r1
  }

  // Merge point: create a phi over the predecessor definitions
  let r = st.fn_.new_tmp("ld", sl.cls)
  let p = @types.Phi::new(@types.Ref::tmp(r), sl.cls)
  st.ilog.push(Insert::{
    isphi: true,
    num: st.inum,
    bid: b,
    rpo_id: st.fn_.blks[b].rpo_id,
    off: 0,
    ins: @types.Ins::new_void(
      @types.Nop,
      @types.Kw,
      @types.Ref::none(),
      @types.Ref::none(),
    ),
    phi_m: sl,
    phi_p: p,
  })
  st.inum = st.inum + 1
  st.nlog = st.nlog + 1
  for np in 0..<npred {
    let bp = st.fn_.blks[b].pred[np]
    let l = Loc::{ kind: il.kind, off: il.off, blk: il.blk, }
    if st.fn_.blks[bp].jmp.s2 < 0 &&
      il.kind != LocType::LNoLoad &&
      st.fn_.blks[bp].loop_depth < st.fn_.blks[il.blk].loop_depth {
      l.kind = LocType::LLoad
    } else {
      l.kind = LocType::LNoLoad
    }
    l.blk = bp
    l.off = st.fn_.blks[bp].ins.length()
    let r1 = def(st, sl, msks, bp, -1, l)
    if r1.is_none() {
      return load_abort(st, sl, msk, il, oldl, oldt)
    }
    p.args.push(@types.PhiArg::{ value: r1, blk_id: bp, })
  }
  let mut r = @types.Ref::tmp(r)
  if msk != msks {
    r = mask(st, r, cls, msk, il)
  }
  r
}

///|
// Comparator for the insertion log (C icmp).
// Phis in the same block compare equal (return 0), like the reference.
fn icmp(a : Insert, b : Insert) -> Int32 {
  // The reference sorts by block->id, which fillrpo sets to the RPO index.
  // MoonBit's block id is the definition order, so key on the RPO index.
  if a.rpo_id != b.rpo_id {
    return a.rpo_id - b.rpo_id
  }
  if a.isphi && b.isphi {
    // The reference's qsort preserves the insertion order of equal-key phis
    // (macOS stable qsort); `num` is a unique monotone insertion counter.
    return a.num - b.num
  }
  if a.isphi {
    return -1
  }
  if b.isphi {
    return 1
  }
  if a.off != b.off {
    return a.off - b.off
  }
  a.num - b.num
}

///|
// Redundancy elimination of loads (C loadopt).
// Returns the -dM debug text (empty when print_dbg is false).
pub fn loadopt(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let st = LoadState::{ fn_, inum: 0, ilog: [], nlog: 0, }
  // First pass: for each load, try to replace it
  for b_id in fn_.def_order {
    for ii in 0..<fn_.blks[b_id].ins.length() {
      let ins = fn_.blks[b_id].ins[ii]
      if !ins.op.is_load() {
        continue
      }
      let sz = loadsz(ins)
      let sl = Slice::{ r: ins.arg1, off: 0, sz, cls: ins.cls, }
      let l = Loc::{ kind: LocType::LRoot, off: ii, blk: b_id, }
      fn_.blks[b_id].ins[ii].arg2 = def(st, sl, mask_of(sz), b_id, ii, l)
    }
  }
  // Sort the insertion log and append a sentinel
  @util.qsort_c(st.ilog, icmp)
  st.ilog.push(Insert::{
    isphi: false,
    num: 0,
    bid: fn_.nblk(),
    rpo_id: fn_.nblk(),
    off: 0,
    ins: @types.Ins::new_void(
      @types.Nop,
      @types.Kw,
      @types.Ref::none(),
      @types.Ref::none(),
    ),
    phi_m: Slice::{ r: @types.Ref::none(), off: 0, sz: 0, cls: @types.Kw, },
    phi_p: @types.Phi::new(@types.Ref::none(), @types.Kw),
  })
  let mut ist = 0
  for n in 0..<fn_.rpo.length() {
    let b_id = fn_.rpo[n]
    // Prepend new phi nodes to the block
    while st.ilog[ist].rpo_id == n && st.ilog[ist].isphi {
      fn_.blks[b_id].phi.insert(0, st.ilog[ist].phi_p)
      ist = ist + 1
    }
    let mut ni = 0
    let ib : Array[@types.Ins] = []
    while true {
      if st.ilog[ist].rpo_id == n && st.ilog[ist].off == ni {
        ib.push(st.ilog[ist].ins)
        ist = ist + 1
      } else {
        if ni == fn_.blks[b_id].ins.length() {
          break
        }
        let ins = fn_.blks[b_id].ins[ni]
        ni = ni + 1
        if ins.op.is_load() && !ins.arg2.is_none() {
          // The load was replaced: turn it into a copy/extension
          let ext = @types.Op::from_index(
            @types.Extsb.index() + ins.op.index() - @types.Loadsb.index(),
          )
          match ins.op {
            @types.Loadsb | @types.Loadub | @types.Loadsh | @types.Loaduh =>
              ins.op = ext
            @types.Loadsw | @types.Loaduw =>
              if ins.cls == @types.Kl {
                ins.op = ext
              } else {
                ins.op = @types.Copy
              }
            @types.Load => ins.op = @types.Copy
            _ => ()
          }
          ins.arg1 = ins.arg2
          ins.arg2 = @types.Ref::none()
        }
        ib.push(ins)
      }
    }
    // Replace the block's instructions
    fn_.blks[b_id].ins.clear()
    for x in ib {
      fn_.blks[b_id].ins.push(x)
    }
  }
  if print_dbg {
    let sb = StringBuilder::StringBuilder()
    sb.write_string("\n> After load elimination:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}
