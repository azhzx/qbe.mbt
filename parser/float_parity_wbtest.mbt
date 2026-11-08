///|
test "audit float: decimal single rounds directly without double rounding" {
  let (_, f, error) = parse_float_literal("s_1.0000000596046448")
  assert_eq(error, "")
  assert_eq(f.reinterpret_as_uint(), 0x3f800001U)
}

///|
test "audit float: hexadecimal single subnormal rounds only once" {
  let (_, f, error) = parse_float_literal("s_0x1.000001p-150")
  assert_eq(error, "")
  assert_eq(f.reinterpret_as_uint(), 1U)
}

///|
test "audit float: hexadecimal double subnormal rounds only once" {
  let (d, _, error) = parse_float_literal("d_0x1.00000000000008p-1075")
  assert_eq(error, "")
  assert_eq(d.reinterpret_as_int64(), 1L)
}

///|
test "audit float: decimal overflow is infinity rather than syntax error" {
  let (d, _, error) = parse_float_literal("d_1e309")
  assert_eq(error, "")
  assert_eq(d.reinterpret_as_int64(), 0x7ff0000000000000L)
}
