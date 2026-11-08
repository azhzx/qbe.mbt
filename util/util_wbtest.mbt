///|
// White-box unit tests for the util package helpers.

///|
test "Interner interning is stable" {
  let it = Interner::new()
  let a = it.intern("hello")
  let b = it.intern("world")
  let c = it.intern("hello")
  assert_true(a == 0 && b == 1)
  assert_true(a == c)
  assert_true(it.get(a) == "hello")
  assert_true(it.get(b) == "world")
}

///|
test "Interner handles empty and unicode strings" {
  let it = Interner::new()
  let e = it.intern("")
  let u = it.intern("符号")
  assert_true(e == 0 && u == 1)
  assert_true(it.get(u) == "符号")
}

///|
test "lpad pads and truncates" {
  assert_true(lpad("ab", 4) == "ab  ")
  assert_true(lpad("abcd", 4) == "abcd")
  assert_true(lpad("abcde", 4) == "abcde")
  assert_true(lpad("", 2) == "  ")
}

///|
test "rpad right-justifies integers" {
  assert_true(rpad(7, 3) == "  7")
  assert_true(rpad(123, 3) == "123")
  assert_true(rpad(1234, 3) == "1234")
  assert_true(rpad(-5, 4) == "  -5")
}

///|
// The formatter must handle values above 2^63 (it used to saturate through
// Int64, printing FLT_MAX as 9223372036854.775807) and C's special values.
test "fmt_fixed handles large, special and signed-zero values" {
  assert_true(
    fmt_fixed(3.4028234663852886e38, 6) ==
    "340282346638528859811704183484516925440.000000",
  )
  assert_true(fmt_fixed(1.0 / 0.0, 6) == "inf")
  assert_true(fmt_fixed(-1.0 / 0.0, 6) == "-inf")
  // IEEE leaves the sign of 0.0/0.0 unspecified: x86 yields -nan while
  // arm64 yields +nan, so construct both NaNs from bits instead.
  let qnan = 0x7FF8000000000000UL.reinterpret_as_int64().reinterpret_as_double()
  assert_true(fmt_fixed(qnan, 6) == "nan")
  let nnan = 0xFFF8000000000000UL.reinterpret_as_int64().reinterpret_as_double()
  assert_true(fmt_fixed(nnan, 6) == "-nan")
  assert_true(fmt_fixed(-0.0, 6) == "-0.000000")
  assert_true(fmt_fixed(5.0e-324, 6) == "0.000000")
}

///|
test "fmt_fixed formats with round half to even" {
  assert_true(fmt_fixed(3.14, 2) == "3.14")
  assert_true(fmt_fixed(3.14159, 2) == "3.14")
  // C printf("%.0f") prints no decimal point.
  assert_true(fmt_fixed(2.5, 0) == "2")
  assert_true(fmt_fixed(3.5, 0) == "4")
  assert_true(fmt_fixed(0.125, 3) == "0.125")
  assert_true(fmt_fixed(1.0, 4) == "1.0000")
  assert_true(fmt_fixed(-1.5, 1) == "-1.5")
  assert_true(fmt_fixed(123.456, 1) == "123.5")
}

///|
test "QbeError constructors are distinct" {
  let p = QbeError::ParseError("f", 2, "msg")
  let c = QbeError::CompileError("oops")
  let i = QbeError::Ice("ice")
  assert_true(p is QbeError::ParseError("f", 2, "msg"))
  assert_true(c is QbeError::CompileError("oops"))
  assert_true(i is QbeError::Ice("ice"))
}

///|
test "emit_dbgfile dedups and numbers files" {
  dbg_reset()
  let sb = StringBuilder::StringBuilder()
  emit_dbgfile("a.c", sb)
  emit_dbgfile("a.c", sb)
  emit_dbgfile("b.c", sb)
  assert_eq(sb.to_string(), ".file 1 \"a.c\"\n.file 2 \"b.c\"\n")
}

///|
test "emit_dbgloc uses the current file number" {
  dbg_reset()
  let sb = StringBuilder::StringBuilder()
  emit_dbgfile("a.c", sb)
  emit_dbgloc(7, 0, sb)
  emit_dbgloc(9, 3, sb)
  assert_eq(sb.to_string(), ".file 1 \"a.c\"\n\t.loc 1 7\n\t.loc 1 9 3\n")
}
