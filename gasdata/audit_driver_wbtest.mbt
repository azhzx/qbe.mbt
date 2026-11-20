///|
// vendor/qbe/emit.c:24-46: synthesized Apple TLS section has raw fields.
test "audit driver: Apple TLS section preserves section type field" {
  let sb = StringBuilder::StringBuilder()
  let n = @types.Dat::name("x", false)
  n.is_thread = true
  emit(@types.Dat::start(), "_", true, sb)
  emit(n, "_", true, sb)
  emit(@types.Dat::byte(1), "_", true, sb)
  emit(@types.Dat::end(), "_", true, sb)
  assert_true(
    sb
    .to_string()
    .contains(".section __DATA,__thread_data,thread_local_regular\n"),
  )
}

///|
test "audit driver: user sections retain token quoting" {
  let sb = StringBuilder::StringBuilder()
  let n = @types.Dat::name("x", false)
  // The parser stores parse.c's raw token text, quotes included.
  n.sec = "\".custom\""
  n.secf = "\"aw\""
  emit(@types.Dat::start(), "", false, sb)
  emit(n, "", false, sb)
  emit(@types.Dat::byte(1), "", false, sb)
  emit(@types.Dat::end(), "", false, sb)
  assert_true(sb.to_string().contains(".section \".custom\",\"aw\"\n"))
}

///|
// parse.c stores the Tstr token raw, so `section ""` is the two-character
// string `""`, not the empty string: it must not fall back to .data.
test "audit driver: present-but-empty section is not absent" {
  let sb = StringBuilder::StringBuilder()
  let n = @types.Dat::name("x", false)
  n.sec = "\"\""
  emit(@types.Dat::start(), "", false, sb)
  emit(n, "", false, sb)
  emit(@types.Dat::byte(1), "", false, sb)
  emit(@types.Dat::end(), "", false, sb)
  assert_true(sb.to_string().contains(".section \"\"\n"))
}

///|
test "audit driver: present-but-empty section flags are printed" {
  let sb = StringBuilder::StringBuilder()
  let n = @types.Dat::name("x", false)
  n.sec = "\"x\""
  n.secf = "\"\""
  emit(@types.Dat::start(), "", false, sb)
  emit(n, "", false, sb)
  emit(@types.Dat::byte(1), "", false, sb)
  emit(@types.Dat::end(), "", false, sb)
  assert_true(sb.to_string().contains(".section \"x\",\"\"\n"))
}

///|
test "audit driver: absent section falls back to .data" {
  let sb = StringBuilder::StringBuilder()
  let n = @types.Dat::name("x", false)
  emit(@types.Dat::start(), "", false, sb)
  emit(n, "", false, sb)
  emit(@types.Dat::byte(1), "", false, sb)
  emit(@types.Dat::end(), "", false, sb)
  assert_true(sb.to_string().contains(".data\n"))
  assert_true(!sb.to_string().contains(".section"))
}
