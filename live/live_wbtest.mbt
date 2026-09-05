///|
// White-box tests for liveness analysis.

///|
// Build a two-block function:
//   @start:  %s =w add %a, %b   jmp @ret
//   @ret:    retw %s
fn make_two_block_fn() -> @types.Fn {
  let f = @types.Fn::new("t")
  f.def_order.push(f.add_blk("@start"))
  f.def_order.push(f.add_blk("@ret"))
  f.init_regs()
  let ta = f.add_tmp("a", @types.Kw)
  let tb = f.add_tmp("b", @types.Kw)
  let ts = f.add_tmp("s", @types.Kw)
  let i = @types.Ins::new(
    @types.Add,
    @types.Kw,
    @types.Ref::tmp(ts),
    @types.Ref::tmp(ta),
    @types.Ref::tmp(tb),
  )
  f.blks[0].ins.push(i)
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jretw, @types.Ref::tmp(ts), -1, -1)
  f
}

///|
test "filllive computes live-in and counts" {
  let f = make_two_block_fn()
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let out = filllive(f, false)
  assert_true(out == "")
  let ta = @types.Tmp0
  let tb = @types.Tmp0 + 1
  let ts = @types.Tmp0 + 2
  // The return block needs %s live-in.
  let ret_in = f.blks[1].in_set.unwrap()
  assert_true(ret_in.has(ts))
  assert_true(!ret_in.has(ta))
  // The start block needs %a, %b live-in; %s is defined there so it is not.
  let start_in = f.blks[0].in_set.unwrap()
  assert_true(start_in.has(ta))
  assert_true(start_in.has(tb))
  assert_true(!start_in.has(ts))
  // RBP/RSP are always live, so the counts include them.
  assert_true(f.blks[0].nlive_w == 4)
  assert_true(f.blks[1].nlive_w == 3)
  // %s is generated in the start block.
  assert_true(f.blks[0].gen_set.unwrap().has(ts))
}

///|
test "filllive debug output mentions liveness" {
  let f = make_two_block_fn()
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let out = filllive(f, true)
  assert_true(out.contains("Liveness analysis"))
  assert_true(out.contains("in:"))
}

///|
test "filllive keeps values live around a back edge" {
  // b0: %t = add %a, 1; %c = copy %a; jmp b1
  // b1: jnz %c, b2, b1        (self loop)
  // b2: retw %t               (%t crosses the loop block b1)
  let f = @types.Fn::new("t")
  f.def_order.push(f.add_blk("b0"))
  f.def_order.push(f.add_blk("b1"))
  f.def_order.push(f.add_blk("b2"))
  f.init_regs()
  let ta = f.add_tmp("a", @types.Kw)
  let tt = f.add_tmp("t", @types.Kw)
  let tc = f.add_tmp("c", @types.Kw)
  f.blks[0].ins.push(
    @types.Ins::new(
      @types.Add,
      @types.Kw,
      @types.Ref::tmp(tt),
      @types.Ref::tmp(ta),
      @types.Ref::con(f.get_con(1)),
    ),
  )
  f.blks[0].ins.push(
    @types.Ins::new(
      @types.Copy,
      @types.Kw,
      @types.Ref::tmp(tc),
      @types.Ref::tmp(ta),
      @types.Ref::none(),
    ),
  )
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jjnz, @types.Ref::tmp(tc), 2, 1)
  f.blks[2].jmp = @types.Jump::full(@types.Jretw, @types.Ref::tmp(tt), -1, -1)
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let _ = filllive(f, false)
  // %t is defined before the loop and used after it: live-in at b1
  let b1_in = f.blks[1].in_set.unwrap()
  assert_true(b1_in.has(tt))
  assert_true(b1_in.has(tc))
  // %t is defined in b0, so it is not live-in there
  assert_true(!f.blks[0].in_set.unwrap().has(tt))
  // b2 is the exit: only %t is live-in
  assert_true(f.blks[2].in_set.unwrap().has(tt))
  assert_true(!f.blks[2].in_set.unwrap().has(tc))
}
