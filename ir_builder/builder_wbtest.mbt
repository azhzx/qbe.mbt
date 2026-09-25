///|
test "builder: add matches parser" {
  let src = "export function w $add(w %a, w %b) {\n@start\n  %r =w add %a, %b\n  ret %r\n}\n"
  let expected = match @qbe.compile_arm64(src) {
    Ok(s) => s
    Err(_) => fail("parser compile failed")
  }
  let b = Builder::new()
  let f = b.add_func("add", Word, [@types.Kw, @types.Kw], true)
  let a = b.param(f, 0)
  let bb = b.param(f, 1)
  let r = b.arith(f, @types.Add, @types.Kw, a, bb)
  b.ret(f, r)
  let got = b.emit_asm()
  assert_eq(got, expected)
}

///|
test "builder: conditional matches parser" {
  let src = "export function w $max(w %a, w %b) {\n@start\n  %c =w csgtw %a, %b\n  jnz %c, @then, @else\n@then\n  ret %a\n@else\n  ret %b\n}\n"
  let expected = match @qbe.compile_arm64(src) {
    Ok(s) => s
    Err(_) => fail("parser compile failed")
  }
  let b = Builder::new()
  let f = b.add_func("max", Word, [@types.Kw, @types.Kw], true)
  let a = b.param(f, 0)
  let bb = b.param(f, 1)
  let then = b.add_block(f, "then")
  let els = b.add_block(f, "else")
  let c = b.cmp(f, @types.Csgtw, @types.Kw, a, bb)
  b.jnz(f, c, then, [], els, [])
  b.switch_to(f, then)
  b.ret(f, a)
  b.switch_to(f, els)
  b.ret(f, bb)
  let got = b.emit_asm()
  assert_eq(got, expected)
}

///|
test "builder: block params match parser" {
  let src = "export function w $pick(w %n) {\n@start\n  %c =w csgtw %n, 0\n  jnz %c, @pos, @neg\n@pos\n  jmp @join\n@neg\n  jmp @join\n@join\n  %r =w phi @pos 1, @neg 2\n  ret %r\n}\n"
  let expected = match @qbe.compile_arm64(src) {
    Ok(s) => s
    Err(_) => fail("parser compile failed")
  }
  let b = Builder::new()
  let f = b.add_func("pick", Word, [@types.Kw], true)
  let n = b.param(f, 0)
  let pos = b.add_block(f, "pos")
  let neg = b.add_block(f, "neg")
  let join = b.add_block(f, "join")
  let c = b.cmp(f, @types.Csgtw, @types.Kw, n, b.iconst(f, 0L))
  b.jnz(f, c, pos, [], neg, [])
  b.switch_to(f, pos)
  b.jmp(f, join, [b.iconst(f, 1L)])
  b.switch_to(f, neg)
  b.jmp(f, join, [b.iconst(f, 2L)])
  b.switch_to(f, join)
  let r = b.block_param(f, join, @types.Kw)
  b.ret(f, r)
  let got = b.emit_asm()
  assert_eq(got, expected)
}

///|
// Build the recursive fib from the C smoke test, entirely in-process, and run
// it through the Route B JIT.
test "builder: fib runs in-process" {
  let b = Builder::new()
  let f = b.add_func("fib", Word, [@types.Kw], true)
  let base = b.add_block(f, "base")
  let rec = b.add_block(f, "rec")
  let n = b.param(f, 0)
  let one = b.iconst(f, 1L)
  let cond = b.cmp(f, @types.Cslew, @types.Kw, n, one)
  b.jnz(f, cond, base, [], rec, [])
  b.switch_to(f, base)
  b.ret(f, n)
  b.switch_to(f, rec)
  let n1 = b.arith(f, @types.Sub, @types.Kw, n, one)
  b.emit_void(f, @types.Arg, @types.Kw, n1, -1)
  let f1 = b.call(f, "fib", [], Word)
  let two = b.iconst(f, 2L)
  let n2 = b.arith(f, @types.Sub, @types.Kw, n, two)
  b.emit_void(f, @types.Arg, @types.Kw, n2, -1)
  let f2 = b.call(f, "fib", [], Word)
  let r = b.arith(f, @types.Add, @types.Kw, f1, f2)
  b.ret(f, r)
  if !@native.host_supported() {
    return
  }
  let m = b.emit_bin_module()
  let exec = @jit.ExecBlock::load_module(m.image(), m.code_bytes)
  let mut off = -1
  for p in m.fns {
    if p.0 == "fib" {
      off = p.1
    }
  }
  assert_true(off >= 0)
  assert_eq(exec.call1_at(off, 10L), 55L)
  assert_eq(exec.call1_at(off, 0L), 0L)
  assert_eq(exec.call1_at(off, 20L), 6765L)
}

