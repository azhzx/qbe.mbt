// White-box tests for the SSA interpreter core: value semantics, memory,
// control flow, calls and data.

///|
// Parse one IL source and return the module artifacts.
fn interp_parse(
  src : String,
) -> (Array[@types.Fn], Array[@types.Dat], @util.Interner) raise {
  let lexer = @lexer.Lexer::new(src, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  (parser.get_funcs(), parser.get_datas(), parser.interner_ref())
}

///|
// Run a module, mapping errors to their message for assertions.
fn interp_run(
  src : String,
  entry? : String = "main",
  args? : Array[InterpValue] = [],
  max_steps? : Int = 10000000,
) -> Result[InterpValue, String] raise {
  let r = interp_parse(src)
  match run_module(r.0, r.1, r.2, entry, args, max_steps~) {
    Ok((v, _out)) => Ok(v)
    Err(@util.QbeError::CompileError(m)) => Err(m)
    Err(@util.QbeError::Ice(m)) => Err("ice: \{m}")
    Err(@util.QbeError::ParseError(_, _, m)) => Err("parse: \{m}")
  }
}

///|
test "interp: integer arithmetic and word truncation" {
  let r = interp_run(
    (
      #|export function l $main(l %a, l %b) {
      #|@start
      #|  %w =w add %a, %b
      #|  %l =l add %a, %b
      #|  %we =l extsw %w
      #|  %p =l mul %we, %l
      #|  ret %p
      #|}
      #|
    ),
    args=[InterpValue::VInt(2000000000L), InterpValue::VInt(2000000000L)],
  )
  // %w = sext32(4e9) = -294967296; %l = 4e9; p = -294967296 * 4e9
  match r {
    Ok(InterpValue::VInt(v)) => assert_eq(v, -294967296L * 4000000000L)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: unsigned division" {
  let r = interp_run(
    (
      #|export function l $main(l %a) {
      #|@start
      #|  %h =l udiv %a, 3
      #|  ret %h
      #|}
      #|
    ),
    args=[InterpValue::VInt(-1L)],
  )
  // (-1 as u64) / 3 = 0x5555555555555555
  match r {
    Ok(InterpValue::VInt(v)) =>
      assert_eq(v.reinterpret_as_uint64(), 0x5555555555555555UL)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: comparisons" {
  let src =
    #|export function w $main(w %a, w %b) {
    #|@start
    #|  %eq =w ceqw %a, %b
    #|  %lt =w csltw %a, %b
    #|  %ug =w cugtw %a, %b
    #|  %r =w add %eq, %lt
    #|  %r2 =w add %r, %ug
    #|  ret %r2
    #|}
    #|
  // a=-1, b=1: eq=0, lt(sext: -1<1)=1, ug(0xffffffff>1)=1 -> 2
  match interp_run(src, args=[InterpValue::VInt(-1L), InterpValue::VInt(1L)]) {
    Ok(InterpValue::VInt(v)) => assert_eq(v, 2L)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: float arithmetic and conversion" {
  let src =
    #|export function d $main(d %a) {
    #|@start
    #|  %h =d div %a, d_2.0
    #|  %i =w dtosi %h
    #|  %j =d swtof %i
    #|  ret %j
    #|}
    #|
  match interp_run(src, args=[InterpValue::VDouble(9.75)]) {
    Ok(InterpValue::VDouble(d)) => assert_eq(d, 4.0)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: extension ops" {
  let src =
    #|export function l $main(w %a) {
    #|@start
    #|  %b =w extsb %a
    #|  %c =w extub %a
    #|  %d =w sub %c, %b
    #|  %e =l extsw %d
    #|  ret %e
    #|}
    #|
  // a=0x1ff: extsb=0xff(-1), extub=0xff(255) -> 255-(-1)=256
  match interp_run(src, args=[InterpValue::VInt(0x1FFL)]) {
    Ok(InterpValue::VInt(v)) => assert_eq(v, 256L)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: data segment loads of all widths" {
  let src =
    #|data $pat = { b 17, b 34, b 51, b 68 }
    #|
    #|export function l $main() {
    #|@start
    #|  %sb =l loadsb $pat
    #|  %pa =l add $pat, 1
    #|  %ub =l loadub %pa
    #|  %sh =l loadsh $pat
    #|  %uh =l loaduh $pat
    #|  %sw =l loadsw $pat
    #|  %uw =l loaduw $pat
    #|  %ll =l loadl $pat
    #|  %s =l add %sb, %ub
    #|  %s =l add %s, %sh
    #|  %s =l add %s, %uh
    #|  %s =l add %s, %sw
    #|  %s =l add %s, %uw
    #|  %s =l add %s, %ll
    #|  ret %s
    #|}
    #|
  match interp_run(src) {
    Ok(InterpValue::VInt(v)) =>
      // sb=17; ub(34)=34; sh=0x2211=8721; uh=8721; sw=0x44332211=1144201745;
      // uw=1144201745; ll=0x4433221100=292458755328
      assert_eq(
        v,
        17L + 34L + 8721L + 8721L + 1144201745L + 1144201745L + 1144201745L,
      )
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: stack writes through alloc" {
  let src =
    #|export function l $main(l %a, l %b) {
    #|@start
    #|  %p =l alloc8 16
    #|  storel %a, %p
    #|  %q =l add %p, 8
    #|  storel %b, %q
    #|  %x =l loadl %p
    #|  %y =l loadl %q
    #|  %r =l sub %x, %y
    #|  ret %r
    #|}
    #|
  match
    interp_run(src, args=[InterpValue::VInt(100L), InterpValue::VInt(58L)]) {
    Ok(InterpValue::VInt(v)) => assert_eq(v, 42L)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: while loop with phi" {
  let src =
    #|export function l $main(l %n) {
    #|@start
    #|  jmp @loop
    #|
    #|@loop
    #|  %i =l phi @start 0, @loop %j
    #|  %acc =l phi @start 0, @loop %s
    #|  %j =l add %i, 1
    #|  %s =l add %acc, %i
    #|  %c =w csltl %j, %n
    #|  jnz %c, @loop, @done
    #|
    #|@done
    #|  ret %acc
    #|}
    #|
  match interp_run(src, args=[InterpValue::VInt(11L)]) {
    Ok(InterpValue::VInt(v)) => assert_eq(v, 45L)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: recursion and mixed-type calls" {
  let src =
    #|export function d $main(l %n, d %acc) {
    #|@start
    #|  %c =w cslel %n, 0
    #|  jnz %c, @base, @rec
    #|
    #|@base
    #|  ret %acc
    #|
    #|@rec
    #|  %m =l sub %n, 1
    #|  %a2 =d add %acc, d_0.5
    #|  %r =d call $main(l %m, d %a2)
    #|  ret %r
    #|}
    #|
  match
    interp_run(src, args=[InterpValue::VInt(6L), InterpValue::VDouble(0.0)]) {
    Ok(InterpValue::VDouble(d)) => assert_eq(d, 3.0)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: indirect call through a function pointer" {
  let src =
    #|data $fpinc = { w $inc }
    #|
    #|export function w $inc(w %x) {
    #|@start
    #|  %r =w add %x, 1
    #|  ret %r
    #|}
    #|
    #|export function w $apply(l %g, w %x) {
    #|@start
    #|  %r =w call %g(w %x)
    #|  ret %r
    #|}
    #|
    #|export function w $main() {
    #|@start
    #|  %fp =l loadl $fpinc
    #|  %r =w call $apply(l %fp, w 41)
    #|  ret %r
    #|}
    #|
  match interp_run(src) {
    // the data segment holds the code address of $inc: applied to 41 -> 42
    Ok(InterpValue::VInt(v)) => assert_eq(v, 42L)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: data segment with symbol references" {
  let src =
    #|data $ptr = { w $target }
    #|
    #|export function w $target() {
    #|@start
    #|  ret 7
    #|}
    #|
    #|export function w $f() {
    #|@start
    #|  %fp =l loadl $ptr
    #|  %r =w call %fp()
    #|  ret %r
    #|}
    #|
  match interp_run(src, entry="f") {
    Ok(InterpValue::VInt(v)) => assert_eq(v, 7L)
    Ok(_) => fail("wrong kind")
    Err(m) => fail("err: \{m}")
  }
}

///|
test "interp: division by zero reports an error" {
  let r = interp_run(
    (
      #|export function l $main() {
      #|@start
      #|  %r =l div 1, 0
      #|  ret %r
      #|}
      #|
    ),
  )
  match r {
    Err(m) => assert_true(m.contains("division by zero"))
    _ => fail("expected an error")
  }
}

///|
test "interp: unknown function reports an error" {
  let r = interp_run(
    (
      #|export function l $main() {
      #|@start
      #|  %r =l call $nope()
      #|  ret %r
      #|}
      #|
    ),
  )
  match r {
    Err(m) =>
      assert_true(
        m.contains("unknown external function") ||
        m.contains("unknown function"),
      )
    _ => fail("expected an error")
  }
}

///|
test "interp: step limit terminates infinite loops" {
  let r = interp_run(
    (
      #|export function l $main() {
      #|@start
      #|@loop
      #|  jmp @loop
      #|@end
      #|  ret 0
      #|}
      #|
    ),
    max_steps=1000,
  )
  match r {
    Err(m) => assert_true(m.contains("step limit"))
    _ => fail("expected an error")
  }
}
