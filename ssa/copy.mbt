///|
// Copy propagation and elimination - corresponds to copy.c in QBE

///|
// Copy-of function
fn copyof(r : @types.Ref, cp : Array[@types.Ref]) -> @types.Ref {
  if r.is_tmp() {
    cp[r.tmp_val()]
  } else {
    r
  }
}

///|
// Update the copy chain for temp r
fn update(
  r : @types.Ref,
  rcp : @types.Ref,
  cp : Array[@types.Ref],
  wl : Array[Int],
  visited : Array[Bool],
) -> Unit {
  let rv = r.tmp_val()
  if !cp[rv].eq(rcp) {
    cp[rv] = rcp
    if !visited[rv] {
      visited[rv] = true
      wl.push(rv)
    }
  }
}

///|
// Whether instruction i is a copy (extensions that copy)
fn iscopy(i : @types.Ins, r : @types.Ref, fn_ : @types.Fn) -> Bool {
  if i.op == @types.Copy {
    return true
  }
  if !i.op.is_ext() || !r.is_tmp() {
    return false
  }
  if (i.op == @types.Extsw || i.op == @types.Extuw) && i.cls == @types.Kw {
    return true
  }
  let t = fn_.tmps[r.tmp_val()]
  if i.cls == @types.Kl && t.cls == @types.Kw {
    return false
  }
  // width-based extension copy check
  let b = extcpy_width(t.width.code())
  let w = i.op.ext_width_idx()
  (b & (1 << w)) != 0
}

///|
// Widths that each width's extension copies can be (C extcpy table)
fn extcpy_width(w : Int) -> Int {
  match w {
    0 => 0 // WFull
    1 => (1 << 1) | (1 << 3) | (1 << 5) // Wsb: Wsb|Wsh|Wsw
    2 => (1 << 2) | (1 << 4) | (1 << 6) // Wub: Wub|Wuh|Wuw
    3 => (1 << 3) | (1 << 5) // Wsh: Wsh|Wsw
    4 => (1 << 4) | (1 << 6) // Wuh: Wuh|Wuw
    5 => 1 << 5 // Wsw
    6 => 1 << 6 // Wuw
    _ => 0
  }
}

///|
fn visitphi(
  p : @types.Phi,
  cp : Array[@types.Ref],
  wl : Array[Int],
  visited : Array[Bool],
) -> Unit {
  let mut r = @types.Ref::none()
  for a in p.args {
    let r1 = copyof(a.value, cp)
    if r1.is_none() || r1.eq(p.to) {
      continue
    }
    if r.is_none() || r.eq(r1) {
      r = r1
    } else {
      r = p.to
      break
    }
  }
  update(p.to, r, cp, wl, visited)
}

///|
fn visitins(
  i : @types.Ins,
  cp : Array[@types.Ref],
  wl : Array[Int],
  visited : Array[Bool],
  fn_ : @types.Fn,
) -> Unit {
  let r = copyof(i.arg1, cp)
  if iscopy(i, r, fn_) {
    update(i.to, r, cp, wl, visited)
  } else if !i.to.is_none() {
    update(i.to, i.to, cp, wl, visited)
  }
}

///|
// Copy propagation and elimination (C copy).
// Returns the -dC debug text (empty when print_dbg is false).
pub fn copy(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let nt = fn_.ntmp()
  let cp : Array[@types.Ref] = Array::make(nt, @types.Ref::none())
  let wl : Array[Int] = Array::new()
  let visited : Array[Bool] = Array::make(nt, false)
  // Initial visit
  for id in fn_.def_order {
    let b = fn_.blks[id]
    for p in b.phi {
      visitphi(p, cp, wl, visited)
    }
    for i in b.ins {
      visitins(i, cp, wl, visited, fn_)
    }
  }
  // Worklist processing
  let mut wi = 0
  while wi < wl.length() {
    let t = wl[wi]
    wi = wi + 1
    let tmp = fn_.tmps[t]
    for u in tmp.uses {
      match u.kind {
        @types.UPhi => {
          let p = fn_.blks[u.blk_id].phi[u.ins_idx]
          visitphi(p, cp, wl, visited)
        }
        @types.UIns => {
          let i = fn_.blks[u.blk_id].ins[u.ins_idx]
          visitins(i, cp, wl, visited, fn_)
        }
        @types.UJmp => ()
        _ => ()
      }
    }
  }
  // Apply substitutions
  for id in fn_.def_order {
    let b = fn_.blks[id]
    // Remove phi nodes that became copies of themselves
    let mut pi = 0
    while pi < b.phi.length() {
      let p = b.phi[pi]
      let r = cp[p.to.tmp_val()]
      if !r.eq(p.to) {
        let _ = b.phi.remove(pi)
        continue
      }
      for ai in 0..<p.args.length() {
        let a = p.args[ai]
        let rr = copyof(a.value, cp)
        b.phi[pi].args[ai] = @types.PhiArg::{ value: rr, blk_id: a.blk_id, }
      }
      pi = pi + 1
    }
    // Instructions
    for ii in 0..<b.ins.length() {
      let i = b.ins[ii]
      let r = copyof(i.to, cp)
      if !r.eq(i.to) {
        b.ins[ii] = @types.Ins::new_void(
          @types.Nop,
          @types.Kw,
          @types.Ref::none(),
          @types.Ref::none(),
        )
        continue
      }
      // Substitute args
      let a1 = copyof(i.arg1, cp)
      let a2 = copyof(i.arg2, cp)
      b.ins[ii] = @types.Ins::new(i.op, i.cls, i.to, a1, a2)
    }
    // Jump argument
    let ja = copyof(b.jmp.arg, cp)
    b.jmp.arg = ja
  }
  // Debug output (-dC)
  if print_dbg {
    let sb = StringBuilder::new()
    sb.write_string("\n> Copy information:")
    for t in @types.Tmp0..<nt {
      if cp[t].eq(@types.Ref::none()) {
        sb.write_char('\n')
        let name = fn_.tmps[t].name
        let pad = " ".repeat(
          if 10 > name.length() {
            10 - name.length()
          } else {
            0
          },
        )
        sb.write_string(pad)
        sb.write_string(name)
        sb.write_string(" not seen!")
      } else if !cp[t].eq(@types.Ref::tmp(t)) {
        sb.write_char('\n')
        let name = fn_.tmps[t].name
        let pad = " ".repeat(
          if 10 > name.length() {
            10 - name.length()
          } else {
            0
          },
        )
        sb.write_string(pad)
        sb.write_string(name)
        sb.write_string(" copy of ")
        printref_str(cp[t], fn_, interner, sb, all_typs)
      }
    }
    sb.write_string("\n\n> After copy elimination:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}

///|
// Print a ref to a string builder (local helper for -dC output)
fn printref_str(
  r : @types.Ref,
  fn_ : @types.Fn,
  interner : @util.Interner,
  sb : StringBuilder,
  all_typs : Array[@types.Typ],
) -> Unit {
  @parser.printref(r, fn_, interner, sb, all_typs)
}
