///|
// Tests for CLI error formatting (matches the reference qbe CLI style).

///|
test "format_qbe_error: parse errors carry file, line and message" {
  let msg = format_qbe_error(
    @util.QbeError::ParseError("input.ssa", 12, "unexpected token"),
  )
  assert_eq(msg, "input.ssa:12: error: unexpected token")
}

///|
test "format_qbe_error: compile errors are bare messages" {
  let msg = format_qbe_error(
    @util.QbeError::CompileError("unknown gas flavor 'x'"),
  )
  assert_eq(msg, "error: unknown gas flavor 'x'")
}

///|
test "format_qbe_error: internal errors are marked as ICE" {
  let msg = format_qbe_error(@util.QbeError::Ice("phi to not a tmp"))
  assert_eq(msg, "ICE: phi to not a tmp")
}

///|
test "parse_run_spec: integers, floats and entry name" {
  let (name, args) = parse_run_spec("fact,10,-2,1.5,s_0.25")
  assert_eq(name, "fact")
  assert_eq(args.length(), 4)
  match args[0] {
    @interp.VInt(v) => assert_eq(v, 10L)
    _ => fail("expected VInt")
  }
  match args[1] {
    @interp.VInt(v) => assert_eq(v, -2L)
    _ => fail("expected VInt")
  }
  match args[2] {
    @interp.VDouble(d) => assert_true(d == 1.5)
    _ => fail("expected VDouble")
  }
  match args[3] {
    @interp.VFloat(f) => assert_true(f == 0.25)
    _ => fail("expected VFloat")
  }
}

///|
test "parse_run_spec: bare entry name has no args" {
  let (name, args) = parse_run_spec("main")
  assert_eq(name, "main")
  assert_eq(args.length(), 0)
}
