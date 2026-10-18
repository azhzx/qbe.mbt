///|
test "decode_data_string handles escapes and plain text" {
  assert_eq(decode_data_string("abc"), [97, 98, 99])
  assert_eq(decode_data_string("a\\nb"), [97, 10, 98])
  assert_eq(decode_data_string("\\t"), [9])
  assert_eq(decode_data_string("\\x41\\x42"), [65, 66])
  assert_eq(decode_data_string("\\101"), [65])
  // A byte above 0x7f must survive the char round trip.
  assert_eq(decode_data_string("\\xff"), [255])
}
