///|
// White-box tests for the IL parser and pretty-printer.

///|
// Parse a full module and return (funcs, datas, typs).
fn parse_all(
  src : String,
) -> (Array[@types.Fn], Array[@types.Dat], Array[@types.Typ], @util.Interner) raise {
  let tokens = @lexer.Lexer::new(src, "test").tokenize()
  let p = Parser::new(tokens, "test")
  p.parse()
  (p.get_funcs(), p.get_datas(), p.get_typs(), p.interner_ref())
}

///|
test "parse a simple function" {
  let src =
    #|export function w $add(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (funcs, datas, _, _) = parse_all(src)
  assert_true(funcs.length() == 1)
  assert_true(datas.length() == 0)
  let f = funcs[0]
  assert_true(f.name == "add")
  assert_true(f.is_export)
  assert_true(f.nblk() == 1)
  assert_true(f.blks[0].name == "start")
  // 64 register temps + 2 params + result temp
  assert_true(f.ntmp() == 67)
  // Par instructions for %a/%b are prepended to the start block.
  assert_true(f.blks[0].ins.length() == 3)
  assert_true(f.blks[0].ins[0].op == @types.Par)
  let ins = f.blks[0].ins[2]
  assert_true(ins.op == @types.Add)
  assert_true(ins.cls == @types.Kw)
  assert_true(ins.to.is_tmp())
  assert_true(f.blks[0].jmp.kind == @types.Jretw)
}

///|
test "parse function with phi and branch" {
  let src =
    #|function l $sum(l %n) {
    #|@start
    #|  %a =l add %n, 1
    #|  jnz %a, @then, @else
    #|@then
    #|  jmp @merge
    #|@else
    #|  jmp @merge
    #|@merge
    #|  %r =l phi @then %a, @else 2
    #|  ret %r
    #|}
    #|
  let (funcs, _, _, _) = parse_all(src)
  let f = funcs[0]
  assert_true(f.nblk() == 4)
  assert_true(f.blks[0].jmp.kind == @types.Jjnz)
  assert_true(f.blks[3].phi.length() == 1)
  assert_true(f.blks[3].phi[0].args.length() == 2)
  assert_true(f.blks[3].jmp.kind == @types.Jretl)
}

///|
test "parse data section" {
  let src =
    #|data $msg = { b "hello", b 0 }
    #|
  let (funcs, datas, _, _) = parse_all(src)
  assert_true(funcs.length() == 0)
  // DStart + DName + 2*DB + DEnd = 5 items
  assert_true(datas.length() == 5)
  assert_true(datas[0].kind == @types.DStart)
  assert_true(datas[1].kind == @types.DName)
  assert_true(datas[1].str == "msg")
}

///|
test "parse type definition" {
  let src =
    #|type :Pair = { w 4, l 8 }
    #|
  let (funcs, _, typs, _) = parse_all(src)
  assert_true(funcs.length() == 0)
  assert_true(typs.length() == 1)
  assert_true(typs[0].name == "Pair")
  assert_true(typs[0].size > 0)
}

///|
test "printfn spells the return jump with its class" {
  // The reference printer emits retw/ret0 (printfn in parse.c), and its lexer
  // only accepts the bare "ret" keyword, so printed output is not meant to be
  // parsed back; check the spelling instead.
  let src =
    #|export function w $one() {
    #|@start
    #|  %s =w add 1, 2
    #|  ret %s
    #|}
    #|
  let (funcs, _, _, interner) = parse_all(src)
  let printed = printfn(funcs[0], interner, [])
  assert_true(printed.contains("$one"))
  assert_true(printed.contains("add 1, 2"))
  assert_true(printed.contains("retw"))
  let void_src =
    #|export function w $f() {
    #|@start
    #|  ret
    #|}
    #|
  let (funcs2, _, _, interner2) = parse_all(void_src)
  let printed2 = printfn(funcs2[0], interner2, [])
  assert_true(printed2.contains("ret0"))
}

///|
test "bare ret in a non-void function becomes ret0" {
  // C parse.c: a Tret followed by a newline sets Jret0 regardless of the
  // declared function return class.
  let src =
    #|function w $f() {
    #|@start
    #|  ret
    #|}
    #|
  let (funcs, _, _, _) = parse_all(src)
  assert_true(funcs[0].blks[0].jmp.kind == @types.Jret0)
}

///|
test "data references retain positive offsets" {
  let src =
    #|data $p = { l $base + 8 }
    #|
  let (funcs, datas, _, _) = parse_all(src)
  assert_eq(funcs.length(), 0)
  assert_true(datas[2].is_ref)
  assert_eq(datas[2].ref_offset, 8L)
}

///|
test "parse errors raise QbeError" {
  let tokens = @lexer.Lexer::new("function w %bad\n", "test").tokenize()
  let p = Parser::new(tokens, "test")
  try p.parse() catch {
    @util.QbeError::ParseError(file, line, _) => {
      assert_true(file == "test")
      assert_true(line >= 1)
    }
    _ => fail("expected a parse error")
  } noraise {
    _ => fail("expected a parse error")
  }
}

///|
test "duplicate block names rejected" {
  let src =
    #|function w $f() {
    #|@start
    #|  ret 0
    #|@start
    #|  ret 0
    #|}
    #|
  let tokens = @lexer.Lexer::new(src, "test").tokenize()
  let p = Parser::new(tokens, "test")
  try p.parse() catch {
    @util.QbeError::ParseError(_, _, _) => ()
    _ => fail("expected a parse error")
  } noraise {
    _ => fail("expected a parse error")
  }
}

