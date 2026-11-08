///|
test "audit rv64 rejects external addresses with offsets" {
  let f = @types.Fn::new("f")
  let intern = @util.Interner::new()
  let c = @types.Con::{
    kind: @types.CAddr,
    label: intern.intern("ext"),
    sym_type: 2,
    bits: @types.ConBits::{ i: 8L, d: 0.0, s: 0.0, },
    flt: 0,
    is_local: false,
  }
  let st = rv64_emit_new(f, intern, ".L", "", StringBuilder())
  let rejected = try {
    rv64_loadaddr(st, c, "a0")
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "audit rv64 rejects TLS and offset direct call operands" {
  for (sym_type, offset) in [(1, 0L), (0, 8L)] {
    let f = @types.Fn::new("f")
    let intern = @util.Interner::new()
    let c = @types.Con::{
      kind: @types.CAddr,
      label: intern.intern("target"),
      sym_type,
      bits: @types.ConBits::{ i: offset, d: 0.0, s: 0.0, },
      flt: 0,
      is_local: false,
    }
    let ci = f.add_con(c)
    let st = rv64_emit_new(f, intern, ".L", "", StringBuilder())
    let rejected = try {
      rv64_emitins(
        st,
        @types.Ins::new_void(
          @types.Call,
          @types.Kw,
          @types.Ref::con(ci),
          @types.Ref::call(0),
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "audit rv64 copy from spill slot emits a load" {
  let f = @types.Fn::new("f")
  f.slot = 2
  let sb = StringBuilder()
  let st = rv64_emit_new(f, @util.Interner::new(), ".L", "", sb)
  rv64_emitins(
    st,
    @types.Ins::new(
      @types.Copy,
      @types.Kl,
      @types.Ref::tmp(@types.A0),
      @types.Ref::slot(0),
      @types.Ref::none(),
    ),
  )
  assert_eq(sb.to_string(), "\tld a0, -8(fp)\n")
}

///|
test "audit rv64 copy to spill slot emits a store" {
  let f = @types.Fn::new("f")
  f.slot = 2
  let sb = StringBuilder()
  let st = rv64_emit_new(f, @util.Interner::new(), ".L", "", sb)
  rv64_emitins(
    st,
    @types.Ins::new(
      @types.Copy,
      @types.Kd,
      @types.Ref::slot(0),
      @types.Ref::tmp(@types.FA0),
      @types.Ref::none(),
    ),
  )
  assert_eq(sb.to_string(), "\tfsd fa0, -8(fp)\n")
}

///|
test "audit rv64 halt emits ebreak" {
  let f = @types.Fn::new("f")
  let b = f.add_blk("start")
  f.rpo.push(b)
  f.blks[b].jmp.kind = @types.Jhlt
  let assembly = emit_rv64(f, @util.Interner::new(), ".L", "", false, [])
  assert_true(assembly.contains("\tebreak\n"))
}

///|
test "audit rv64 spilled branch condition is loaded" {
  let f = @types.Fn::new("f")
  f.slot = 2
  let b = f.add_blk("start")
  let yes = f.add_blk("yes")
  let no = f.add_blk("no")
  f.rpo.push(b)
  f.rpo.push(yes)
  f.rpo.push(no)
  f.blks[b].jmp.kind = @types.Jjnz
  f.blks[b].jmp.arg = @types.Ref::slot(0)
  f.blks[b].jmp.s1 = yes
  f.blks[b].jmp.s2 = no
  f.blks[yes].jmp.kind = @types.Jret0
  f.blks[no].jmp.kind = @types.Jret0
  let assembly = emit_rv64(f, @util.Interner::new(), ".L", "", false, [])
  assert_true(assembly.contains("\tlw t6, -8(fp)\n\tbeqz t6,"))
}
