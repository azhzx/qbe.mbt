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

///|
// route B: object emission -> Mach-O with relocations -> link with clang/ld
// and run. Only the final link uses the system toolchain; the object itself is
// built entirely by qbe.mbt.
test "route B: object emission links and runs" {
  if !host_ok() {
    return
  }
  let src =
    #|data $g = { w 7 }
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
    #|export
    #|function w $get_g() {
    #|@start
    #|  %x =w loadw $g
    #|  ret %x
    #|}
    #|
  let obj = @qbe.compile_arm64_object(src) catch {
    _ => abort("route B object compile failed")
  }
  assert_true(obj.length() > 0)
  write_file("/tmp/qbe_route_b.o", obj)
  let driver =
    #|int fact(int);
    #|int get_g(void);
    #|int main(void) { return (fact(5) == 120 && get_g() == 7) ? 0 : 1; }
    #|
  write_file("/tmp/qbe_route_b_driver.c", @utf8.encode(driver))
  assert_eq(
    run_command(
      "clang -o /tmp/qbe_route_b_exe /tmp/qbe_route_b.o /tmp/qbe_route_b_driver.c",
    ),
    0,
  )
  assert_eq(run_command("/tmp/qbe_route_b_exe"), 0)
}

///|
// route B: parallel-copy swap and a floating-point rodata constant.
test "route B: swap and float constants run" {
  if !host_ok() {
    return
  }
  let src =
    #|export
    #|function l $fib(l %n) {
    #|@start
    #|  %a =l copy 0
    #|  %b =l copy 1
    #|  %i =l copy 0
    #|@loop
    #|  %i2 =l phi @start %i, @body %i3
    #|  %a2 =l phi @start %a, @body %a3
    #|  %b2 =l phi @start %b, @body %b3
    #|  %c =l csltl %i2, %n
    #|  jnz %c, @body, @end
    #|@body
    #|  %a3 =l copy %b2
    #|  %b3 =l add %a2, %b2
    #|  %i3 =l add %i2, 1
    #|  jmp @loop
    #|@end
    #|  ret %a2
    #|}
    #|
    #|export
    #|function w $fp_demo(l %x) {
    #|@start
    #|  %d =d sltof %x
    #|  %e =d add %d, d_1.5
    #|  %r =w dtosi %e
    #|  ret %r
    #|}
    #|
  let m = @qbe.compile_arm64_bin_module(src) catch {
    _ => abort("route B fib/fp compile failed")
  }
  let blk = ExecBlock::load_module(m.image(), m.code_bytes)
  let mut fib_off = 0
  let mut fp_off = 0
  for f in m.fns {
    if f.0 == "fib" {
      fib_off = f.1
    }
    if f.0 == "fp_demo" {
      fp_off = f.1
    }
  }
  assert_eq(blk.call1_at(fib_off, 10L), 55L)
  assert_eq(blk.call1_at(fib_off, 20L), 6765L)
  // l -> d, +1.5, back to w: 2.0 + 1.5 = 3.5 -> 3, 10.0 + 1.5 = 11.5 -> 11.
  assert_eq(blk.call1_at(fp_off, 2L), 3L)
  assert_eq(blk.call1_at(fp_off, 10L), 11L)
}

///|
// route B: a data pointer referencing another global needs an UNSIGNED
// relocation so the linker fills in the address.
test "route B: data pointer UNSIGNED relocation" {
  if !host_ok() {
    return
  }
  let src =
    #|data $t = { w 7 }
    #|data $r = { l $t }
    #|export
    #|function w $deref() {
    #|@start
    #|  %p =l load $r
    #|  %v =w loadw %p
    #|  ret %v
    #|}
    #|
  let obj = @qbe.compile_arm64_object(src) catch {
    _ => abort("route B data-ref compile failed")
  }
  write_file("/tmp/qbe_rb_data.o", obj)
  let driver =
    #|int deref(void);
    #|int main(void) { return deref() == 7 ? 0 : 1; }
    #|
  write_file("/tmp/qbe_rb_data.c", @utf8.encode(driver))
  assert_eq(
    run_command(
      "clang -o /tmp/qbe_rb_data /tmp/qbe_rb_data.o /tmp/qbe_rb_data.c",
    ),
    0,
  )
  assert_eq(run_command("/tmp/qbe_rb_data"), 0)
}

///|
// route B: a self-contained main function (like demo/11_main.ssa) links with
// the system C compiler and runs.
test "route B: a main-bearing object links and runs" {
  if !host_ok() {
    return
  }
  let src =
    #|data $msg = { b "Hi!", b 0 }
    #|export
    #|function w $main() {
    #|@start
    #|  %p0 =l copy $msg
    #|  jmp @loop
    #|@loop
    #|  %p =l phi @start %p0, @body %p2
    #|  %c =w loadub %p
    #|  %z =w ceqw %c, 0
    #|  jnz %z, @end, @body
    #|@body
    #|  %r =w call $putchar(w %c)
    #|  %p2 =l add %p, 1
    #|  jmp @loop
    #|@end
    #|  ret 0
    #|}
    #|
  let obj = @qbe.compile_arm64_object(src) catch {
    _ => abort("route B main compile failed")
  }
  write_file("/tmp/qbe_rb_main.o", obj)
  assert_eq(run_command("cc -o /tmp/qbe_rb_main /tmp/qbe_rb_main.o"), 0)
  assert_eq(run_command("/tmp/qbe_rb_main"), 0)
}

///|
// JitModule: map a linked image and resolve/call a function by name.
test "jit module resolves and calls functions" {
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
  let m = @qbe.compile_arm64_bin_module(src)
  let jm = JitModule::from_bin_module(m)
  let names = jm.function_names()
  assert_true(names.length() == 1)
  assert_true(names[0] == "sum_to")
  assert_eq(jm.call_i64_1("sum_to", 10L), 55L)
  assert_eq(jm.call_i64_1("sum_to", 100L), 5050L)
  jm.close()
}
