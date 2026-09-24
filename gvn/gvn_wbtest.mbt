// White-box tests for the GVN and GCM passes.

///|
// Bring a parsed function through the real frontend pipeline up to (but not
// including) GVN.
fn gvn_pipeline(
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
  (f, interner, typs)
}

///|
fn count_op(f : @types.Fn, op : @types.Op) -> Int {
  let mut n = 0
  for id in f.def_order {
    for ins in f.blks[id].ins {
      if ins.op == op {
        n = n + 1
      }
    }
  }
  n
}

///|
test "gvn deduplicates identical expressions" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %x =w add %a, %b
    #|  %y =w add %a, %b
    #|  %z =w add %x, %y
    #|  ret %z
    #|}
    #|
  let (f, interner, typs) = gvn_pipeline(src)
  let dbg = gvn(f, false, interner, typs)
  assert_eq(dbg, "")
  // The duplicate add became a nop, so only %x and %z remain.
  assert_eq(count_op(f, @types.Add), 2)
}

///|
test "gvn debug dump is emitted when requested" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %x =w add %a, %b
    #|  %y =w add %a, %b
    #|  %z =w add %x, %y
    #|  ret %z
    #|}
    #|
  let (f, interner, typs) = gvn_pipeline(src)
  let dbg = gvn(f, true, interner, typs)
  assert_true(dbg.contains("After GVN"))
}

///|
test "gcm runs after gvn and stays silent when not printing" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %x =w add %a, %b
    #|  %y =w add %x, 1
    #|  %z =w add %y, %x
    #|  ret %z
    #|}
    #|
  let (f, interner, typs) = gvn_pipeline(src)
  let _ = gvn(f, false, interner, typs)
  let dbg = gcm(f, false, interner, typs)
  assert_eq(dbg, "")
}

///|
test "gvn snapshot of deduplicated function" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %x =w add %a, %b
    #|  %y =w add %a, %b
    #|  %z =w add %x, %y
    #|  ret %z
    #|}
    #|
  let (f, interner, typs) = gvn_pipeline(src)
  inspect(
    gvn(f, true, interner, typs),
    content=(
      #|
      #|> After GVN:
      #|function $f() {
      #|@start
      #|	%a =w par
      #|	%b =w par
      #|	%x =w add %a, %b
      #|	nop
      #|	%z =w add %x, %x
      #|	retw %z
      #|}
      #|
    ),
  )
}

///|
test "gcm snapshot of deduplicated function" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %x =w add %a, %b
    #|  %y =w add %a, %b
    #|  %z =w add %x, %y
    #|  ret %z
    #|}
    #|
  let (f, interner, typs) = gvn_pipeline(src)
  let _ = gvn(f, false, interner, typs)
  inspect(
    gcm(f, true, interner, typs),
    content=(
      #|
      #|> After GCM:
      #|function $f() {
      #|@start
      #|	%a =w par
      #|	%b =w par
      #|	%x =w add %a, %b
      #|	%z =w add %x, %x
      #|	retw %z
      #|}
      #|
    ),
  )
}

///|
test "loop gvn snapshot" {
  let src =
    #|function w $f(w %n) {
    #|@start
    #|  jmp @loop
    #|@loop
    #|  %i =w phi @start %n, @body %j
    #|  %j =w add %i, 1
    #|  %c =w csltw %j, 10
    #|  jnz %c, @body, @exit
    #|@body
    #|  jmp @loop
    #|@exit
    #|  ret %j
    #|}
    #|
  let (f, interner, typs) = gvn_pipeline(src)
  inspect(
    gvn(f, true, interner, typs),
    content=(
      #|
      #|> After GVN:
      #|function $f() {
      #|@start
      #|	%n =w par
      #|	nop
      #|@loop
      #|	%i =w phi @start %n, @body %j
      #|	%j =w add %i, 1
      #|	%c =w csltw %j, 10
      #|	jnz %c, @body, @exit
      #|@body
      #|	jmp @loop
      #|@exit
      #|	retw %j
      #|}
      #|
    ),
  )
}

///|
test "loop gcm snapshot" {
  let src =
    #|function w $f(w %n) {
    #|@start
    #|  jmp @loop
    #|@loop
    #|  %i =w phi @start %n, @body %j
    #|  %j =w add %i, 1
    #|  %c =w csltw %j, 10
    #|  jnz %c, @body, @exit
    #|@body
    #|  jmp @loop
    #|@exit
    #|  ret %j
    #|}
    #|
  let (f, interner, typs) = gvn_pipeline(src)
  let _ = gvn(f, false, interner, typs)
  inspect(
    gcm(f, true, interner, typs),
    content=(
      #|
      #|> After GCM:
      #|function $f() {
      #|@start
      #|	%n =w par
      #|@loop
      #|	%i =w phi @start %n, @body %j
      #|	%j =w add %i, 1
      #|	%c =w csltw %j, 10
      #|	jnz %c, @body, @exit
      #|@body
      #|	jmp @loop
      #|@exit
      #|	%snk.1 =w add %i, 1
      #|	retw %snk.1
      #|}
      #|
    ),
  )
}

///|
test "branch gvn snapshot" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  jnz %a, @l1, @l2
    #|@l1
    #|  %x =w add %a, %b
    #|  jmp @end
    #|@l2
    #|  %y =w add %b, %a
    #|  jmp @end
    #|@end
    #|  %z =w phi @l1 %x, @l2 %y
    #|  ret %z
    #|}
    #|
  let (f, interner, typs) = gvn_pipeline(src)
  inspect(
    gvn(f, true, interner, typs),
    content=(
      #|
      #|> After GVN:
      #|function $f() {
      #|@start
      #|	%a =w par
      #|	%b =w par
      #|	jnz %a, @l1, @l2
      #|@l1
      #|	%x =w add %a, %b
      #|	jmp @end
      #|@l2
      #|	nop
      #|@end
      #|	%z =w phi @l1 %x, @l2 %b
      #|	retw %z
      #|}
      #|
    ),
  )
}
