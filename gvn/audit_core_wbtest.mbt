///|
test "audit core subtraction respects full symbol identity" {
  let a = @types.Con::addr_sym(7, 0)
  let b = @types.Con::addr_sym(7, 1)
  assert_true(c_foldint(@types.Sub, true, a, b) is None)
}

///|
test "audit core eliminated phi use is skipped before indexing" {
  let f = @types.Fn::new("removed_phi")
  f.init_regs()
  let b = f.add_blk("start")
  f.def_order.push(b)
  let t = f.add_tmp("arg", @types.Kw)
  f.blks[b].phi.push(@types.Phi::new(@types.Ref::none(), @types.Kw))
  gvn_adduse(f, t, @types.UPhi, b, 0, 0)
  assert_true(usewidthle(GState::new(f), @types.Ref::tmp(t), 8))
}

///|
test "audit core subword abi operations remain pinned" {
  for
    op in [
      @types.Parsb,
      @types.Parub,
      @types.Parsh,
      @types.Paruh,
      @types.Argsb,
      @types.Argub,
      @types.Argsh,
      @types.Arguh,
    ] {
    assert_true(
      pinned(
        @types.Ins::new_void(
          op,
          @types.Kw,
          @types.Ref::none(),
          @types.Ref::none(),
        ),
      ),
    )
  }
}

///|
test "audit core scheduler groups both halves of blit" {
  let f = @types.Fn::new("group")
  let b = f.add_blk("start")
  f.blks[b].ins.push(
    @types.Ins::new_void(
      @types.Blit0,
      @types.Kw,
      @types.Ref::tmp(64),
      @types.Ref::tmp(65),
    ),
  )
  f.blks[b].ins.push(
    @types.Ins::new_void(
      @types.Blit1,
      @types.Kw,
      @types.Ref::rint(8),
      @types.Ref::none(),
    ),
  )
  assert_eq(igroup(f, f.blks[b], 0), (0, 2))
  assert_eq(igroup(f, f.blks[b], 1), (0, 2))
}

///|
test "audit core value numbering retains instruction reference identity" {
  let f = @types.Fn::new("identity")
  let st = GState::new(f)
  st.tbl = Array::make(7, None)
  let i = @types.Ins::new(
    @types.Add,
    @types.Kw,
    @types.Ref::tmp(64),
    @types.Ref::tmp(65),
    @types.Ref::tmp(66),
  )
  ignore(gvndup(st, i, true))
  let entry = gvndup(st, i, false).unwrap()
  i.arg1 = @types.Ref::tmp(67)
  assert_true(entry.arg1.eq(i.arg1))
}

///|
test "audit core long to single rounds once" {
  let c = @types.Con::int(9007199791611905L)
  let s = c_foldflt(@types.Sltof, false, c, @types.Con::int(0)).unwrap()
  assert_eq(s.bits.i, 0x5a000001L)
  let u = c_foldflt(@types.Ultowf, false, c, @types.Con::int(0)).unwrap()
  assert_eq(u.bits.i, 0x5a000001L)
}

///|
test "audit core integer negation is cheap for sinking" {
  let i = @types.Ins::new(
    @types.Neg,
    @types.Kl,
    @types.Ref::tmp(64),
    @types.Ref::tmp(65),
    @types.Ref::none(),
  )
  assert_true(cheap(i))
}
