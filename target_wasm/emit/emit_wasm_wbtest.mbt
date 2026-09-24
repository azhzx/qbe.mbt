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
  let sb = StringBuilder::StringBuilder()
  emit_fn(f, interner, sb)
  inspect(
    sb.to_string(),
    content=(
      #|  (func $add (param $t64 i32) (param $t65 i32) (result i32)
      #|(local $pc i32)
      #|(local $t66 i32)
      #|    i32.const 0
      #|    local.set $pc
      #|    (block $exit
      #|      (loop $dispatch
      #|        (block $case0
      #|          local.get $pc
      #|          br_table $case0
      #|        )
      #|        local.get $t64
      #|        local.get $t65
      #|        i32.add
      #|        local.set $t66
      #|        local.get $t66
      #|        return
      #|      )
      #|    )
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
  let sb = StringBuilder::StringBuilder()
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
  let sb = StringBuilder::StringBuilder()
  emit_fn(f, interner, sb)
  let wat = sb.to_string()
  assert_true(wat.contains("f32"))
}

///|
test "emit_fn: loop and phi lower to a dispatch loop" {
  let src =
    #|function w $sum_to(w %n) {
    #|@start
    #|  %i =w copy 0
    #|  %s =w copy 0
    #|@loop
    #|  %i2 =w phi @start %i, @body %i3
    #|  %s2 =w phi @start %s, @body %s3
    #|  %c =w csltw %i2, %n
    #|  jnz %c, @body, @end
    #|@body
    #|  %s3 =w add %s2, %i2
    #|  %i3 =w add %i2, 1
    #|  jmp @loop
    #|@end
    #|  ret %s2
    #|}
    #|
  let (f, interner, _typs) = wat_parse_pipeline(src)
  let sb = StringBuilder::StringBuilder()
  emit_fn(f, interner, sb)
  let wat = sb.to_string()
  assert_true(wat.contains("loop $dispatch"))
  assert_true(wat.contains("br_table"))
  assert_true(wat.contains("br $dispatch"))
}

///|
test "emit_fn: long constant uses i64.const" {
  let src =
    #|function l $one() {
    #|@start
    #|  %x =l copy 1
    #|  ret %x
    #|}
    #|
  let (f, interner, _typs) = wat_parse_pipeline(src)
  let sb = StringBuilder::StringBuilder()
  emit_fn(f, interner, sb)
  assert_true(sb.to_string().contains("i64.const 1"))
}

///|
test "emit_wat_module: data segment and global address resolve" {
  let src =
    #|data $g = { w 7 }
    #|export function w $get() {
    #|@start
    #|  %x =w loadw $g
    #|  ret %x
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let sb = StringBuilder::StringBuilder()
  emit_wat_module(
    parser.get_funcs(),
    parser.get_datas(),
    parser.get_order(),
    parser.interner_ref(),
    sb,
  )
  let wat = sb.to_string()
  assert_true(wat.contains("(data (i32.const 1024)"))
  assert_true(wat.contains("i32.const 1024"))
}
