///|
// JIT tests: route B images mapped and called in-process.

///|
fn host_ok() -> Bool {
  @native.host_supported()
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

///|
// JitModule resolves external symbols (libc putchar) through a veneer.
test "jit module calls libc" {
  if !host_ok() {
    return
  }
  let src =
    #|export
    #|function w $emit(w %c) {
    #|@start
    #|  %r =w call $putchar(w %c)
    #|  ret %r
    #|}
    #|
  let (m, fx) = @qbe.compile_arm64_bin_module_ex(src) catch {
    e => abort("compile failed: {Repr(e)}")
  }
  let jm = JitModule::from_bin_module_ex(m, fx)
  assert_eq(jm.call_i64_1("emit", 65L), 65L)
  jm.close()
}

///|
test "run-asm: execute in-memory arm64 code (self-contained)" {
  if !host_ok() {
    return
  }
  let text = @object.words_to_bytes([
    @object.enc_add_imm(0, 0, 1),
    @object.enc_ret(),
  ])
  let m = ExecBlock::load_text(text)
  assert_eq(m.call1(41L), 42L)
  assert_eq(m.call1(0L), 1L)
}
