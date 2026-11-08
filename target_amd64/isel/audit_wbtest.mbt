///|
fn audit_isel_state() -> IselState {
  let f = @types.Fn::new("audit")
  f.init_regs()
  IselState::{
    fn_: f,
    buf: [],
    an: [],
    cur_ins: [],
    interner: @util.Interner::new(),
    apple: false,
  }
}

///|
test "audit: float equality combines ordered flag" {
  for op in [@types.Ceqd, @types.Cned] {
    let st = audit_isel_state()
    let a = isel_newtmp(st, @types.Kd)
    let b = isel_newtmp(st, @types.Kd)
    let out = isel_newtmp(st, @types.Kw)
    sel(st, @types.Ins::new(op, @types.Kw, out, a, b))
    let want = if op == @types.Ceqd { @types.Flagfo } else { @types.Flagfuo }
    assert_true(st.buf.any(fn(i) { i.op == want }))
    assert_true(
      st.buf.any(fn(i) {
        i.to.eq(out) &&
        i.op == (if op == @types.Ceqd { @types.And } else { @types.Or })
      }),
    )
  }
}

///|
test "audit: float equality branch uses computed result flags" {
  let st = audit_isel_state()
  let bid = st.fn_.add_blk("start")
  let b = st.fn_.blks[bid]
  let a = isel_newtmp(st, @types.Kd)
  let r = isel_newtmp(st, @types.Kw)
  b.ins.push(@types.Ins::new(@types.Ceqd, @types.Kw, r, a, a))
  b.jmp = @types.Jump::full(@types.Jjnz, r, 1, 2)
  seljmp(st, b)
  assert_eq(b.jmp.kind, @types.Jjfine)
  assert_eq(b.ins[0].op, @types.Ceqd)
}

///|
test "audit: multiuse comparison jump follows swapped operands" {
  let st = audit_isel_state()
  let bid = st.fn_.add_blk("start")
  let b = st.fn_.blks[bid]
  let a = isel_newtmp(st, @types.Kw)
  let r = isel_newtmp(st, @types.Kw)
  st.fn_.tmps[r.tmp_val()].nuse = 2
  b.ins.push(
    @types.Ins::new(
      @types.Csltw,
      @types.Kw,
      r,
      @types.Ref::con(st.fn_.get_con(3L)),
      a,
    ),
  )
  b.jmp = @types.Jump::full(@types.Jjnz, r, 1, 2)
  seljmp(st, b)
  assert_eq(b.jmp.kind, jjf_op(CISGT))
}

///|
test "audit: numeric call targets are materialized even when small" {
  let st = audit_isel_state()
  let dest = @types.Ref::con(st.fn_.get_con(4096L))
  let i = @types.Ins::new(
    @types.Call,
    @types.Kw,
    @types.Ref::none(),
    dest,
    @types.Ref::call(0),
  )
  sel(st, i)
  assert_true(st.buf[0].arg1.is_tmp())
  assert_true(st.buf.any(fn(i) { i.op == @types.Copy && i.arg1.eq(dest) }))
}

///|
test "audit: static alloc rejects invalid signed size" {
  let src =
    #|function l $f() {
    #|@start
    #|  %p =l alloc8 -8
    #|  ret %p
    #|}
    #|
  let (f, interner, typs) = isel_parse_frontend(src)
  let rejected = try {
    ignore(isel(f, interner, false, typs))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "audit: store symbol value is materialized separately from address" {
  let st = audit_isel_state()
  let sym = @types.Ref::con(
    st.fn_.add_con(@types.Con::addr(st.interner.intern("value"))),
  )
  let ptr = @types.Ref::tmp(@types.RDI)
  for _ in 0..<st.fn_.tmps.length() {
    st.an.push(ANum::new())
  }
  sel(
    st,
    @types.Ins::new(@types.Storel, @types.Kw, @types.Ref::none(), sym, ptr),
  )
  assert_true(st.buf[0].arg1.is_tmp())
  assert_true(st.buf.any(fn(i) { i.op == @types.Addr && i.arg1.eq(sym) }))
}

///|
test "audit: numeric index offset remains base less" {
  let st = audit_isel_state()
  let a = @types.Addr::new()
  a.offset = @types.Con::int(8L)
  a.index = @types.Ref::tmp(@types.RAX)
  a.scale = 4
  st.fn_.mems.push(a)
  ignore(fixarg(st, @types.Ref::mem(0), @types.Kl, Some(@types.Load)))
  assert_true(a.base.is_none())
  assert_eq(st.buf.length(), 0)
}

///|
test "audit: Apple TLS selection calls descriptor resolver" {
  let src =
    #|function l $tls() {
    #|@start
    #|  ret thread $tlsvar
    #|}
    #|
  let (f, interner, typs) = isel_parse_frontend(src)
  ignore(isel(f, interner, false, typs, apple=true))
  assert_true(
    f.blks[f.start_id].ins.any(fn(i) {
      i.op == @types.Call && i.arg2.call_val() == 17
    }),
  )
}

///|
test "audit: dynamic constant allocation rejects negative size" {
  let st = audit_isel_state()
  let out = isel_newtmp(st, @types.Kl)
  let size = @types.Ref::con(st.fn_.get_con(-16L))
  let rejected = try {
    sel(
      st,
      @types.Ins::new(@types.Alloc8, @types.Kl, out, size, @types.Ref::none()),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "audit: selector receives instruction by value" {
  let st = audit_isel_state()
  let a = isel_newtmp(st, @types.Kl)
  let b = isel_newtmp(st, @types.Kw)
  let out = isel_newtmp(st, @types.Kl)
  let i = @types.Ins::new(@types.Shl, @types.Kl, out, a, b)
  sel(st, i)
  assert_eq(i.arg2, b)
}

///|
test "audit: fast local cannot be divisor shift count or allocation size" {
  for op in [@types.Div, @types.Shl, @types.Alloc8] {
    let st = audit_isel_state()
    let local = isel_newtmp(st, @types.Kl)
    st.fn_.tmps[local.tmp_val()].slot = 0
    let out = isel_newtmp(st, @types.Kl)
    let a = if op == @types.Alloc8 {
      local
    } else {
      @types.Ref::con(st.fn_.get_con(8L))
    }
    let b = if op == @types.Alloc8 { @types.Ref::none() } else { local }
    let rejected = try {
      sel(st, @types.Ins::new(op, @types.Kl, out, a, b))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "audit: slot plus symbol is not converted to indexed slot" {
  let st = audit_isel_state()
  let local = isel_newtmp(st, @types.Kl)
  st.fn_.tmps[local.tmp_val()].slot = 0
  let sum = isel_newtmp(st, @types.Kl)
  let bid = st.fn_.add_blk("start")
  let b = st.fn_.blks[bid]
  let sym = @types.Ref::con(
    st.fn_.add_con(@types.Con::addr(st.interner.intern("global"))),
  )
  b.ins.push(@types.Ins::new(@types.Add, @types.Kl, sum, local, sym))
  for _ in 0..<st.fn_.tmps.length() {
    st.an.push(ANum::new())
  }
  anumber(st, b)
  assert_eq(seladdr(st, sum), sum)
}
