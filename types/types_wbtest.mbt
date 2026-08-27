///|
// White-box unit tests for the IR data types in the `types` package.

///|
test "BSet basic bit operations" {
  let b = BSet::new(70)
  assert_true(b.count() == 0)
  b.set(0)
  b.set(63)
  b.set(64)
  b.set(69)
  assert_true(b.has(0))
  assert_true(b.has(63))
  assert_true(b.has(64))
  assert_true(b.has(69))
  assert_true(!b.has(62))
  assert_true(!b.has(65))
  assert_true(b.count() == 4)
  b.clr(63)
  assert_true(!b.has(63))
  assert_true(b.count() == 3)
}

///|
test "BSet set/union/inter/diff" {
  let a = BSet::new(70)
  let b = BSet::new(70)
  a.set(1)
  a.set(2)
  b.set(2)
  b.set(3)
  // union returns true iff changed
  let changed = a.union(b)
  assert_true(changed)
  assert_true(a.has(1) && a.has(2) && a.has(3))
  assert_true(!a.union(b))
  let c = BSet::new(70)
  c.set(2)
  c.set(3)
  c.inter(a)
  assert_true(c.has(2) && c.has(3) && !c.has(1))
  let d = BSet::new(70)
  d.set(1)
  d.set(2)
  d.diff(b)
  assert_true(d.has(1) && !d.has(2) && !d.has(3))
  assert_true(!a.equal(c))
  let _ = c.union(a)
  assert_true(a.equal(c))
}

///|
test "BSet iter and copy_from" {
  let a = BSet::new(10)
  a.set(0)
  a.set(4)
  a.set(7)
  let b = BSet::new(10)
  b.copy_from(a)
  assert_true(b.count() == 3)
  // iter returns the next set bit >= start, or -1
  let found : Array[Int] = []
  let mut t = a.iter(0)
  while t >= 0 {
    found.push(t)
    t = a.iter(t + 1)
  }
  assert_true(found == [0, 4, 7])
  assert_true(a.iter(5) == 7)
  assert_true(a.iter(8) == -1)
}

///|
test "BSet each and each_from" {
  let a = BSet::new(100)
  a.set(1)
  a.set(5)
  a.set(70)
  let all : Array[Int] = []
  a.each(t => all.push(t))
  assert_true(all == [1, 5, 70])
  let from : Array[Int] = []
  a.each_from(5, t => from.push(t))
  assert_true(from == [5, 70])
  let from2 : Array[Int] = []
  a.each_from(-5, t => from2.push(t))
  assert_true(from2 == [1, 5, 70])
  // each over an empty set does nothing
  let empty = BSet::new(10)
  let hits : Array[Int] = []
  empty.each(t => hits.push(t))
  assert_true(hits.length() == 0)
}

///|
test "BSet out-of-range access" {
  let b = BSet::new(3)
  b.set(2)
  assert_true(b.has(2))
  // Out of range: has() must not panic
  assert_true(!b.has(3))
  assert_true(!b.has(-1))
}

///|
test "Con int/double/single/addr" {
  let i = Con::int(42)
  assert_true(i.kind == CBits)
  assert_true(i.flt == 0)
  assert_true(i.bits.i == 42)
  let d = Con::double(1.5)
  assert_true(d.kind == CBits && d.flt == 2)
  assert_true(d.bits.d == 1.5)
  let s = Con::single(0.5)
  assert_true(s.kind == CBits && s.flt == 1)
  assert_true(s.bits.s == 0.5)
  let a = Con::addr(7)
  assert_true(a.kind == CAddr && a.label == 7)
}

///|
test "Con is_zero and raw bits" {
  assert_true(Con::int(0).is_zero(true))
  assert_true(Con::int(0).is_zero(false))
  assert_true(!Con::int(5).is_zero(true))
  // 0x1_0000_0000 is zero as a word but not as a long
  let big = Con::int(0x100000000)
  assert_true(!big.is_zero(true))
  assert_true(big.is_zero(false))
  assert_true(Con::int(-3).raw_bits() == -3)
  assert_true(!Con::addr(1).is_zero(true))
}

///|
test "addcon address arithmetic" {
  let c = Con::addr(5).add(Con::int(3))
  assert_true(c.kind == CAddr && c.label == 5 && c.bits.i == 3)
  // Adding to an undef constant returns the other one
  let c2 = Con::new().add(Con::int(9))
  assert_true(c2.bits.i == 9)
}

///|
test "Fn constant interning" {
  let f = Fn::new("test")
  let i0 = f.get_con(5)
  let i1 = f.get_con(5)
  let i2 = f.get_con(6)
  assert_true(i0 == i1)
  assert_true(i0 != i2)
  // get_con_by interns by raw bits, so int(5) and double bit-equal intern together
  let j0 = f.get_con_by(Con::int(5))
  assert_true(j0 == i0)
}

