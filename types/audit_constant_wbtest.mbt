///|
// C parsefn reserves con[0]=UNDEF and con[1]=CON_Z before parsing operands.
test "audit function constants reserve undefined and zero identities" {
  let f = Fn::new("sentinels")
  assert_eq(f.ncon(), 2)
  assert_eq(f.undef(), 0)
  assert_eq(f.get_con(0), 1)
  assert_eq(f.cons[0].kind, CBits)
  assert_eq(f.cons[0].bits.i, 0xdeaddeadL)
}

///|
// newcon/getcon start at one even though con[0] has ordinary numeric bits.
test "audit integer literal deaddead is not undefined" {
  let f = Fn::new("literal_first")
  let literal = f.get_con(0xdeaddeadL)
  assert_true(literal != f.undef())
  assert_eq(f.get_con_by(Con::int(0xdeaddeadL)), literal)
}

///|
test "audit undefined first does not capture deaddead literal" {
  let f = Fn::new("undef_first")
  let undef = f.undef()
  let literal = f.get_con_by(Con::int(0xdeaddeadL))
  assert_true(undef != literal)
  assert_eq(f.get_con(0xdeaddeadL), literal)
}

///|
// getcon compares CBits bits.i only, not its presentation flag flt.
test "audit getcon reuses float constants by raw bits" {
  let f = Fn::new("float_first")
  let floating = f.get_con_by(Con::double(1.0))
  assert_eq(f.get_con(0x3ff0000000000000L), floating)
}
