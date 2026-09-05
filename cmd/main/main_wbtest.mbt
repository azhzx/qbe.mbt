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
