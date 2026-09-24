///|
// White-box tests for ARM64 instruction selection.

///|
fn arm64_isel_parse_frontend(
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
  let _ = @abi_arm64.abi_arm64(f, typs, false, interner, false, typs)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  (f, interner, typs)
}

///|
// Collect the op sequence of the whole function.
fn arm64_sel_ops(f : @types.Fn) -> Array[@types.Op] {
  let ops : Array[@types.Op] = []
  for id in f.def_order {
    for ins in f.blks[id].ins {
      ops.push(ins.op)
    }
  }
  ops
}

///|
test "arm64 isel: compare and branch lower to cmp + flags jump" {
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
  let (f, interner, typs) = arm64_isel_parse_frontend(src)
  let _ = isel_arm64(f, interner, false, typs)
  let ops = arm64_sel_ops(f)
  // the comparison becomes an arm64 cmp (Acmp); no flags op remains because
  // the branch consumed it
  assert_true(ops.contains(@types.Acmp))
  assert_true(!ops.contains(@types.Flagieq))
  // the terminator is a flags-based conditional jump (Jjf family)
  let start = f.blks[f.start_id]
  let code = start.jmp.kind.index()
  assert_true(code >= @types.Jjfieq.index())
  assert_true(code <= @types.Jjffuo.index())
  // amd64-style flag materialization never appears
  assert_true(!ops.contains(@types.Xcmp))
}

///|
test "arm64 isel: comparison result keeps the flags op" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %c =w cslew %a, %b
    #|  jnz %c, @t, @t
    #|@t
    #|  ret %c
    #|}
    #|
  let (f, interner, typs) = arm64_isel_parse_frontend(src)
  let _ = isel_arm64(f, interner, false, typs)
  // the comparison value is used by the caller of jnz too (ret %c after
  // the ssa copy), so the flags op materializes into the destination
  let mut has_flag = false
  for id in f.def_order {
    for ins in f.blks[id].ins {
      let idx = ins.op.index()
      if idx >= @types.Flagieq.index() && idx <= @types.Flagfuo.index() {
        has_flag = true
      }
    }
  }
  assert_true(has_flag)
}

///|
test "arm64 isel: division stays a native sdiv (no amd64 xidiv)" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w div %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = arm64_isel_parse_frontend(src)
  let _ = isel_arm64(f, interner, false, typs)
  let ops = arm64_sel_ops(f)
  assert_true(ops.contains(@types.Div))
  assert_true(!ops.contains(@types.Xidiv))
  assert_true(!ops.contains(@types.Sign))
}

///|
test "arm64 isel: fast alloc resolves to a 4-byte-unit stack slot" {
  let src =
    #|export function w $f() {
    #|@start
    #|  %p =l alloc8 8
    #|  storew 42, %p
    #|  %x =w call $g(l %p)
    #|  ret %x
    #|}
    #|
  let (f, interner, typs) = arm64_isel_parse_frontend(src)
  let _ = isel_arm64(f, interner, false, typs)
  let start = f.blks[f.start_id]
  for ins in start.ins {
    assert_true(ins.op != @types.Alloc8)
  }
  // 8 bytes -> two 4-byte slot units
  assert_eq(f.slot, 2)
}

///|
test "arm64 isel: float constants are stashed into the rodata pool" {
  let src =
    #|function d $f(d %x) {
    #|@start
    #|  %y =d add %x, d_2.25
    #|  ret %y
    #|}
    #|
  let (f, interner, typs) = arm64_isel_parse_frontend(src)
  let _ = isel_arm64(f, interner, false, typs)
  // the constant went through gasstash: at least one pool entry exists
  assert_true(@types.fp_stash_len() >= 1)
  // and the selection emitted a Load from the materialized address
  let start = f.blks[f.start_id]
  let mut loads = 0
  for ins in start.ins {
    if ins.op == @types.Load && ins.cls == @types.Kd {
      loads = loads + 1
    }
  }
  assert_true(loads >= 1)
  @types.fp_stash_reset()
}

///|
test "arm64 isel: immediate folding keeps small constants in cmp" {
  let src =
    #|function w $f(w %a) {
    #|@start
    #|  %c =w csltw %a, 100
    #|  jnz %c, @t, @e
    #|@t
    #|  jmp @e
    #|@e
    #|  ret 0
    #|}
    #|
  let (f, interner, typs) = arm64_isel_parse_frontend(src)
  let _ = isel_arm64(f, interner, false, typs)
  // 100 fits in the 12-bit immediate window: no constant materialization
  // copy precedes the cmp
  let start = f.blks[f.start_id]
  let mut copies = 0
  for ins in start.ins {
    if ins.op == @types.Copy && ins.to.is_tmp() {
      // ignore the ABI parameter copies from machine registers
      if ins.arg1.is_tmp() && ins.arg1.tmp_val() < @types.Arm64Tmp0 {
        continue
      }
      copies = copies + 1
    }
  }
  assert_eq(copies, 0)
}
