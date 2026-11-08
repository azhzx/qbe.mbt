///|
test "audit arm64: extern symbol offset is split before GOT copy" {
  // QBE IL cannot spell "$g+8" in an instruction operand, so build the
  // address constant directly (C fixarg's hascon case).
  let f = @types.Fn::new("f")
  f.init_regs()
  let b = f.add_blk("start")
  f.def_order.push(b)
  f.rpo.push(b)
  f.start_id = b
  let interner = @util.Interner::new()
  let c = @types.Con::{
    kind: @types.CAddr,
    label: interner.intern("g"),
    bits: @types.ConBits::{ i: 8L, d: 0.0, s: 0.0, },
    flt: 0,
    is_local: false,
    sym_type: @types.SYM_EXT,
  }
  let ci = f.add_con(c)
  let t = f.add_tmp("p", @types.Kl)
  f.blks[b].ins.push(
    @types.Ins::new(
      @types.Copy,
      @types.Kl,
      @types.Ref::tmp(t),
      @types.Ref::con(ci),
      @types.Ref::none(),
    ),
  )
  f.blks[b].jmp = @types.Jump::full(@types.Jretl, @types.Ref::tmp(t), -1, -1)
  let _ = isel_arm64(f, interner, false, [])
  let mut add = false
  for bid in f.def_order {
    for i in f.blks[bid].ins {
      if i.op == @types.Copy && i.arg1.is_con() {
        let cc = f.cons[i.arg1.con_val()]
        if cc.kind == @types.CAddr && cc.is_ext() {
          assert_eq(cc.bits.i, 0L)
        }
      }
      if i.op == @types.Add {
        add = true
      }
    }
  }
  assert_true(add)
}

///|
test "audit arm64: float comparison swap follows upstream order" {
  assert_eq(arm64_cmpop(10), 10)
  assert_eq(arm64_cmpop(11), 13)
  assert_eq(arm64_cmpop(12), 14)
  assert_eq(arm64_cmpop(13), 11)
  assert_eq(arm64_cmpop(14), 12)
  assert_eq(arm64_cmpop(15), 15)
  assert_eq(arm64_cmpop(16), 16)
  assert_eq(arm64_cmpop(17), 17)
}
