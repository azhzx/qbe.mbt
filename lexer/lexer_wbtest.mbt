///|
// White-box unit tests for the lexer.

///|
// Join token kinds into a single string for easy comparison.
fn kinds_str(tokens : Array[Token]) -> String {
  tokens.map(t => t.kind.to_string()).join(" ")
}

///|
test "tokenize a function header" {
  let src =
    #|export function w $add(w %a, w %b) {
    #|@start
    #|}
    #|
  let tokens = Lexer::new(src, "test").tokenize()
  assert_true(
    kinds_str(tokens) ==
    "export function id global ( id temp , id temp ) { newline label newline } newline eof",
  )
  assert_true(tokens[3].raw == "add")
  assert_true(tokens[6].raw == "a")
}

///|
test "tokenize numbers" {
  let src = "1 123 -42 3.14 -2.5\n"
  let tokens = Lexer::new(src, "test").tokenize()
  assert_true(tokens[0].kind == TInt && tokens[0].raw == "1")
  assert_true(tokens[1].kind == TInt && tokens[1].raw == "123")
  assert_true(tokens[2].kind == TInt && tokens[2].raw == "-42")
  assert_true(tokens[3].kind == TFlt && tokens[3].raw == "3.14")
  assert_true(tokens[4].kind == TFlt && tokens[4].raw == "-2.5")
  assert_true(tokens[5].kind == TNl)
  assert_true(tokens[6].kind == TEof)
}

///|
test "tokenize keywords and ops" {
  let src = "data type phi jmp jnz ret hlt = , ... ->\n"
  let tokens = Lexer::new(src, "test").tokenize()
  assert_true(
    kinds_str(tokens) == "data type phi jmp jnz ret hlt = , ... -> newline eof",
  )
}

///|
test "tokenize string literal" {
  let src = "\"hello world\" \"esc\\\"aped\"\n"
  let tokens = Lexer::new(src, "test").tokenize()
  assert_true(tokens[0].kind == TStr && tokens[0].raw == "hello world")
  assert_true(tokens[1].kind == TStr && tokens[1].raw == "esc\\\"aped")
}

///|
test "comments are skipped" {
  let src = "function # a comment\nw # inline\n"
  let tokens = Lexer::new(src, "test").tokenize()
  // A comment runs to but does not consume the newline.
  assert_true(kinds_str(tokens) == "function newline id newline eof")
  assert_true(tokens[2].kind == TId && tokens[2].raw == "w")
}

///|
test "line and column tracking" {
  let src = "%a\n%b\n"
  let tokens = Lexer::new(src, "test").tokenize()
  assert_true(tokens[0].line == 1 && tokens[0].col == 1)
  assert_true(tokens[2].line == 2 && tokens[2].col == 1)
}

///|
test "unexpected character produces TErr" {
  let tokens = Lexer::new("$a !\n", "test").tokenize()
  assert_true(tokens[1].kind == TErr)
  assert_true(tokens[1].raw == "!")
}

///|
test "lone colon is an error" {
  let tokens = Lexer::new(":x", "test").tokenize()
  // ":x" reads a type reference
  assert_true(tokens[0].kind == TTyp && tokens[0].raw == "x")
  let tokens2 = Lexer::new(":", "test").tokenize()
  assert_true(tokens2[0].kind == TErr)
}

///|
test "float literal prefixes s_ and d_" {
  let tokens = Lexer::new("s_1.5 d_2.25\n", "test").tokenize()
  assert_true(tokens[0].kind == TFlt && tokens[0].raw == "s_1.5")
  assert_true(tokens[1].kind == TFlt && tokens[1].raw == "d_2.25")
}

///|
test "Token::kind_str and to_string" {
  assert_true(TokenKind::TEof.to_string() == "eof")
  assert_true(TokenKind::TRbr.to_string() == "}")
  assert_true(TokenKind::TCom.to_string() == ",")
  assert_true(TokenKind::TTemp.to_string() == "temp")
  let t = Token::new(TTemp, 1, 1, "%x")
  assert_true(t.kind_str() == "temp")
  assert_true(t.kind == TTemp)
  assert_true(t.line == 1)
  assert_true(t.raw == "%x")
}
