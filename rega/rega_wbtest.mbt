///|
// Tests for register allocation (C rega.c).

///|
// Bring a parsed function through the real pipeline up to rega:
// frontend passes -> ABI -> isel -> liveness -> loop costs -> spill.
fn rega_parse_pipeline(
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
  let _ = @abi.abi(f, typs, false, interner, typs)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let _ = @isel.isel(f, interner, false, typs)
  @cfg.fillrpo(f)
  let _ = @live.filllive(f, false)
  let _ = @spill.fillcost(f, false)
  let _ = @spill.spill(f, false, interner, typs)
  (f, interner, typs)
}

///|
test "rega: all instruction operands become physical registers" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = rega_parse_pipeline(src)
  let _ = rega(f, false, interner, typs)
  for id in f.def_order {
    for ins in f.blks[id].ins {
      if ins.to.is_tmp() {
        assert_true(ins.to.tmp_val() < @types.Tmp0)
      }
      if ins.arg1.is_tmp() {
        assert_true(ins.arg1.tmp_val() < @types.Tmp0)
      }
      if ins.arg2.is_tmp() {
        assert_true(ins.arg2.tmp_val() < @types.Tmp0)
      }
    }
  }
}

///|
test "rega: high-pressure function still allocates only physical registers" {
  let src =
    #|function w $f(w %a, w %b, w %c, w %d, w %e, w %f, w %g, w %h) {
    #|@start
    #|  %s1 =w add %a, %b
    #|  %s2 =w add %c, %d
    #|  %s3 =w add %e, %f
    #|  %s4 =w add %g, %h
    #|  %s5 =w add %s1, %s2
    #|  %s6 =w add %s3, %s4
    #|  %t =w add %s5, %s6
    #|  ret %t
    #|}
    #|
  let (f, interner, typs) = rega_parse_pipeline(src)
  let _ = rega(f, false, interner, typs)
  for id in f.def_order {
    for ins in f.blks[id].ins {
      if ins.arg1.is_tmp() {
        assert_true(ins.arg1.tmp_val() < @types.Tmp0)
      }
      if ins.arg2.is_tmp() {
        assert_true(ins.arg2.tmp_val() < @types.Tmp0)
      }
      if ins.to.is_tmp() {
        assert_true(ins.to.tmp_val() < @types.Tmp0)
      }
    }
  }
}

///|
test "rega: debug dump toggles with print_dbg" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = rega_parse_pipeline(src)
  let quiet = rega(f, false, interner, typs)
  assert_eq(quiet, "")
  let (f2, interner2, typs2) = rega_parse_pipeline(src)
  let dbg = rega(f2, true, interner2, typs2)
  assert_true(dbg.contains("After register allocation"))
}

///|
test "rega: loop body function allocates correctly" {
  let src =
    #|function w $f(w %n) {
    #|@start
    #|  jmp @loop
    #|@loop
    #|  %i =w add %n, 1
    #|  jnz %i, @loop, @exit
    #|@exit
    #|  ret %i
    #|}
    #|
  let (f, interner, typs) = rega_parse_pipeline(src)
  let _ = rega(f, false, interner, typs)
  for id in f.def_order {
    for ins in f.blks[id].ins {
      if ins.to.is_tmp() {
        assert_true(ins.to.tmp_val() < @types.Tmp0)
      }
      if ins.arg1.is_tmp() {
        assert_true(ins.arg1.tmp_val() < @types.Tmp0)
      }
    }
  }
}
