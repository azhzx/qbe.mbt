///|
// P0 spike: prove that MoonBit can allocate executable memory, write machine
// code into it, and call the resulting address.

///|
test "run-asm: mmap + write + call a hand-encoded aarch64 stub" {
  // mov x0, #42 ; ret
  let code : Bytes = b"\x40\x05\x80\xd2\xc0\x03\x5f\xd6"
  let addr = mbt_run_asm_alloc(16)
  if addr == 0L {
    abort("run-asm: mmap failed")
  }
  mbt_run_asm_write_bytes(addr, 0, code)
  assert_eq(mbt_run_asm_protect(addr, 16), 0)
  assert_eq(mbt_run_asm_call_i64_1(addr, 0L), 42L)
  mbt_run_asm_free(addr, 16)
}

///|
test "run-asm: dlsym resolves a libc symbol" {
  let p = mbt_run_asm_sym(b"malloc")
  assert_true(p != 0L)
}

///|
// route A: assembly text -> .o bytes
test "run-asm: assemble text into a Mach-O object" {
  let src =
    #|.text
    #|.balign 4
    #|.globl _add1
    #|_add1:
    #|	add	x0, x0, #1
    #|	ret
    #|
  let obj = assemble_object(src)
  assert_true(obj.length() > 0)
  // Mach-O magic, little-endian MH_MAGIC_64 = 0xfeedfacf
  assert_eq(obj[0].to_int(), 0xcf)
  assert_eq(obj[1].to_int(), 0xfa)
  assert_eq(obj[2].to_int(), 0xed)
  assert_eq(obj[3].to_int(), 0xfe)
}

///|
// route A: assembly text -> dylib -> call
test "run-asm: load shared module and call a function" {
  let src =
    #|.text
    #|.balign 4
    #|.globl _add1
    #|_add1:
    #|	add	x0, x0, #1
    #|	ret
    #|
  let m = RunAsmModule::load_shared(src)
  assert_eq(m.call1("add1", 41L), 42L)
}
