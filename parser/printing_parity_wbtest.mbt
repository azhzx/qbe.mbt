///|
test "audit: sentinel identity does not hide matching integer literal" {
  let (fs, _, ts, interner) = parse_all(
    "function l $f() {\n@start\nret 3735936685\n}\n",
  )
  assert_true(printfn(fs[0], interner, ts).contains("retl 3735936685"))
}

///|
test "audit: absent reference and undefined constant print distinctly" {
  let f = @types.Fn::new("f")
  let i = @util.Interner::new()
  let sb = StringBuilder::new()
  printref(@types.Ref::none(), f, i, sb, [])
  assert_eq(sb.to_string(), "R")
  let sb = StringBuilder::new()
  printref(@types.Ref::con(f.undef()), f, i, sb, [])
  assert_eq(sb.to_string(), "UNDEF")
}

///|
test "audit: memory displacement matching undef bits remains numeric" {
  let sb = StringBuilder::new()
  printcon(@types.Con::int(3735936685L), @util.Interner::new(), sb)
  assert_eq(sb.to_string(), "3735936685")
}
