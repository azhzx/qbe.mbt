///|
test "audit core conditional blit must not be speculated" {
  let src =
    #|function $f(w %c, l %src, l %dst) {
    #|@start
    #|  jnz %c, @copy, @done
    #|@copy
    #|  blit %src, %dst, 8
    #|  jmp @done
    #|@done
    #|  ret
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "<audit>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<audit>")
  parser.parse()
  let f = parser.get_funcs()[0]
  @cfg.fillcfg(f)
  ignore(ifconvert(f, false, parser.interner_ref(), parser.get_typs()))
  assert_true(f.blks[f.start_id].jmp.kind == @types.Jjnz)
}

///|
test "audit core opaque side effects are pinned in if conversion" {
  for
    op in [
      @types.InlineAsm,
      @types.AtomicLoad,
      @types.AtomicStore,
      @types.Fence,
      @types.Blit0,
      @types.Blit1,
    ] {
    let i = @types.Ins::new_void(
      op,
      @types.Kw,
      @types.Ref::none(),
      @types.Ref::none(),
    )
    assert_true(pinned(i))
  }
}
