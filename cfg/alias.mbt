///|
// Alias analysis - corresponds to alias.c in QBE.
// Requires: fillrpo already computed.

///|
// Result of the alias() comparison
pub enum AliasResult {
  MustAlias
  MayAlias
  NoAlias
}

///|
// Fetch the alias info of a reference, following stack slots up to the
// underlying alloc's current type (C getalias).
fn getalias(r : @types.Ref, fn_ : @types.Fn) -> @types.AliasInfo {
  match r {
    @types.RTmp(v) => {
      let a = fn_.tmps[v].alias_info
      if a.kind.astack() {
        // The underlying slot's type reflects escaping.
        let slot = fn_.tmps[a.slot].alias_info
        @types.AliasInfo::{
          kind: slot.kind,
          base: a.base,
          label: a.label,
          offset: a.offset,
          slot: a.slot,
          sz: a.sz,
          m: a.m,
        }
      } else {
        @types.AliasInfo::{
          kind: a.kind,
          base: a.base,
          label: a.label,
          offset: a.offset,
          slot: a.slot,
          sz: a.sz,
          m: a.m,
        }
      }
    }
    @types.RCon(v) => {
      let c = fn_.cons[v]
      if c.kind == @types.CAddr {
        @types.AliasInfo::{
          kind: ASym,
          base: @types.Ref::none(),
          label: c.label,
          offset: c.bits.i,
          slot: -1,
          sz: -1,
          m: 0UL,
        }
      } else {
        @types.AliasInfo::{
          kind: ACon,
          base: @types.Ref::none(),
          label: 0,
          offset: c.bits.i,
          slot: -1,
          sz: -1,
          m: 0UL,
        }
      }
    }
    _ => @types.AliasInfo::default()
  }
}

///|
// Compare two memory references for aliasing (C alias).
// Returns the result and the offset delta (p.offset - q.offset).
pub fn check_alias(
  p : @types.Ref,
  poff : Int32,
  sp : Int32,
  q : @types.Ref,
  sq : Int32,
  fn_ : @types.Fn,
) -> (AliasResult, Int64) {
  let ap = getalias(p, fn_)
  let aq = getalias(q, fn_)
  ap.offset = ap.offset + poff.to_int64()
  let delta = ap.offset - aq.offset
  let ovlap = ap.offset < aq.offset + sq.to_int64() &&
    aq.offset < ap.offset + sp.to_int64()
  if ap.kind.astack() && aq.kind.astack() {
    if ap.base.eq(aq.base) && ovlap {
      return (MustAlias, delta)
    }
    return (NoAlias, delta)
  }
  if ap.kind == @types.ASym && aq.kind == @types.ASym {
    if ap.label != aq.label {
      return (MayAlias, delta)
    }
    if ovlap {
      return (MustAlias, delta)
    }
    return (NoAlias, delta)
  }
  if (ap.kind == @types.ACon && aq.kind == @types.ACon) ||
    (ap.kind == aq.kind && ap.base.eq(aq.base)) {
    if ovlap {
      return (MustAlias, delta)
    }
    return (NoAlias, delta)
  }
  if ap.kind == @types.AUnk && aq.kind != @types.ALoc {
    return (MayAlias, delta)
  }
  if aq.kind == @types.AUnk && ap.kind != @types.ALoc {
    return (MayAlias, delta)
  }
  (NoAlias, delta)
}

///|
// Whether a reference may escape the function (C escapes).
pub fn escapes(r : @types.Ref, fn_ : @types.Fn) -> Bool {
  if !r.is_tmp() {
    return true
  }
  let a = fn_.tmps[r.tmp_val()].alias_info
  !a.kind.astack() || fn_.tmps[a.slot].alias_info.kind == @types.AEsc
}

///|
// Mark a reference as escaping (C esc).
fn esc(r : @types.Ref, fn_ : @types.Fn) -> Unit {
  if r.is_tmp() {
    let a = fn_.tmps[r.tmp_val()].alias_info
    if a.kind.astack() {
      fn_.tmps[a.slot].alias_info.kind = @types.AEsc
    }
  }
}

