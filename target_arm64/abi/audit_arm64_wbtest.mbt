///|
test "audit arm64: three doubles remain HFA before large aggregate rule" {
  let src =
    #|type :h = { d, d, d }
    #|function :h $f(:h %x) {
    #|@start
    #| ret %x
    #|}
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let _ = abi_arm64(f, typs, false, interner, false, typs)
  assert_true(f.retr.is_none())
  assert_eq(f.blks[f.start_id].jmp.arg.call_val(), 3 << 2)
  assert_eq(
    f.reg,
    (1UL << @types.ARM64_V0) |
    (1UL << @types.ARM64_V1) |
    (1UL << @types.ARM64_V2),
  )
}

///|
test "audit arm64: stacked indirect aggregate preserves pointer class" {
  let src =
    #|type :big = { l, l, l }
    #|function l $f(l %a, l %b, l %c, l %d, l %e, l %f, l %g, l %h, :big %p) {
    #|@start
    #| %v =l loadl %p
    #| ret %v
    #|}
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let _ = abi_arm64(f, typs, false, interner, false, typs)
  let mut found = false
  for i in f.blks[f.start_id].ins {
    if i.op == @types.Load && i.arg1.is_slot() {
      assert_eq(i.cls, @types.Kl)
      assert_eq(i.arg1, @types.Ref::slot(-2))
      found = true
    }
  }
  assert_true(found)
}

///|
test "audit arm64: environment parameter arrives in x9" {
  let src =
    #|function l $f(env %e) {
    #|@start
    #| ret %e
    #|}
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let _ = abi_arm64(f, typs, false, interner, false, typs)
  assert_true((f.reg & (1UL << @types.ARM64_R9)) != 0UL)
  assert_true(
    f.blks[f.start_id].ins[0].arg1 == @types.Ref::tmp(@types.ARM64_R9),
  )
}

///|
test "audit arm64: environment call sets x9 argument mask" {
  let src =
    #|function l $f(l %e) {
    #|@start
    #| %r =l call $g(env %e)
    #| ret %r
    #|}
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let _ = abi_arm64(f, typs, false, interner, false, typs)
  let mut seen = false
  for i in f.blks[f.start_id].ins {
    if i.op == @types.Call {
      assert_eq(i.arg2.call_val(), (1 << 14) | 1)
      seen = true
    }
  }
  assert_true(seen)
}

///|
test "audit arm64: Apple stacked narrow parameters use signed loads" {
  let src =
    #|function w $f(l %a, l %b, l %c, l %d, l %e, l %f, l %g, l %h, sb %x, uh %y) {
    #|@start
    #| %r =w add %x, %y
    #| ret %r
    #|}
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let _ = abi_arm64(f, typs, false, interner, true, typs)
  let mut seen = 0
  for i in f.blks[f.start_id].ins {
    if i.op == @types.Loadsb {
      assert_eq(i.arg1, @types.Ref::slot(-2))
      seen += 1
    }
    if i.op == @types.Loaduh {
      assert_eq(i.arg1, @types.Ref::slot(-4))
      seen += 1
    }
  }
  assert_eq(seen, 2)
}

///|
test "audit arm64: Apple pre-ABI extends sub-word args and return" {
  let f = @types.Fn::new("f")
  f.init_regs()
  let b = f.add_blk("start")
  f.def_order.push(b)
  f.start_id = b
  let v = f.add_tmp("v", @types.Kw)
  let ci = f.add_con(@types.Con::addr(1))
  f.blks[b].ins.push(
    @types.Ins::new_void(
      @types.Argsb,
      @types.Kw,
      @types.Ref::tmp(v),
      @types.Ref::none(),
    ),
  )
  f.blks[b].ins.push(
    @types.Ins::new_void(
      @types.Call,
      @types.Kw,
      @types.Ref::con(ci),
      @types.Ref::none(),
    ),
  )
  f.blks[b].jmp = @types.Jump::full(@types.Jretub, @types.Ref::tmp(v), -1, -1)
  apple_extsb(f)
  // The return is extended and becomes a word return.
  assert_eq(f.blks[b].jmp.kind, @types.Jretw)
  assert_true(f.blks[b].jmp.arg.is_tmp())
  let ins = f.blks[b].ins
  // extension for the argument, the argument copy using the new long temp,
  // the call, and finally the return extension.
  assert_eq(ins[0].op, @types.Extsb)
  assert_eq(ins[1].op, @types.Argsb)
  assert_true(ins[1].arg1.is_tmp())
  assert_eq(f.tmps[ins[1].arg1.tmp_val()].cls, @types.Kl)
  assert_eq(ins[2].op, @types.Call)
  assert_eq(ins[3].op, @types.Extub)
  assert_true(ins[3].to.eq(f.blks[b].jmp.arg))
}
