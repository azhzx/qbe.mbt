// White-box tests for ARM64 assembly emission (C arm64_emitfn shape).

///|
// Bring a parsed function through the whole arm64 pipeline so that it is
// ready for emission.
fn arm64_emit_parse_pipeline(
  text : String,
) -> (@types.Fn, @util.Interner, Array[@types.Typ]) raise {
  let lexer = @lexer.Lexer::new(text, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  let typs = parser.get_typs()
  let interner = parser.interner_ref()
  @types.init_arm64_target()
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
  let _ = @abi_arm64.abi_arm64(f, typs, false, interner, typs)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let _ = @isel_arm64.isel_arm64(f, interner, false, typs)
  @types.init_arm64_target()
  @cfg.fillrpo(f)
  let _ = @live.filllive(f, false)
  let _ = @spill.fillcost(f, false)
  let _ = @spill.spill(f, false, interner, typs)
  let _ = @rega.rega(f, false, interner, typs)
  @cfg.fillrpo(f)
  @cfg.simpljmp(f)
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  (f, interner, typs)
}

///|
test "arm64 emit: simple add function" {
  let src =
    #|export
    #|function w $add(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = arm64_emit_parse_pipeline(src)
  let asm = emit_arm64(f, interner, typs)
  inspect(
    asm,
    content=(
      #|.text
      #|.balign 16
      #|.globl add
      #|add:
      #|	hint	#34
      #|	stp	x29, x30, [sp, -16]!
      #|	mov	x29, sp
      #|	add	w0, w0, w1
      #|	ldp	x29, x30, [sp], 16
      #|	ret
      #|.type add, @function
      #|.size add, .-add
      #|

    ),
  )
}

///|
test "arm64 emit: conditional branch and loop labels" {
  let src =
    #|export
    #|function w $count(w %n) {
    #|@start
    #|  jnz %n, @loop, @done
    #|
    #|@loop
    #|  %n2 =w phi @start %n, @loop %m
    #|  %m =w sub %n2, 1
    #|  %c =w csgtw %m, 0
    #|  jnz %c, @loop, @done
    #|
    #|@done
    #|  ret 0
    #|
    #|}
  let (f, interner, typs) = arm64_emit_parse_pipeline(src)
  let asm = emit_arm64(f, interner, typs)
  inspect(
    asm,
    content=(
      #|.text
      #|.balign 16
      #|.globl count
      #|count:
      #|	hint	#34
      #|	stp	x29, x30, [sp, -16]!
      #|	mov	x29, sp
      #|	cmp	w0, #0
      #|	beq	.L2
      #|.L1:
      #|	mov	w1, #1
      #|	sub	w0, w0, w1
      #|	cmp	w0, #0
      #|	bgt	.L1
      #|.L2:
      #|	mov	w0, #0
      #|	ldp	x29, x30, [sp], 16
      #|	ret
      #|.type count, @function
      #|.size count, .-count
      #|







    ),
  )
}

///|
test "arm64 emit: vararg prologue saves the argument registers" {
  let src =
    #|export
    #|function w $f(w %n, ...) {
    #|@start
    #|  %ap =l alloc8 24
    #|  vastart %ap
    #|  ret %n
    #|}
    #|
  let (f, interner, typs) = arm64_emit_parse_pipeline(src)
  let asm = emit_arm64(f, interner, typs)
  assert_true(asm.contains("\tstr\tq7, [sp, -16]!\n"))
  assert_true(asm.contains("\tstp\tx0, x1, [sp, -16]!\n"))
  assert_true(asm.contains("\tmov\tx29, sp\n"))
  assert_true(asm.contains("\tret\n"))
}
