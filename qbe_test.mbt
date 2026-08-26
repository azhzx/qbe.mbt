///|
// Black-box end-to-end tests of the `@qbe` facade: full IL -> assembly and
// staged debug dumps, without requiring the reference qbe binary.

///|
test "compile a minimal function to assembly" {
  let src =
    #|export function w $one() {
    #|@start
    #|  ret 1
    #|}
    #|
  let assembly = match @qbe.compile(src) {
    Ok(s) => s
    Err(_) => fail("compile failed")
  }
  assert_true(assembly.contains(".text"))
  assert_true(assembly.contains("one:"))
  assert_true(assembly.contains("ret"))
}

///|
test "compile arithmetic emits add/sub/mul" {
  let src =
    #|export function w $add(w %a, w %b) {
    #|@start
    #|  %c =w add %a, %b
    #|  ret %c
    #|}
    #|export function l $mul(l %a, l %b) {
    #|@start
    #|  %c =l mul %a, %b
    #|  ret %c
    #|}
    #|
  let assembly = match @qbe.compile(src) {
    Ok(s) => s
    Err(_) => fail("compile failed")
  }
  assert_true(assembly.contains("addl"))
  assert_true(assembly.contains("imulq"))
  assert_true(assembly.contains("add:"))
  assert_true(assembly.contains("mul:"))
}

///|
test "compile_recursion_emits_call_and_branches" {
  let src =
    #|export function w $fact(w %n) {
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
  let assembly = match @qbe.compile(src) {
    Ok(s) => s
    Err(_) => fail("compile failed")
  }
  assert_true(assembly.contains("callq"))
  assert_true(assembly.contains("fact:"))
  assert_true(assembly.contains("jg"))
}

///|
test "compile with macho gas flavor" {
  let src =
    #|export function w $one() {
    #|@start
    #|  ret 1
    #|}
    #|
  let assembly = match @qbe.compile(src, gas="m") {
    Ok(s) => s
    Err(_) => fail("compile failed")
  }
  assert_true(assembly.contains("_one:"))
}

///|
test "compile data section" {
  let src =
    #|data $msg = { b "hi", b 0 }
    #|export function w $len() {
    #|@start
    #|  ret 0
    #|}
    #|
  let assembly = match @qbe.compile(src) {
    Ok(s) => s
    Err(_) => fail("compile failed")
  }
  assert_true(assembly.contains("msg:"))
  assert_true(assembly.contains(".ascii"))
  assert_true(assembly.contains(".byte"))
}

///|
test "compile rejects malformed input" {
  let result = @qbe.compile("function w %bad\n")
  match result {
    Ok(_) => fail("expected a compile error")
    Err(_) => ()
  }
}

///|
test "compile rejects unknown gas flavor" {
  let result = @qbe.compile(
    "export function w $f() { @start ret 0 }\n",
    gas="x",
  )
  match result {
    Ok(_) => fail("expected a compile error")
    Err(@util.QbeError::CompileError(msg)) =>
      assert_true(msg.contains("gas flavor"))
    Err(_) => fail("expected a CompileError")
  }
}

///|
test "compile_debug emits staged dumps" {
  let src =
    #|export function w $one() {
    #|@start
    #|  ret 1
    #|}
    #|
  let dump = match @qbe.compile_debug(src, "P") {
    Ok(dump) => dump
    Err(_) => fail("compile failed")
  }
  assert_true(dump.contains("**** Function one ****"))
  assert_true(dump.contains("After parsing"))
  assert_true(dump.contains("function $one()"))
}

///|
test "compile_debug with multiple flags" {
  let src =
    #|export function w $one() {
    #|@start
    #|  ret 1
    #|}
    #|
  let dump = match @qbe.compile_debug(src, "PN") {
    Ok(dump) => dump
    Err(_) => fail("compile failed")
  }
  assert_true(dump.contains("After parsing"))
  assert_true(dump.contains("Dominators"))
}

///|
test "compile_debug full pipeline flags" {
  let src =
    #|export function w $one() {
    #|@start
    #|  ret 1
    #|}
    #|
  let dump = match @qbe.compile_debug(src, "MNCASLR") {
    Ok(dump) => dump
    Err(_) => fail("compile failed")
  }
  assert_true(dump.contains("After SSA construction"))
  assert_true(dump.contains("Liveness analysis"))
}

///|
test "compile float arithmetic emits double instructions" {
  let src =
    #|export function d $poly(d %x) {
    #|@start
    #|  %x2 =d mul %x, %x
    #|  %r =d mul %x2, d_2.0
    #|  %r2 =d add %r, %x2
    #|  ret %r2
    #|}
    #|
  let assembly = match @qbe.compile(src) {
    Ok(s) => s
    Err(_) => fail("compile failed")
  }
  assert_true(assembly.contains("poly:"))
  assert_true(assembly.contains("mulsd"))
  assert_true(assembly.contains("addsd"))
}

///|
test "compile memory ops emits load/store" {
  let src =
    #|export function l $mem_demo(l %n) {
    #|@start
    #|  %a =l alloc8 %n
    #|  storel 42, %a
    #|  %v =l load %a
    #|  ret %v
    #|}
    #|
  let assembly = match @qbe.compile(src) {
    Ok(s) => s
    Err(_) => fail("compile failed")
  }
  assert_true(assembly.contains("mem_demo:"))
  assert_true(assembly.contains("movq"))
}

///|
test "compile phi loop with many temps" {
  // A small loop with a phi node exercises regalloc and loop analysis.
  let src =
    #|export function w $count(w %n) {
    #|@start
    #|  jmp @loop
    #|@loop
    #|  %i =w phi @start 0, @body %i2
    #|  %c =w csltw %i, %n
    #|  jnz %c, @body, @done
    #|@body
    #|  %i2 =w add %i, 1
    #|  jmp @loop
    #|@done
    #|  ret %i
    #|}
    #|
  let assembly = match @qbe.compile(src) {
    Ok(s) => s
    Err(_) => fail("compile failed")
  }
  assert_true(assembly.contains("count:"))
  assert_true(assembly.contains("ret"))
}

///|
test "type re-exports are usable" {
  let f : @qbe.Fn = @types.Fn::new("f")
  assert_true(f.name == "f")
  let r : @qbe.Ref = @qbe.Ref::tmp(3)
  assert_true(r.tmp_val() == 3)
  let i : @qbe.Ins = @types.Ins::new(
    @qbe.Op::Add,
    @qbe.Class::Kw,
    @qbe.Ref::tmp(1),
    @qbe.Ref::tmp(2),
    @qbe.Ref::tmp(3),
  )
  assert_true(i.op == @qbe.Op::Add)
}
