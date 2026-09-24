///|
// Tests for the wasm32 ABI lowering: Par/Arg are retained (the emitter needs
// them to declare wasm parameters and push call arguments) and Call keeps only
// its callee reference (no return-type operand on the wasm target).

///|
// Parse IL text and set up def_order so abi_wasm can iterate blocks.
fn wasm_abi_parse(text : String) -> @types.Fn raise {
  let lexer = @lexer.Lexer::new(text, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  @cfg.fillrpo(f)
  f
}

///|
test "abi_wasm: Arg becomes Nop, Par is kept" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let f = wasm_abi_parse(src)
  let _ = abi_wasm(f, [], false, @util.Interner::new(), [])
  let mut pars = 0
  for id in f.def_order {
    for ins in f.blks[id].ins {
      assert_true(!ins.op.is_arg())
      if ins.op.is_par() {
        pars = pars + 1
      }
    }
  }
  assert_eq(pars, 2)
}

///|
test "abi_wasm: call arguments are kept, call keeps callee only" {
  let src =
    #|export function w $main() {
    #|@start
    #|  %r =w call $g(w 1, w 2)
    #|  ret %r
    #|}
    #|
  let f = wasm_abi_parse(src)
  let _ = abi_wasm(f, [], false, @util.Interner::new(), [])
  let start = f.blks[f.start_id]
  let mut calls = 0
  let mut args = 0
  for ins in start.ins {
    match ins.op {
      @types.Call => {
        calls = calls + 1
        // callee reference preserved in arg1, return-type operand dropped
        assert_true(!ins.arg1.is_none())
        assert_true(ins.arg2.is_none())
      }
      @types.Arg | @types.Arge => {
        // Argument values stay on the instruction (arg1) so the emitter can
        // push them for the following call.
        args = args + 1
        assert_true(!ins.arg1.is_none())
      }
      @types.Nop => ()
      _ => ()
    }
  }
  assert_eq(calls, 1)
  assert_eq(args, 2)
}

///|
test "abi_wasm: non-call instructions are untouched" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  %t =w mul %s, %a
    #|  ret %t
    #|}
    #|
  let f = wasm_abi_parse(src)
  let _ = abi_wasm(f, [], false, @util.Interner::new(), [])
  let start = f.blks[f.start_id]
  let mut adds = 0
  let muls = 0
  for ins in start.ins {
    if ins.op == @types.Add {
      adds = adds + 1
      assert_true(!ins.to.is_none())
      assert_true(!ins.arg1.is_none())
      assert_true(!ins.arg2.is_none())
    }
  }
  assert_eq(adds, 1)
  assert_eq(muls, 0)
}

///|
test "abi_wasm: debug output toggles with print_dbg" {
  let src =
    #|function w $f(w %a) {
    #|@start
    #|  ret %a
    #|}
    #|
  let f = wasm_abi_parse(src)
  let quiet = abi_wasm(f, [], false, @util.Interner::new(), [])
  assert_eq(quiet, "")
  let dbg = abi_wasm(f, [], true, @util.Interner::new(), [])
  assert_true(dbg.contains("After wasm ABI lowering"))
}
