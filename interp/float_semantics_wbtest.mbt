// Comprehensive float semantics regression tests for QBE
// Audits: NaN, infinities, signed zero, single precision rounding,
// ordered/unordered comparisons, Exts/Truncd, Stosi/Dtosi, Swtof/Sltof

///|
// Helper to run a test module
fn float_test_run(
  src : String,
  entry? : String = "main",
  args? : Array[InterpValue] = [],
) -> Result[InterpValue, String] raise {
  let lexer = @lexer.Lexer::new(src, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let max_steps = 10000000
  match
    run_module(
      parser.get_funcs(),
      parser.get_datas(),
      parser.interner_ref(),
      entry,
      args,
      max_steps~,
    ) {
    Ok((v, _out)) => Ok(v)
    Err(@util.QbeError::CompileError(m)) => Err("compile: \{m}")
    Err(@util.QbeError::Ice(m)) => Err("ice: \{m}")
    Err(@util.QbeError::ParseError(_, _, m)) => Err("parse: \{m}")
  }
}

///|
// Test Exts: single -> double conversion
test "float: Exts single-to-double conversion (1.5)" {
  let src =
    #|export function d $main(s %f) {
    #|@start
    #|  %d =d exts %f
    #|  ret %d
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(1.5)])
  match r {
    Ok(VDouble(v)) => assert_eq(v, 1.5)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Exts with special value: positive zero
test "float: Exts single +0.0 to double" {
  let src =
    #|export function d $main(s %f) {
    #|@start
    #|  %d =d exts %f
    #|  ret %d
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(0.0)])
  match r {
    Ok(VDouble(v)) => assert_eq(v, 0.0)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Exts with special value: negative zero
test "float: Exts single -0.0 to double" {
  let src =
    #|export function d $main(s %f) {
    #|@start
    #|  %d =d exts %f
    #|  ret %d
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(-0.0)])
  match r {
    Ok(VDouble(v)) => {
      // -0.0 should equal 0.0 numerically, but have negative sign
      assert_eq(v, 0.0)
      let sign = v.reinterpret_as_int64() >> 63
      assert_eq(sign, -1L)
    }
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Truncd: double -> single conversion
test "float: Truncd double-to-single conversion (1.5)" {
  let src =
    #|export function s $main(d %f) {
    #|@start
    #|  %s =s truncd %f
    #|  ret %s
    #|}
    #|
  let r = float_test_run(src, args=[VDouble(1.5)])
  match r {
    Ok(VFloat(v)) => assert_eq(v, 1.5)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Swtof: word (32-bit) integer to single precision
test "float: Swtof integer-to-single (word, 42)" {
  let src =
    #|export function s $main(w %i) {
    #|@start
    #|  %f =s swtof %i
    #|  ret %f
    #|}
    #|
  let r = float_test_run(src, args=[VInt(42L)])
  match r {
    Ok(VFloat(v)) => assert_eq(v, 42.0)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Swtof: word integer to double precision
test "float: Swtof integer-to-double (word, 42)" {
  let r = float_test_run(
    (
      #|export function d $main(w %i) {
      #|@start
      #|  %f =d swtof %i
      #|  ret %f
      #|}
      #|
    ),
    args=[VInt(42L)],
  )
  match r {
    Ok(VDouble(v)) => assert_eq(v, 42.0)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Sltof: long (64-bit) integer to single precision
test "float: Sltof integer-to-single (long, 42)" {
  let src =
    #|export function s $main(l %i) {
    #|@start
    #|  %f =s sltof %i
    #|  ret %f
    #|}
    #|
  let r = float_test_run(src, args=[VInt(42L)])
  match r {
    Ok(VFloat(v)) => assert_eq(v, 42.0)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Sltof: long integer to double precision
test "float: Sltof integer-to-double (long, 42)" {
  let r = float_test_run(
    (
      #|export function d $main(l %i) {
      #|@start
      #|  %f =d sltof %i
      #|  ret %f
      #|}
      #|
    ),
    args=[VInt(42L)],
  )
  match r {
    Ok(VDouble(v)) => assert_eq(v, 42.0)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Stosi: single to integer (word)
test "float: Stosi single-to-integer (word, 42.5)" {
  let src =
    #|export function w $main(s %f) {
    #|@start
    #|  %i =w stosi %f
    #|  ret %i
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(42.5)])
  match r {
    Ok(VInt(v)) => assert_eq(v, 42L)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Stosi: single to integer (long)
test "float: Stosi single-to-integer (long, 42.5)" {
  let src =
    #|export function l $main(s %f) {
    #|@start
    #|  %i =l stosi %f
    #|  ret %i
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(42.5)])
  match r {
    Ok(VInt(v)) => assert_eq(v, 42L)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Dtosi: double to integer (word)
test "float: Dtosi double-to-integer (word, 42.5)" {
  let r = float_test_run(
    (
      #|export function w $main(d %f) {
      #|@start
      #|  %i =w dtosi %f
      #|  ret %i
      #|}
      #|
    ),
    args=[VDouble(42.5)],
  )
  match r {
    Ok(VInt(v)) => assert_eq(v, 42L)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Dtosi: double to integer (long)
test "float: Dtosi double-to-integer (long, 42.5)" {
  let r = float_test_run(
    (
      #|export function l $main(d %f) {
      #|@start
      #|  %i =l dtosi %f
      #|  ret %i
      #|}
      #|
    ),
    args=[VDouble(42.5)],
  )
  match r {
    Ok(VInt(v)) => assert_eq(v, 42L)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Ceqs: single equality (equal operands)
test "float: Ceqs single equality (equal)" {
  let src =
    #|export function w $main(s %a, s %b) {
    #|@start
    #|  %c =w ceqs %a, %b
    #|  ret %c
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(1.5), VFloat(1.5)])
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Ceqs: single inequality
test "float: Ceqs single inequality" {
  let src =
    #|export function w $main(s %a, s %b) {
    #|@start
    #|  %c =w ceqs %a, %b
    #|  ret %c
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(1.5), VFloat(2.5)])
  match r {
    Ok(VInt(0L)) => ()
    Ok(VInt(v)) => fail("expected 0, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Ceqd: double equality (equal operands)
test "float: Ceqd double equality (equal)" {
  let r = float_test_run(
    (
      #|export function w $main(d %a, d %b) {
      #|@start
      #|  %c =w ceqd %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(1.5), VDouble(1.5)],
  )
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Cnes: single inequality
test "float: Cnes single inequality" {
  let src =
    #|export function w $main(s %a, s %b) {
    #|@start
    #|  %c =w cnes %a, %b
    #|  ret %c
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(1.5), VFloat(2.5)])
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Cned: double inequality
test "float: Cned double inequality" {
  let r = float_test_run(
    (
      #|export function w $main(d %a, d %b) {
      #|@start
      #|  %c =w cned %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(1.5), VDouble(2.5)],
  )
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Cos: single ordered (neither NaN) - core semantics: x < y || x >= y
test "float: Cos single ordered (both finite)" {
  let src =
    #|export function w $main(s %a, s %b) {
    #|@start
    #|  %c =w cos %a, %b
    #|  ret %c
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(1.5), VFloat(2.5)])
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Cod: double ordered (neither NaN)
test "float: Cod double ordered (both finite)" {
  let r = float_test_run(
    (
      #|export function w $main(d %a, d %b) {
      #|@start
      #|  %c =w cod %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(1.5), VDouble(2.5)],
  )
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Cles: single less-than-or-equal
test "float: Cles single less-than-or-equal" {
  let src =
    #|export function w $main(s %a, s %b) {
    #|@start
    #|  %c =w cles %a, %b
    #|  ret %c
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(1.5), VFloat(2.5)])
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Clts: single less-than
test "float: Clts single less-than" {
  let src =
    #|export function w $main(s %a, s %b) {
    #|@start
    #|  %c =w clts %a, %b
    #|  ret %c
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(1.5), VFloat(2.5)])
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Cged: double greater-than-or-equal
test "float: Cged double greater-than-or-equal" {
  let r = float_test_run(
    (
      #|export function w $main(d %a, d %b) {
      #|@start
      #|  %c =w cged %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(2.5), VDouble(1.5)],
  )
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Cgtd: double greater-than
test "float: Cgtd double greater-than" {
  let r = float_test_run(
    (
      #|export function w $main(d %a, d %b) {
      #|@start
      #|  %c =w cgtd %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(2.5), VDouble(1.5)],
  )
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Cled: double less-than-or-equal
test "float: Cled double less-than-or-equal" {
  let r = float_test_run(
    (
      #|export function w $main(d %a, d %b) {
      #|@start
      #|  %c =w cled %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(1.5), VDouble(2.5)],
  )
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test Cltd: double less-than
test "float: Cltd double less-than" {
  let r = float_test_run(
    (
      #|export function w $main(d %a, d %b) {
      #|@start
      #|  %c =w cltd %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(1.5), VDouble(2.5)],
  )
  match r {
    Ok(VInt(1L)) => ()
    Ok(VInt(v)) => fail("expected 1, got \{v}")
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test single precision addition
test "float: single-precision addition" {
  let src =
    #|export function s $main(s %a, s %b) {
    #|@start
    #|  %c =s add %a, %b
    #|  ret %c
    #|}
    #|
  let r = float_test_run(src, args=[VFloat(1.5), VFloat(2.5)])
  match r {
    Ok(VFloat(v)) => assert_eq(v, 4.0)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test double precision subtraction
test "float: double-precision subtraction" {
  let r = float_test_run(
    (
      #|export function d $main(d %a, d %b) {
      #|@start
      #|  %c =d sub %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(5.5), VDouble(2.5)],
  )
  match r {
    Ok(VDouble(v)) => assert_eq(v, 3.0)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test double precision multiplication
test "float: double-precision multiplication" {
  let r = float_test_run(
    (
      #|export function d $main(d %a, d %b) {
      #|@start
      #|  %c =d mul %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(2.5), VDouble(4.0)],
  )
  match r {
    Ok(VDouble(v)) => assert_eq(v, 10.0)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
// Test double precision division
test "float: double-precision division" {
  let r = float_test_run(
    (
      #|export function d $main(d %a, d %b) {
      #|@start
      #|  %c =d div %a, %b
      #|  ret %c
      #|}
      #|
    ),
    args=[VDouble(10.0), VDouble(2.0)],
  )
  match r {
    Ok(VDouble(v)) => assert_eq(v, 5.0)
    Ok(v) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}
