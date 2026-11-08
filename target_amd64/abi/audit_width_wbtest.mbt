///|
test "audit: aggregate classifier truncates size to C unsigned width" {
  let f = @types.Fn::new("audit")
  let t = @types.Typ::new("wrapped")
  t.size = 4294967304L
  t.align = 3
  t.fields.push(@types.Field::new(@types.Fl, 8))
  t.fields.push(@types.Field::end())
  let st = AbiState::{
    fn_: f,
    typs: [t],
    buf: [],
    ral: None,
    env: @types.Ref::none(),
    fa: 0,
  }
  let a = typclass(st, AClass::new(), t)
  assert_eq(a.inmem, 0)
  assert_eq(a.size.to_int64(), 8L)
}

///|
test "audit: aggregate allocation retains unsigned 32 bit size" {
  let f = @types.Fn::new("audit")
  let t = @types.Typ::new("large")
  t.size = 2147483648L
  t.align = 3
  t.dark = 1
  let st = AbiState::{
    fn_: f,
    typs: [t],
    buf: [],
    ral: None,
    env: @types.Ref::none(),
    fa: 0,
  }
  let a = typclass(st, AClass::new(), t)
  assert_eq(a.size.to_int64(), 2147483648L)
}
