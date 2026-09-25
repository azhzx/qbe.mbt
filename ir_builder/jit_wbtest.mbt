///|
// JIT test: run builder-built fib in-process (native only; uses @jit/@native).
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
