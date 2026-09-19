///|
// Slot coalescing (C mem.c coalesce).
// Requires: fillrpo/fillpreds already run, as in C main.c.
// Returns the -dM debug text (empty when print_dbg is false).

///|
// [a, b) with 0 <= a (C struct Range).
priv struct Range {
  mut a : Int
  mut b : Int
}

///|
fn range_new(a : Int, b : Int) -> Range {
  Range::{ a, b, }
}

///|
// C rin.
fn rin(r : Range, n : Int) -> Bool {
  r.a <= n && n < r.b
}

///|
// C rovlap.
fn rovlap(r0 : Range, r1 : Range) -> Bool {
  r0.b != 0 && r1.b != 0 && r0.a < r1.b && r1.a < r0.b
}

///|
// C radd.
fn radd(r : Range, n : Int) -> Unit {
  if r.b == 0 {
    r.a = n
    r.b = n + 1
  } else if n < r.a {
    r.a = n
  } else if n >= r.b {
    r.b = n + 1
  }
}

///|
// A pending store (C struct Store).
priv struct StoreRec {
  ip : Int
  blk : Int
  idx : Int
}

///|
// A stack slot (C struct Slot).
priv struct Slot {
  t : Int
  sz : Int
  m : UInt64
  mut l : UInt64
  r : Range
  mut s : Int
  st : Array[StoreRec]
  mut nst : Int
}

///|
// Left shift that drops every bit when the offset leaves the 64-bit word
// (the C reference relies on host shift semantics here).
fn shl_bits(x : UInt64, off : Int64) -> UInt64 {
  if off < 0L || off >= 64L {
    0UL
  } else {
    x << off.to_int()
  }
}

///|
// C slot(): resolve a memory ref to a slot index and offset.
fn slot_of(
  r : @types.Ref,
  fn_ : @types.Fn,
  al : Array[AliasL],
) -> (Int, Int64)? {
  let a = local_getalias(r, fn_, al)
  if a.kind != @types.ALoc {
    return None
  }
  if a.base < 0 || a.base >= fn_.ntmp() {
    return None
  }
  let t = fn_.tmps[a.base]
  if t.visit < 0 {
    return None
  }
  Some((t.visit, a.offset))
}

///|
// C load(): OR the loaded bits into the slot's live mask.
fn slot_load(
  fn_ : @types.Fn,
  al : Array[AliasL],
  sl : Array[Slot],
  r : @types.Ref,
  x : UInt64,
  ip : Int,
) -> Unit {
  match slot_of(r, fn_, al) {
    Some((idx, off)) => {
      let s = sl[idx]
      s.l = s.l | shl_bits(x, off)
      s.l = s.l & s.m
      if s.l != 0UL {
        radd(s.r, ip)
      }
    }
    None => ()
  }
}

///|
// C store(): either kill live bits or record a dead store candidate.
fn slot_store(
  fn_ : @types.Fn,
  al : Array[AliasL],
  sl : Array[Slot],
  r : @types.Ref,
  x : UInt64,
  ip : Int,
  blk : Int,
  idx : Int,
) -> Unit {
  match slot_of(r, fn_, al) {
    Some((si, off)) => {
      let s = sl[si]
      if s.l != 0UL {
        radd(s.r, ip)
        s.l = s.l & (shl_bits(x, off) ^ 0xFFFFFFFFFFFFFFFFUL)
      } else {
        s.st.push(StoreRec::{ ip, blk, idx, })
        s.nst = s.nst + 1
      }
    }
    None => ()
  }
}

///|
// C scmp.
fn scmp(a : Slot, b : Slot) -> Int {
  if a.sz != b.sz {
    return b.sz - a.sz
  }
  a.r.a - b.r.a
}

///|
// Stable insertion sort with the C scmp ordering (qsort replacement).
fn sort_slots(a : Array[Slot], n : Int) -> Unit {
  for i in 1..<n {
    let key = a[i]
    let mut j = i
    while j > 0 && scmp(a[j - 1], key) > 0 {
      a[j] = a[j - 1]
      j = j - 1
    }
    a[j] = key
  }
}

