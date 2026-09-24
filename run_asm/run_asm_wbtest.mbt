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

///|
// route B: source -> binary arm64 words -> executable memory -> call. No
// assembler, linker or clang anywhere in this path.
test "route B: self-contained binary sum_to runs" {
  if !host_ok() {
    return
  }
  let src =
    #|export
    #|function w $sum_to(w %n) {
    #|@start
    #|  %i =w copy 0
    #|  %s =w copy 0
    #|@loop
    #|  %i2 =w phi @start %i, @body %i3
    #|  %s2 =w phi @start %s, @body %s3
    #|  %c =w cslew %i2, %n
    #|  jnz %c, @body, @end
    #|@body
    #|  %s3 =w add %s2, %i2
    #|  %i3 =w add %i2, 1
    #|  jmp @loop
    #|@end
    #|  ret %s2
    #|}
    #|
  let words = @qbe.compile_arm64_bin(src) catch {
    e => abort("route B compile failed: {Repr(e)}")
  }
  assert_eq(words.length(), 1)
  let m = ExecBlock::load_text(@object.words_to_bytes(words[0]))
  assert_eq(m.call1(0L), 0L)
  assert_eq(m.call1(10L), 55L)
  assert_eq(m.call1(100L), 5050L)
  assert_eq(m.call1(1000L), 500500L)
}

///|
// route B: recursion and cross-function calls in one linked binary module.
test "route B: binary module links recursion and cross-function calls" {
  if !host_ok() {
    return
  }
  let src =
    #|export
    #|function w $fact(w %n) {
    #|@start
    #|  %c =w csgtw %n, 1
    #|  jnz %c, @rec, @base
    #|@base
    #|  ret 1
    #|@rec
    #|  %m =w sub %n, 1
    #|  %r =w call $fact(w %m)
    #|  %res =w mul %n, %r
    #|  ret %res
    #|}
    #|
    #|function w $twice(w %x) {
    #|@start
    #|  %y =w mul %x, 2
    #|  ret %y
    #|}
    #|
    #|export
    #|function w $plus_one(w %x) {
    #|@start
    #|  %t =w call $twice(w %x)
    #|  %r =w add %t, 1
    #|  ret %r
    #|}
    #|
  let m = @qbe.compile_arm64_bin_module(src) catch {
    _ => abort("route B module compile failed")
  }
  let blk = ExecBlock::load_text(@object.words_to_bytes(m.words))
  let mut fact_off = 0
  let mut plus_off = 0
  for f in m.fns {
    if f.0 == "fact" {
      fact_off = f.1
    }
    if f.0 == "plus_one" {
      plus_off = f.1
    }
  }
  assert_eq(blk.call1_at(fact_off, 0L), 1L)
  assert_eq(blk.call1_at(fact_off, 5L), 120L)
  assert_eq(blk.call1_at(fact_off, 10L), 3628800L)
  assert_eq(blk.call1_at(plus_off, 20L), 41L)
}

///|
// route B: global data laid out in the same executable image, with adrp/add
// addresses patched at link time.
test "route B: binary module handles global data" {
  if !host_ok() {
    return
  }
  let src =
    #|data $g = { w 0 }
    #|data $nums = { w 1, w 2, w 3, w 4 }
    #|export
    #|function w $global_demo() {
    #|@start
    #|  %x =w loadw $g
    #|  %x2 =w add %x, 1
    #|  storew %x2, $g
    #|  %r =w loadw $g
    #|  ret %r
    #|}
    #|
    #|export
    #|function l $sum_nums() {
    #|@start
    #|  %a =l load $nums
    #|  ret %a
    #|}
    #|
  let m = @qbe.compile_arm64_bin_module(src) catch {
    _ => abort("route B data compile failed")
  }
  let blk = ExecBlock::load_module(m.image(), m.code_bytes)
  let mut g_off = 0
  let mut nums_off = 0
  for f in m.fns {
    if f.0 == "global_demo" {
      g_off = f.1
    }
    if f.0 == "sum_nums" {
      nums_off = f.1
    }
  }
  assert_eq(blk.call1_at(g_off, 0L), 1L)
  assert_eq(blk.call1_at(g_off, 0L), 2L)
  // Little-endian first two words of $nums: 0x0000000200000001.
  assert_eq(blk.call1_at(nums_off, 0L), 8589934593L)
}
