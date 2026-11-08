///|
fn audit_parse_reject(src : String) -> Unit raise {
  try parse_all(src) catch {
    @util.QbeError::ParseError(_, _, _) => ()
    _ => fail("expected parse error")
  } noraise {
    _ => fail("expected rejection")
  }
}

///|
test "audit: debug positions fit unsigned 29 bit references" {
  audit_parse_reject("function $f() {\n@start\ndbgloc -1\nret\n}\n")
  audit_parse_reject("function $f() {\n@start\ndbgloc 536870912\nret\n}\n")
  audit_parse_reject("function $f() {\n@start\ndbgloc 1, -1\nret\n}\n")
}

///|
test "audit: blit size fits signed 29 bit reference" {
  audit_parse_reject(
    "function $f(l %p, l %q) {\n@start\nblit %p, %q, 268435456\nret\n}\n",
  )
}

///|
test "audit: unused extra operands are still parsed" {
  audit_parse_reject(
    "function w $f() {\n@start\n%x =w add 1, 2, bogus\nret %x\n}\n",
  )
}

///|
test "audit: variadic marker cannot prefix a longer identifier" {
  audit_parse_reject("function $f(...x) {\n@start\nret\n}\n")
}

///|
test "audit: type size max uses unsigned comparison" {
  let (_, _, ts, _) = parse_all("type :t = { b -1 }\n")
  assert_eq(ts[0].size, -1L)
}

///|
test "audit: negative type alignment follows C division" {
  let (_, _, ts, _) = parse_all("type :t = align -8 { 8 }\n")
  assert_eq(ts[0].align, 3)
}

///|
test "audit: single float conversion skips fscanf whitespace" {
  let (_, ds, _, _) = parse_all("data $f = { s s_ 1.5 }\n")
  assert_eq(ds[2].num, 1069547520L)
}

///|
test "audit: data lists retain adjacent symbols and strings" {
  let (_, ds, _, _) = parse_all(
    "data $refs = { l $a $b + -4 }\ndata $text = { b \"a\" \"b\" 0 }\n",
  )
  assert_eq(ds[2].ref_name, "a")
  assert_eq(ds[3].ref_name, "b")
  assert_eq(ds[3].ref_offset, -4L)
  assert_eq(ds[7].str, "a")
  assert_eq(ds[8].str, "b")
}

///|
test "audit: data references preserve each declared width" {
  let (_, ds, _, _) = parse_all("data $refs = { b $a, h $b, w $c, l $d }\n")
  assert_eq(ds[2].kind, @types.DB)
  assert_eq(ds[3].kind, @types.DH)
  assert_eq(ds[4].kind, @types.DW)
  assert_eq(ds[5].kind, @types.DL)
}

///|
test "audit: type fields require closing brace" {
  try parse_all("type :t = { w\n") catch {
    @util.QbeError::ParseError(_, _, _) => ()
    _ => fail("expected parse error")
  } noraise {
    _ => fail("accepted unterminated type")
  }
}

///|
test "audit: type fields retain C NField limit and full size" {
  let (_, _, ts, _) = parse_all("type :t = { b 40 }\n")
  assert_eq(ts[0].size, 40L)
  assert_eq(ts[0].fields.length(), 33)
  assert_eq(ts[0].fields[32].kind, @types.FEnd)
}

///|
test "audit: extern and thread apply only to globals" {
  for prefix in ["extern", "thread"] {
    try
      parse_all("function l $f(l %x) {\n@start\nret " + prefix + " %x\n}\n")
    catch {
      @util.QbeError::ParseError(_, _, _) => ()
      _ => fail("expected parse error")
    } noraise {
      _ => fail("accepted modifier on temporary")
    }
  }
}

///|
test "audit: subword call result is a word" {
  let (fs, _, _, _) = parse_all(
    "function w $f() {\n@start\n%x =sb call $g()\nret %x\n}\n",
  )
  assert_eq(fs[0].blks[0].ins[0].cls, @types.Kw)
}

///|
test "audit: phi cannot appear in the start block" {
  try parse_all("function w $f() {\n@start\n%x =w phi\nret %x\n}\n") catch {
    @util.QbeError::ParseError(_, _, _) => ()
    _ => fail("expected parse error")
  } noraise {
    _ => fail("accepted start phi")
  }
}

///|
test "audit: aggregate classes are only valid for calls" {
  try
    parse_all(
      "type :t = { w }\nfunction w $f() {\n@start\n%x =:t copy 1\nret 0\n}\n",
    )
  catch {
    @util.QbeError::ParseError(_, _, _) => ()
    _ => fail("expected parse error")
  } noraise {
    _ => fail("accepted aggregate copy")
  }
}
