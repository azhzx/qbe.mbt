///|
// If-conversion - corresponds to ifopt.c in QBE.
//
// Eliminates if-then[-else] graphlets with select instructions.  Requires
// reverse post-order, predecessor lists and uses; it breaks the cfg's
// predecessor information and uses, so callers must rebuild them.
//
// Missing shared API worked around locally:
//   * @types.Op has no Sel0/Sel1 constructors and the enum is closed, so the
//     select pseudo-instructions produced by convert() are stored under the
//     placeholder ops sel0_op/sel1_op.  dump_fn() renders them back as
//     "sel0"/"sel1" so the -dK dump still matches the C reference.
//   * @types.OpInfo has no pinned field; pinned() reimplements the ops.h
//     F(...) pinned column.
//   * @types.TargetCfg has no cansel capability flag, so nothing tells a
//     caller whether the active target supports select (the C reference runs
//     ifconvert only when T.cansel is set).

///|
// MaxIns in ifopt.c.
let max_ins : Int = 2

///|
// MaxPhis in ifopt.c.
let max_phis : Int = 2

///|
// QBE's Osel0 (internal).
let sel0_op : @types.Op = @types.Sel0

///|
// QBE's Osel1 (internal).
let sel1_op : @types.Op = @types.Sel1

///|
// Return the block iteration order used by the C reference's block link list.
// Falls back to every block when the caller has not built def_order yet.
fn block_order(fn_ : @types.Fn) -> Array[Int] {
  if fn_.def_order.length() > 0 {
    return fn_.def_order
  }
  let a : Array[Int] = []
  for i in 0..<fn_.blks.length() {
    a.push(i)
  }
  a
}

///|
// C gcm.c isdivwl: integer division/remainder is pinned.
fn is_div_wl(i : @types.Ins) -> Bool {
  match i.op {
    @types.Div | @types.Rem | @types.Udiv | @types.Urem => i.cls.base() == 0
    _ => false
  }
}

///|
// C gcm.c pinned().  @types.OpInfo has no pinned field, so the flags are
// reimplemented here from the pinned column of ops.h.
fn pinned(i : @types.Ins) -> Bool {
  match i.op {
    @types.Storeb
    | @types.Storeh
    | @types.Storew
    | @types.Storel
    | @types.Stores
    | @types.Stored
    | @types.Loadsb
    | @types.Loadub
    | @types.Loadsh
    | @types.Loaduh
    | @types.Loadsw
    | @types.Loaduw
    | @types.Load
    | @types.Alloc4
    | @types.Alloc8
    | @types.Alloc16
    | @types.Vaarg
    | @types.Vastart
    | @types.Par
    | @types.Parc
    | @types.Pare
    | @types.Arg
    | @types.Argc
    | @types.Arge
    | @types.Call
    | @types.Vacall => true
    _ => is_div_wl(i)
  }
}

///|
// C ifopt.c okbranch: a branch block is small and unpinned.
fn okbranch(b : @types.Blk) -> Bool {
  let mut n = 0
  for i in b.ins {
    // The reference skips Odbgloc here.
    if i.op == @types.Dbgloc {
      continue
    }
    if pinned(i) {
      return false
    }
    if i.op != @types.Nop {
      n = n + 1
    }
  }
  n <= max_ins
}

///|
// C ifopt.c okjoin: the join block has at most two integer phis.
fn okjoin(b : @types.Blk) -> Bool {
  let mut n = 0
  for p in b.phi {
    if p.cls.base() != 0 {
      return false
    }
    n = n + 1
  }
  n <= max_phis
}

///|
// C ifopt.c ifgraph.  Returns (ok, thenb, elseb, joinb).
fn ifgraph(fn_ : @types.Fn, ifb : Int) -> (Bool, Int, Int, Int) {
  let nb = fn_.blks[ifb]
  if nb.jmp.kind != @types.Jjnz {
    return (false, -1, -1, -1)
  }
  let mut s1 = nb.jmp.s1
  let mut s2 = nb.jmp.s2
  if s1 < 0 || s2 < 0 || s1 >= fn_.blks.length() || s2 >= fn_.blks.length() {
    return (false, -1, -1, -1)
  }
  // The reference swaps both the blocks and the output pointers; swapped
  // records the pointer swap so the then/else results are assigned correctly.
  let mut swapped = false
  if fn_.blks[s1].id > fn_.blks[s2].id {
    let t = s1
    s1 = s2
    s2 = t
    swapped = true
  }
  if s1 == s2 {
    return (false, -1, -1, -1)
  }
  if fn_.blks[s1].jmp.kind != @types.Jjmp || fn_.blks[s1].npred != 1 {
    return (false, -1, -1, -1)
  }
  let mut thenb = -1
  let mut elseb = -1
  let mut joinb = -1
  if fn_.blks[s1].jmp.s1 == s2 {
    // if-then / if-else
    if fn_.blks[s2].npred != 2 {
      return (false, -1, -1, -1)
    }
    thenb = s1
    elseb = ifb
    joinb = s2
  } else {
    if fn_.blks[s2].jmp.kind != @types.Jjmp || fn_.blks[s2].npred != 1 {
      return (false, -1, -1, -1)
    }
    let join = fn_.blks[s1].jmp.s1
    if join != fn_.blks[s2].jmp.s1 || fn_.blks[join].npred != 2 {
      return (false, -1, -1, -1)
    }
    thenb = s1
    elseb = s2
    joinb = join
  }
  if swapped {
    (true, elseb, thenb, joinb)
  } else {
    (true, thenb, elseb, joinb)
  }
}

