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
  n.sec = ".custom"
  n.secf = "aw"
  emit(@types.Dat::start(), "", false, sb)
  emit(n, "", false, sb)
  emit(@types.Dat::byte(1), "", false, sb)
  emit(@types.Dat::end(), "", false, sb)
  assert_true(sb.to_string().contains(".section \".custom\",\"aw\"\n"))
}