///|
test "parse errors carry the source line" {
  let src =
    #|function w $f() {
    #|@start
    #|  !
    #|  ret 0
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "bad.ssa")
  let parser = Parser::new(lexer.tokenize(), "bad.ssa")
  try parser.parse() catch {
    @util.QbeError::ParseError(f, line, _) => {
      assert_eq(f, "bad.ssa")
      assert_true(line == 3)
    }
    _ => fail("expected a ParseError")
  } noraise {
    _ => fail("expected a ParseError")
  }
}

///|
test "parse multiple functions preserves module order" {
  let src =
    #|function w $first() {
    #|@start
    #|  ret 1
    #|}
    #|function w $second() {
    #|@start
    #|  ret 2
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "test")
  let parser = Parser::new(lexer.tokenize(), "test")
  parser.parse()
  let funcs = parser.get_funcs()
  assert_eq(funcs.length(), 2)
  assert_eq(funcs[0].name, "first")
  assert_eq(funcs[1].name, "second")
}

///|
test "dbgfile markers keep top-level order" {
  let src =
    #|function w $f() {
    #|@start
    #|  ret 0
    #|}
    #|dbgfile "a.c"
    #|function w $g() {
    #|@start
    #|  ret 0
    #|}
    #|dbgfile "a.c"
    #|dbgfile "b.c"
    #|
  let p = Parser::new(@lexer.Lexer::new(src, "test").tokenize(), "test")
  p.parse()
  let order = p.get_order()
  // Repeated paths are kept in the order list; the emitter dedups and numbers
  // them (C emit.c emitdbgfile).
  assert_eq(order.length(), 5)
  assert_eq(order[0], "f")
  assert_eq(order[1], "dbgfile:a.c")
  assert_eq(order[2], "f")
  assert_eq(order[3], "dbgfile:a.c")
  assert_eq(order[4], "dbgfile:b.c")
}

///|
test "dbgloc parses line and column" {
  let src =
    #|function w $f() {
    #|@start
    #|  dbgloc 7
    #|  dbgloc 9, 3
    #|  ret 0
    #|}
    #|
  let (funcs, _, _, _) = parse_all(src)
  let ins = funcs[0].blks[0].ins
  assert_eq(ins[0].op, @types.Dbgloc)
  assert_eq(ins[0].arg1.rint_val(), 7)
  assert_eq(ins[0].arg2.rint_val(), 0)
  assert_eq(ins[1].op, @types.Dbgloc)
  assert_eq(ins[1].arg1.rint_val(), 9)
  assert_eq(ins[1].arg2.rint_val(), 3)
}

///|
test "inline asm parses, prints and round-trips" {
  let src =
    #|export function l $f(l %a) {
    #|@start
    #|  %o =l asm "rbit %0, %1" (%a)
    #|  asm "dmb ish"
    #|  ret %o
    #|}
    #|
  let (funcs, _, _, interner) = parse_all(src)
  let f = funcs[0]
  let ins = f.blks[0].ins
  // Par, the asm with a result, the asm without one.
  assert_eq(ins.length(), 3)
  assert_eq(ins[1].op, @types.InlineAsm)
  assert_eq(ins[1].asm_text, "rbit %0, %1")
  assert_eq(ins[1].cls, @types.Kl)
  assert_true(ins[1].to.is_tmp())
  assert_true(ins[1].arg1.is_tmp())
  assert_eq(ins[2].op, @types.InlineAsm)
  assert_eq(ins[2].asm_text, "dmb ish")
  assert_true(ins[2].to.is_none())
  // The printer keeps the text and the operands.
  let printed = printfn(f, interner, [])
  assert_true(printed.contains("asm \"rbit %0, %1\" ("))
  assert_true(printed.contains("asm \"dmb ish\"\n"))
}

///|
test "printfn prints dbgloc" {
  let src =
    #|function w $f() {
    #|@start
    #|  dbgloc 7
    #|  dbgloc 9, 3
    #|  ret 0
    #|}
    #|
  let (funcs, _, _, interner) = parse_all(src)
  let printed = printfn(funcs[0], interner, [])
  assert_true(printed.contains("\tdbgloc 7, 0\n"))
  assert_true(printed.contains("\tdbgloc 9, 3\n"))
}

///|
// C parselnk accepts repeated linkage keywords before a definition.
test "repeated export is accepted" {
  let src =
    #|export
    #|export
    #|function w $f() {
    #|@start
    #|  ret 0
    #|}
    #|
  let (funcs, _, _, _) = parse_all(src)
  assert_eq(funcs.length(), 1)
  assert_true(funcs[0].is_export)
}

///|
test "export before a non-definition is rejected" {
  let src =
    #|export
    #|type :t = { w 4 }
    #|
  let tokens = @lexer.Lexer::new(src, "test").tokenize()
  let p = Parser::new(tokens, "test")
  try p.parse() catch {
    @util.QbeError::ParseError(_, _, msg) =>
      assert_true(msg.contains("only data and function have linkage"))
    _ => fail("expected a parse error")
  } noraise {
    _ => fail("expected a parse error")
  }
}

///|
// C keeps a data item's value in a union; the emitters print u.num, so float
// items must carry their bit pattern there (this used to emit .int 0 / .quad 0).
test "data: float items carry their bit pattern" {
  let src =
    #|data $c = { d d_0x1.8p1, s s_0x1p-1, s s_-0.0 }
    #|
  let (_, datas, _, _) = parse_all(src)
  let nums : Array[Int64] = []
  for d in datas {
    if !d.is_ref && !d.is_str && (d.kind == @types.DL || d.kind == @types.DW) {
      nums.push(d.num)
    }
  }
  assert_eq(nums.length(), 3)
  assert_eq(nums[0], 3.0.reinterpret_as_int64())
  assert_eq(nums[1], Float::from_double(0.5).reinterpret_as_uint().to_int64())
  assert_eq(nums[2], Float::from_double(-0.0).reinterpret_as_uint().to_int64())
}
