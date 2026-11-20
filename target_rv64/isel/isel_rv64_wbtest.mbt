///|
test "audit rv64 rejects invalid dynamic constant alloc sizes" {
  for size in [-1L, 2147483632L] {
    let f = @types.Fn::new("f")
    let st = rv64_isel_new(f, @util.Interner::new())
    let ins = @types.Ins::new(
      @types.Alloc8,
      @types.Kl,
      @types.Ref::tmp(64),
      @types.Ref::con(f.get_con(size)),
      @types.Ref::none(),
    )
    let rejected = try {
      sel(st, ins)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "audit rv64 rejects invalid fast alloc sizes" {
  for size in [-1L, 2147483632L] {
    let f = @types.Fn::new("f")
    f.init_regs()
    let b = f.add_blk("start")
    f.def_order.push(b)
    let to = @types.Ref::tmp(f.new_tmp("alloc", @types.Kl))
    f.blks[b].ins.push(
      @types.Ins::new(
        @types.Alloc8,
        @types.Kl,
        to,
        @types.Ref::con(f.get_con(size)),
        @types.Ref::none(),
      ),
    )
    let rejected = try {
      ignore(isel_rv64(f, @util.Interner::new(), false, []))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "audit rv64 float inequality lowers to equality and xor" {
  @types.init_rv64_target()
  let f = @types.Fn::new("f")
  f.init_regs()
  let st = rv64_isel_new(f, @util.Interner::new())
  sel(
    st,
    @types.Ins::new(
      @types.Cned,
      @types.Kw,
      @types.Ref::tmp(@types.A0),
      @types.Ref::tmp(@types.FA0),
      @types.Ref::tmp(@types.FA1),
    ),
  )
  let ins = emit_block(st)
  assert_eq(ins.length(), 2)
  assert_true(ins[0].op == @types.Ceqd)
  assert_true(ins[1].op == @types.Xor)
}

///|
test "audit rv64 dynamic constant alloc materializes size register" {
  @types.init_rv64_target()
  let f = @types.Fn::new("f")
  f.init_regs()
  let st = rv64_isel_new(f, @util.Interner::new())
  let c = @types.Ref::con(f.get_con(4096L))
  sel(
    st,
    @types.Ins::new(
      @types.Alloc16,
      @types.Kl,
      @types.Ref::tmp(@types.A0),
      c,
      @types.Ref::none(),
    ),
  )
  let ins = emit_block(st)
  assert_eq(ins.length(), 2)
  assert_true(ins[0].op == @types.Copy)
  assert_true(ins[1].op == @types.Salloc && ins[1].arg1.is_tmp())
}

///|
test "audit rv64 dynamic alloc stops later fast allocs of same alignment" {
  @types.init_rv64_target()
  let f = @types.Fn::new("f")
  f.init_regs()
  let bid = f.add_blk("start")
  f.def_order.push(bid)
  let n = @types.Ref::tmp(f.new_tmp("n", @types.Kl))
  let a = @types.Ref::tmp(f.new_tmp("a", @types.Kl))
  let b = @types.Ref::tmp(f.new_tmp("b", @types.Kl))
  f.blks[bid].ins.push(
    @types.Ins::new(@types.Alloc8, @types.Kl, a, n, @types.Ref::none()),
  )
  f.blks[bid].ins.push(
    @types.Ins::new(
      @types.Alloc8,
      @types.Kl,
      b,
      @types.Ref::con(f.get_con(16L)),
      @types.Ref::none(),
    ),
  )
  ignore(isel_rv64(f, @util.Interner::new(), false, []))
  assert_eq(f.tmps[b.tmp_val()].slot, -1)
}

///|
// C util.c salloc: a dynamic allocation size that already owns a stack slot
// would make the allocator use a stack address as its size.
test "audit rv64 dynamic alloc rejects a size temporary that owns a slot" {
  @types.init_rv64_target()
  let f = @types.Fn::new("f")
  f.init_regs()
  let st = rv64_isel_new(f, @util.Interner::new())
  let n = @types.Ref::tmp(f.new_tmp("n", @types.Kl))
  f.tmps[n.tmp_val()].slot = 0
  let to = @types.Ref::tmp(f.new_tmp("a", @types.Kl))
  let rejected = try {
    sel(
      st,
      @types.Ins::new(@types.Alloc8, @types.Kl, to, n, @types.Ref::none()),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
// C rv64/isel.c fixarg: the Oaddr that materializes a slotted operand keeps
// the operand class k (it used to be hardcoded Kl).
test "audit rv64 address materialization keeps the operand class" {
  @types.init_rv64_target()
  let f = @types.Fn::new("f")
  f.init_regs()
  let st = rv64_isel_new(f, @util.Interner::new())
  let p = @types.Ref::tmp(f.new_tmp("p", @types.Kl))
  f.tmps[p.tmp_val()].slot = 0
  let r = fixarg(st, p, @types.Kw, None, 0)
  assert_true(r.is_tmp())
  assert_eq(st.buf.length(), 1)
  assert_true(st.buf[0].op == @types.Addr)
  assert_true(st.buf[0].cls == @types.Kw)
}
