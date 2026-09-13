// White-box tests for the LoongArch (LP64D) ABI lowering.

///|
// Bring a parsed function through the target-agnostic pipeline up to the
// la64 ABI lowering (mirrors rega_wbtest.mbt's helper, stopping before isel).
fn la64_abi_parse_pipeline(
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
  let _ = abi_la64(f, typs, false, interner, typs)
  (f, interner, typs)
}

///|
// Collect the source register of a Copy instruction (for parameter checks).
fn la64_copy_src(ins : @types.Ins) -> Int {
  if ins.op == @types.Copy && ins.arg1.is_tmp() {
    ins.arg1.tmp_val()
  } else {
    -1
  }
}

///|
test "la64 abi: int params come from a0/a1, float params from fa0" {
  let src =
    #|function w $f(w %a, w %b, d %x) {
    #|@start
    #|  ret 0
    #|}
    #|
  let (f, _interner, _typs) = la64_abi_parse_pipeline(src)
  let start = f.blks[f.start_id]
  let mut int_copies = 0
  let mut float_copy_seen = false
  for ins in start.ins {
    let s = la64_copy_src(ins)
    if s == @types.LA_A0 || s == @types.LA_A1 {
      int_copies = int_copies + 1
    }
    if s == @types.LA_FA0 {
      float_copy_seen = true
    }
  }
  assert_eq(int_copies, 2)
  assert_true(float_copy_seen)
}

///|
test "la64 abi: call result register counts are encoded in the call ref" {
  // Regression test: without the return-value counts in the call ref,
  // rega treated a0 as clobbered and evicted the call result to a
  // callee-saved register.
  let src =
    #|function w $f(w %n) {
    #|@start
    #|  %d =w call $g(w %n)
    #|  ret %d
    #|
    #|}
    #|
  let (f, _interner, _typs) = la64_abi_parse_pipeline(src)
  let mut found_call = false
  for id in f.def_order {
    for ins in f.blks[id].ins {
      if ins.op == @types.Call {
        found_call = true
        let (bits, ni, nf) = ins.arg2.la64_retregs()
        assert_true((bits & (1UL << @types.LA_A0)) != 0UL)
        assert_eq(ni, 1)
        assert_eq(nf, 0)
      }
    }
  }
  assert_true(found_call)
}

///|
test "la64 abi: float call result encodes fa0" {
  let src =
    #|function d $f(d %x) {
    #|@start
    #|  %r =d call $g(d %x)
    #|  ret %r
    #|
    #|}
    #|
  let (f, _interner, _typs) = la64_abi_parse_pipeline(src)
  let mut found_call = false
  for id in f.def_order {
    for ins in f.blks[id].ins {
      if ins.op == @types.Call {
        found_call = true
        let (bits, ni, nf) = ins.arg2.la64_retregs()
        assert_true((bits & (1UL << @types.LA_FA0)) != 0UL)
        assert_eq(ni, 0)
        assert_eq(nf, 1)
      }
    }
  }
  assert_true(found_call)
}

///|
test "la64 abi: return value goes to a0 / fa0" {
  let src =
    #|function w $f(w %a) {
    #|@start
    #|  ret %a
    #|}
    #|
  let (f, _interner, _typs) = la64_abi_parse_pipeline(src)
  let start = f.blks[f.start_id]
  let mut ret_to_a0 = false
  for ins in start.ins {
    if ins.op == @types.Copy &&
      ins.to.is_tmp() &&
      ins.to.tmp_val() == @types.LA_A0 {
      ret_to_a0 = true
    }
  }
  assert_true(ret_to_a0)
}
