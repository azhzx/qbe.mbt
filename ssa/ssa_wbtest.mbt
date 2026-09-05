///|
// White-box tests for SSA use analysis and checks.

///|
// Build a two-block function:
//   @start:  %s =w add %a, %b   jmp @ret
//   @ret:    retw %s
fn make_two_block_fn() -> @types.Fn {
  let f = @types.Fn::new("t")
  f.def_order.push(f.add_blk("@start"))
  f.def_order.push(f.add_blk("@ret"))
  f.init_regs()
  let ta = f.add_tmp("a", @types.Kw)
  let tb = f.add_tmp("b", @types.Kw)
  let ts = f.add_tmp("s", @types.Kw)
  let i = @types.Ins::new(
    @types.Add,
    @types.Kw,
    @types.Ref::tmp(ts),
    @types.Ref::tmp(ta),
    @types.Ref::tmp(tb),
  )
  f.blks[0].ins.push(i)
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jretw, @types.Ref::tmp(ts), -1, -1)
  f
}

///|
test "filluse counts definitions and uses" {
  let f = make_two_block_fn()
  filluse(f)
  let ta = @types.Tmp0
  let tb = @types.Tmp0 + 1
  let ts = @types.Tmp0 + 2
  // %a and %b are used once (by the add), never defined.
  assert_true(f.tmp(ta).nuse == 1)
  assert_true(f.tmp(ta).ndef == 0)
  assert_true(f.tmp(tb).nuse == 1)
  // %s is defined once, used once (by retw).
  assert_true(f.tmp(ts).ndef == 1)
  assert_true(f.tmp(ts).nuse == 1)
  assert_true(f.tmp(ts).cls == @types.Kw)
  // The use of %s lives in block @ret as a UJmp use.
  assert_true(f.tmp(ts).uses.length() == 1)
  assert_true(f.tmp(ts).uses[0].kind == @types.UJmp)
  assert_true(f.tmp(ts).uses[0].blk_id == 1)
}

///|
test "filluse on a well-formed function then ssacheck passes" {
  // Same shape but %a/%b are defined by Par instructions so the function is
  // valid SSA.
  let f = @types.Fn::new("t")
  f.def_order.push(f.add_blk("@start"))
  f.def_order.push(f.add_blk("@ret"))
  f.init_regs()
  let ta = f.add_tmp("a", @types.Kw)
  let tb = f.add_tmp("b", @types.Kw)
  let ts = f.add_tmp("s", @types.Kw)
  let none = @types.Ref::none()
  f.blks[0].ins.push(
    @types.Ins::new(@types.Par, @types.Kw, @types.Ref::tmp(ta), none, none),
  )
  f.blks[0].ins.push(
    @types.Ins::new(@types.Par, @types.Kw, @types.Ref::tmp(tb), none, none),
  )
  f.blks[0].ins.push(
    @types.Ins::new(
      @types.Add,
      @types.Kw,
      @types.Ref::tmp(ts),
      @types.Ref::tmp(ta),
      @types.Ref::tmp(tb),
    ),
  )
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, none, 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jretw, @types.Ref::tmp(ts), -1, -1)
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @cfg.filldom(f)
  filluse(f)
  ssacheck(f)
}

///|
test "filluse raises ICE on a non-tmp destination" {
  let f = make_two_block_fn()
  f.blks[0].ins[0].to = @types.Ref::con(0)
  try filluse(f) catch {
    @util.QbeError::Ice(_) => ()
    _ => fail("expected an ICE for a non-tmp destination")
  } noraise {
    _ => fail("expected an ICE for a non-tmp destination")
  }
}

///|
// Parse IL and set up CFG/liveness state so SSA construction passes run.
fn ssa_parse_setup(text : String) -> (@types.Fn, @util.Interner, Array[@types.Typ]) raise {
  let lexer = @lexer.Lexer::new(text, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  let typs = parser.get_typs()
  let interner = parser.interner_ref()
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @cfg.filldom(f)
  @cfg.fillfron(f)
  let _ = @live.filllive(f, false)
  (f, interner, typs)
}

///|
test "phiins inserts a phi at a merge point of two definitions" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  jnz %a, @t, @e
    #|@t
    #|  %x =w add %a, %b
    #|  jmp @m
    #|@e
    #|  %x =w add %a, 1
    #|  jmp @m
    #|@m
    #|  ret %x
    #|}
    #|
  let (f, interner, typs) = ssa_parse_setup(src)
  let _ = (interner, typs)
  filluse(f)
  phiins(f)
  renblk(f)
  let m = f.blks[f.find_blk("m")]
  assert_true(m.phi.length() == 1)
  let p = m.phi[0]
  assert_true(p.cls == @types.Kw)
  // both branch blocks contribute an argument to the phi
  assert_true(p.args.length() == 2)
  // both branch blocks contribute an argument (order follows pred order)
  let ids = [p.args[0].blk_id, p.args[1].blk_id]
  assert_true(ids.contains(f.find_blk("t")))
  assert_true(ids.contains(f.find_blk("e")))
}

///|
test "copy propagates through uses and removes the copy" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %x =w add %a, %b
    #|  %y =w copy %x
    #|  ret %y
    #|}
    #|
  let (f, interner, typs) = ssa_parse_setup(src)
  let _ = typs
  filluse(f)
  let _ = copy(f, false, interner, [])
  // the return now reads %x directly; the copy is gone
  let start = f.blks[f.start_id]
  let mut copies = 0
  for ins in start.ins {
    if ins.op == @types.Copy {
      copies = copies + 1
    }
  }
  assert_eq(copies, 0)
  // `ret %y` is carried by the block jump, which now reads %x directly
  let start_jmp = f.blks[f.start_id].jmp
  assert_true(start_jmp.kind == @types.Jretw)
  assert_true(start_jmp.arg.is_tmp())
}

///|
test "memopt forwards stores to loads of a fresh allocation" {
  let src =
    #|export function w $f() {
    #|@start
    #|  %p =l alloc8 8
    #|  storew 42, %p
    #|  %v =w loadw %p
    #|  ret %v
    #|}
    #|
  let (f, interner, typs) = ssa_parse_setup(src)
  let _ = (interner, typs)
  filluse(f)
  memopt(f)
  // all loads/stores are gone, replaced by copies of the forwarded constant
  let start = f.blks[f.start_id]
  for ins in start.ins {
    assert_true(!ins.op.is_load() && !ins.op.is_store())
  }
  let mut forwarded = false
  for ins in start.ins {
    if ins.op == @types.Copy && ins.arg1.is_con() {
      let c = f.cons[ins.arg1.con_val()]
      if c.bits.i == 42L {
        forwarded = true
      }
    }
  }
  assert_true(forwarded)
  assert_true(start.jmp.kind == @types.Jretw)
}
