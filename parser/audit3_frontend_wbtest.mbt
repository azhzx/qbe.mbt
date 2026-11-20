///|
// audit3 frontend: white-box regressions for the parse.c transcription fixes.
// Every case was first reproduced against vendor/qbe (the reference either
// accepts and the port rejected it, or the other way round).

///|
fn audit3_parse(
  src : String,
) -> (Array[@types.Fn], Array[@types.Dat], Array[@types.Typ]) raise {
  let tokens = @lexer.Lexer::new(src, "test").tokenize()
  let p = Parser::new(tokens, "test")
  p.parse()
  (p.get_funcs(), p.get_datas(), p.get_typs())
}

///|
fn audit3_parse_reject(src : String) -> String raise {
  try audit3_parse(src) catch {
    @util.QbeError::ParseError(_, _, msg) => return msg
    _ => fail("expected a QbeError parse error")
  } noraise {
    _ => fail("expected a parse error")
  }
}

///|
// C parse.c parses every instruction through one operand loop, so a blit may
// carry extra operands (they are discarded) and a blit written with a result
// is accepted with the result dropped.
test "audit3: blit extra operand and resultful blit" {
  let src =
    #|function $f() {
    #|@start
    #|  %p =l copy $g
    #|  %q =l copy $g
    #|  blit %p, %q, 4, 5
    #|  %r =w blit %p, %q, 8
    #|  ret
    #|}
    #|
  let (funcs, _, _) = audit3_parse(src)
  let ins = funcs[0].blks[0].ins
  // copy, copy, blit0, blit1, blit0, blit1
  assert_eq(ins.length(), 6)
  assert_eq(ins[2].op, @types.Blit0)
  assert_eq(ins[3].op, @types.Blit1)
  assert_eq(ins[3].arg1.rint_val(), 4)
  assert_eq(ins[4].op, @types.Blit0)
  assert_eq(ins[5].arg1.rint_val(), 8)
}

///|
// C parse.c NPred = 63: a phi may have 63 arguments, the 64th is an error.
test "audit3: phi operand limit is NPred" {
  let mk = fn(n : Int32) -> String {
    let sb = StringBuilder::new()
    sb.write_string("function $f() {\n@s\n  jmp @b0\n")
    for i in 0..<n {
      sb.write_string("@b\{i}\n  jmp @join\n")
    }
    sb.write_string("@join\n  %x =w phi")
    for i in 0..<n {
      if i > 0 {
        sb.write_string(",")
      }
      sb.write_string(" @b\{i} 0")
    }
    sb.write_string("\n  ret\n}\n")
    sb.to_string()
  }
  let (f63, _, _) = audit3_parse(mk(63))
  let join = f63[0].find_blk("join")
  assert_eq(f63[0].blks[join].phi[0].args.length(), 63)
  let msg = audit3_parse_reject(mk(64))
  assert_true(msg.contains("too many arguments"))
}

///|
// The same NPred bound applies to an ordinary instruction's operands.
test "audit3: instruction operand limit is NPred" {
  let sb = StringBuilder::new()
  sb.write_string("function $f() {\n@start\n  %x =w add")
  for i in 0..<64 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(" 1")
  }
  sb.write_string("\n  ret\n}\n")
  let msg = audit3_parse_reject(sb.to_string())
  assert_true(msg.contains("too many arguments"))
}

///|
// C parse.c: vastart is rejected in a non-variadic function before its
// operands are read, whether or not the instruction has a result.
test "audit3: resultful vastart needs a variadic function" {
  let msg = audit3_parse_reject(
    "function $f() {\n@start\n  %p =l add 0, 0\n  %x =w vastart %p\n  ret\n}\n",
  )
  assert_true(msg.contains("cannot use vastart in non-variadic function"))
  let (funcs, _, _) = audit3_parse(
    "function $f(...) {\n@start\n  %p =l add 0, 0\n  %x =w vastart %p\n  ret\n}\n",
  )
  assert_eq(funcs[0].blks[0].ins[1].op, @types.Vastart)
}

