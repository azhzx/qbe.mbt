///|
// parse.c lexical aliases allocate with at least four-byte alignment.
test "audit alloc1 and alloc2 aliases select alloc4" {
  assert_eq(Op::from_string("alloc1"), Alloc4)
  assert_eq(Op::from_string("alloc2"), Alloc4)
}

///|
// Check all mapped indices, not only the historical pre-subword prefix.
test "audit opcode metadata covers all declared indices" {
  for i in 0..<163 {
    let op = Op::from_index(i)
    assert_eq(op.index(), i)
    assert_true(op_info(op).a0.length() == 4)
    assert_true(op_info(op).a1.length() == 4)
  }
}
