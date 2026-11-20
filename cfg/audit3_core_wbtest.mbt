///|
// audit round 3 white-box tests for cfg/: alias.c fillalias and cfg.c simplcfg.

///|
// C alias.c scans the start link chain for the final "phi arguments escape"
// loop; dead blocks are unlinked by fillcfg before fillalias runs.  A phi in an
// unreachable block must not mark a live alloc's slot as escaping.
test "audit3 core fillalias ignores phis of dead blocks" {
  let f = @types.Fn::new("alias_dead_phi")
  f.init_regs()
  let start = f.add_blk("start")
  f.start_id = start
  f.def_order.push(start)
  f.rpo.push(start)
  let t = f.add_tmp("a", @types.Kl)
  let sz = @types.Ref::con(f.get_con(8L))
  f.blks[start].ins.push(
    @types.Ins::new(
      @types.Alloc8,
      @types.Kl,
      @types.Ref::tmp(t),
      sz,
      @types.Ref::none(),
    ),
  )
  f.blks[start].jmp = @types.Jump::full(
    @types.Jret0,
    @types.Ref::none(),
    -1,
    -1,
  )
  // Unreachable block: kept in storage but not in def_order, exactly like a
  // block fillrpo has pruned from the link chain.
  let dead = f.add_blk("dead")
  let pt = f.add_tmp("p", @types.Kl)
  let p = @types.Phi::new(@types.Ref::tmp(pt), @types.Kl)
  p.args.push(@types.PhiArg::{ value: @types.Ref::tmp(t), blk_id: dead, })
  f.blks[dead].phi.push(p)
  fillalias(f)
  assert_true(f.tmps[t].alias_info.kind is @types.ALoc)
}

///|
// C cfg.c simplcfg ends with fillcfg(), so after the pass every phi argument
// names a block that still branches to the phi's block, and the rpo is fresh.
// The graphlet is the same threading chain as test/audit3_core_cfg.ssa.
test "audit3 core simplcfg finishes with a consistent CFG" {
  let f = @types.Fn::new("thread")
  f.init_regs()
  let start = f.add_blk("start")
  let a = f.add_blk("a")
  let b = f.add_blk("b")
  let x1 = f.add_blk("x1")
  let x2 = f.add_blk("x2")
  let join = f.add_blk("join")
  f.start_id = start
  for i in [start, a, b, x1, x2, join] {
    f.def_order.push(i)
  }
  let c = @types.Ref::tmp(f.add_tmp("c", @types.Kw))
  let v = @types.Ref::tmp(f.add_tmp("v", @types.Kw))
  let t = @types.Ref::tmp(f.add_tmp("t", @types.Kw))
  let t2 = @types.Ref::tmp(f.add_tmp("t2", @types.Kw))
  let u = @types.Ref::tmp(f.add_tmp("u", @types.Kw))
  let p = @types.Ref::tmp(f.add_tmp("p", @types.Kw))
  let q = @types.Ref::tmp(f.add_tmp("q", @types.Kw))
  let k2 = @types.Ref::con(f.get_con(2L))
  let k3 = @types.Ref::con(f.get_con(3L))
  f.blks[start].jmp = @types.Jump::full(@types.Jjnz, c, a, b)
  f.blks[a].ins.push(@types.Ins::new(@types.Add, @types.Kw, t, v, k2))
  f.blks[a].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), x1, -1)
  f.blks[b].ins.push(@types.Ins::new(@types.Add, @types.Kw, t2, v, k3))
  f.blks[b].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), join, -1)
  f.blks[x1].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), x2, -1)
  f.blks[x2].ins.push(@types.Ins::new(@types.Mul, @types.Kw, u, v, k3))
  f.blks[x2].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), join, -1)
  let jp = @types.Phi::new(p, @types.Kw)
  jp.args.push(@types.PhiArg::{ value: u, blk_id: x2, })
  jp.args.push(@types.PhiArg::{ value: t2, blk_id: b, })
  f.blks[join].phi.push(jp)
  f.blks[join].ins.push(@types.Ins::new(@types.Add, @types.Kw, q, p, k3))
  f.blks[join].jmp = @types.Jump::full(@types.Jretw, q, -1, -1)
  fillcfg(f)
  let out = simplcfg(f, false, @util.Interner::new(), [])
  assert_eq(out, "")
  for n in 0..<f.rpo.length() {
    assert_eq(f.blks[f.rpo[n]].rpo_id, n)
  }
  for id in f.def_order {
    for phi in f.blks[id].phi {
      for arg in phi.args {
        let bb = f.blks[arg.blk_id]
        assert_true(bb.jmp.s1 == id || bb.jmp.s2 == id)
      }
    }
  }
}
