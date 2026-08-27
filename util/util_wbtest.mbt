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
test "fmt_fixed formats with round half to even" {
  assert_true(fmt_fixed(3.14, 2) == "3.14")
  assert_true(fmt_fixed(3.14159, 2) == "3.14")
  assert_true(fmt_fixed(2.5, 0) == "2.0")
  assert_true(fmt_fixed(3.5, 0) == "4.0")
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
