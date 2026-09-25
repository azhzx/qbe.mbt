///|
// CFG simplification (C cfg.c simplcfg), the -dC pass. Requires rpo.
// Returns the -dC debug text (empty when print_dbg is false).

///|
fn addins(vins : Array[@types.Ins], i : @types.Ins) -> Unit {
  if i.op != @types.Nop {
    vins.push(i)
  }
}

///|
fn addbins(vins : Array[@types.Ins], b : @types.Blk) -> Unit {
  for i in b.ins {
    addins(vins, i)
  }
}

///|
fn phiargn(p : @types.Phi, b_id : Int) -> Int {
  for i in 0..<p.args.length() {
    if p.args[i].blk_id == b_id {
      return i
    }
  }
  -1
}

///|
fn phiarg(fn_ : @types.Fn, p : @types.Phi, b_id : Int) -> @types.Ref {
  let n = phiargn(p, b_id)
  if n < 0 {
    abort("block not found in phi")
  }
  p.args[n].value
}

///|
fn jmpeq(
  jtype : Array[@types.JumpKind],
  jarg : Array[@types.Ref],
  js1 : Array[Int],
  js2 : Array[Int],
  a : Int,
  b : Int,
) -> Bool {
  jtype[a] == jtype[b] &&
  jarg[a].eq(jarg[b]) &&
  js1[a] == js1[b] &&
  js2[a] == js2[b]
}

///|
fn jmpnophi(fn_ : @types.Fn, s1 : Int, s2 : Int) -> Bool {
  if s1 >= 0 && fn_.blks[s1].phi.length() > 0 {
    return false
  }
  if s2 >= 0 && fn_.blks[s2].phi.length() > 0 {
    return false
  }
  true
}

///|
// Minimize the CFG (C simplcfg). Requires rpo and breaks use information.
pub fn simplcfg(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  typs : Array[@types.Typ],
) -> String raise {
  let sb = StringBuilder::StringBuilder()
  if print_dbg {
    sb.write_string("\n> Before CFG simplification:\n")
    sb.write_string(@parser.printfn(fn_, interner, typs))
    sb.write_string("\n")
  }
  // 1. A block with a single predecessor: turn its phis into copies in that
  // predecessor (C simplcfg's first loop).
  for id in fn_.def_order {
    let b = fn_.blks[id]
    if b.npred == 1 {
      let pred = b.pred[0]
      for p in b.phi {
        let v = phiarg(fn_, p, pred)
        let cpy = @types.Ins::new(
          @types.Copy,
          p.cls,
          p.to,
          v,
          @types.Ref::none(),
        )
        addins(fn_.blks[pred].ins, cpy)
      }
      b.phi.clear()
    }
  }
  // 2. Snapshot jump records and emptiness.
  let n = fn_.blks.length()
  let jtype : Array[@types.JumpKind] = Array::make(n, @types.Jxxx)
  let jarg : Array[@types.Ref] = []
  for _ in 0..<n {
    jarg.push(@types.Ref::none())
  }
  let js1 : Array[Int] = Array::make(n, -1)
  let js2 : Array[Int] = Array::make(n, -1)
  let empty : Array[Bool] = Array::make(n, true)
  let dead : Array[Bool] = Array::make(n, false)
  for id in fn_.def_order {
    let b = fn_.blks[id]
    jtype[id] = b.jmp.kind
    jarg[id] = b.jmp.arg
    js1[id] = b.jmp.s1
    js2[id] = b.jmp.s2
    let mut e = b.phi.length() == 0
    for i in b.ins {
      if i.op != @types.Nop && i.op != @types.Dbgloc {
        e = false
        break
      }
    }
    empty[id] = e
  }
  // 3. Thread jumps and merge identical branch targets until a fixpoint.
  let mut done = false
  while !done {
    done = true
    for id in fn_.def_order {
      if dead[id] {
        continue
      }
      if jtype[id] == @types.Jjmp &&
        js1[id] >= 0 &&
        fn_.blks[js1[id]].npred == 1 {
        let s1 = js1[id]
        addbins(fn_.blks[id].ins, fn_.blks[s1])
        empty[id] = empty[id] && empty[s1]
        // Redirect s1's successors' phis from s1 to id.
        let succs : Array[Int] = [js1[s1], js2[s1]]
        for succ in succs {
          if succ >= 0 {
            for pi in 0..<fn_.blks[succ].phi.length() {
              let p = fn_.blks[succ].phi[pi]
              let k = phiargn(p, s1)
              if k >= 0 {
                p.args[k].blk_id = id
              }
            }
          }
        }
        dead[s1] = true
        jtype[id] = jtype[s1]
        jarg[id] = jarg[s1]
        js1[id] = js1[s1]
        js2[id] = js2[s1]
        done = false
      } else if jtype[id] == @types.Jjnz &&
        js1[id] >= 0 &&
        js2[id] >= 0 &&
        empty[js1[id]] &&
        empty[js2[id]] &&
        jmpeq(jtype, jarg, js1, js2, js1[id], js2[id]) &&
        jmpnophi(fn_, js1[js1[id]], js2[js1[id]]) {
        jtype[id] = jtype[js1[id]]
        jarg[id] = jarg[js1[id]]
        js1[id] = js1[js1[id]]
        js2[id] = js2[js1[id]]
        done = false
      }
    }
  }
  // 4. Write back jumps of live blocks.
  for id in fn_.def_order {
    if !dead[id] {
      let b = fn_.blks[id]
      b.jmp.kind = jtype[id]
      b.jmp.arg = jarg[id]
      b.jmp.s1 = js1[id]
      b.jmp.s2 = js2[id]
    }
  }
  fillrpo(fn_)
  fillpreds(fn_)
  if print_dbg {
    sb.write_string("\n> After CFG simplification:\n")
    sb.write_string(@parser.printfn(fn_, interner, typs))
    sb.write_string("\n")
  }
  sb.to_string()
}
