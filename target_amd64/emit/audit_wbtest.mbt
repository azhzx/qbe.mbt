///|
fn audit_emit_state(apple~ : Bool = false) -> EmitState {
  let f = @types.Fn::new("audit")
  f.slot = 4
  EmitState::{
    fn_: f,
    interner: @util.Interner::new(),
    gasloc: ".L",
    gassym: "",
    apple,
    windows: false,
    sb: StringBuilder::StringBuilder(),
    fp: "%rbp",
    fsz: 16,
    nclob: 0,
  }
}

///|
test "audit: absolute memory constant does not become RIP relative" {
  let st = audit_emit_state()
  let p = @types.Ref::con(st.fn_.get_con(4096L))
  emitins(
    st,
    @types.Ins::new(
      @types.Load,
      @types.Kl,
      @types.Ref::tmp(@types.RAX),
      p,
      @types.Ref::none(),
    ),
  )
  assert_eq(st.sb.to_string(), "\tmovq 4096, %rax\n")
}

///|
test "audit: base less indexed memory does not acquire RIP" {
  let st = audit_emit_state()
  let a = @types.Addr::new()
  a.offset = @types.Con::int(8L)
  a.index = @types.Ref::tmp(@types.RAX)
  a.scale = 4
  st.fn_.mems.push(a)
  emit_mem(st, @types.Ref::mem(0))
  assert_eq(st.sb.to_string(), "8(, %rax, 4)")
}

///|
test "audit: large constant spill copy uses two stores" {
  let st = audit_emit_state()
  let v = @types.Ref::con(st.fn_.get_con(4294967296L))
  emitcopy(st, @types.Ref::slot(0), v, @types.Kl)
  assert_eq(
    st.sb.to_string(),
    "\tmovl $4294967296, -16(%rbp)\n\tmovl $4294967296>>32, 4+-16(%rbp)\n",
  )
}

///|
test "audit: memory to slot copy uses reserved XMM15" {
  let st = audit_emit_state()
  emitcopy(st, @types.Ref::slot(0), @types.Ref::slot(2), @types.Kl)
  assert_eq(
    st.sb.to_string(),
    "\tmovsd -8(%rbp), %xmm15\n\tmovsd %xmm15, -16(%rbp)\n",
  )
}

///|
test "audit: same register subtraction avoids negation trick" {
  let st = audit_emit_state()
  let r = @types.Ref::tmp(@types.RAX)
  emitins(st, @types.Ins::new(@types.Sub, @types.Kl, r, r, r))
  assert_eq(st.sb.to_string(), "\tsubq %rax, %rax\n")
}

///|
test "audit: emitins preserves caller instruction value" {
  let st = audit_emit_state()
  let r = @types.Ref::tmp(@types.RAX)
  let v = @types.Ref::con(st.fn_.get_con(3L))
  let i = @types.Ins::new(@types.Mul, @types.Kl, r, r, v)
  emitins(st, i)
  assert_eq(i.arg1, r)
  assert_eq(i.arg2, v)
}

///|
test "audit: Apple TLS descriptor uses tlvp relocation" {
  let st = audit_emit_state(apple=true)
  let c = @types.Con::addr_sym(st.interner.intern("tlsvar"), @types.SYM_THR)
  let r = @types.Ref::con(st.fn_.add_con(c))
  emitins(
    st,
    @types.Ins::new(
      @types.Addr,
      @types.Kl,
      @types.Ref::tmp(@types.RAX),
      r,
      @types.Ref::none(),
    ),
  )
  assert_eq(st.sb.to_string(), "\tmovq tlsvar@tlvp(%rip), %rax\n")
}

///|
test "audit: Apple extern call does not use ELF plt suffix" {
  let st = audit_emit_state(apple=true)
  let c = @types.Con::addr_sym(st.interner.intern("callee"), @types.SYM_EXT)
  let r = @types.Ref::con(st.fn_.add_con(c))
  emitins(
    st,
    @types.Ins::new(
      @types.Call,
      @types.Kw,
      @types.Ref::none(),
      r,
      @types.Ref::call(0),
    ),
  )
  assert_eq(st.sb.to_string(), "\tcallq callee\n")
}

///|
test "audit: frame size retains upstream 64 bit width" {
  let st = audit_emit_state()
  st.fn_.slot = 1073741824
  assert_eq(framesz(st), 4294967296L)
}
