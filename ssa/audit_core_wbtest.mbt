///|
test "audit core reconstructed load preserves symbol type" {
  let f = @types.Fn::new("reload")
  f.init_regs()
  let b = f.add_blk("start")
  f.def_order.push(b)
  let t = f.add_tmp("address", @types.Kl)
  f.tmps[t].alias_info.kind = @types.ASym
  f.tmps[t].alias_info.label = 7
  f.tmps[t].alias_info.sym_type = 1
  let st = LoadState::{ fn_: f, inum: 0, ilog: [], nlog: 0, }
  let sl = Slice::{ r: @types.Ref::tmp(t), off: 0, sz: 4, cls: @types.Kw, }
  let l = Loc::{ kind: LLoad, off: 0, blk: b, }
  ignore(load(st, sl, mask_of(4), l))
  let addr = st.ilog[0].ins.arg1
  assert_eq(f.cons[addr.con_val()].sym_type, 1)
}

///|
test "audit core rebasing reuses equivalent address slice phi" {
  let src =
    #|function w $f(l %p, w %c, w %d) {
    #|@start
    #| %q =l add %p, 4
    #| jnz %c, @one, @two
    #|@one
    #| storew 1, %q
    #| jmp @join
    #|@two
    #| storew 2, %q
    #| jmp @join
    #|@join
    #| jnz %d, @left, @right
    #|@left
    #| %a =w loadw %q
    #| jmp @done
    #|@right
    #| %r =l add %p, 4
    #| %b =w loadw %r
    #| jmp @done
    #|@done
    #| %v =w phi @left %a, @right %b
    #| ret %v
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "<audit>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<audit>")
  parser.parse()
  let f = parser.get_funcs()[0]
  @cfg.fillcfg(f)
  @cfg.filldom(f)
  filluse(f)
  @cfg.fillalias(f)
  ignore(loadopt(f, false, parser.interner_ref(), parser.get_typs()))
  assert_eq(f.blks[f.find_blk("join")].phi.length(), 1)
}

///|
test "audit core insertion comparator preserves equal phi keys" {
  let p = @types.Phi::new(@types.Ref::tmp(64), @types.Kw)
  let m = Slice::{ r: @types.Ref::tmp(65), off: 0, sz: 4, cls: @types.Kw, }
  let i = @types.Ins::new_void(
    @types.Nop,
    @types.Kw,
    @types.Ref::none(),
    @types.Ref::none(),
  )
  let a = Insert::{
    isphi: true,
    num: 1,
    bid: 0,
    rpo_id: 0,
    off: 0,
    ins: i,
    phi_m: m,
    phi_p: p,
  }
  let b = Insert::{
    isphi: true,
    num: 2,
    bid: 0,
    rpo_id: 0,
    off: 0,
    ins: i,
    phi_m: m,
    phi_p: p,
  }
  assert_eq(icmp(a, b), 0)
}

///|
test "audit core comparison result width is unsigned byte" {
  let f = @types.Fn::new("width")
  f.init_regs()
  let b = f.add_blk("start")
  f.def_order.push(b)
  let t = f.add_tmp("cmp", @types.Kw)
  let z = @types.Ref::con(f.get_con(0))
  f.blks[b].ins.push(
    @types.Ins::new(@types.Ceqw, @types.Kw, @types.Ref::tmp(t), z, z),
  )
  filluse(f)
  assert_true(f.tmps[t].width == @types.Wub)
}
