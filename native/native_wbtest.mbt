///|
// Native shim tests: executable memory and symbol lookup.

///|
fn host_ok() -> Bool {
  mbt_native_host_supported() != 0
}

///|
test "run-asm: mmap + write + call a hand-encoded aarch64 stub" {
  if !host_ok() {
    return
  }
  // mov x0, #42 ; ret
  let code : Bytes = b"\x40\x05\x80\xd2\xc0\x03\x5f\xd6"
  let addr = mbt_native_alloc(16)
  if addr == 0L {
    abort("run-asm: mmap failed")
  }
  mbt_native_write_bytes(addr, 0, code)
  assert_eq(mbt_native_protect(addr, 16), 0)
  assert_eq(mbt_native_call_i64_1(addr, 0L), 42L)
  mbt_native_free(addr, 16)
}

///|
test "run-asm: dlsym resolves a libc symbol" {
  let p = mbt_native_sym(b"malloc")
  assert_true(p != 0L)
}
