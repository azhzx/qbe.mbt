///|
// Tests for the spiller (C spill.c) and loop cost aggregation (fillcost).

///|
// Bring a parsed function through the real pipeline up to the spiller:
// frontend passes -> ABI lowering -> isel -> liveness -> loop costs.
fn spill_parse_pipeline(
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
  (f, interner, typs)
}

///|
// Count spill reload/store instructions: any Load/Store* family op.
fn count_mem_ops(f : @types.Fn) -> Int {
  let mut n = 0
  for id in f.def_order {
    for ins in f.blks[id].ins {
      if ins.op.is_load() || ins.op.is_store() {
        n = n + 1
      }
    }
  }
  n
}

///|
test "spill: low pressure function needs no spill stores" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = spill_parse_pipeline(src)
  let dbg = spill(f, false, interner, typs)
  assert_eq(dbg, "")
  assert_eq(count_mem_ops(f), 0)
}

///|
test "spill: register pressure above NGPS forces spill stores" {
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
  let (f, interner, typs) = spill_parse_pipeline(src)
  let _ = spill(f, false, interner, typs)
  assert_true(count_mem_ops(f) > 0)
}

///|
test "spill: debug dump shows the rewritten function" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = spill_parse_pipeline(src)
  let dbg = spill(f, true, interner, typs)
  assert_true(dbg.contains("After spilling"))
}

///|
test "fillcost: loop information dump toggles with print_dbg" {
  let src =
    #|function w $f(w %n) {
    #|@start
    #|@loop
    #|  %i =w add %n, 1
    #|  jnz %i, @loop, @exit
    #|@exit
    #|  ret %i
    #|}
    #|
  let (f, interner, typs) = spill_parse_pipeline(src)
  @cfg.fillloop(f)
  let quiet = fillcost(f, false)
  assert_eq(quiet, "")
  let dbg = fillcost(f, true)
  assert_true(dbg.contains("Loop information"))
}
