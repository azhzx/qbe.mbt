///|
// Route A / object tests: assemble with clang and emit Mach-O objects.

///|
fn host_ok() -> Bool {
  @native.host_supported()
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
  @native.write_file("/tmp/qbe_route_b.o", obj)
  let driver =
    #|int fact(int);
    #|int get_g(void);
    #|int main(void) { return (fact(5) == 120 && get_g() == 7) ? 0 : 1; }
    #|
  @native.write_file("/tmp/qbe_route_b_driver.c", @utf8.encode(driver))
  assert_eq(
    @native.run_command(
      "clang -o /tmp/qbe_route_b_exe /tmp/qbe_route_b.o /tmp/qbe_route_b_driver.c",
    ),
    0,
  )
  assert_eq(@native.run_command("/tmp/qbe_route_b_exe"), 0)
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
  @native.write_file("/tmp/qbe_rb_data.o", obj)
  let driver =
    #|int deref(void);
    #|int main(void) { return deref() == 7 ? 0 : 1; }
    #|
  @native.write_file("/tmp/qbe_rb_data.c", @utf8.encode(driver))
  assert_eq(
    @native.run_command(
      "clang -o /tmp/qbe_rb_data /tmp/qbe_rb_data.o /tmp/qbe_rb_data.c",
    ),
    0,
  )
  assert_eq(@native.run_command("/tmp/qbe_rb_data"), 0)
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
  @native.write_file("/tmp/qbe_rb_main.o", obj)
  assert_eq(@native.run_command("cc -o /tmp/qbe_rb_main /tmp/qbe_rb_main.o"), 0)
  assert_eq(@native.run_command("/tmp/qbe_rb_main"), 0)
}