///|
fn set_nop(i : @types.Ins) -> Unit {
  i.op = @types.Nop
  i.cls = @types.Kw
  i.to = @types.Ref::none()
  i.arg1 = @types.Ref::none()
  i.arg2 = @types.Ref::none()
}

///|
fn copy_ins_fields(src : @types.Ins, dst : @types.Ins) -> Unit {
  dst.op = src.op
  dst.cls = src.cls
  dst.to = src.to
  dst.arg1 = src.arg1
  dst.arg2 = src.arg2
}

///|
// C "\tfuse (% 3db) [" size field (space flag, minimum width 3).
fn fmt_space3(n : Int) -> String {
  let body = " " + n.to_string()
  if body.length() >= 3 {
    body
  } else {
    " ".repeat(3 - body.length()) + body
  }
}

///|
// Minimize stack usage by coalescing slots (C mem.c coalesce).
pub fn coalesce(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  typs : Array[@types.Typ],
) -> String {
  let sb = StringBuilder::StringBuilder()
  // Local alias analysis (C fillalias runs right before coalesce).
  let al : Array[AliasL] = []
  for _ in 0..<fn_.ntmp() {
    al.push(alias_default())
  }
  local_fillalias(fn_, al)
  // types.Tmp has no def pointer, so record where each tmp is defined.
  let def_blk : Array[Int] = []
  let def_idx : Array[Int] = []
  let def_pos : Array[Int] = []
  for _ in 0..<fn_.ntmp() {
    def_blk.push(-1)
    def_idx.push(-1)
    def_pos.push(-1)
  }
  let mut pos = 0
  for id in fn_.def_order {
    let b = fn_.blks[id]
    for p in b.phi {
      if p.to.is_tmp() {
        let to = p.to.tmp_val()
        def_blk[to] = id
        def_idx[to] = -1
        def_pos[to] = pos
      }
      pos = pos + 1
    }
    for ii in 0..<b.ins.length() {
      let ins = b.ins[ii]
      if ins.to.is_tmp() {
        let to = ins.to.tmp_val()
        def_blk[to] = id
        def_idx[to] = ii
        def_pos[to] = pos
      }
      pos = pos + 1
    }
  }
  // Collect the slots.
  let sl : Array[Slot] = []
  let mut nsl = 0
  for n in @types.Tmp0..<fn_.ntmp() {
    fn_.tmps[n].visit = -1
  }
  for n in @types.Tmp0..<fn_.ntmp() {
    let a = al[n]
    if a.kind == @types.ALoc &&
      a.slot == n &&
      def_blk[n] == fn_.start_id &&
      a.sz != -1 {
      fn_.tmps[n].visit = nsl
      sl.push(Slot::{
        t: n,
        sz: a.sz,
        m: a.m,
        l: 0UL,
        r: range_new(0, 0),
        s: -1,
        st: [],
        nst: 0,
      })
      nsl = nsl + 1
    }
  }
  // One-pass liveness analysis (C loopiter(fn, maxrpo)).
  let max_loop : Array[Int] = []
  for _ in 0..<fn_.blks.length() {
    max_loop.push(-1)
  }
  @cfg.loopiter(fn_, fn(hd, blk) {
    if max_loop[hd] < fn_.blks[blk].rpo_id {
      max_loop[hd] = fn_.blks[blk].rpo_id
    }
  })
  let nblk = fn_.rpo.length()
  let br_a : Array[Int] = []
  let br_b : Array[Int] = []
  for _ in 0..<nblk {
    br_a.push(0)
    br_b.push(0)
  }
  let mut ip = 2147483646
  let mut n = nblk
  while n > 0 {
    n = n - 1
    let b = fn_.blks[fn_.rpo[n]]
    let succ1 = b.jmp.s1
    let succ2 = b.jmp.s2
    br_b[n] = ip
    ip = ip - 1
    let succs : Array[Int] = []
    if succ1 >= 0 {
      succs.push(succ1)
      if succ2 >= 0 {
        succs.push(succ2)
      }
    }
    for si in 0..<nsl {
      let s = sl[si]
      s.l = 0UL
      for m_id in succs {
        let m = fn_.blks[m_id].rpo_id
        if m > n && rin(s.r, br_a[m]) {
          s.l = s.m
          radd(s.r, ip)
        }
      }
    }
    if b.jmp.kind == @types.Jretc {
      ip = ip - 1
      slot_load(fn_, al, sl, b.jmp.arg, 0xFFFFFFFFFFFFFFFFUL, ip)
    }
    let mut ii = b.ins.length()
    while ii > 0 {
      ii = ii - 1
      let i = b.ins[ii]
      if i.op == @types.Argc {
        ip = ip - 1
        slot_load(fn_, al, sl, i.arg2, 0xFFFFFFFFFFFFFFFFUL, ip)
      }
      if i.op.is_load() {
        let x = (1UL << loadsz(i)) - 1UL
        ip = ip - 1
        slot_load(fn_, al, sl, i.arg1, x, ip)
      }
      if i.op.is_store() {
        let x = (1UL << storesz(i)) - 1UL
        slot_store(fn_, al, sl, i.arg2, x, ip, b.id, ii)
        ip = ip - 1
      }
    }
    for si in 0..<nsl {
      let s = sl[si]
      if s.l != 0UL {
        radd(s.r, ip)
        let lp = max_loop[b.id]
        if lp != -1 {
          radd(s.r, br_b[lp] - 1)
        }
      }
    }
    br_a[n] = ip
  }
  // Kill dead stores.
  for s in sl {
    for k in 0..<s.nst {
      let st = s.st[k]
      if !rin(s.r, st.ip) {
        set_nop(fn_.blks[st.blk].ins[st.idx])
      }
    }
  }
  // Kill slots with an empty live range.
  let mut total = 0
  let mut freed = 0
  let stk : Array[Int] = []
  let mut nn = 0
  let mut w = 0
  for si in 0..<nsl {
    let s = sl[si]
    total = total + s.sz
    if s.r.b == 0 {
      stk.push(s.t)
      nn = nn + 1
      freed = freed + s.sz
    } else {
      sl[w] = s
      w = w + 1
    }
  }
  nsl = w
  if print_dbg {
    sb.write_string("\n> Slot coalescing:\n")
    if nn > 0 {
      sb.write_string("\tkill [")
      for m in 0..<nn {
        sb.write_string(" %\{fn_.tmps[stk[m]].name}")
      }
      sb.write_string(" ]\n")
    }
  }
  while nn > 0 {
    nn = nn - 1
    let t = fn_.tmps[stk[nn]]
    let db = def_blk[stk[nn]]
    let di = def_idx[stk[nn]]
    let tdef = fn_.blks[db].ins[di]
    if tdef.op.is_load() {
      tdef.op = @types.Copy
      // The MoonBit port represents C's UNDEF by the zero constant (see
      // ssa/ssa.mbt getstk), so use the interned zero here too.
      tdef.arg1 = @types.Ref::con(fn_.get_con(0))
      continue
    }
    set_nop(tdef)
    for u in t.uses {
      if u.kind == @types.UJmp {
        let b2 = fn_.blks[u.blk_id]
        b2.jmp.kind = @types.Jret0
        b2.jmp.arg = @types.Ref::none()
        continue
      }
      let ui = fn_.blks[u.blk_id].ins[u.ins_idx]
      if !ui.to.is_none() {
        if ui.to.is_tmp() {
          nn = nn + 1
          let v = ui.to.tmp_val()
          if stk.length() < nn {
            stk.push(v)
          } else {
            stk[nn - 1] = v
          }
        }
      } else if ui.op.is_arg() {
        // C CON_Z: the zero constant is interned at index 0 in this port.
        ui.arg2 = @types.Ref::con(fn_.get_con(0))
      } else {
        set_nop(ui)
      }
    }
  }
  // Fuse slots by decreasing size.
  sort_slots(sl, nsl)
  let mut fused = 0
  for n0 in 0..<nsl {
    if sl[n0].s != -1 {
      continue
    }
    sl[n0].s = n0
    let r = range_new(sl[n0].r.a, sl[n0].r.b)
    for s in (n0 + 1)..<nsl {
      if sl[s].s != -1 || sl[s].r.b == 0 {
        continue
      }
      let mut skip = false
      if rovlap(r, sl[s].r) {
        let mut m = n0
        while m < s {
          if sl[m].s == n0 && rovlap(sl[m].r, sl[s].r) {
            skip = true
            break
          }
          m = m + 1
        }
      }
      if skip {
        continue
      }
      radd(r, sl[s].r.a)
      radd(r, sl[s].r.b - 1)
      sl[s].s = n0
      fused = fused + sl[s].sz
    }
  }
  // Substitute fused slots.
  let cur_blk : Array[Int] = []
  let cur_idx : Array[Int] = []
  for t in 0..<fn_.ntmp() {
    cur_blk.push(def_blk[t])
    cur_idx.push(def_idx[t])
  }
  for si in 0..<nsl {
    let s = sl[si]
    let t = fn_.tmps[s.t]
    t.visit = si
    if s.s == si {
      continue
    }
    if cur_idx[s.t] >= 0 {
      set_nop(fn_.blks[cur_blk[s.t]].ins[cur_idx[s.t]])
    }
    let ts_t = sl[s.s].t
    let swap = if cur_blk[s.t] == cur_blk[ts_t] {
      cur_idx[s.t] < cur_idx[ts_t]
    } else {
      def_pos[s.t] < def_pos[ts_t]
    }
    if cur_idx[s.t] >= 0 && cur_idx[ts_t] >= 0 && swap {
      let src = fn_.blks[cur_blk[ts_t]].ins[cur_idx[ts_t]]
      let dst = fn_.blks[cur_blk[s.t]].ins[cur_idx[s.t]]
      copy_ins_fields(src, dst)
      set_nop(src)
      cur_blk[ts_t] = cur_blk[s.t]
      cur_idx[ts_t] = cur_idx[s.t]
    }
    for u in t.uses {
      if u.kind == @types.UJmp {
        fn_.blks[u.blk_id].jmp.arg = @types.Ref::tmp(ts_t)
        continue
      }
      let ui = fn_.blks[u.blk_id].ins[u.ins_idx]
      if ui.arg1.eq(@types.Ref::tmp(s.t)) {
        ui.arg1 = @types.Ref::tmp(ts_t)
      }
      if ui.arg2.eq(@types.Ref::tmp(s.t)) {
        ui.arg2 = @types.Ref::tmp(ts_t)
      }
    }
  }
  if print_dbg {
    for s0 in 0..<nsl {
      if sl[s0].s != s0 {
        continue
      }
      sb.write_string("\tfuse (")
      sb.write_string(fmt_space3(sl[s0].sz))
      sb.write_string("b) [")
      for s in s0..<nsl {
        if sl[s].s != s0 {
          continue
        }
        sb.write_string(" %\{fn_.tmps[sl[s].t].name}")
        if sl[s].r.b != 0 {
          sb.write_string("[")
          sb.write_string((sl[s].r.a - ip).to_string())
          sb.write_string(",")
          sb.write_string((sl[s].r.b - ip).to_string())
          sb.write_string(")")
        } else {
          sb.write_string("{}")
        }
      }
      sb.write_string(" ]\n")
    }
    sb.write_string("\tsums ")
    sb.write_string(freed.to_string())
    sb.write_string("/")
    sb.write_string(fused.to_string())
    sb.write_string("/")
    sb.write_string(total.to_string())
    sb.write_string(" (killed/fused/total)\n\n")
    sb.write_string(@parser.printfn(fn_, interner, typs))
    sb.write_string("\n")
  }
  sb.to_string()
}
