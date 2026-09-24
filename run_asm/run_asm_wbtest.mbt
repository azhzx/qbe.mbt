///|
// P0 spike: MoonBit can allocate executable memory, write machine code into
// it, and call the resulting address. aarch64 only (skipped elsewhere).

///|
fn host_ok() -> Bool {
  mbt_run_asm_host_supported() != 0
}

///|
test "run-asm: mmap + write + call a hand-encoded aarch64 stub" {
  if !host_ok() {
    return
  }
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
  if !host_ok() {
    return
  }
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
  assert_eq(obj[0].to_int(), 0xCF)
  assert_eq(obj[1].to_int(), 0xFA)
  assert_eq(obj[2].to_int(), 0xED)
  assert_eq(obj[3].to_int(), 0xFE)
}

///|
// route A: assembly text -> dylib -> call
test "run-asm: load shared module and call a function" {
  if !host_ok() {
    return
  }
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
