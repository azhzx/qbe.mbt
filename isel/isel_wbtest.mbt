///|
// Tests for amd64 instruction selection (C amd64/isel.c).
// The helper mirrors the real pipeline: target-agnostic frontend passes, then
// SysV ABI lowering, then isel — the exact state isel receives in production.

///|
fn isel_parse_frontend(
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
  (f, interner, typs)
}

///|
test "isel: plain add survives unchanged" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = isel_parse_frontend(src)
  let _ = isel(f, interner, false, typs)
  let start = f.blks[f.start_id]
  let mut adds = 0
  for ins in start.ins {
    if ins.op == @types.Add {
      adds = adds + 1
      assert_true(!ins.to.is_none())
      assert_true(!ins.arg1.is_none())
      assert_true(!ins.arg2.is_none())
    }
  }
  assert_eq(adds, 1)
}

///|
test "isel: division by a constant forces the divisor into a temp" {
  let src =
    #|function w $f(w %a) {
    #|@start
    #|  %s =w div %a, 7
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = isel_parse_frontend(src)
  let _ = isel(f, interner, false, typs)
  let start = f.blks[f.start_id]
  let mut divs = 0
  for ins in start.ins {
    if ins.op == @types.Xidiv {
      divs = divs + 1
      // amd64 idiv cannot take an immediate; the divisor must be a temp
      assert_true(ins.arg1.is_tmp())
      assert_true(ins.arg1.tmp_val() >= @types.Tmp0)
    }
  }
  assert_eq(divs, 1)
}

///|
test "isel: alloc4 is resolved to a stack slot at isel time" {
  let src =
    #|export function w $f() {
    #|@start
    #|  %p =l alloc4 8
    #|  storew 42, %p
    #|  %x =w call $g(l %p)
    #|  ret %x
    #|}
    #|
  let (f, interner, typs) = isel_parse_frontend(src)
  let _ = isel(f, interner, false, typs)
  let start = f.blks[f.start_id]
  // the alloc has been resolved to a stack slot; no Alloc4 instruction remains
  for ins in start.ins {
    assert_true(ins.op != @types.Alloc4)
  }
  assert_true(f.slot >= 2)
}

///|
test "isel: branch structure is preserved" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %c =w cslew %a, %b
    #|  jnz %c, @t, @e
    #|@t
    #|  jmp @e
    #|@e
    #|  ret 0
    #|}
    #|
  let (f, interner, typs) = isel_parse_frontend(src)
  let _ = isel(f, interner, false, typs)
  let start = f.blks[f.start_id]
  // the compare+branch pair is lowered to a flags-based conditional jump
  assert_true(start.jmp.kind != @types.Jjnz)
  assert_true(start.jmp.kind != @types.Jjmp)
  assert_true(start.jmp.s1 >= 0 && start.jmp.s2 >= 0)
}

///|
test "isel: debug dump toggles with print_dbg" {
  let src =
    #|function w $f(w %a) {
    #|@start
    #|  ret %a
    #|}
    #|
  let (f, interner, typs) = isel_parse_frontend(src)
  let quiet = isel(f, interner, false, typs)
  assert_eq(quiet, "")
  let (f2, interner2, typs2) = isel_parse_frontend(src)
  let dbg = isel(f2, interner2, true, typs2)
  assert_true(dbg.contains("After instruction selection"))
}
