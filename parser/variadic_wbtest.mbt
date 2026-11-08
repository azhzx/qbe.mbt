///|
test "variadic calls reject a second ellipsis" {
  let src =
    #|function w $f() {
    #|@start
    #|  call $g(..., ...)
    #|  ret 0
    #|}
    #|
  let p = Parser::new(@lexer.Lexer::new(src, "test").tokenize(), "test")
  try p.parse() catch {
    @util.QbeError::ParseError(_, _, msg) =>
      assert_true(msg.contains("only one '...' allowed"))
    _ => fail("expected a parse error")
  } noraise {
    _ => fail("expected a parse error")
  }
}

///|
test "variadic calls retain arguments after ellipsis" {
  let src =
    #|function w $f() {
    #|@start
    #|  call $g(w 1, ..., w 2)
    #|  ret 0
    #|}
    #|
  let p = Parser::new(@lexer.Lexer::new(src, "test").tokenize(), "test")
  p.parse() catch {
    _ => fail("expected valid variadic call")
  }
}
