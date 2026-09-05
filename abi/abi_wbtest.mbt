///|
// Tests for SysV ABI lowering (C abi / amd64_sysv.c).
// Each test parses a small IL snippet, runs the same target-agnostic frontend
// passes as the real pipeline (up to but excluding abi), then lowers the ABI
// and inspects the result.

///|
// Parse IL text and run the frontend pipeline up to (not including) abi(),
// mirroring pipeline.mbt::run_passes so the function is in the same state the
// real compiler hands to the ABI stage.
fn abi_parse_frontend(
  text : String,
) -> (@types.Fn, @util.Interner, Array[@types.Typ]) raise {
  let lexer = @lexer.Lexer::new(text, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  let typs = parser.get_typs()
  let interner = parser.interner_ref()
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  @ssa.memopt(f)
  @cfg.filldom(f)
  @cfg.fillfron(f)
  let _ = @live.filllive(f, false)
  @ssa.phiins(f)
  @ssa.renblk(f)
  @ssa.filluse(f)
  @ssa.ssacheck(f)
  @cfg.fillloop(f)
  @cfg.fillalias(f)
  let _ = @ssa.loadopt(f, false, interner, typs)
  @ssa.filluse(f)
  @ssa.ssacheck(f)
  let _ = @ssa.copy(f, false, interner, typs)
  @ssa.filluse(f)
  let _ = @fold.fold(f, false, interner, typs)
  (f, interner, typs)
}

///|
test "abi: two word parameters come in via RDI and RSI" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let dbg = abi(f, typs, true, interner, typs)
  // parameters are copied out of the SysV integer argument registers
  assert_true(dbg.contains("R5")) // RDI
  assert_true(dbg.contains("R4")) // RSI
  // the result is returned through RAX
  assert_true(dbg.contains("R1")) // RAX
  assert_true(dbg.contains("After ABI lowering"))
}

///|
test "abi: float parameters come in via XMM registers" {
  let src =
    #|function s $f(s %a, s %b) {
    #|@start
    #|  %s =s add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let dbg = abi(f, typs, true, interner, typs)
  assert_true(dbg.contains("R17")) // XMM0
  assert_true(dbg.contains("R18")) // XMM1
}

///|
test "abi: call lowering passes arguments in registers" {
  let src =
    #|export function w $main() {
    #|@start
    #|  %r =w call $g(w 1, w 2)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let dbg = abi(f, typs, true, interner, typs)
  assert_true(dbg.contains("call $g"))
  assert_true(dbg.contains("R5")) // first argument into RDI
  assert_true(dbg.contains("R1")) // result taken from RAX
}

///|
test "abi: more than six integer arguments spill to the stack" {
  let src =
    #|export function w $main() {
    #|@start
    #|  %r =w call $g(w 1, w 2, w 3, w 4, w 5, w 6, w 7)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let dbg = abi(f, typs, true, interner, typs)
  // stack space is allocated for the 7th argument
  assert_true(dbg.contains("salloc"))
}

///|
test "abi: void function returns without a value" {
  let src =
    #|export function $f() {
    #|@start
    #|  ret
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let dbg = abi(f, typs, true, interner, typs)
  assert_true(dbg.contains("ret"))
  // no RAX copy is emitted for a value-less return
  assert_true(!dbg.contains("=w copy R1"))
}

///|
test "abi: no debug output when print_dbg is false" {
  let src =
    #|function w $f(w %a) {
    #|@start
    #|  ret %a
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let dbg = abi(f, typs, false, interner, typs)
  assert_eq(dbg, "")
}

///|
test "abi: lowering mutates the function in place" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let _ = abi(f, typs, false, interner, typs)
  // all Par instructions in the entry block have been consumed
  for id in f.def_order {
    for ins in f.blks[id].ins {
      assert_true(!ins.op.is_par())
    }
  }
}
