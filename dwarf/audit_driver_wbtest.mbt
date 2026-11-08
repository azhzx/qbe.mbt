///|
// UTF-8 é occupies two bytes; UTF-16 String.length reports one.
test "audit driver: DWARF unit and type offsets count UTF8 bytes" {
  reset()
  record_fn("f", "begin", "end", [
    DbgLoc::{ name: "v", ty: @types.DbgW, kind: 0, value: 0, },
  ])
  let ascii = StringBuilder::StringBuilder()
  emit_debug_info(".L", "u", ".", false, ascii)
  let unicode = StringBuilder::StringBuilder()
  emit_debug_info(".L", "é", ".", false, unicode)
  // Header + CU is 46 bytes for ASCII, 47 for this UTF-8 name.
  assert_true(ascii.to_string().contains("\t.long 46\n"))
  assert_true(unicode.to_string().contains("\t.long 47\n"))
}