///|
test "Ref constructor/accessor round-trip" {
  assert_true(Ref::none().is_none())
  let t = Ref::tmp(3)
  assert_true(t.is_tmp() && t.tmp_val() == 3)
  assert_true(!t.is_con())
  assert_true(t.con_val() == -1)
  let c = Ref::con(9)
  assert_true(c.is_con() && c.con_val() == 9)
  assert_true(c.tmp_val() == -1)
  let ty = Ref::typ(1)
  assert_true(ty.is_tmp() == false && ty.typ_val() == 1)
  let s = Ref::slot(0x1fffffff)
  assert_true(s.is_slot() && s.slot_val() == 0x1fffffff)
  // SLOT masks the value to 29 bits
  let s2 = Ref::slot(0x3fffffff)
  assert_true(s2.slot_val() == 0x1fffffff)
  let call = Ref::call(4)
  assert_true(call.is_mem() == false && call.call_val() == 4)
  let m = Ref::mem(2)
  assert_true(m.is_mem() && m.mem_val() == 2)
  assert_true(Ref::tmp(1).eq(Ref::tmp(1)))
  assert_true(!Ref::tmp(1).eq(Ref::tmp(2)))
}

///|
test "Op classification helpers" {
  assert_true(Storew.is_store())
  assert_true(Stored.is_store())
  assert_true(!Load.is_store())
  assert_true(Loadsb.is_load())
  assert_true(Loaduw.is_load())
  assert_true(!Storel.is_load())
  assert_true(Extsb.is_ext())
  assert_true(Extuw.is_ext())
  assert_true(!Cast.is_ext())
  assert_true(Par.is_par())
  assert_true(Parc.is_par())
  assert_true(!Arg.is_par())
  assert_true(Argc.is_arg())
  assert_true(!Par.is_arg())
  assert_true(Loadsb.load_width_idx() == 1)
  assert_true(Loaduw.load_width_idx() == 6)
  assert_true(Extsh.ext_width_idx() == 3)
  assert_true(Extuw.ext_width_idx() == 6)
}

///|
test "op_from_string and round-trip" {
  assert_true(Op::from_string("add") == Add)
  assert_true(Op::from_string("sub") == Sub)
  assert_true(Op::from_string("storeb") == Storeb)
  assert_true(Op::from_string("loadl") == Load)
  assert_true(Op::from_string("call") == Call)
  assert_true(Op::from_string("nonsense") == Oxxx)
  // op_index / op_from_index are exact inverses on the optab
  for i in 0..<120 {
    let o = Op::from_index(i)
    assert_true(o.index() == i)
  }
  assert_true(Add.index() == 1)
  assert_true(Call.index() == 100)
  assert_true(Flagfuo.index() == 119)
}

///|
test "OpInfo and Op::name" {
  assert_true(op_info(Add).name == "add")
  assert_true(op_info(Call).name == "call")
  assert_true(Add.name() == "add")
  assert_true(op_info(Add).a0 == [0, 1, 2, 3])
  assert_true(op_info(Add).canfold)
}

///|
test "Class helper functions" {
  assert_true(Kw.code() == 0)
  assert_true(Kl.code() == 1)
  assert_true(Ks.code() == 2)
  assert_true(Kd.code() == 3)
  assert_true(Kx.code() == -1)
  assert_true(Kw.base() == 0 && Kl.base() == 0)
  assert_true(Ks.base() == 1 && Kd.base() == 1)
  assert_true(Kl.wide() == 1 && Kd.wide() == 1)
  assert_true(Kw.wide() == 0 && Ks.wide() == 0)
  for c in 0..<4 {
    assert_true(Class::from_code(c).code() == c)
  }
  assert_true(Class::from_code(-1) == Kx)
  assert_true(Class::from_code(99) == Kx)
}

///|
test "JumpKind helpers" {
  assert_true(Jret0.is_ret())
  assert_true(Jretc.is_ret())
  assert_true(!Jjmp.is_ret())
  assert_true(!Jjnz.is_ret())
  for i in 0..<27 {
    assert_true(JumpKind::from_index(i).index() == i)
  }
  assert_true(Jret0.index() == 1)
  assert_true(Jjnz.index() == 8)
}

///|
test "cmpneg is an involution" {
  for c in 0..<18 {
    assert_true(cmpneg(cmpneg(c)) == c)
  }
  assert_true(cmpneg(0) == 1)
  assert_true(cmpneg(3) == 4)
  assert_true(cmpneg(10) == 15)
}

