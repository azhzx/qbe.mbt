///|
// audit round 3 white-box tests for gvn/: util.c igroup group boundaries.

///|
// C util.c igroup groups a sel0 with the run of sel1 instructions after it,
// and a sel1 run with the sel0 before it, so scheduling keeps select chains
// together.  Every index of the run must report the same group.
test "audit3 core igroup groups sel0 with following sel1" {
  let f = @types.Fn::new("igroup_sel")
  f.init_regs()
  let b = f.add_tmp("b", @types.Kw)
  let x = f.add_tmp("x", @types.Kw)
  let y = f.add_tmp("y", @types.Kw)
  let z = f.add_tmp("z", @types.Kw)
  let blk = f.add_blk("start")
  f.blks[blk].ins.push(
    @types.Ins::new_void(
      @types.Sel0,
      @types.Kw,
      @types.Ref::tmp(b),
      @types.Ref::none(),
    ),
  )
  f.blks[blk].ins.push(
    @types.Ins::new(
      @types.Sel1,
      @types.Kw,
      @types.Ref::tmp(x),
      @types.Ref::tmp(y),
      @types.Ref::tmp(z),
    ),
  )
  f.blks[blk].ins.push(
    @types.Ins::new(
      @types.Sel1,
      @types.Kw,
      @types.Ref::tmp(y),
      @types.Ref::tmp(x),
      @types.Ref::tmp(z),
    ),
  )
  f.blks[blk].ins.push(
    @types.Ins::new(
      @types.Add,
      @types.Kw,
      @types.Ref::tmp(z),
      @types.Ref::tmp(x),
      @types.Ref::tmp(y),
    ),
  )
  // igroup is only meaningful at a group start; schedblk advances i by the
  // group size, so a sel1 run is entered through its sel0.
  let (a0, a1) = igroup(f, f.blks[blk], 0)
  let (d0, d1) = igroup(f, f.blks[blk], 3)
  assert_eq(a0, 0)
  assert_eq(a1, 3)
  assert_eq(d0, 3)
  assert_eq(d1, 4)
}

///|
// C util.c igroup: a blit1 belongs to the blit0 before it, and a blit0 group
// covers both pseudo instructions.
test "audit3 core igroup keeps a blit pair together" {
  let f = @types.Fn::new("igroup_blit")
  f.init_regs()
  let p = f.add_tmp("p", @types.Kl)
  let q = f.add_tmp("q", @types.Kl)
  let blk = f.add_blk("start")
  let sz = @types.Ref::rint(3)
  f.blks[blk].ins.push(
    @types.Ins::new(
      @types.Blit0,
      @types.Kl,
      @types.Ref::none(),
      @types.Ref::tmp(p),
      @types.Ref::tmp(q),
    ),
  )
  f.blks[blk].ins.push(
    @types.Ins::new_void(@types.Blit1, @types.Kw, sz, @types.Ref::none()),
  )
  let (a0, a1) = igroup(f, f.blks[blk], 0)
  let (b0, b1) = igroup(f, f.blks[blk], 1)
  assert_eq(a0, 0)
  assert_eq(a1, 2)
  assert_eq(b0, 0)
  assert_eq(b1, 2)
}
