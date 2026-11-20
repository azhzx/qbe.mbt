///|
// audit round 3 white-box tests for ifopt/: the -dK dump must be produced by
// the shared IL printer (parser.printfn), not by a second copy of it.

///|
// Build the canonical if-then-else graphlet by hand (the parser's phi
// validation rejects hand-written phis).
fn audit3_ifelse_graphlet() -> @types.Fn {
  let f = @types.Fn::new("ifelse")
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
  f
}

///|
test "audit3 core ifconvert dump is parser.printfn plus the conversion lines" {
  let interner = @util.Interner::new()
  let f = audit3_ifelse_graphlet()
  let out = ifconvert(f, true, interner, [])
  let expected = "\n> If-conversion:\n" +
    "    @start -> @then, @else -> @join\n" +
    "\n> After if-conversion:\n" +
    @parser.printfn(f, interner, []) +
    "\n"
  assert_eq(out, expected)
  assert_true(out.contains("sel0 %c"))
  assert_true(out.contains("%r =w sel1 %t, %e"))
}
