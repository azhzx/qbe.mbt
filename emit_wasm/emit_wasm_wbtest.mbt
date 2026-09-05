///|
// Tests for WAT emission (wasm text output).

///|
// Bring a parsed function through the wasm pipeline: target-agnostic frontend
// passes, then wasm ABI lowering and wasm instruction selection.
fn wat_parse_pipeline(
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
  let _ = @abi_wasm.abi_wasm(f, typs, false, interner, typs)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let _ = @isel_wasm.isel_wasm(f, interner, false, typs)
  (f, interner, typs)
}

///|
test "emit_fn: wasm function body snapshot" {
  let src =
    #|function w $add(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = wat_parse_pipeline(src)
  let sb = StringBuilder::new()
  emit_fn(f, interner, sb)
  inspect(
    sb.to_string(),
    content=(
      #|  (func $add
      #|(local $t66 i32)
      #|    local.get $t64
      #|    local.get $t65
      #|    i32.add
      #|    local.set $t66
      #|    local.get $t66
      #|    return
      #|  )
      #|
    ),
  )
}

///|
test "emit_wat_module: module opens and closes with memory" {
  let src =
    #|function w $one() {
    #|@start
    #|  ret 1
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let funcs = parser.get_funcs()
  let sb = StringBuilder::new()
  emit_wat_module(funcs, [], [], parser.interner_ref(), sb)
  let wat = sb.to_string()
  assert_true(wat.contains("(module"))
  assert_true(wat.contains("memory"))
  assert_true(wat.contains(")"))
}

///|
test "emit_fn: float computation emits f32 arithmetic" {
  let src =
    #|function s $f(s %a, s %b) {
    #|@start
    #|  %s =s add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = wat_parse_pipeline(src)
  let sb = StringBuilder::new()
  emit_fn(f, interner, sb)
  let wat = sb.to_string()
  assert_true(wat.contains("f32"))
}
