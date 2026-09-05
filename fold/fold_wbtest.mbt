///|
// White-box tests for constant folding of individual operations.

///|
// Assert that a folded constant is CBits with the given integer value.
fn check_int(r : (Bool, @types.Con), expected : Int64) -> Unit raise {
  assert_true(!r.0)
  let c = r.1
  assert_true(c.kind == @types.CBits)
  assert_true(c.bits.i == expected)
}

///|
test "foldint arithmetic" {
  check_int(
    foldint(@types.Add, false, @types.Con::int(2), @types.Con::int(3)),
    5,
  )
  check_int(
    foldint(@types.Sub, false, @types.Con::int(10), @types.Con::int(4)),
    6,
  )
  check_int(
    foldint(@types.Mul, true, @types.Con::int(6), @types.Con::int(7)),
    42,
  )
  check_int(
    foldint(@types.Div, false, @types.Con::int(7), @types.Con::int(2)),
    3,
  )
  check_int(
    foldint(@types.Rem, false, @types.Con::int(7), @types.Con::int(2)),
    1,
  )
}

///|
test "foldint bitwise and shifts" {
  check_int(
    foldint(@types.And, false, @types.Con::int(0b1100), @types.Con::int(0b1010)),
    0b1000,
  )
  check_int(
    foldint(@types.Or, false, @types.Con::int(0b1100), @types.Con::int(0b0011)),
    0b1111,
  )
  check_int(
    foldint(@types.Xor, false, @types.Con::int(0b1111), @types.Con::int(0b0101)),
    0b1010,
  )
  check_int(
    foldint(@types.Shl, false, @types.Con::int(1), @types.Con::int(4)),
    16,
  )
  check_int(
    foldint(@types.Shr, false, @types.Con::int(16), @types.Con::int(4)),
    1,
  )
  check_int(
    foldint(@types.Sar, false, @types.Con::int(-16), @types.Con::int(2)),
    -4,
  )
}

///|
test "foldint word comparisons" {
  check_int(
    foldint(@types.Ceqw, false, @types.Con::int(3), @types.Con::int(3)),
    1,
  )
  check_int(
    foldint(@types.Cnew, false, @types.Con::int(3), @types.Con::int(4)),
    1,
  )
  check_int(
    foldint(@types.Csltw, false, @types.Con::int(3), @types.Con::int(4)),
    1,
  )
  check_int(
    foldint(@types.Csltw, false, @types.Con::int(4), @types.Con::int(3)),
    0,
  )
  check_int(
    foldint(@types.Csgew, false, @types.Con::int(4), @types.Con::int(3)),
    1,
  )
  check_int(
    foldint(@types.Cugtw, false, @types.Con::int(-1), @types.Con::int(1)),
    1,
  )
  // Word comparisons sign-extend the low 32 bits.
  check_int(
    foldint(
      @types.Ceqw,
      false,
      @types.Con::int(0x1_0000_0001),
      @types.Con::int(1),
    ),
    1,
  )
}

///|
test "foldint long comparisons" {
  check_int(
    foldint(@types.Ceql, true, @types.Con::int(7), @types.Con::int(7)),
    1,
  )
  check_int(
    foldint(@types.Csgtl, true, @types.Con::int(8), @types.Con::int(7)),
    1,
  )
  check_int(
    foldint(@types.Cultl, true, @types.Con::int(2), @types.Con::int(3)),
    1,
  )
  check_int(
    foldint(@types.Cultl, true, @types.Con::int(-1), @types.Con::int(2)),
    0,
  )
}

///|
test "foldint unsigned division" {
  // -1 / 2 as unsigned is a huge quotient.
  let r = foldint(@types.Udiv, true, @types.Con::int(-1), @types.Con::int(2))
  assert_true(!r.0)
  assert_true(r.1.bits.i == 9223372036854775807)
  let (bot, _) = foldint(
    @types.Urem,
    true,
    @types.Con::int(5),
    @types.Con::int(3),
  )
  assert_true(!bot)
}