///|
// "argv" is an internal op the reference lexer does not know; the port used to
// accept it as a source keyword.
test "audit3: argv is not a source keyword" {
  let msg = audit3_parse_reject(
    "function $f() {\n@start\n  %x =w argv\n  ret\n}\n",
  )
  assert_true(msg.contains("unknown keyword argv"))
}

///|
// C parsedatref reads the offset with next(), so a newline after '+' is an
// error (the port used to skip it with nextnl()).
test "audit3: data ref offset does not skip newlines" {
  let msg = audit3_parse_reject(
    "data $a = { l $b +\n  8 }\ndata $b = { l 0 }\n",
  )
  assert_true(msg.contains("invalid token after offset in ref"))
  let (_, datas, _) = audit3_parse(
    "data $a = { l $b + 8 }\ndata $b = { l 0 }\n",
  )
  assert_eq(datas[2].ref_offset, 8L)
}

///|
// C parse.c parsedat diagnostics: the name/eq check is one message, and the
// size-specifier error prints the token's leading character.
test "audit3: data diagnostics match parse.c" {
  let m1 = audit3_parse_reject("data $e align 4 { w 1 }\n")
  assert_true(m1.contains("data name, then = expected"))
  let m2 = audit3_parse_reject("data $e = { s_1.5 }\n")
  assert_eq(m2, "invalid size specifier s in data")
}

///|
// C parselnk keeps the Tstr token text with its quotes, which keeps a present
// but empty section ("") distinct from no section, and lets the parser reject
// a second section keyword.
test "audit3: section text is stored verbatim like parse.c" {
  let (funcs, datas, _) = audit3_parse(
    "section \"my sec\" \"aw\" data $d = { w 1 }\nsection \"\" export function $f() {\n@start\n  ret\n}\n",
  )
  assert_eq(funcs[0].sec, "\"\"")
  assert_eq(funcs[0].is_export, true)
  let name = datas[1]
  assert_eq(name.sec, "\"my sec\"")
  assert_eq(name.secf, "\"aw\"")
  let m1 = audit3_parse_reject(
    "section \"a\" section \"b\" data $d = { w 1 }\n",
  )
  assert_true(m1.contains("only one section allowed"))
  let m2 = audit3_parse_reject("section \"\" section \"\" data $d = { w 1 }\n")
  assert_true(m2.contains("only one section allowed"))
}

///|
// C all.h NIns: the parser rejects the instruction that does not fit in the
// shared insb[] buffer (the port used growable arrays with no limit).
test "audit3: NIns instruction buffer limit" {
  let f = @types.Fn::new("f")
  let b = f.add_blk("start")
  f.def_order.push(b)
  let p = Parser::new(@lexer.Lexer::new("", "test").tokenize(), "test")
  p.curfn = Some(f)
  p.curblk = b
  p.blk_nins = NINS - 1
  let ins = @types.Ins::new_void(
    @types.Copy,
    @types.Kw,
    @types.Ref::none(),
    @types.Ref::none(),
  )
  p.emit_ins(ins)
  assert_eq(p.blk_nins, NINS)
  try p.emit_ins(ins) catch {
    @util.QbeError::ParseError(_, _, msg) =>
      assert_true(msg.contains("too many instructions"))
    _ => fail("expected a parse error")
  } noraise {
    _ => fail("expected the NIns limit to raise")
  }
}

///|
// The parser's token cursor must behave like the C lexer at end of input:
// repeated next() calls keep returning Teof instead of running off the array.
test "audit3: end of input is a stable Teof" {
  let p = Parser::new(
    @lexer.Lexer::new("function $f() {\n@start\n  %x =sb call", "test").tokenize(),
    "test",
  )
  // The reference rejects this with "( expected, got ?? instead"; any panic
  // (array out of bounds) would escape as a non-ParseError.
  try p.parse() catch {
    @util.QbeError::ParseError(_, _, msg) =>
      assert_true(msg.contains("( expected"))
    _ => fail("expected a parse error")
  } noraise {
    _ => fail("expected a parse error")
  }
}