///|
// C alias.c store(): record in the slot mask which bytes something writes
// through a pointer that aliases it.
fn store_mask(r : @types.Ref, sz : Int32, fn_ : @types.Fn) -> Unit {
  if r.is_tmp() {
    let a = fn_.tmps[r.tmp_val()].alias_info
    if a.slot >= 0 {
      let off = a.offset
      let m = if sz >= 64 || off < 0L || off >= 64L {
        0xFFFFFFFFFFFFFFFFUL
      } else {
        ((1UL << sz.to_int64().to_int()) - 1UL) << off.to_int()
      }
      fn_.tmps[a.slot].alias_info.m = fn_.tmps[a.slot].alias_info.m | m
    }
  }
}

///|
// Fill alias information for all temporaries (C fillalias).
pub fn fillalias(fn_ : @types.Fn) -> Unit {
  for n in 0..<fn_.rpo.length() {
    let b = fn_.blks[fn_.rpo[n]]
    // Phi nodes
    for p in b.phi {
      let to = p.to.tmp_val()
      fn_.tmps[to].alias_info = @types.AliasInfo::{
        kind: AUnk,
        base: p.to,
        label: 0,
        offset: 0,
        slot: -1,
        sz: -1,
        m: 0UL,
      }
    }
    // Instructions (indexed: a blit consumes its blit1 as well)
    let mut ii = 0
    while ii < b.ins.length() {
      let ins = b.ins[ii]
      let mut has_to = false
      if !ins.to.is_none() {
        let to = ins.to.tmp_val()
        has_to = true
        if is_alloc(ins.op) {
          fn_.tmps[to].alias_info.kind = @types.ALoc
          fn_.tmps[to].alias_info.slot = to // points to itself
          // C alias.c: the slot size comes from the alloc's constant argument.
          fn_.tmps[to].alias_info.sz = -1
          if ins.arg1.is_con() {
            let c = fn_.cons[ins.arg1.con_val()]
            if c.kind == @types.CBits {
              let x = c.bits.i
              if x >= 0L && x <= 64L {
                fn_.tmps[to].alias_info.sz = x.to_int()
              }
            }
          }
        } else {
          fn_.tmps[to].alias_info.kind = @types.AUnk
          fn_.tmps[to].alias_info.slot = -1
        }
        fn_.tmps[to].alias_info.base = ins.to
        fn_.tmps[to].alias_info.offset = 0
        if ins.op == @types.Copy {
          fn_.tmps[to].alias_info = getalias(ins.arg1, fn_)
        }
        if ins.op == @types.Add {
          let a0 = getalias(ins.arg1, fn_)
          let a1 = getalias(ins.arg2, fn_)
          if a0.kind == @types.ACon {
            fn_.tmps[to].alias_info = a1
            fn_.tmps[to].alias_info.offset = fn_.tmps[to].alias_info.offset +
              a0.offset
          } else if a1.kind == @types.ACon {
            fn_.tmps[to].alias_info = a0
            fn_.tmps[to].alias_info.offset = fn_.tmps[to].alias_info.offset +
              a1.offset
          }
        }
      }
      let cur = if has_to {
        fn_.tmps[ins.to.tmp_val()].alias_info.kind
      } else {
        @types.AUnk
      }
      if !has_to || cur == @types.AUnk {
        // C alias.c skips a blit here: it writes through arg2 and reads arg1,
        // so neither address escapes.
        if ins.op != @types.Blit0 {
          if !ins.op.is_load() {
            esc(ins.arg1, fn_)
          }
          if !ins.op.is_store() {
            if ins.op != @types.Argc {
              esc(ins.arg2, fn_)
            }
          }
        }
      }
      // C alias.c: a blit writes its size through the destination.
      if ins.op == @types.Blit0 {
        let b1 = b.ins[ii + 1]
        let raw = b1.arg1.rint_val()
        let sz = if raw < 0 { -raw } else { raw }
        store_mask(ins.arg2, sz, fn_)
        ii = ii + 1
      }
      if ins.op.is_store() {
        store_mask(ins.arg2, @types.op_storesz(ins), fn_)
      }
      ii = ii + 1
    }
    // C alias.c: a Jretc returns a memory copy, not an escape.
    if b.jmp.kind != @types.Jretc {
      esc(b.jmp.arg, fn_)
    }
  }
  // C alias.c: phi arguments escape.
  for blk in fn_.blks {
    for p in blk.phi {
      for a in p.args {
        esc(a.value, fn_)
      }
    }
  }
}

///|
// Whether the op is an alloc (Oalloc..Oalloc1 in QBE)
fn is_alloc(op : @types.Op) -> Bool {
  op == @types.Alloc4 || op == @types.Alloc8 || op == @types.Alloc16
}
