///|
// Upstream sysv.c skips Opare/Oarge when assigning ordinary registers.
test "audit: environment parameter does not consume RDI" {
  let src =
    #|function l $f(env %e, l %a) {
    #|@start
    #|  %r =l add %e, %a
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let env = f.blks[f.start_id].ins[0].to
  let arg = f.blks[f.start_id].ins[1].to
  ignore(abi(f, typs, false, interner, typs))
  let mut env_copies = 0
  let mut arg_reg = -1
  for i in f.blks[f.start_id].ins {
    if i.op == @types.Copy && i.to.eq(env) {
      env_copies += 1
      assert_eq(i.arg1.tmp_val(), @types.RAX)
    }
    if i.op == @types.Copy && i.to.eq(arg) {
      arg_reg = i.arg1.tmp_val()
    }
  }
  assert_eq(env_copies, 1)
  assert_eq(arg_reg, @types.RDI)
}

///|
test "audit: incoming environment and ordinary registers are marked live" {
  let src =
    #|function l $f(env %e, l %a, d %b) {
    #|@start
    #|  ret %a
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi(f, typs, false, interner, typs))
  assert_eq(
    f.reg,
    (1UL << @types.RAX) | (1UL << @types.RDI) | (1UL << @types.XMM0),
  )
}

///|
test "audit: environment argument does not consume RDI" {
  let src =
    #|function l $f(l %e, l %a) {
    #|@start
    #|  %r =l call $g(env %e, l %a)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let env = f.blks[f.start_id].ins[0].to
  let arg = f.blks[f.start_id].ins[1].to
  ignore(abi(f, typs, false, interner, typs))
  let mut env_reg = -1
  let mut arg_reg = -1
  for i in f.blks[f.start_id].ins {
    if i.op == @types.Copy && i.to.is_tmp() && i.to.tmp_val() < @types.Tmp0 {
      if i.arg1.eq(env) {
        env_reg = i.to.tmp_val()
      }
      if i.arg1.eq(arg) {
        arg_reg = i.to.tmp_val()
      }
    }
  }
  assert_eq(env_reg, @types.RAX)
  assert_eq(arg_reg, @types.RDI)
}
