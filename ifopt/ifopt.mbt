///|
// If-conversion - corresponds to ifopt.c in QBE.
//
// Eliminates if-then[-else] graphlets with select instructions.  Requires
// reverse post-order, predecessor lists and uses; it breaks the cfg's
// predecessor information and uses, so callers must rebuild them.
//
// The select pseudo-instructions are @types.Sel0/@types.Sel1, and the pinned
// predicate is shared with GVN/GCM (@gvn.pinned).  The debug dump uses
// @parser.printfn, the single printer for IL, which renders sel0/sel1 from
// their op names.  Whether the active target supports select is the caller's
// concern: the reference runs ifconvert only when T.cansel is set.

///|
// MaxIns in ifopt.c.
let max_ins : Int32 = 2

///|
// MaxPhis in ifopt.c.
let max_phis : Int32 = 2

///|
// Return the block iteration order used by the C reference's block link list.
// Falls back to every block when the caller has not built def_order yet.
fn block_order(fn_ : @types.Fn) -> Array[Int32] {
  if fn_.def_order.length() > 0 {
    return fn_.def_order
  }
  let a : Array[Int32] = []
  for i in 0..<fn_.blks.length() {
    a.push(i)
  }
  a
}

///|
// C ifopt.c uses the same gcm.c pinned predicate as GVN/GCM.
fn pinned(i : @types.Ins) -> Bool {
  @gvn.pinned(i)
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
fn ifgraph(fn_ : @types.Fn, ifb : Int32) -> (Bool, Int32, Int32, Int32) {
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
  // C compares Blk.id, which fillrpo assigns as the RPO index; the port keeps
  // block ids as definition order and exposes the RPO index as rpo_id.
  if fn_.blks[s1].rpo_id > fn_.blks[s2].rpo_id {
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
  ifb : Int32,
  thenb : Int32,
  elseb : Int32,
  joinb : Int32,
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
fn phiarg(p : @types.Phi, b : Int32) -> @types.Ref {
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
  ifb : Int32,
  thenb : Int32,
  elseb : Int32,
  joinb : Int32,
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
      @types.Sel0,
      @types.Kw,
      fn_.blks[ifb].jmp.arg,
      @types.Ref::none(),
    )
    addins(vins, sel)
  }
  for p in fn_.blks[joinb].phi {
    let sel = @types.Ins::new(
      @types.Sel1,
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
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
  }
  sb.to_string()
}
