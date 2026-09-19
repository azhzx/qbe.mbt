// White-box tests for LoongArch assembly emission (C emitfn shape).

///|
// Bring a parsed function through the whole la64 pipeline so that it is
// ready for emission.
fn la64_emit_parse_pipeline(
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
  let _ = @abi_la64.abi_la64(f, typs, false, interner, typs)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let _ = @isel_la64.isel_la64(f, interner, false, typs)
  @types.init_la64_target()
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
test "la64 emit: simple add function" {
  let src =
    #|export
    #|function w $add(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = la64_emit_parse_pipeline(src)
  let asm = emit_la64(f, interner, ".L", "", typs)
  inspect(
    asm,
    content=(
      #|	.globl add
      #|	.type add, @function
      #|add:
      #|	st.d $fp, $sp, -16
      #|	st.d $ra, $sp, -8
      #|	addi.d $fp, $sp, -16
      #|	addi.d $sp, $sp, -16
      #|	add.w $a0, $a0, $a1
      #|	addi.d $sp, $fp, 16
      #|	ld.d $ra, $fp, 8
      #|	ld.d $fp, $fp, 0
      #|	ret
      #|	.size add, .-add
      #|
    ),
  )
}

///|
test "la64 emit: conditional branch and loop labels" {
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
  let (f, interner, typs) = la64_emit_parse_pipeline(src)
  let asm = emit_la64(f, interner, ".L", "", typs)
  inspect(
    asm,
    content=(
      #|	.globl count
      #|	.type count, @function
      #|count:
      #|	st.d $fp, $sp, -16
      #|	st.d $ra, $sp, -8
      #|	addi.d $fp, $sp, -16
      #|	addi.d $sp, $sp, -16
      #|	beqz $a0, .L2
      #|.L1:
      #|	li.d $t0, 1
      #|	sub.w $a0, $a0, $t0
      #|	li.d $t0, 0
      #|	slt $t0, $t0, $a0
      #|	bnez $t0, .L1
      #|.L2:
      #|	li.d $a0, 0
      #|	addi.d $sp, $fp, 16
      #|	ld.d $ra, $fp, 8
      #|	ld.d $fp, $fp, 0
      #|	ret
      #|	.size count, .-count
      #|
    ),
  )
}

///|
test "la64 emit: data directive spellings" {
  // gasemitdat_la64 uses the portable ELF spellings (.balign, .half, .word)
  let d0 = @types.Dat::start()
  let dn = @types.Dat::name("tbl", true)
  let db = @types.Dat::byte(7)
  let sb = StringBuilder::StringBuilder()
  gasemitdat_la64(d0, ".L", "", sb)
  gasemitdat_la64(dn, ".L", "", sb)
  gasemitdat_la64(db, ".L", "", sb)
  inspect(
    sb.to_string(),
    content=(
      #|.data
      #|.balign 8
      #|.globl tbl
      #|tbl:
      #|	.byte 7
      #|
    ),
  )
}
