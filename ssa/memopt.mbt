///|
// Memory optimization - corresponds to mem.c in QBE.
// Requires: filluse already called (maintains per-tmp use lists).
// A Use stores (blk_id, ins_idx) so the affected instruction may live in any
// block, not just the start block where the alloc resides.

///|
// Map a load op to its corresponding extension op (loadsb->extsb, ...)
fn load_to_ext(op : @types.Op) -> @types.Op {
  let i = @types.op_index(op)
  let base = @types.op_index(@types.Extsb) + i - @types.op_index(@types.Loadsb)
  @types.op_from_index(base)
}

///|
// The instruction that uses the alloc, located by the use record.
fn use_ins(fn_ : @types.Fn, u : @types.Use) -> @types.Ins {
  fn_.blks[u.blk_id].ins[u.ins_idx]
}

///|
// Promote uniform stack slots to temporaries (C memopt)
pub fn memopt(fn_ : @types.Fn) -> Unit raise {
  let b = fn_.blks[fn_.start_id]
  for ii in 0..<b.ins.length() {
    let i = b.ins[ii]
    if i.op != @types.Alloc4 && i.op != @types.Alloc8 && i.op != @types.Alloc16 {
      continue
    }
    if !i.to.is_tmp() {
      raise @util.QbeError::Ice("alloc to not a tmp")
    }
    let alloc_t = i.to.tmp_val()
    if fn_.tmps[alloc_t].ndef != 1 {
      continue
    }
    let mut k = -1
    let mut s = -1
    let mut usable = true
    for u in fn_.tmps[alloc_t].uses {
      if u.kind != @types.UIns {
        usable = false
        break
      }
      let l = use_ins(fn_, u)
      if @types.is_load(l.op) {
        if s == -1 || s == loadsz(l) {
          s = loadsz(l)
          continue
        }
        usable = false
        break
      }
      if @types.is_store(l.op) {
        if @types.req(i.to, l.arg2) &&
          !@types.req(i.to, l.arg1) &&
          (s == -1 || s == storesz(l)) &&
          (k == -1 || k == @types.op_info(l.op).a0[0]) {
          s = storesz(l)
          k = @types.op_info(l.op).a0[0]
          continue
        }
        usable = false
        break
      }
      usable = false
      break
    }
    if !usable {
      continue
    }
    // Get rid of the alloc and replace uses
    b.ins[ii] = @types.Ins::new_void(
      @types.Nop,
      @types.Kw,
      @types.ref_none(),
      @types.ref_none(),
    )
    fn_.tmps[alloc_t].ndef = fn_.tmps[alloc_t].ndef - 1
    for u in fn_.tmps[alloc_t].uses {
      let l = use_ins(fn_, u)
      if @types.is_store(l.op) {
        // store value, addr -> copy addr, value
        let ins = fn_.blks[u.blk_id].ins[u.ins_idx]
        ins.cls = @types.class_from_code(k)
        ins.op = @types.Copy
        ins.to = l.arg2
        ins.arg2 = @types.ref_none()
        fn_.tmps[alloc_t].nuse = fn_.tmps[alloc_t].nuse - 1
        fn_.tmps[alloc_t].ndef = fn_.tmps[alloc_t].ndef + 1
      } else {
        if k == -1 {
          raise @util.QbeError::Ice("slot is read but never stored to")
        }
        // Turn loads into copies/extensions so they can be eliminated later.
        // C mem.c: Oloadsw/Oloaduw fall through to Oload when k != Kl.
        let ins = fn_.blks[u.blk_id].ins[u.ins_idx]
        match l.op {
          @types.Loadsw | @types.Loaduw | @types.Load =>
            if (l.op == @types.Loadsw || l.op == @types.Loaduw) && k == 1 {
              // k == Kl: extend (loadsw -> extsw, loaduw -> extuw)
              ins.op = load_to_ext(l.op)
            } else if k / 2 != kcode(l.cls) / 2 {
              ins.op = @types.Cast
            } else {
              ins.op = @types.Copy
            }
          _ =>
            // loadsb -> extsb, loadub -> extub, loadsh -> extsh, loaduh -> extuh
            ins.op = load_to_ext(l.op)
        }
      }
    }
  }
}

///|
// kcode is defined in use.mbt (package-level shared)
