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
  // C's lexer reads integers only: a bare decimal is an int followed by an
  // identifier-like ".14" token (which the parser then rejects). Floats must
  // be written s_.../d_....
  let src = "1 123 -42 3.14 -2.5\n"
  let tokens = Lexer::new(src, "test").tokenize()
  assert_true(tokens[0].kind == TInt && tokens[0].raw == "1")
  assert_true(tokens[1].kind == TInt && tokens[1].raw == "123")
  assert_true(tokens[2].kind == TInt && tokens[2].raw == "-42")
  assert_true(tokens[3].kind == TInt && tokens[3].raw == "3")
  assert_true(tokens[4].kind == TId && tokens[4].raw == ".14")
  assert_true(tokens[5].kind == TInt && tokens[5].raw == "-2")
  assert_true(tokens[6].kind == TId && tokens[6].raw == ".5")
  assert_true(tokens[7].kind == TNl)
  assert_true(tokens[8].kind == TEof)
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
test "unterminated strings produce an error token" {
  let tokens = Lexer::new("b \\\"unterminated", "test").tokenize()
  assert_true(tokens[0].kind == TId)
  assert_true(tokens[1].kind == TErr)
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

///|
// The lexer must accept the same float text C's fscanf("%f") accepts:
// signed exponents, hexadecimal floats, inf/nan and a leading sign.
test "lexer: C-style floating literal text" {
  let src = "s_1e+3 d_0x1.8p1 s_inf d_nan d_-0x1p-1074 s_+1.5 d_1E-10"
  let toks = Lexer::new(src, "<test>").tokenize()
  let raws : Array[String] = []
  for t in toks {
    if t.kind == TFlt {
      raws.push(t.raw)
    }
  }
  assert_eq(raws, [
    "s_1e+3", "d_0x1.8p1", "s_inf", "d_nan", "d_-0x1p-1074", "s_+1.5", "d_1E-10",
  ])
}

///|
// '$' is an identifier character in C's lexer (isalpha || '$' || '.' || '_').
test "lexer: dollar sign is allowed inside identifiers" {
  let toks = Lexer::new("%a$b @c$d $e$f :t$u", "<test>").tokenize()
  assert_eq(toks[0].kind, TTemp)
  assert_eq(toks[0].raw, "a$b")
  assert_eq(toks[1].kind, TLoc)
  assert_eq(toks[1].raw, "c$d")
  assert_eq(toks[2].kind, TGlo)
  assert_eq(toks[2].raw, "e$f")
  assert_eq(toks[3].kind, TTyp)
  assert_eq(toks[3].raw, "t$u")
}

///|
// C lexes $"name" as a global whose quotes are part of the symbol name.
test "quoted global symbols keep their quotes" {
  let src = "$\"g lo\" $plain"
  let toks = Lexer::new(src, "<test>").tokenize()
  assert_true(toks[0].kind == TGlo)
  assert_true(toks[0].raw == "\"g lo\"")
  assert_true(toks[1].kind == TGlo)
  assert_true(toks[1].raw == "plain")
}

///|
test "prefixed names require a valid identifier start" {
  let temp = Lexer::new("%1", "<test>").tokenize()
  assert_eq(temp[0].kind, TErr)
  assert_eq(temp[0].raw, "%")
  let global = Lexer::new("$1", "<test>").tokenize()
  assert_eq(global[0].kind, TErr)
  assert_eq(global[0].raw, "$")
  let label = Lexer::new("@1", "<test>").tokenize()
  assert_eq(label[0].kind, TErr)
  assert_eq(label[0].raw, "@")
}
