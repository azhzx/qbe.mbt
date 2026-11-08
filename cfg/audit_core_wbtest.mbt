///|
test "audit core alias preserves symbol type" {
  let f = @types.Fn::new("alias")
  let c = @types.Con::addr_sym(7, 1)
  let r = @types.Ref::con(f.add_con(c))
  assert_eq(getalias(r, f).sym_type, 1)
}

///|
test "audit core alias distinguishes same name different symbol type" {
  let f = @types.Fn::new("alias")
  let c = @types.Con::addr_sym(7, 0)
  let p = @types.Ref::con(f.add_con(c))
  let d = @types.Con::addr_sym(7, 1)
  let q = @types.Ref::con(f.add_con(d))
  let (result, _) = check_alias(p, 0, 4, q, 4, f)
  assert_true(result is MayAlias)
}
