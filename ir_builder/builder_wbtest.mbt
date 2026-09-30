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
// Build `add`, a data string, a phi loop (`tri`) and a recursive `fib`, then
// check that printing the IL, re-parsing it and compiling yields exactly the
// assembly produced directly from the builder IR.

///|
// Remove register numbers so the two paths can differ in allocation only.
fn strip_regs(s : String) -> String {
  let out = StringBuilder::new()
  let cs = s.to_array()
  let mut i = 0
  while i < cs.length() {
    let c = cs[i]
    if (c == 'w' || c == 'x' || c == 's' || c == 'd') &&
      i + 1 < cs.length() &&
      cs[i + 1] >= '0' &&
      cs[i + 1] <= '9' {
      out.write_char(c)
      i = i + 1
      while i < cs.length() && cs[i] >= '0' && cs[i] <= '9' {
        i = i + 1
      }
    } else {
      out.write_char(c)
      i = i + 1
    }
  }
  out.to_string()
}

///|
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
  assert_eq(strip_regs(direct), strip_regs(parsed))
}

///|
test "builder: -g emits DWARF for declared variables" {
  let b = Builder::new()
  b.set_dbg_compile_unit("t.c", "/tmp")
  let f = b.add_func("add", Word, [@types.Kw, @types.Kw], true)
  let a = b.param(f, 0)
  let c = b.param(f, 1)
  let r = b.arith(f, @types.Add, @types.Kw, a, c)
  b.dbg_var(f, "sum", @types.DbgW, r)
  b.ret(f, r)
  @util.set_debug_info(true)
  let asm = b.emit_asm(gas="m")
  @util.set_debug_info(false)
  assert_true(asm.contains(".section __DWARF,__debug_info,regular,debug\n"))
  assert_true(asm.contains(".section __DWARF,__debug_loc,regular,debug\n"))
  assert_true(asm.contains("\t.asciz \"add\"\n"))
  assert_true(asm.contains("\t.asciz \"sum\"\n"))
  assert_true(asm.contains("\t.asciz \"int\"\n"))
  // Without -g the assembly stays unchanged.
  let plain = b.emit_asm(gas="m")
  assert_true(!plain.contains(".debug_info"))
}

///|
test "builder: variadic signature, va ops and call_vararg round-trip" {
  let b = Builder::new()
  // function w $sum(w %n, ...) { %ap =l alloc8 32; vastart %ap; ret vaarg }
  let fs = b.add_func("sum", Word, [@types.Kw], true, is_vararg=true)
  let size = b.iconst(fs, 32L)
  let ap = b.emit_ins(fs, @types.Alloc8, @types.Kl, @types.Kl, size, -1)
  b.vastart(fs, ap)
  let v = b.vaarg(fs, @types.Kw, ap)
  b.ret(fs, v)
  // export function w $main() { %r =w call $sum(w 1, ..., w 2) }
  let fm = b.add_func("main", Word, [], true)
  let a = b.iconst(fm, 1L)
  let c = b.iconst(fm, 2L)
  let r = b.call_vararg(fm, "sum", [(@types.Kw, a)], [(@types.Kw, c)], Word)
  b.ret(fm, r)
  let il = b.emit_il()
  if !(il.contains("$sum(w %") && il.contains(", ...)")) {
    fail("IL was:\n" + il)
  }
  assert_true(il.contains("..., w "))
  let direct = b.emit_asm()
  let parsed = match @qbe.compile_arm64(il) {
    Ok(s) => s
    Err(e) => fail("re-parse failed: \{Repr(e)}\n--- IL ---\n\{il}")
  }
  assert_eq(strip_regs(direct), strip_regs(parsed))
}
