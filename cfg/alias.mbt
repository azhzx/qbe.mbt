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
pub fn getalias(r : @types.Ref, fn_ : @types.Fn) -> @types.AliasInfo {
  match r {
    @types.RTmp(v) => {
      let a = fn_.tmps[v].alias_info
      if @types.astack(a.kind) {
        // The underlying slot's type reflects escaping.
        let slot = fn_.tmps[a.slot].alias_info
        @types.AliasInfo::{
          kind: slot.kind,
          base: a.base,
          label: a.label,
          offset: a.offset,
          slot: a.slot,
        }
      } else {
        @types.AliasInfo::{
          kind: a.kind,
          base: a.base,
          label: a.label,
          offset: a.offset,
          slot: a.slot,
        }
      }
    }
    @types.RCon(v) => {
      let c = fn_.cons[v]
      if c.kind == @types.CAddr {
        @types.AliasInfo::{
          kind: ASym,
          base: @types.ref_none(),
          label: c.label,
          offset: c.bits.i,
          slot: -1,
        }
      } else {
        @types.AliasInfo::{
          kind: ACon,
          base: @types.ref_none(),
          label: 0,
          offset: c.bits.i,
          slot: -1,
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
  sp : Int,
  q : @types.Ref,
  sq : Int,
  fn_ : @types.Fn,
) -> (AliasResult, Int64) {
  let ap = getalias(p, fn_)
  let aq = getalias(q, fn_)
  let delta = ap.offset - aq.offset
  let ovlap = ap.offset < aq.offset + sq.to_int64() &&
    aq.offset < ap.offset + sp.to_int64()
  if @types.astack(ap.kind) && @types.astack(aq.kind) {
    if @types.req(ap.base, aq.base) && ovlap {
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
    (ap.kind == aq.kind && @types.req(ap.base, aq.base)) {
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
  !@types.astack(a.kind) || fn_.tmps[a.slot].alias_info.kind == @types.AEsc
}

///|
// Mark a reference as escaping (C esc).
fn esc(r : @types.Ref, fn_ : @types.Fn) -> Unit {
  if r.is_tmp() {
    let a = fn_.tmps[r.tmp_val()].alias_info
    if @types.astack(a.kind) {
      fn_.tmps[a.slot].alias_info.kind = @types.AEsc
    }
  }
}

///|
// Fill alias information for all temporaries (C fillalias).
pub fn fillalias(fn_ : @types.Fn) -> Unit {
  for n = 0; n < fn_.rpo.length(); n = n + 1 {
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
      }
    }
    // Instructions
    for ins in b.ins {
      let mut has_to = false
      if !ins.to.is_none() {
        let to = ins.to.tmp_val()
        has_to = true
        if is_alloc(ins.op) {
          fn_.tmps[to].alias_info.kind = @types.ALoc
          fn_.tmps[to].alias_info.slot = to // points to itself
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
        if !@types.is_load(ins.op) {
          esc(ins.arg1, fn_)
        }
        if !@types.is_store(ins.op) {
          esc(ins.arg2, fn_)
        }
      }
    }
    // Jump argument
    esc(b.jmp.arg, fn_)
  }
}

///|
// Whether the op is an alloc (Oalloc..Oalloc1 in QBE)
fn is_alloc(op : @types.Op) -> Bool {
  op == @types.Alloc4 || op == @types.Alloc8 || op == @types.Alloc16
}
