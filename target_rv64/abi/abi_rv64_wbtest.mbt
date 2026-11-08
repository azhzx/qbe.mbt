///|
test "audit rv64 single alternative union uses integer convention" {
  let t = @types.Typ::new("union")
  t.isunion = true
  t.fields.push(@types.Field::new(@types.Fd, 8))
  t.fields.push(@types.Field::end())
  t.compute_layout([])
  let st = rv64_abi_new(@types.Fn::new("f"), [t])
  let c = rv64_typclass(st, Rv64Class::new(), t, true)
  assert_eq(c.nfp, 0)
  assert_eq(c.ngp, 1)
  assert_true(c.cls[0] == @types.Kl)
}

///|
test "audit rv64 nested aggregate offsets follow upstream fpstruct" {
  let inner = @types.Typ::new("inner")
  inner.fields.push(@types.Field::new(@types.Fd, 8))
  inner.fields.push(@types.Field::end())
  inner.compute_layout([])
  let outer = @types.Typ::new("outer")
  outer.fields.push(@types.Field::new(@types.FTyp, 0))
  outer.fields.push(@types.Field::new(@types.Fd, 8))
  outer.fields.push(@types.Field::end())
  outer.compute_layout([inner])
  let st = rv64_abi_new(@types.Fn::new("f"), [inner, outer])
  let c = rv64_typclass(st, Rv64Class::new(), outer, true)
  assert_eq(c.nfp, 2)
  // vendor/qbe/rv64/abi.c:109 does not advance off after FTyp.
  assert_eq(c.off[1], 0)
}

///|
test "audit rv64 three register aggregate parameters fit temporary storage" {
  @types.init_rv64_target()
  let t = @types.Typ::new("pair")
  t.fields.push(@types.Field::new(@types.Fl, 8))
  t.fields.push(@types.Field::new(@types.Fl, 8))
  t.fields.push(@types.Field::end())
  t.compute_layout([])
  let f = @types.Fn::new("f")
  f.init_regs()
  let bid = f.add_blk("start")
  f.def_order.push(bid)
  for _ in 0..<3 {
    let to = @types.Ref::tmp(f.new_tmp("par", @types.Kl))
    f.blks[bid].ins.push(
      @types.Ins::new(
        @types.Parc,
        @types.Kl,
        to,
        @types.Ref::typ(0),
        @types.Ref::none(),
      ),
    )
  }
  let st = rv64_abi_new(f, [t])
  rv64_selpar(st, 3)
  let regs = st.buf.filter(fn(i) {
    i.op == @types.Copy && i.arg1.is_tmp() && i.arg1.tmp_val() < 64
  })
  assert_eq(regs.length(), 6)
}

///|
test "audit rv64 stkblob retains uint64 size before alignment" {
  let t = @types.Typ::new("large")
  t.size = 4294967304L
  t.align = 3
  let f = @types.Fn::new("f")
  let st = rv64_abi_new(f, [t])
  rv64_stkblob(st, @types.Ref::tmp(64), t)
  assert_eq(f.cons[st.buf[0].arg1.con_val()].bits.i, 4294967304L)
}