///|
test "retregs/argregs register masks" {
  let one : UInt64 = 1
  // RCall(1): ni=1, nf=0 -> returns RAX
  let (bits, ngp, nf) = Ref::call(1).retregs()
  assert_true(ngp == 1 && nf == 0)
  assert_true(bits == one << RAX)
  // RCall(2): ni=2, nf=0 -> RAX|RDX
  let (bits2, ngp2, nf2) = Ref::call(2).retregs()
  assert_true(ngp2 == 2 && nf2 == 0)
  assert_true(bits2 == ((one << RAX) | (one << RDX)))
  // argregs with ni=1 (bits 4-7), nf=1 (bits 8-11), ra=0: rsave[0]=RDI and XMM0
  let v = (1 << 4) | (1 << 8)
  let (b3, ngp3, nf3) = Ref::call(v).argregs()
  assert_true(ngp3 == 1 && nf3 == 1)
  assert_true(b3 == ((one << RDI) | (one << XMM0)))
  assert_true(rglob_mask() == ((one << RBP) | (one << RSP)))
}

///|
test "Fn basic structure" {
  let f = Fn::new("main")
  assert_true(f.nblk() == 0)
  let b0 = f.add_blk("start")
  let b1 = f.add_blk("loop")
  assert_true(b0 == 0 && b1 == 1)
  assert_true(f.find_blk("loop") == 1)
  assert_true(f.find_blk("missing") == -1)
  assert_true(f.blk(0).name == "start")
  let t0 = f.add_tmp("x", Kw)
  assert_true(t0 == 0)
  assert_true(f.tmp(0).name == "x" && f.tmp(0).cls == Kw)
  assert_true(f.ntmp() == 1)
  assert_true(f.ncon() == 0)
  // new_tmp with a prefix gets a unique generated name
  let t1 = f.new_tmp("tmp", Kl)
  assert_true(t1 == 1)
  assert_true(f.tmp(1).name == "tmp.1")
  let t2 = f.new_tmp("tmp", Kl)
  assert_true(t2 == 2)
  assert_true(f.tmp(2).name == "tmp.2")
  // empty prefix stays anonymous
  let t3 = f.new_tmp("", Kl)
  assert_true(f.tmp(t3).name == "")
}

///|
test "Fn init_regs seeds register temps" {
  let f = Fn::new("main")
  f.init_regs()
  assert_true(f.ntmp() == Tmp0)
  assert_true(f.tmp(RAX).cls == Kl)
  assert_true(f.tmp(XMM0).cls == Kd)
}

///|
test "Blk and Jump construction" {
  let b = Blk::new(0, "@start")
  assert_true(b.id == 0)
  assert_true(b.npred == 0 && b.idom == -1 && b.rpo_id == -1)
  let j = Jump::new(Jjmp)
  assert_true(j.kind == Jjmp && j.arg.is_none() && j.s1 == -1)
  let j2 = Jump::full(Jjnz, Ref::tmp(1), 2, 3)
  assert_true(j2.s1 == 2 && j2.s2 == 3 && j2.arg.tmp_val() == 1)
}

///|
test "Ins and Phi construction" {
  let i = Ins::new(Add, Kw, Ref::tmp(0), Ref::tmp(1), Ref::tmp(2))
  assert_true(i.op == Add && i.to.tmp_val() == 0)
  let v = Ins::new_void(Storel, Kw, Ref::tmp(1), Ref::tmp(2))
  assert_true(v.to.is_none())
  let p = Phi::new(Ref::tmp(5), Kl)
  assert_true(p.to.tmp_val() == 5 && p.args.length() == 0)
}

///|
test "Dat and Typ construction" {
  let d = Dat::byte(42)
  assert_true(d.kind == DB && d.num == 42)
  assert_true(Dat::align(8).kind == DAlign)
  assert_true(Dat::zero(16).kind == DZ)
  let s = Dat::string("hi")
  assert_true(s.is_str && s.str == "hi")
  let r = Dat::ref_to("foo", 4)
  assert_true(r.is_ref && r.ref_name == "foo" && r.ref_offset == 4)
  assert_true(Dat::start().kind == DStart)
  assert_true(Dat::end().kind == DEnd)
  let t = Typ::new("T")
  assert_true(t.name == "T" && t.size == 0)
  assert_true(Field::new(Fw, 4).len == 4)
  assert_true(Field::end().kind == FEnd)
}

///|
test "gasstash deduplicates float constants" {
  // Reset-independent: stash grows monotonically across tests; only check
  // that identical pushes are deduplicated.
  let i0 = gasstash(0x3ff0000000000000, 0, 8)
  let i1 = gasstash(0x3ff0000000000000, 0, 8)
  assert_true(i0 == i1)
  let e = fp_stash_at(i0)
  assert_true(e.b0 == 0x3ff0000000000000 && e.size == 8)
  assert_true(fp_stash_len() >= 1)
}

///|
test "TmpWidth code round-trip" {
  assert_true(WFull.code() == 0)
  assert_true(Wuw.code() == 6)
  assert_true(TmpWidth::from_code(3) == Wsh)
  assert_true(TmpWidth::from_code(0) == WFull)
  assert_true(TmpWidth::from_code(-1) == WFull)
}

///|
test "astack classification" {
  assert_true(ALoc.astack())
  assert_true(AEsc.astack())
  assert_true(!ACon.astack())
  assert_true(!AUnk.astack())
}
