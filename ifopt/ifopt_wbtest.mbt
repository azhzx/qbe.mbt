///|
// White-box tests for the ifopt package (ifconvert + simpl).

///|
test "simpl lowers udiv/urem by a power of two" {
  let src =
    #|function w $f(w %x) {
    #|@start
    #|  %a =w udiv %x, 8
    #|  %b =w urem %x, 8
    #|  %c =w udiv %x, 7
    #|  %d =w udiv %x, 1
    #|  ret %a
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  let dbg = simpl(f, false, parser.interner_ref(), parser.get_typs())
  assert_eq(dbg, "")
  let b = f.blks[f.def_order[0]]
  let mut saw_shr3 = false
  let mut saw_shr0 = false
  let mut and_ = false
  let mut mask = -1L
  let mut udiv = false
  for ins in b.ins {
    if ins.op == @types.Shr {
      let v = f.cons[ins.arg2.con_val()].bits.i
      if v == 3L {
        saw_shr3 = true
      }
      if v == 0L {
        saw_shr0 = true
      }
    }
    if ins.op == @types.And {
      and_ = true
      mask = f.cons[ins.arg2.con_val()].bits.i
    }
    if ins.op == @types.Udiv {
      udiv = true
    }
  }
  // udiv by 8 -> shr 3, urem by 8 -> and 7, udiv by 1 -> shr 0, udiv by 7 stays.
  assert_true(saw_shr3)
  assert_true(saw_shr0)
  assert_true(and_)
  assert_true(udiv)
  assert_eq(mask, 7L)
}

///|
test "simpl ignores non-power-of-two divisors" {
  let src =
    #|function w $f(w %x) {
    #|@start
    #|  %a =w udiv %x, 6
    #|  %b =w urem %x, 3
    #|  ret %a
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  let _ = simpl(f, false, parser.interner_ref(), parser.get_typs())
  for ins in f.blks[f.def_order[0]].ins {
    assert_true(ins.op != @types.Shr)
    assert_true(ins.op != @types.And)
  }
}

///|
// ifconvert's dump helper must agree with parser.printfn when no select is
// introduced.
test "ifconvert dump matches parser.printf for an untouched function" {
  let src =
    #|function w $g(w %a) {
    #|@start
    #|  %b =w add %a, 1
    #|  ret %b
    #|}
    #|
  let lexer = @lexer.Lexer::new(src, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  let interner = parser.interner_ref()
  let typs = parser.get_typs()
  let out = ifconvert(f, true, interner, typs)
  let expected = "\n> If-conversion:\n\n> After if-conversion:\n" +
    @parser.printfn(f, interner, typs) +
    "\n"
  assert_eq(out, expected)
  let quiet = ifconvert(f, false, interner, typs)
  assert_eq(quiet, "")
}

///|
// Build the canonical if-then-else graphlet by hand.  The parser cannot be
// used here because its phi validation compares against the function-wide
// successor set (parser/typecheck.mbt), which rejects any function with a
// non-trivial phi.
test "ifconvert converts an if-then-else graphlet" {
  let f = @types.Fn::new("f")
  f.init_regs()
  let r_c = @types.Ref::tmp(f.add_tmp("c", @types.Kw))
  let r_x = @types.Ref::tmp(f.add_tmp("x", @types.Kw))
  let r_y = @types.Ref::tmp(f.add_tmp("y", @types.Kw))
  let r_t = @types.Ref::tmp(f.add_tmp("t", @types.Kw))
  let r_e = @types.Ref::tmp(f.add_tmp("e", @types.Kw))
  let r_r = @types.Ref::tmp(f.add_tmp("r", @types.Kw))
  let k1 = @types.Ref::con(f.get_con(1L))
  let start = f.add_blk("start")
  let thenb = f.add_blk("then")
  let elseb = f.add_blk("else")
  let joinb = f.add_blk("join")
  f.start_id = start
  for i in [start, thenb, elseb, joinb] {
    f.def_order.push(i)
  }
  f.blks[start].jmp = @types.Jump::full(@types.Jjnz, r_c, thenb, elseb)
  f.blks[thenb].ins.push(@types.Ins::new(@types.Add, @types.Kw, r_t, r_x, k1))
  f.blks[thenb].jmp = @types.Jump::full(
    @types.Jjmp,
    @types.Ref::none(),
    joinb,
    -1,
  )
  f.blks[elseb].ins.push(@types.Ins::new(@types.Add, @types.Kw, r_e, r_y, k1))
  f.blks[elseb].jmp = @types.Jump::full(
    @types.Jjmp,
    @types.Ref::none(),
    joinb,
    -1,
  )
  let p = @types.Phi::new(r_r, @types.Kw)
  p.args.push(@types.PhiArg::{ value: r_t, blk_id: thenb, })
  p.args.push(@types.PhiArg::{ value: r_e, blk_id: elseb, })
  f.blks[joinb].phi.push(p)
  f.blks[joinb].jmp = @types.Jump::full(@types.Jretw, r_r, -1, -1)
  @cfg.fillpreds(f)
  let out = ifconvert(f, true, @util.Interner::new(), [])
  assert_true(out.contains("> If-conversion:"))
  assert_true(out.contains("    @start -> @then, @else -> @join"))
  assert_true(out.contains("sel0 %c"))
  assert_true(out.contains("%r =w sel1 %t, %e"))
  assert_true(out.contains("retw %r"))
  assert_true(f.blks[start].jmp.kind == @types.Jjmp)
  assert_true(f.blks[start].jmp.s1 == joinb)
  assert_true(f.blks[joinb].phi.length() == 0)
  assert_true(f.blks[joinb].npred == 1)
}

///|
test "ulog2 returns the exponent for every power of two" {
  for n in 0..<64 {
    let v = 1UL << n
    assert_true(ispow2(v))
    assert_eq(ulog2(v), n)
  }
  assert_true(!ispow2(0UL))
  assert_true(!ispow2(3UL))
  assert_true(!ispow2(0x8000000000000001UL))
}

///|
test "blit expands a two-byte copy" {
  let f = @types.Fn::new("blt")
  let out = blit(@types.Ref::tmp(0), @types.Ref::tmp(1), 2, f)
  assert_eq(out.length(), 4)
  assert_true(out[0].op == @types.Add)
  assert_true(out[1].op == @types.Loaduh)
  assert_true(out[1].cls == @types.Kw)
  assert_true(out[2].op == @types.Add)
  assert_true(out[3].op == @types.Storeh)
}
