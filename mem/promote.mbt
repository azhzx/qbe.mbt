///|
// Promote uniform stack slots to temporaries (C mem.c promote).
// Requires: fillrpo/fillpreds and filluse already run, as in C main.c.
// Returns the -dM debug text (empty when print_dbg is false).
pub fn promote(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  typs : Array[@types.Typ],
) -> String {
  let b = fn_.blks[fn_.start_id]
  for ii in 0..<b.ins.length() {
    let i = b.ins[ii]
    if !(i.op == @types.Alloc4 ||
      i.op == @types.Alloc8 ||
      i.op == @types.Alloc16) {
      continue
    }
    if !i.to.is_tmp() {
      abort("alloc to not a tmp")
    }
    let alloc_t = i.to.tmp_val()
    if fn_.tmps[alloc_t].ndef != 1 {
      continue
    }
    let mut k = -1
    let mut s = -1
    let mut skip = false
    for u in fn_.tmps[alloc_t].uses {
      if u.kind != @types.UIns {
        skip = true
        break
      }
      let l = fn_.blks[u.blk_id].ins[u.ins_idx]
      if l.op.is_load() {
        if s == -1 || s == loadsz(l) {
          s = loadsz(l)
          continue
        }
        skip = true
        break
      }
      if l.op.is_store() {
        if i.to.eq(l.arg2) &&
          !i.to.eq(l.arg1) &&
          (s == -1 || s == storesz(l)) &&
          (k == -1 || k == @types.op_info(l.op).a0[0]) {
          s = storesz(l)
          k = @types.op_info(l.op).a0[0]
          continue
        }
        skip = true
        break
      }
      skip = true
      break
    }
    if skip {
      continue
    }
    // Get rid of the alloc and replace its uses.
    i.op = @types.Nop
    i.cls = @types.Kw
    i.to = @types.Ref::none()
    i.arg1 = @types.Ref::none()
    i.arg2 = @types.Ref::none()
    let t = fn_.tmps[alloc_t]
    t.ndef = t.ndef - 1
    for u in t.uses {
      let l = fn_.blks[u.blk_id].ins[u.ins_idx]
      if l.op.is_store() {
        l.cls = @types.Class::from_code(k)
        l.op = @types.Copy
        l.to = l.arg2
        l.arg2 = @types.Ref::none()
        t.nuse = t.nuse - 1
        t.ndef = t.ndef + 1
      } else {
        if k == -1 {
          abort(
            "slot %\{fn_.tmps[l.arg1.tmp_val()].name} is read but never stored to",
          )
        }
        match l.op {
          @types.Loadsw | @types.Loaduw =>
            if k == 1 {
              l.op = load_to_ext(l.op)
            } else if k / 2 != l.cls.code() / 2 {
              l.op = @types.Cast
            } else {
              l.op = @types.Copy
            }
          @types.Load =>
            if k / 2 != l.cls.code() / 2 {
              l.op = @types.Cast
            } else {
              l.op = @types.Copy
            }
          _ => l.op = load_to_ext(l.op)
        }
      }
    }
  }
  if print_dbg {
    "\n> After slot promotion:\n" + @parser.printfn(fn_, interner, typs) + "\n"
  } else {
    ""
  }
}
