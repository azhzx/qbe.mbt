// Black-box end-to-end tests for the interpreter facade.

///|
async test "interpret: recursion, memory and builtin printf" {
  let src =
    #|data $msg = { b 102, b 105, b 98, b 40, b 37, b 100, b 41, b 61, b 32, b 10, b 0 }
    #|
    #|export function l $fib(l %n) {
    #|@start
    #|  %c =w cslel %n, 2
    #|  jnz %c, @base, @rec
    #|
    #|@base
    #|  ret %n
    #|
    #|@rec
    #|  %m =l sub %n, 1
    #|  %a =l call $fib(l %m)
    #|  %m2 =l sub %n, 2
    #|  %b =l call $fib(l %m2)
    #|  %r =l add %a, %b
    #|  ret %r
    #|}
    #|
    #|export function w $main() {
    #|@start
    #|  %r =l call $fib(l 10)
    #|  %p =l call $printf(l $msg, l %r)
    #|  ret 0
    #|}
    #|
  match @qbe.interpret(src) {
    Ok((@interp.VInt(v), out)) => {
      assert_eq(v, 0L)
      assert_true(out.contains("fib(89)="))
    }
    Ok(_) => fail("unexpected kind")
    Err(@util.QbeError::CompileError(m)) => fail("interpret failed: \{m}")
    Err(@util.QbeError::Ice(m)) => fail("ice: \{m}")
    Err(@util.QbeError::ParseError(_, _, m)) => fail("parse: \{m}")
  }
}

///|
async test "interpret: exit builtin ends with the code" {
  let src =
    #|export function l $main() {
    #|@start
    #|  %r =l call $exit(l 5)
    #|  ret 0
    #|}
    #|
  match @qbe.interpret(src) {
    Ok((@interp.VInt(v), _out)) => assert_eq(v, 5L)
    Ok(_) => fail("unexpected result kind")
    Err(@util.QbeError::CompileError(m)) => fail("interpret failed: \{m}")
    Err(@util.QbeError::Ice(m)) => fail("ice: \{m}")
    Err(@util.QbeError::ParseError(_, _, m)) => fail("parse: \{m}")
  }
}

///|
async test "interpret: extern hook is consulted first" {
  let src =
    #|export function l $main() {
    #|@start
    #|  %r =l call $answer(l 40)
    #|  ret %r
    #|}
    #|
  let hook : (String, Array[@interp.InterpValue]) -> @interp.InterpValue? = fn(
    name,
    args,
  ) {
    if name == "answer" {
      match args.get(0) {
        Some(@interp.VInt(v)) => Some(@interp.VInt(v + 2L))
        _ => None
      }
    } else {
      None
    }
  }
  match @qbe.interpret(src, hook=Some(hook)) {
    Ok((@interp.VInt(v), _out)) => assert_eq(v, 42L)
    Ok(_) => fail("unexpected result kind")
    Err(@util.QbeError::CompileError(m)) => fail("interpret failed: \{m}")
    Err(@util.QbeError::Ice(m)) => fail("ice: \{m}")
    Err(@util.QbeError::ParseError(_, _, m)) => fail("parse: \{m}")
  }
}

///|
async test "interpret: parse errors propagate" {
  match @qbe.interpret("export function w $f( { @start ret 0 }\n") {
    Err(@util.QbeError::ParseError(_, _, _)) => ()
    _ => fail("expected a parse error")
  }
}
