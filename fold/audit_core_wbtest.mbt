///|
test "audit core legacy fold unary operand uses zero not undef" {
  let f = @types.Fn::new("unary")
  f.init_regs()
  let b = f.add_blk("start")
  f.def_order.push(b)
  let t = f.add_tmp("v", @types.Ks)
  let c = @types.Ref::con(f.get_con_by(@types.Con::single(1.0)))
  f.blks[b].ins.push(
    @types.Ins::new(
      @types.Neg,
      @types.Ks,
      @types.Ref::tmp(t),
      c,
      @types.Ref::none(),
    ),
  )
  f.blks[b].jmp = @types.Jump::full(@types.Jrets, @types.Ref::tmp(t), -1, -1)
  @cfg.fillcfg(f)
  @ssa.filluse(f)
  ignore(fold(f, false, @util.Interner::new(), []))
  assert_eq(f.cons[f.blks[b].jmp.arg.con_val()].bits.i, 0xbf800000L)
}

///|
test "audit core legacy fold preserves symbol qualifiers" {
  let c = @types.Con::addr_sym(7, 1)
  let (_, r) = foldint(@types.Add, true, c, @types.Con::int(4))
  assert_eq(r.sym_type, 1)
  let (invalid, _) = foldint(@types.Sub, true, c, @types.Con::addr_sym(7, 0))
  assert_true(invalid)
}

///|
test "audit core legacy opfold truncates word results" {
  let f = @types.Fn::new("word")
  let st = FoldState::{
    fn_: f,
    val: [],
    edges: [],
    usewrk: [],
    nuse: 0,
    work: [],
  }
  let n = opfold(
    st,
    @types.Add,
    @types.Kw,
    @types.Con::int(0xffffffffL),
    @types.Con::int(1),
  )
  assert_eq(f.cons[n].bits.i, 0L)
}
