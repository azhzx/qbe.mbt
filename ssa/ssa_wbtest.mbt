///|
// White-box tests for SSA use analysis and checks.

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
test "filluse counts definitions and uses" {
  let f = make_two_block_fn()
  filluse(f)
  let ta = @types.Tmp0
  let tb = @types.Tmp0 + 1
  let ts = @types.Tmp0 + 2
  // %a and %b are used once (by the add), never defined.
  assert_true(f.tmp(ta).nuse == 1)
  assert_true(f.tmp(ta).ndef == 0)
  assert_true(f.tmp(tb).nuse == 1)
  // %s is defined once, used once (by retw).
  assert_true(f.tmp(ts).ndef == 1)
  assert_true(f.tmp(ts).nuse == 1)
  assert_true(f.tmp(ts).cls == @types.Kw)
  // The use of %s lives in block @ret as a UJmp use.
  assert_true(f.tmp(ts).uses.length() == 1)
  assert_true(f.tmp(ts).uses[0].kind == @types.UJmp)
  assert_true(f.tmp(ts).uses[0].blk_id == 1)
}

///|
test "filluse on a well-formed function then ssacheck passes" {
  // Same shape but %a/%b are defined by Par instructions so the function is
  // valid SSA.
  let f = @types.Fn::new("t")
  f.def_order.push(f.add_blk("@start"))
  f.def_order.push(f.add_blk("@ret"))
  f.init_regs()
  let ta = f.add_tmp("a", @types.Kw)
  let tb = f.add_tmp("b", @types.Kw)
  let ts = f.add_tmp("s", @types.Kw)
  let none = @types.Ref::none()
  f.blks[0].ins.push(
    @types.Ins::new(@types.Par, @types.Kw, @types.Ref::tmp(ta), none, none),
  )
  f.blks[0].ins.push(
    @types.Ins::new(@types.Par, @types.Kw, @types.Ref::tmp(tb), none, none),
  )
  f.blks[0].ins.push(
    @types.Ins::new(
      @types.Add,
      @types.Kw,
      @types.Ref::tmp(ts),
      @types.Ref::tmp(ta),
      @types.Ref::tmp(tb),
    ),
  )
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, none, 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jretw, @types.Ref::tmp(ts), -1, -1)
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @cfg.filldom(f)
  filluse(f)
  ssacheck(f)
}

///|
test "filluse raises ICE on a non-tmp destination" {
  let f = make_two_block_fn()
  f.blks[0].ins[0].to = @types.Ref::con(0)
  try filluse(f) catch {
    @util.QbeError::Ice(_) => ()
    _ => fail("expected an ICE for a non-tmp destination")
  } noraise {
    _ => fail("expected an ICE for a non-tmp destination")
  }
}