///|
// C ifopt.c okgraph.
fn okgraph(
  fn_ : @types.Fn,
  ifb : Int,
  thenb : Int,
  elseb : Int,
  joinb : Int,
) -> Bool {
  if fn_.blks[joinb].npred != 2 || !okjoin(fn_.blks[joinb]) {
    return false
  }
  if thenb != ifb && !okbranch(fn_.blks[thenb]) {
    return false
  }
  if elseb != ifb && !okbranch(fn_.blks[elseb]) {
    return false
  }
  true
}

///|
// C util.c phiarg: value of a phi coming from block b.
fn phiarg(p : @types.Phi, b : Int) -> @types.Ref {
  for a in p.args {
    if a.blk_id == b {
      return a.value
    }
  }
  abort("phiarg: block not found")
}

///|
// C util.c addins: append an instruction unless it is a nop.
fn addins(vins : Array[@types.Ins], i : @types.Ins) -> Unit {
  if i.op == @types.Nop {
    return
  }
  vins.push(i)
}

///|
// C util.c addbins: append every instruction of a block.
fn addbins(vins : Array[@types.Ins], b : @types.Blk) -> Unit {
  for i in b.ins {
    addins(vins, i)
  }
}

///|
// C ifopt.c convert: rebuild the if block with select instructions.
fn convert(
  fn_ : @types.Fn,
  ifb : Int,
  thenb : Int,
  elseb : Int,
  joinb : Int,
) -> Unit {
  let vins : Array[@types.Ins] = []
  addbins(vins, fn_.blks[ifb])
  if thenb != ifb {
    addbins(vins, fn_.blks[thenb])
  }
  if elseb != ifb {
    addbins(vins, fn_.blks[elseb])
  }
  // assert(fn_.blks[joinb].npred == 2)
  if fn_.blks[joinb].phi.length() > 0 {
    let sel = @types.Ins::new_void(
      sel0_op,
      @types.Kw,
      fn_.blks[ifb].jmp.arg,
      @types.Ref::none(),
    )
    addins(vins, sel)
  }
  for p in fn_.blks[joinb].phi {
    let sel = @types.Ins::new(
      sel1_op,
      p.cls,
      p.to,
      phiarg(p, thenb),
      phiarg(p, elseb),
    )
    addins(vins, sel)
  }
  // idup(ifb, vins, n)
  let b = fn_.blks[ifb]
  b.ins.clear()
  for i in vins {
    b.ins.push(i)
  }
  b.jmp.kind = @types.Jjmp
  b.jmp.arg = @types.Ref::none()
  b.jmp.s1 = joinb
  b.jmp.s2 = -1
  let j = fn_.blks[joinb]
  j.npred = 1
  j.pred.clear()
  j.pred.push(ifb)
  j.phi.clear()
}

///|
// C parse.c ktoc (also used by parser/print.mbt).
fn class_char(k : @types.Class) -> Char {
  match k {
    @types.Kw => 'w'
    @types.Kl => 'l'
    @types.Ks => 's'
    @types.Kd => 'd'
    @types.Kx => '?'
  }
}

///|
// C parse.c jtoa.
fn jump_name(j : @types.JumpKind) -> String {
  match j {
    @types.Jret0 => "ret0"
    @types.Jretw => "retw"
    @types.Jretl => "retl"
    @types.Jrets => "rets"
    @types.Jretd => "retd"
    @types.Jretc => "retc"
    @types.Jjmp => "jmp"
    @types.Jjnz => "jnz"
    @types.Jjfieq => "jfieq"
    @types.Jjfine => "jfine"
    @types.Jjfisge => "jfisge"
    @types.Jjfisgt => "jfisgt"
    @types.Jjfisle => "jfisle"
    @types.Jjfislt => "jfislt"
    @types.Jjfiuge => "jfiuge"
    @types.Jjfiugt => "jfiugt"
    @types.Jjfiule => "jfiule"
    @types.Jjfiult => "jfiult"
    @types.Jjffeq => "jffeq"
    @types.Jjffge => "jffge"
    @types.Jjffgt => "jffgt"
    @types.Jjffle => "jffle"
    @types.Jjfflt => "jfflt"
    @types.Jjffne => "jffne"
    @types.Jjffo => "jffo"
    @types.Jjffuo => "jffuo"
    @types.Jxxx => "???"
  }
}