///|
// Build `add`, a data string, a phi loop (`tri`) and a recursive `fib`, then
// check that printing the IL, re-parsing it and compiling yields exactly the
// assembly produced directly from the builder IR.
test "builder: emit_il round-trips through the parser" {
  let b = Builder::new()

  // export function w $add(w %a, w %b)
  let fa = b.add_func("add", Word, [@types.Kw, @types.Kw], true)
  let a = b.param(fa, 0)
  let c = b.param(fa, 1)
  b.ret(fa, b.arith(fa, @types.Add, @types.Kw, a, c))

  b.data_string("msg", true, "hi")

  // export function w $tri(w %n): 1 + 2 + ... + n, phi loop
  let ft = b.add_func("tri", Word, [@types.Kw], true)
  let n = b.param(ft, 0)
  let init = b.add_block(ft, "init")
  let zero = b.add_block(ft, "zero")
  let lp = b.add_block(ft, "loop")
  let body = b.add_block(ft, "body")
  let end = b.add_block(ft, "end")
  let one = b.iconst(ft, 1L)
  let z = b.iconst(ft, 0L)
  let c0 = b.cmp(ft, @types.Csgtw, @types.Kw, n, z)
  b.jnz(ft, c0, init, [], zero, [])
  b.switch_to(ft, init)
  b.jmp(ft, lp, [one, z])
  b.switch_to(ft, zero)
  b.ret(ft, z)
  b.switch_to(ft, lp)
  let i = b.block_param(ft, lp, @types.Kw)
  let s = b.block_param(ft, lp, @types.Kw)
  let s2 = b.arith(ft, @types.Add, @types.Kw, s, i)
  let i2 = b.arith(ft, @types.Add, @types.Kw, i, one)
  let cc = b.cmp(ft, @types.Cslew, @types.Kw, i2, n)
  b.jnz(ft, cc, body, [], end, [])
  b.switch_to(ft, body)
  b.jmp(ft, lp, [i2, s2])
  b.switch_to(ft, end)
  b.ret(ft, s2)

  // export function w $fib(w %n): recursive, exercises call printing
  let ff = b.add_func("fib", Word, [@types.Kw], true)
  let base = b.add_block(ff, "base")
  let rec = b.add_block(ff, "rec")
  let nn = b.param(ff, 0)
  let one2 = b.iconst(ff, 1L)
  let cond = b.cmp(ff, @types.Cslew, @types.Kw, nn, one2)
  b.jnz(ff, cond, base, [], rec, [])
  b.switch_to(ff, base)
  b.ret(ff, nn)
  b.switch_to(ff, rec)
  let n1 = b.arith(ff, @types.Sub, @types.Kw, nn, one2)
  let f1 = b.call(ff, "fib", [(@types.Kw, n1)], Word)
  let two = b.iconst(ff, 2L)
  let n2 = b.arith(ff, @types.Sub, @types.Kw, nn, two)
  let f2 = b.call(ff, "fib", [(@types.Kw, n2)], Word)
  b.ret(ff, b.arith(ff, @types.Add, @types.Kw, f1, f2))

  let il = b.emit_il()
  assert_true(il.contains("export function w $add(w %"))
  assert_true(il.contains("phi @init"))
  assert_true(il.contains("call $fib(w %"))
  assert_true(il.contains("export data $msg = { b \"hi\" }"))
  let direct = b.emit_asm()
  let parsed = match @qbe.compile_arm64(il) {
    Ok(s) => s
    Err(e) => fail("re-parse failed: \{Repr(e)}\n--- IL ---\n\{il}")
  }
  assert_eq(direct, parsed)
}