///|
test "foldint extensions" {
  check_int(
    foldint(@types.Extsb, false, @types.Con::int(0xFF), @types.Con::int(0)),
    -1,
  )
  check_int(
    foldint(@types.Extub, false, @types.Con::int(0x1FF), @types.Con::int(0)),
    0xFF,
  )
  check_int(
    foldint(
      @types.Extsw,
      false,
      @types.Con::int(0x80000000),
      @types.Con::int(0),
    ),
    -2147483648,
  )
  check_int(
    foldint(@types.Extuw, false, @types.Con::int(-1), @types.Con::int(0)),
    0xFFFFFFFF,
  )
}

///|
test "foldint address arithmetic keeps label" {
  // addr + offset keeps the label and kind.
  let r = foldint(@types.Add, true, @types.Con::addr(3), @types.Con::int(4))
  assert_true(!r.0)
  assert_true(r.1.kind == @types.CAddr)
  assert_true(r.1.label == 3)
  assert_true(r.1.bits.i == 4)
  // addr - addr with different labels is an ICE.
  try
    foldint(@types.Sub, true, @types.Con::addr(1), @types.Con::addr(2))
  catch {
    @util.QbeError::Ice(_) => ()
    _ => fail("expected ICE for addr1 - addr2")
  } noraise {
    _ => fail("expected ICE for addr1 - addr2")
  }
}

///|
test "null divisor raises an ICE during folding" {
  // folding `div 1, 0` must surface an error, not trap the compiler
  let src =
    #|function w $f() {
    #|@start
    #|  %x =w div 1, 0
    #|  ret %x
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  try fold(f, false, parser.interner_ref(), []) catch {
    @util.QbeError::Ice(_) => ()
    _ => fail("expected ICE for a null divisor")
  } noraise {
    _ => fail("expected ICE for a null divisor")
  }
}

///|
test "foldint signed word comparisons sign-extend operands" {
  // -1 as a 32-bit word compares less than 1 once sign-extended
  let m1 = 0xFFFFFFFFL
  check_int(
    foldint(@types.Csltw, false, @types.Con::int(m1), @types.Con::int(1)),
    1,
  )
  // the same bits compared unsigned are much greater
  check_int(
    foldint(@types.Cultw, false, @types.Con::int(m1), @types.Con::int(1)),
    0,
  )
}

///|
test "foldint address arithmetic produces CAddr labels" {
  let a = @types.Con::addr(7)
  let r = foldint(@types.Add, false, a, @types.Con::int(4))
  assert_true(!r.0)
  assert_true(r.1.kind == @types.CAddr)
  assert_true(r.1.label == 7)
  // addr + addr is a compile-time error
  try foldint(@types.Add, false, a, a) catch {
    @util.QbeError::Ice(_) => ()
    _ => fail("expected ICE for addr + addr")
  } noraise {
    _ => fail("expected ICE for addr + addr")
  }
}

///|
test "foldflt folds double and single arithmetic" {
  let one = @types.Con::double(1.0)
  let two = @types.Con::double(2.0)
  let d = foldflt(@types.Add, true, one, two)
  assert_true(d.kind == @types.CBits)
  assert_eq(con_double(d), 3.0)
  let half = foldflt(
    @types.Div,
    false,
    @types.Con::single(1.0),
    @types.Con::single(2.0),
  )
  assert_eq(con_single(half), 0.5)
}

///|
test "comparison predicate classification" {
  assert_true(is_word_cmp(@types.Ceqw) && is_word_cmp(@types.Cultw))
  assert_true(!is_word_cmp(@types.Ceql))
  assert_true(is_long_cmp(@types.Ceql) && is_long_cmp(@types.Cugel))
  assert_true(!is_long_cmp(@types.Ceqw))
  assert_true(is_single_cmp(@types.Ceqs) && !is_single_cmp(@types.Ceqd))
  assert_true(is_double_cmp(@types.Ceqd) && !is_double_cmp(@types.Ceqs))
}

///|
test "sext32 sign-extends the low word" {
  assert_eq(sext32(0xFFFFFFFFL), -1L)
  assert_eq(sext32(5L), 5L)
  assert_eq(sext32(0x80000000L), -2147483648L)
}
