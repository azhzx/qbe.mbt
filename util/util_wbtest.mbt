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

///|
test "emit_debug_info writes a DWARF4 CU" {
  let sb = StringBuilder::StringBuilder()
  emit_debug_info(".L", "", "main", "t.c", ".", false, sb)
  let s = sb.to_string()
  // ELF section directives.
  assert_true(s.contains(".section .debug_abbrev,\"\",@progbits\n"))
  assert_true(s.contains(".section .debug_info,\"\",@progbits\n"))
  // Unit length: header 7 + abbrev 1 + producer 8 + lang 2 + name 4 + dir 2 +
  // low/high addr 16 + stmt_list 4 = 44.
  assert_true(s.contains("\t.long 44\n"))
  assert_true(s.contains("\t.short 4\n"))
  assert_true(s.contains(".asciz \"qbe.mbt\"\n"))
  assert_true(s.contains(".asciz \"t.c\"\n"))
  // The CU references the code range directly.
  assert_true(s.contains("\t.quad main\n"))
  assert_true(s.contains("\t.quad .Ldbgend\n"))
  // Mach-O uses the __DWARF segment form.
  let sb2 = StringBuilder::StringBuilder()
  emit_debug_info("L", "_", "main", "t.c", ".", true, sb2)
  assert_true(
    sb2.to_string().contains(".section __DWARF,__debug_info,regular,debug\n"),
  )
}