///|
// A copy of parser.printfn that also renders the sel0/sel1 placeholder ops as
// the C reference would.  parser.printfn cannot be used directly because the
// closed @types.Op enum has no Sel0/Sel1 constructors.
fn dump_fn(
  fn_ : @types.Fn,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let sb = StringBuilder::StringBuilder()
  let order = block_order(fn_)
  sb.write_string("function $\{fn_.name}() {\n")
  for id in order {
    let b = fn_.blks[id]
    sb.write_string("@\{b.name}\n")
    // Phi nodes
    for p in b.phi {
      sb.write_char('\t')
      @parser.printref(p.to, fn_, interner, sb, all_typs)
      sb.write_string(" =\{class_char(p.cls)} phi ")
      let mut first = true
      for a in p.args {
        if !first {
          sb.write_string(", ")
        }
        first = false
        sb.write_string("@\{fn_.blks[a.blk_id].name} ")
        @parser.printref(a.value, fn_, interner, sb, all_typs)
      }
      sb.write_string("\n")
    }
    // Instructions
    for ins in b.ins {
      sb.write_char('\t')
      if !ins.to.is_none() {
        @parser.printref(ins.to, fn_, interner, sb, all_typs)
        sb.write_string(" =\{class_char(ins.cls)} ")
      }
      if ins.op == sel0_op {
        sb.write_string("sel0")
      } else if ins.op == sel1_op {
        sb.write_string("sel1")
      } else {
        sb.write_string(ins.op.name())
      }
      if ins.to.is_none() && ins.op != sel0_op && ins.op != sel1_op {
        // Class suffix for void-result ops (arg, swap, xcmp, ...)
        match ins.op {
          @types.Arg
          | @types.Swap
          | @types.Xcmp
          | @types.Acmp
          | @types.Acmn
          | @types.Afcmp
          | @types.Xtest
          | @types.Xdiv
          | @types.Xidiv => sb.write_char(class_char(ins.cls))
          _ => ()
        }
      }
      if !ins.arg1.is_none() {
        sb.write_char(' ')
        @parser.printref(ins.arg1, fn_, interner, sb, all_typs)
      }
      if !ins.arg2.is_none() {
        sb.write_string(", ")
        @parser.printref(ins.arg2, fn_, interner, sb, all_typs)
      }
      sb.write_string("\n")
    }
    // Jump
    match b.jmp.kind {
      @types.Jjmp => {
        // Omit jmp to the next block in definition order (fall-through)
        let mut next = -1
        for i in 0..<order.length() {
          if order[i] == b.id {
            if i + 1 < order.length() {
              next = order[i + 1]
            }
            break
          }
        }
        if b.jmp.s1 >= 0 && b.jmp.s1 != next {
          sb.write_string("\tjmp @\{fn_.blks[b.jmp.s1].name}\n")
        }
      }
      @types.Jret0
      | @types.Jretw
      | @types.Jretl
      | @types.Jrets
      | @types.Jretd
      | @types.Jretc => {
        sb.write_string("\t\{jump_name(b.jmp.kind)}")
        if !(b.jmp.kind == @types.Jret0 && b.jmp.arg.is_none()) {
          sb.write_char(' ')
          @parser.printref(b.jmp.arg, fn_, interner, sb, all_typs)
        }
        if b.jmp.kind == @types.Jretc {
          sb.write_string(", :")
          sb.write_string(all_typs[fn_.ret_ty].name)
        }
        sb.write_string("\n")
      }
      _ => {
        sb.write_string("\t\{jump_name(b.jmp.kind)} ")
        if b.jmp.kind == @types.Jjnz {
          @parser.printref(b.jmp.arg, fn_, interner, sb, all_typs)
          sb.write_string(", ")
        }
        sb.write_string(
          "@\{fn_.blks[b.jmp.s1].name}, @\{fn_.blks[b.jmp.s2].name}\n",
        )
      }
    }
  }
  sb.write_string("}")
  sb.to_string()
}

///|
// Eliminate if-then[-else] graphlets with select instructions (C ifconvert).
// Returns the -dK debug text (empty when print_dbg is false).
pub fn ifconvert(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let sb = StringBuilder::StringBuilder()
  if print_dbg {
    sb.write_string("\n> If-conversion:\n")
  }
  for ifb in block_order(fn_) {
    let (ok, thenb, elseb, joinb) = ifgraph(fn_, ifb)
    if ok && okgraph(fn_, ifb, thenb, elseb, joinb) {
      if print_dbg {
        sb.write_string(
          "    @\{fn_.blks[ifb].name} -> @\{fn_.blks[thenb].name}, @\{fn_.blks[elseb].name} -> @\{fn_.blks[joinb].name}\n",
        )
      }
      convert(fn_, ifb, thenb, elseb, joinb)
    }
  }
  if print_dbg {
    sb.write_string("\n> After if-conversion:\n")
    sb.write_string(dump_fn(fn_, interner, all_typs))
    sb.write_string("\n")
  }
  sb.to_string()
}
