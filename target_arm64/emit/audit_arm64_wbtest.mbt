///|
fn audit_emit_state(apple : Bool) -> Arm64EmitState {
  let f = @types.Fn::new("f")
  f.init_regs()
  let bid = f.add_blk("start")
  f.def_order.push(bid)
  f.rpo.push(bid)
  f.blks[bid].jmp = @types.Jump::new(@types.Jret0)
  {
    fn_: f,
    interner: @util.Interner::new(),
    sb: StringBuilder(),
    gasloc: if apple {
      "L"
    } else {
      ".L"
    },
    gassym: if apple {
      "_"
    } else {
      ""
    },
    apple,
    frame: 0,
    padding: 0,
  }
}

///|
test "audit arm64: large address uses mov and movk" {
  let st = audit_emit_state(false)
  arm64_emitins(
    st,
    @types.Ins::new(
      @types.Addr,
      @types.Kl,
      @types.Ref::tmp(@types.ARM64_R0),
      @types.Ref::slot(17500),
      @types.Ref::none(),
    ),
  )
  assert_eq(
    st.sb.to_string(),
    "\tmov\tx0, #4480\n\tmovk\tx0, #1, lsl #16\n\tadd\tx0, x29, x0\n",
  )
}

///|
test "audit arm64: large load slot materializes IP1" {
  let st = audit_emit_state(false)
  arm64_emitins(
    st,
    @types.Ins::new(
      @types.Load,
      @types.Kl,
      @types.Ref::tmp(@types.ARM64_R0),
      @types.Ref::slot(17500),
      @types.Ref::none(),
    ),
  )
  assert_true(st.sb.to_string().contains("\tldr\tx0, [x17]\n"))
}

///|
test "audit arm64: Apple large store preserves scratch through V31" {
  let st = audit_emit_state(true)
  arm64_emitins(
    st,
    @types.Ins::new(
      @types.Storew,
      @types.Kw,
      @types.Ref::none(),
      @types.Ref::tmp(@types.ARM64_IP1),
      @types.Ref::slot(17500),
    ),
  )
  assert_true(st.sb.to_string().contains("\tfmov\ts31, w17\n"))
  assert_true(st.sb.to_string().contains("\tstr\ts31, [x17]\n"))
}

///|
test "audit arm64: large frame materializes prologue and epilogue size" {
  let st = audit_emit_state(false)
  st.fn_.slot = 17500
  arm64_emitfn(st)
  assert_true(st.sb.to_string().contains("\tmovk\tx16, #1, lsl #16\n"))
  assert_true(st.sb.to_string().contains("\tsub\tsp, sp, x16\n"))
  assert_true(st.sb.to_string().contains("\tadd\tsp, sp, x16\n"))
}

///|
test "audit arm64: Apple function alignment forced to four" {
  let st = audit_emit_state(true)
  arm64_emitfn(st)
  assert_eq(st.fn_.align, 4)
}
