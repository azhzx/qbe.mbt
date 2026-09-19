// White-box tests for LoongArch instruction selection.

///|
// Bring a parsed function through the pipeline up to la64 instruction
// selection.
fn la64_isel_parse_pipeline(
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
  let _ = isel_la64(f, interner, false, typs)
  (f, interner, typs)
}

///|
// Collect the op of every instruction in the function, in block order.
fn la64_sel_ops(f : @types.Fn) -> Array[@types.Op] {
  let ops : Array[@types.Op] = Array::new()
  for id in f.def_order {
    for ins in f.blks[id].ins {
      ops.push(ins.op)
    }
  }
  ops
}

///|
test "la64 isel: csgew lowers to slt + xor" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %r =w csgew %a, %b
    #|  ret %r
    #|}
    #|
  let (f, _interner, _typs) = la64_isel_parse_pipeline(src)
  let ops = la64_sel_ops(f)
  assert_true(ops.contains(@types.Csltl))
  assert_true(ops.contains(@types.Xor))
}

///|
test "la64 isel: ceql lowers to xor + sltu" {
  let src =
    #|function w $f(l %a, l %b) {
    #|@start
    #|  %r =w ceql %a, %b
    #|  ret %r
    #|}
    #|
  let (f, _interner, _typs) = la64_isel_parse_pipeline(src)
  let ops = la64_sel_ops(f)
  assert_true(ops.contains(@types.Cultl))
  assert_true(ops.contains(@types.Xor))
}

///|
test "la64 isel: csltw rewrites to the long form" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %r =w csltw %a, %b
    #|  ret %r
    #|}
    #|
  let (f, _interner, _typs) = la64_isel_parse_pipeline(src)
  let ops = la64_sel_ops(f)
  assert_true(ops.contains(@types.Csltl))
}

///|
test "la64 isel: constants are materialized into registers" {
  // mul has no immediate form on LoongArch: the constant must go
  // through a Copy (li) first.
  let src =
    #|function w $f(w %a) {
    #|@start
    #|  %r =w mul %a, 3
    #|  ret %r
    #|}
    #|
  let (f, _interner, _typs) = la64_isel_parse_pipeline(src)
  let ops = la64_sel_ops(f)
  assert_true(ops.contains(@types.Copy))
  assert_true(ops.contains(@types.Mul))
}

///|
test "la64 isel: fast allocs become slots" {
  // the address escapes into a call, so memopt cannot remove the alloc
  let src =
    #|export
    #|function w $f(w %v) {
    #|@start
    #|  %p =l alloc4 8
    #|  storew %v, %p
    #|  call $g(l %p)
    #|  ret 0
    #|}
    #|
    #|function $g(l %p) {
    #|@start
    #|  ret
    #|}
    #|
  let (f, _interner, _typs) = la64_isel_parse_pipeline(src)
  let start = f.blks[f.start_id]
  let mut saw_alloc = false
  for ins in start.ins {
    if ins.op == @types.Alloc4 ||
      ins.op == @types.Alloc8 ||
      ins.op == @types.Alloc16 {
      saw_alloc = true
    }
  }
  assert_true(!saw_alloc)
  // the alloc temporary got a stack slot (slot ids start at 0; unused
  // temporaries keep the sentinel -1)
  let mut has_slot = false
  for t in 0..<f.ntmp() {
    if f.tmps[t].slot >= 0 {
      has_slot = true
    }
  }
  assert_true(has_slot)
}
