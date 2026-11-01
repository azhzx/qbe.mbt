///|
test "decode_data_string handles escapes and plain text" {
  assert_eq(decode_data_string("abc"), [97, 98, 99])
  assert_eq(decode_data_string("a\\nb"), [97, 10, 98])
  assert_eq(decode_data_string("\\t"), [9])
  assert_eq(decode_data_string("\\x41\\x42"), [65, 66])
  assert_eq(decode_data_string("\\101"), [65])
  // the assembler decodes these named escapes too, so the object image must
  assert_eq(decode_data_string("\\b\\f"), [8, 12])
  assert_eq(decode_data_string("\\r\\\\\\\""), [13, 92, 34])
  assert_eq(decode_data_string("\\xff"), [255])
  // a decoded C string can hold a literal backslash before a letter; the
  // object writer must not read that back as an escape. Qiang escapes it as
  // \\ before handing the text over, and that is what this asserts.
  assert_eq(decode_data_string("\\\\a"), [92, 97])
  assert_eq(decode_data_string("\\\\n"), [92, 110])
  // control bytes arrive as fixed-width octal, which the assembler accepts
  assert_eq(decode_data_string("\\007\\033\\013"), [7, 27, 11])
}
