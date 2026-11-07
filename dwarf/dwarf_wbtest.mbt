///|
fn count_substring(s : String, needle : String) -> Int32 {
  s.split(needle).count() - 1
}

///|
test "dwarf: each variable location list has its own terminator" {
  reset()
  record_fn("f", "Lbegin", "Lend", [
    DbgLoc::{ name: "a", ty: @types.DbgL, kind: 0, value: 0, },
    DbgLoc::{ name: "b", ty: @types.DbgL, kind: 0, value: 1, },
  ])
  let sb = StringBuilder::StringBuilder()
  emit_debug_info("L", "unit", "/tmp", false, sb)
  assert_eq(count_substring(sb.to_string(), "\t.quad 0\n\t.quad 0\n"), 2)
}

///|
test "dwarf: aggregate byte size is not truncated to one byte" {
  reset()
  record_fn("f", "Lbegin", "Lend", [
    DbgLoc::{ name: "big", ty: @types.DbgAgg("Big", 300), kind: 1, value: -8, },
  ])
  let sb = StringBuilder::StringBuilder()
  emit_debug_info("L", "unit", "/tmp", false, sb)
  assert_true(sb.to_string().contains("\t.long 300\n"))
}

///|
test "dwarf: emitted asciz strings escape assembler metacharacters" {
  reset()
  record_fn("f\"\\name", "Lbegin", "Lend", [
    DbgLoc::{
      name: "v\"\\name",
      ty: @types.DbgAgg("T\"\\name", 8),
      kind: 0,
      value: 0,
    },
  ])
  let sb = StringBuilder::StringBuilder()
  emit_debug_info("L", "u\"\\nit", "d\"\\ir", false, sb)
  let text = sb.to_string()
  assert_true(text.contains("\t.asciz \"u\\\"\\\\nit\"\n"))
  assert_true(text.contains("\t.asciz \"f\\\"\\\\name\"\n"))
  assert_true(text.contains("\t.asciz \"v\\\"\\\\name\"\n"))
  assert_true(text.contains("\t.asciz \"T\\\"\\\\name\"\n"))
}
