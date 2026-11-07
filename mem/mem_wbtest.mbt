///|
// White-box tests for the mem pass (C mem.c).

///|
fn parse_mem_fn(
  text : String,
) -> (@types.Fn, @util.Interner, Array[@types.Typ]) raise {
  let lexer = @lexer.Lexer::new(text, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  (parser.get_funcs()[0], parser.interner_ref(), parser.get_typs())
}

///|
// Run the C main.c prologue up to (but not including) coalesce.
fn run_before_coalesce(
  f : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
) -> Unit raise {
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let _ = promote(f, false, interner, typs)
  @ssa.filluse(f)
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
  @cfg.fillalias(f)
}

///|
test "promote: uniform slot is replaced by copies" {
  let src =
    #|function w $f() {
    #|@start
    #|  %p =l alloc4 4
    #|  storew 42, %p
    #|  %v =w loadw %p
    #|  ret %v
    #|}
    #|
  let (f, interner, typs) = parse_mem_fn(src)
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let alloc_t = f.blks[0].ins[0].to.tmp_val()
  let v_t = f.blks[0].ins[2].to.tmp_val()
  let dbg = promote(f, true, interner, typs)
  assert_eq(
    dbg,
    "\n> After slot promotion:\n" +
    "function $f() {\n" +
    "@start\n" +
    "\tnop\n" +
    "\t%p =w copy 42\n" +
    "\t%v =w copy %p\n" +
    "\tretw %v\n" +
    "}\n",
  )
  let ins = f.blks[0].ins
  assert_true(ins[0].op == @types.Nop)
  assert_true(ins[1].op == @types.Copy)
  assert_true(ins[1].to == @types.Ref::tmp(alloc_t))
  assert_true(ins[1].arg2.is_none())
  assert_true(ins[1].arg1.is_con())
  assert_true(ins[2].op == @types.Copy)
  assert_true(ins[2].to == @types.Ref::tmp(v_t))
  assert_true(ins[2].arg1 == @types.Ref::tmp(alloc_t))
  // The store use is dropped (it became the copy destination); the load use
  // remains, so nuse is still 1 while ndef is back to 1.
  assert_true(f.tmps[alloc_t].nuse == 1)
  assert_true(f.tmps[alloc_t].ndef == 1)
}

///|
test "coalesce: non-uniform slot is fused and substituted" {
  let src =
    #|function w $h() {
    #|@start
    #|  %p =l alloc4 4
    #|  storeb 1, %p
    #|  %a =w loadsw %p
    #|  %q =l alloc4 4
    #|  storeb 2, %q
    #|  %b =w loadsw %q
    #|  %r =w add %a, %b
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = parse_mem_fn(src)
  run_before_coalesce(f, interner, typs)
  let dbg = coalesce(f, true, interner, typs)
  assert_eq(
    dbg,
    "\n> Slot coalescing:\n" +
    "\tfuse (  4b) [ %p[1,2) %q[3,4) ]\n" +
    "\tsums 0/4/8 (killed/fused/total)\n" +
    "\n" +
    "function $h() {\n" +
    "@start\n" +
    "\t%p =l alloc4 4\n" +
    "\tstoreb 1, %p\n" +
    "\t%a =w loadsw %p\n" +
    "\tnop\n" +
    "\tstoreb 2, %p\n" +
    "\t%b =w loadsw %p\n" +
    "\t%r =w add %a, %b\n" +
    "\tretw %r\n" +
    "}\n",
  )
}

///|
test "coalesce: fully dead slot is killed" {
  let src =
    #|function w $g() {
    #|@start
    #|  %p =l alloc4 4
    #|  storeb 1, %p
    #|  storew 2, %p
    #|  %a =w loadw %p
    #|  ret %a
    #|}
    #|
  let (f, interner, typs) = parse_mem_fn(src)
  run_before_coalesce(f, interner, typs)
  let dbg = coalesce(f, true, interner, typs)
  assert_eq(
    dbg,
    "\n> Slot coalescing:\n" +
    "\tkill [ %p ]\n" +
    "\tsums 4/0/4 (killed/fused/total)\n" +
    "\n" +
    "function $g() {\n" +
    "@start\n" +
    "\tnop\n" +
    "\tnop\n" +
    "\tnop\n" +
    "\t%a =w copy 2\n" +
    "\tretw %a\n" +
    "}\n",
  )
}

///|
test "coalesce: loop back-edge keeps the slot live" {
  let src =
    #|function w $m(w %n) {
    #|@start
    #|  %p =l alloc4 4
    #|  %q =l add %p, 0
    #|  storew 1, %q
    #|  jmp @body
    #|@body
    #|  %i =w phi @start 0, @body %i1
    #|  %a =w loadw %q
    #|  storew 2, %q
    #|  %i1 =w add %i, 1
    #|  %c =w csltw %i1, %n
    #|  jnz %c, @body, @end
    #|@end
    #|  ret %a
    #|}
    #|
  let (f, interner, typs) = parse_mem_fn(src)
  run_before_coalesce(f, interner, typs)
  let dbg = coalesce(f, true, interner, typs)
  // The generated tmp names depend on the process-wide newtmp counter, so
  // assert only the deterministic coalesce header and the resulting shape.
  assert_true(
    dbg.contains(
      "\n> Slot coalescing:\n" +
      "\tkill [ %p ]\n" +
      "\tsums 4/0/4 (killed/fused/total)\n" +
      "\n" +
      "function $m() {\n",
    ),
  )
  let start = f.blks[f.start_id]
  assert_true(start.ins[1].op == @types.Nop)
  assert_true(start.ins[2].op == @types.Nop)
  assert_true(start.ins[3].op == @types.Nop)
  assert_true(f.blks[f.find_blk("body")].phi.length() > 0)
}

///|
// C mem.c load(): the position is added to a slot's range only when the
// loaded bits survive the slot's write mask (s->l stays non-zero). A slot
// whose only read falls outside the bytes ever written through it is dead.
// The reference prints "kill [ %p ]" and replaces the load with copy UNDEF.
test "coalesce: a slot only read outside its write mask is dead" {
  let src =
    #|function w $f() {
    #|@start
    #|  %p =l alloc8 16
    #|  storew 1, %p
    #|  %q =l add %p, 8
    #|  %v =w loadw %q
    #|  ret %v
    #|}
    #|
  let (f, interner, typs) = parse_mem_fn(src)
  run_before_coalesce(f, interner, typs)
  let dbg = coalesce(f, true, interner, typs)
  assert_eq(
    dbg,
    "\n> Slot coalescing:\n" +
    "\tkill [ %p ]\n" +
    "\tsums 16/0/16 (killed/fused/total)\n" +
    "\n" +
    "function $f() {\n" +
    "@start\n" +
    "\tnop\n" +
    "\tnop\n" +
    "\tnop\n" +
    "\t%v =w copy UNDEF\n" +
    "\tretw %v\n" +
    "}\n",
  )
}

///|
// C mem.c's fixup loop compares the slots their addresses were *fused* into
// (s->s == s0->s), not the slot entries themselves. When a blit's source and
// destination coalesce into one slot with source before destination, the
// reference flips the direction by negating the blit1 size.
test "coalesce: blit direction flips when both addresses fuse into one slot" {
  let src =
    #|type :t = align 8 { l 1, l 1 }
    #|function :t $f() {
    #|@start
    #|  %p =l alloc8 16
    #|  %q =l alloc8 16
    #|  storel 1, %p
    #|  %s =l add %q, 8
    #|  blit %p, %s, 8
    #|  storel 2, %q
    #|  ret %q
    #|}
    #|
  let (f, interner, typs) = parse_mem_fn(src)
  run_before_coalesce(f, interner, typs)
  let dbg = coalesce(f, true, interner, typs)
  assert_eq(
    dbg,
    "\n> Slot coalescing:\n" +
    "\tfuse ( 16b) [ %p[1,2) %q[2,4) ]\n" +
    "\tsums 0/16/32 (killed/fused/total)\n" +
    "\n" +
    "function $f() {\n" +
    "@start\n" +
    "\t%p =l alloc8 16\n" +
    "\tnop\n" +
    "\tstorel 1, %p\n" +
    "\t%s =l add %p, 8\n" +
    "\tblit0 %p, %s\n" +
    "\tblit1 -8\n" +
    "\tstorel 2, %p\n" +
    "\tretc %p, :t\n" +
    "}\n",
  )
}

///|
// A dead slot can be the *source* of a blit whose destination stays live.
// C mem.c nops both halves of the pair when it kills such a use; noping only
// the blit0 leaves a lone blit1, which the port later rejects as an unknown
// instruction (the reference compiles this input).
test "coalesce: killing a dead blit source removes both halves" {
  let src =
    #|type :t = align 8 { l 1 }
    #|function :t $f() {
    #|@start
    #|  %p =l alloc8 8
    #|  %q =l alloc8 8
    #|  storel 1, %q
    #|  blit %p, %q, 8
    #|  ret %q
    #|}
    #|
  let (f, interner, typs) = parse_mem_fn(src)
  run_before_coalesce(f, interner, typs)
  let dbg = coalesce(f, true, interner, typs)
  assert_eq(
    dbg,
    "\n> Slot coalescing:\n" +
    "\tkill [ %p ]\n" +
    "\tfuse (  8b) [ %q[2,3) ]\n" +
    "\tsums 8/0/16 (killed/fused/total)\n" +
    "\n" +
    "function $f() {\n" +
    "@start\n" +
    "\tnop\n" +
    "\t%q =l alloc8 8\n" +
    "\tnop\n" +
    "\tnop\n" +
    "\tnop\n" +
    "\tretc %q, :t\n" +
    "}\n",
  )
}
