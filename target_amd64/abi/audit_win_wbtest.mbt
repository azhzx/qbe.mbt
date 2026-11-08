///|
// Whitebox tests for the Windows x64 ABI lowering (C amd64/winabi.c).
//
// The frontend helper `abi_parse_frontend` lives in abi_wbtest.mbt and leaves
// the function in the same state the real pipeline hands to the ABI stage.

///|
// Build an artificial Typ with the given size / dark flag (layout is not
// needed by winabi.c).
fn win_test_typ(size : Int64, dark : Int32) -> @types.Typ {
  let t = @types.Typ::new("t")
  t.size = size
  t.dark = dark
  t
}

///|
fn win_test_state(typs : Array[@types.Typ]) -> WinAbi {
  WinAbi::{ fn_: @types.Fn::new("f"), typs, buf: [], extra: None, }
}

///|
// Build an instruction; unused slots are Ref::none().
fn win_test_ins(
  op : @types.Op,
  cls : @types.Class,
  to : @types.Ref,
  arg1 : @types.Ref,
  arg2 : @types.Ref,
) -> @types.Ins {
  @types.Ins::new(op, cls, to, arg1, arg2)
}

///|
fn win_test_slot_ref(offset : Int32) -> @types.Ref {
  @types.Ref::slot(offset)
}

///|
fn win_test_con_i(f : @types.Fn, r : @types.Ref) -> Int64 {
  f.cons[r.con_val()].bits.i
}

///|
fn win_test_count_op(f : @types.Fn, bid : Int32, op : @types.Op) -> Int32 {
  let mut n = 0
  for ins in f.blks[bid].ins {
    if ins.op == op {
      n = n + 1
    }
  }
  n
}

///|
// The parameter refs of the start block, in order (they are prepended by the
// parser and are still Par instructions before the ABI stage).
fn win_test_param_refs(f : @types.Fn) -> Array[@types.Ref] {
  let r : Array[@types.Ref] = []
  for ins in f.blks[f.start_id].ins {
    if !ins.op.is_par() {
      break
    }
    r.push(ins.to)
  }
  r
}

///|
test "win abi: type_is_by_copy only for 1, 2, 4 and 8 bytes and non-dark" {
  assert_true(!type_is_by_copy(win_test_typ(1L, 0)))
  assert_true(!type_is_by_copy(win_test_typ(2L, 0)))
  assert_true(!type_is_by_copy(win_test_typ(4L, 0)))
  assert_true(!type_is_by_copy(win_test_typ(8L, 0)))
  assert_true(type_is_by_copy(win_test_typ(3L, 0)))
  assert_true(type_is_by_copy(win_test_typ(5L, 0)))
  assert_true(type_is_by_copy(win_test_typ(16L, 0)))
  assert_true(type_is_by_copy(win_test_typ(8L, 1)))
}

///|
test "win abi: is_integer_type follows KBASE" {
  assert_true(is_integer_type(@types.Kw.code()))
  assert_true(is_integer_type(@types.Kl.code()))
  assert_true(!is_integer_type(@types.Ks.code()))
  assert_true(!is_integer_type(@types.Kd.code()))
}

///|
test "win abi: integer and float arguments share one register counter" {
  let r0 = @types.Ref::tmp(64)
  let r1 = @types.Ref::tmp(65)
  let r2 = @types.Ref::tmp(66)
  let r3 = @types.Ref::tmp(67)
  let ins : Array[@types.Ins] = [
    win_test_ins(
      @types.Par,
      @types.Kl,
      r0,
      @types.Ref::none(),
      @types.Ref::none(),
    ),
    win_test_ins(
      @types.Par,
      @types.Kd,
      r1,
      @types.Ref::none(),
      @types.Ref::none(),
    ),
    win_test_ins(
      @types.Par,
      @types.Kl,
      r2,
      @types.Ref::none(),
      @types.Ref::none(),
    ),
    win_test_ins(
      @types.Par,
      @types.Kd,
      r3,
      @types.Ref::none(),
      @types.Ref::none(),
    ),
  ]
  let st = win_test_state([])
  let ru = RegisterUsage::new()
  let ac : Array[ArgClass] = []
  for _ in 0..<4 {
    ac.push(ArgClass::new())
  }
  let env = classify_arguments(st, ru, ins, 0, 4, ac)
  assert_true(env.is_none())
  assert_eq(ru.num_regs_passed, 4)
  assert_eq(ru.num_named_args_passed, 4)
  assert_true(ac[0].style == APSRegister)
  assert_true(ac[1].style == APSRegister)
  assert_true(ac[2].style == APSRegister)
  assert_true(ac[3].style == APSRegister)
  assert_true(ac[0].cls == @types.Kl)
  assert_true(ac[1].cls == @types.Kd)
  assert_eq(ac[0].align, 3)
  assert_eq(ac[0].size, 8U)
  // positions 0 and 2 are integer (RCX, R8), 1 and 3 float (XMM1, XMM3)
  assert_eq(
    register_usage_to_call_arg_value(ru),
    (1 << 4) | (1 << 6) | (1 << 9) | (1 << 11),
  )
}

///|
test "win abi: a fifth argument goes on the stack" {
  let ins : Array[@types.Ins] = []
  for i in 0..<5 {
    ins.push(
      win_test_ins(
        @types.Par,
        @types.Kl,
        @types.Ref::tmp(64 + i),
        @types.Ref::none(),
        @types.Ref::none(),
      ),
    )
  }
  let st = win_test_state([])
  let ru = RegisterUsage::new()
  let ac : Array[ArgClass] = []
  for _ in 0..<5 {
    ac.push(ArgClass::new())
  }
  let _ = classify_arguments(st, ru, ins, 0, 5, ac)
  assert_eq(ru.num_regs_passed, 4)
  assert_true(ac[3].style == APSRegister)
  assert_true(ac[4].style == APSInlineOnStack)
}

///|
test "win abi: a fifth by-copy argument goes on the stack as a pointer" {
  let t = win_test_typ(16L, 0)
  let ins : Array[@types.Ins] = []
  for i in 0..<5 {
    ins.push(
      win_test_ins(
        @types.Parc,
        @types.Kl,
        @types.Ref::tmp(64 + i),
        @types.Ref::typ(0),
        @types.Ref::none(),
      ),
    )
  }
  let st = win_test_state([t])
  let ru = RegisterUsage::new()
  let ac : Array[ArgClass] = []
  for _ in 0..<5 {
    ac.push(ArgClass::new())
  }
  let _ = classify_arguments(st, ru, ins, 0, 5, ac)
  assert_true(ac[0].style == APSCopyAndPointerInRegister)
  assert_true(ac[4].style == APSCopyAndPointerOnStack)
  assert_true(ac[0].cls == @types.Kl)
  assert_eq(ac[0].size, 16U)
}

///|
test "win abi: small by-value aggregate is classified as a word" {
  let t = win_test_typ(4L, 0)
  let ins : Array[@types.Ins] = [
    win_test_ins(
      @types.Argc,
      @types.Kl,
      @types.Ref::none(),
      @types.Ref::typ(0),
      @types.Ref::tmp(70),
    ),
  ]
  let st = win_test_state([t])
  let ru = RegisterUsage::new()
  let ac : Array[ArgClass] = [ArgClass::new()]
  let _ = classify_arguments(st, ru, ins, 0, 1, ac)
  assert_true(ac[0].style == APSRegister)
  assert_true(ac[0].cls == @types.Kw)
  assert_eq(ac[0].size, 4U)
}

///|
test "win abi: varargs duplicates float registers into integer ones" {
  let ins : Array[@types.Ins] = [
    win_test_ins(
      @types.Arg,
      @types.Kd,
      @types.Ref::none(),
      @types.Ref::tmp(64),
      @types.Ref::none(),
    ),
    win_test_ins(
      @types.Arg,
      @types.Ks,
      @types.Ref::none(),
      @types.Ref::tmp(65),
      @types.Ref::none(),
    ),
    win_test_ins(
      @types.Argv,
      @types.Kw,
      @types.Ref::none(),
      @types.Ref::none(),
      @types.Ref::none(),
    ),
    win_test_ins(
      @types.Arg,
      @types.Kl,
      @types.Ref::none(),
      @types.Ref::tmp(66),
      @types.Ref::none(),
    ),
  ]
  let st = win_test_state([])
  let ru = RegisterUsage::new()
  let ac : Array[ArgClass] = []
  for _ in 0..<4 {
    ac.push(ArgClass::new())
  }
  let _ = classify_arguments(st, ru, ins, 0, 4, ac)
  assert_true(ru.is_varargs_call)
  assert_true(ac[2].style == APSVarargsTag)
  assert_true(ac[2].cls == @types.Kw)
  // float slots 0 and 1 were also marked as integer slots 0 and 1
  assert_true(ru.regs_passed[0][0])
  assert_true(ru.regs_passed[0][1])
  // slots: XMM0, XMM1, (tag), R8; duplicated floats make RCX/RDX used too.
  assert_eq(
    register_usage_to_call_arg_value(ru),
    (1 << 4) | (1 << 5) | (1 << 6) | (1 << 8) | (1 << 9),
  )
  // register_for_arg maps argument position to the right register file
  assert_eq(register_for_arg(@types.Kl.code(), 0).tmp_val(), @types.RCX)
  assert_eq(register_for_arg(@types.Kl.code(), 1).tmp_val(), @types.RDX)
  assert_eq(register_for_arg(@types.Kl.code(), 2).tmp_val(), @types.R8)
  assert_eq(register_for_arg(@types.Kl.code(), 3).tmp_val(), @types.R9)
  assert_eq(register_for_arg(@types.Kd.code(), 2).tmp_val(), @types.XMM2)
  assert_eq(register_for_arg(@types.Ks.code(), 0).tmp_val(), @types.XMM0)
}

///|
test "win abi: find_end_of_func_parameters stops at the first non-parameter" {
  let b = @types.Blk::new(0, "start")
  b.ins.push(
    win_test_ins(
      @types.Par,
      @types.Kl,
      @types.Ref::tmp(64),
      @types.Ref::none(),
      @types.Ref::none(),
    ),
  )
  b.ins.push(
    win_test_ins(
      @types.Pare,
      @types.Kl,
      @types.Ref::tmp(65),
      @types.Ref::none(),
      @types.Ref::none(),
    ),
  )
  b.ins.push(
    win_test_ins(
      @types.Par,
      @types.Kw,
      @types.Ref::tmp(66),
      @types.Ref::none(),
      @types.Ref::none(),
    ),
  )
  b.ins.push(
    win_test_ins(
      @types.Add,
      @types.Kw,
      @types.Ref::tmp(67),
      @types.Ref::tmp(64),
      @types.Ref::tmp(66),
    ),
  )
  assert_eq(find_end_of_func_parameters(b), 3)
}

///|
test "win abi: word parameters come in via RCX and RDX" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let params = win_test_param_refs(f)
  let dbg = abi_win(f, typs, true, interner, typs)
  assert_true(dbg.contains("\n> After ABI lowering:\n"))
  assert_true(dbg.contains("%a =w copy R2"))
  assert_true(dbg.contains("%b =w copy R3"))
  assert_true(dbg.contains("R1 =w copy %s"))
  assert_true(dbg.contains("ret0 0001"))
  // no Par is left behind
  assert_eq(win_test_count_op(f, f.start_id, @types.Par), 0)
  // the incoming argument registers are marked used
  assert_eq(f.reg, (1UL << @types.RCX) | (1UL << @types.RDX))
  // and the lowering copies from RCX / RDX into the named parameters
  let mut from_a = -1
  let mut from_b = -1
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Copy {
      if ins.to.eq(params[0]) {
        from_a = ins.arg1.tmp_val()
      }
      if ins.to.eq(params[1]) {
        from_b = ins.arg1.tmp_val()
      }
    }
  }
  assert_eq(from_a, @types.RCX)
  assert_eq(from_b, @types.RDX)
}

///|
test "win abi: parameter position picks the register file" {
  let src =
    #|function w $f(w %a, d %b, l %c, s %d) {
    #|@start
    #|  %s =w add %a, 1
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let params = win_test_param_refs(f)
  ignore(abi_win(f, typs, false, interner, typs))
  let regs : Array[Int32] = []
  for p in params {
    let mut r = -1
    for ins in f.blks[f.start_id].ins {
      if ins.op == @types.Copy && ins.to.eq(p) {
        r = ins.arg1.tmp_val()
      }
    }
    regs.push(r)
  }
  assert_eq(regs.length(), 4)
  // position 0 -> RCX, 1 -> XMM1, 2 -> R8, 3 -> XMM3
  assert_eq(regs[0], @types.RCX)
  assert_eq(regs[1], @types.XMM1)
  assert_eq(regs[2], @types.R8)
  assert_eq(regs[3], @types.XMM3)
}

///|
test "win abi: call arguments go into RCX and RDX and shadow space is reserved" {
  let src =
    #|export function w $main() {
    #|@start
    #|  %r =w call $g(w 1, w 2)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut call_ca = -1
  let sallocs : Array[Int64] = []
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Call {
      call_ca = ins.arg2.call_val()
    }
    if ins.op == @types.Salloc && ins.arg1.is_con() {
      sallocs.push(win_test_con_i(f, ins.arg1))
    }
  }
  // bit 0: rax returned; bits 4,5: rcx and rdx passed
  assert_eq(call_ca, 0x31)
  // shadow space reservation and the matching cleanup
  assert_true(sallocs.contains(32L))
  assert_true(sallocs.contains(-32L))
}

///|
test "win abi: fifth integer call argument is stored in the shadow stack area" {
  let src =
    #|export function w $main() {
    #|@start
    #|  %r =w call $g(w 1, w 2, w 3, w 4, w 5)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut call_ca = -1
  let mut salloc48 = 0
  let mut salloc_neg48 = 0
  let mut add32 = 0
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Call {
      call_ca = ins.arg2.call_val()
    }
    if ins.op == @types.Salloc && ins.arg1.is_con() {
      let v = win_test_con_i(f, ins.arg1)
      if v == 48L {
        salloc48 = salloc48 + 1
      }
      if v == -48L {
        salloc_neg48 = salloc_neg48 + 1
      }
    }
    if ins.op == @types.Add && ins.arg2.is_con() {
      if win_test_con_i(f, ins.arg2) == 32L {
        add32 = add32 + 1
      }
    }
  }
  // four int registers are passed, rax is returned
  assert_eq(call_ca, 0xf1)
  // 16 bytes of stack args + 32 bytes of shadow space, plus the cleanup
  assert_eq(salloc48, 1)
  assert_eq(salloc_neg48, 1)
  // the 5th argument is stored at shadow + 0
  assert_eq(add32, 1)
  assert_eq(win_test_count_op(f, f.start_id, @types.Storel), 1)
}

///|
test "win abi: large struct return uses a hidden pointer in RCX" {
  let src =
    #|type :mem = { b 17 }
    #|export function l $main() {
    #|@start
    #|  %r =:mem call $g(w 1, w 2)
    #|  %x =l load %r
    #|  ret %x
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut call_ca = -1
  let mut pad_ref = @types.Ref::none()
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Call {
      call_ca = ins.arg2.call_val()
    }
    if ins.op == @types.Alloc8 && ins.arg1.is_con() {
      if win_test_con_i(f, ins.arg1) == 17L {
        pad_ref = ins.to
      }
    }
  }
  // bit 0: rax returned; bits 4,5,6: rcx (hidden return pointer), rdx and r8
  // (the two arguments, pushed past the hidden pointer)
  assert_eq(call_ca, 0x71)
  assert_true(!pad_ref.is_none())
  // the hidden pointer is loaded into rcx, and the returned pointer is copied
  // out of rax into the call result
  let mut rcx_from_pad = false
  let mut result_from_rax = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Copy {
      if ins.to.tmp_val() == @types.RCX && ins.arg1.eq(pad_ref) {
        rcx_from_pad = true
      }
      if ins.arg1.tmp_val() == @types.RAX {
        result_from_rax = true
      }
    }
  }
  assert_true(rcx_from_pad)
  assert_true(result_from_rax)
}

///|
test "win abi: small struct return is returned in RAX through a copy" {
  let src =
    #|type :st2 = { w }
    #|export function l $main() {
    #|@start
    #|  %r =:st2 call $g()
    #|  %x =l load %r
    #|  ret %x
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  // the call result is the start block's first instruction (no parameters)
  let mut result = @types.Ref::none()
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Call {
      result = ins.to
    }
  }
  ignore(abi_win(f, typs, false, interner, typs))
  let mut call_ca = -1
  let mut alloc_for_result = false
  let mut store_into_result = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Call {
      call_ca = ins.arg2.call_val()
    }
    if ins.op == @types.Alloc8 && ins.to.eq(result) {
      alloc_for_result = true
    }
    if ins.op == @types.Storel && ins.arg2.eq(result) {
      store_into_result = true
    }
  }
  assert_eq(call_ca, 0x1)
  assert_true(alloc_for_result)
  assert_true(store_into_result)
}

///|
test "win abi: large struct argument is copied and passed by pointer" {
  let src =
    #|type :mem = { b 17 }
    #|export function w $main() {
    #|@start
    #|  %p =l alloc4 17
    #|  %r =w call $g(:mem %p)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut copy_ref = @types.Ref::none()
  let mut call_ca = -1
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Alloc8 && ins.arg1.is_con() {
      if win_test_con_i(f, ins.arg1) == 17L {
        copy_ref = ins.to
      }
    }
    if ins.op == @types.Call {
      call_ca = ins.arg2.call_val()
    }
  }
  // bit 0: rax returned; bit 4: rcx passed
  assert_eq(call_ca, 0x11)
  assert_true(!copy_ref.is_none())
  let mut blit0 = false
  let mut blit1 = false
  let mut rcx_from_copy = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Blit0 && ins.arg2.eq(copy_ref) {
      blit0 = true
    }
    if ins.op == @types.Blit1 && ins.arg1.rint_val() == 17 {
      blit1 = true
    }
    if ins.op == @types.Copy &&
      ins.to.tmp_val() == @types.RCX &&
      ins.arg1.eq(copy_ref) {
      rcx_from_copy = true
    }
  }
  assert_true(blit0)
  assert_true(blit1)
  assert_true(rcx_from_copy)
}

///|
test "win abi: small struct argument is loaded from its pointer" {
  let src =
    #|type :st2 = { w }
    #|export function w $main() {
    #|@start
    #|  %p =l alloc4 4
    #|  %r =w call $g(:st2 %p)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut call_ca = -1
  let mut load_into_rcx = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Call {
      call_ca = ins.arg2.call_val()
    }
    if ins.op == @types.Load &&
      ins.to.tmp_val() == @types.RCX &&
      ins.cls == @types.Kw {
      load_into_rcx = true
    }
  }
  assert_eq(call_ca, 0x11)
  assert_true(load_into_rcx)
}

///|
test "win abi: varargs call duplicates float arguments into int registers" {
  let src =
    #|export function w $main() {
    #|@start
    #|  %r =w call $g(d d_1.5, s s_2.5, w 7, d d_3.5, ...)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut call_ca = -1
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Call {
      call_ca = ins.arg2.call_val()
    }
  }
  // rax returned, int slots 0..3 all used (floats 0/1/3 duplicated, w 7),
  // float slots 0/1/3 used.
  assert_eq(call_ca, 0xbf1)
  // one cast per duplicated float argument
  assert_eq(win_test_count_op(f, f.start_id, @types.Cast), 3)
}

///|
test "win abi: varargs function lowers vastart past the named arguments" {
  let src =
    #|export function d $f(l %x, ...) {
    #|@start
    #|  %vp =l alloc8 32
    #|  vastart %vp
    #|  %i =l vaarg %vp
    #|  %n =d vaarg %vp
    #|  ret %n
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  assert_eq(win_test_count_op(f, f.start_id, @types.Vastart), 0)
  assert_eq(win_test_count_op(f, f.start_id, @types.Vaarg), 0)
  // one named argument: rbp + 1*8 + 16 = 24
  let mut vastart_off = -1L
  let mut add8 = 0
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Add &&
      ins.arg1.tmp_val() == @types.RBP &&
      ins.arg2.is_con() {
      vastart_off = win_test_con_i(f, ins.arg2)
    }
    if ins.op == @types.Add && ins.arg2.is_con() {
      if win_test_con_i(f, ins.arg2) == 8L {
        add8 = add8 + 1
      }
    }
  }
  assert_eq(vastart_off, 24L)
  // each of the two vaargs bumps the pointer by 8 bytes
  assert_eq(add8, 2)
}

///|
test "win abi: env parameter comes in via RAX and does not consume RCX" {
  let src =
    #|function l $f(env %e, l %a) {
    #|@start
    #|  %r =l add %e, %a
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let params = win_test_param_refs(f)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut e_reg = -1
  let mut a_reg = -1
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Copy {
      if ins.to.eq(params[0]) {
        e_reg = ins.arg1.tmp_val()
      }
      if ins.to.eq(params[1]) {
        a_reg = ins.arg1.tmp_val()
      }
    }
  }
  assert_eq(e_reg, @types.RAX)
  assert_eq(a_reg, @types.RCX)
}

///|
test "win abi: env call passes the environment in RAX" {
  let src =
    #|function l $f(l %e, l %a) {
    #|@start
    #|  %r =l call $g(env %e, l %a)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut call_ca = -1
  let mut env_to_rax = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Call {
      call_ca = ins.arg2.call_val()
    }
    if ins.op == @types.Copy &&
      ins.to.tmp_val() == @types.RAX &&
      ins.arg1.is_tmp() {
      env_to_rax = true
    }
  }
  // bit 0 (rax returned), bit 4 (rcx arg), bit 12 (env in rax)
  assert_eq(call_ca, 0x1011)
  assert_true(env_to_rax)
}

///|
test "win abi: function returning a large struct writes through the hidden pointer" {
  let src =
    #|type :mem = { b 17 }
    #|export function :mem $f(l %a) {
    #|@start
    #|  %x =l alloc4 17
    #|  ret %x
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let params = win_test_param_refs(f)
  ignore(abi_win(f, typs, false, interner, typs))
  // the hidden return pointer is copied out of rcx into fn.retr
  let mut retr_from_rcx = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Copy && ins.to.eq(f.retr) {
      if ins.arg1.tmp_val() == @types.RCX {
        retr_from_rcx = true
      }
    }
  }
  assert_true(retr_from_rcx)
  // the hidden pointer is the first parameter, so %a comes in via rdx
  let mut a_from_rdx = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Copy && ins.to.eq(params[0]) {
      if ins.arg1.tmp_val() == @types.RDX {
        a_from_rdx = true
      }
    }
  }
  assert_true(a_from_rdx)
  // ret %x lowers to blit0 %x -> fn.retr, blit1 17, copy rax <- fn.retr
  let mut blit0 = false
  let mut blit1 = false
  let mut rax_from_retr = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Blit0 && ins.arg2.eq(f.retr) {
      blit0 = true
    }
    if ins.op == @types.Blit1 && ins.arg1.rint_val() == 17 {
      blit1 = true
    }
    if ins.op == @types.Copy &&
      ins.to.tmp_val() == @types.RAX &&
      ins.arg1.eq(f.retr) {
      rax_from_retr = true
    }
  }
  assert_true(blit0)
  assert_true(blit1)
  assert_true(rax_from_retr)
  assert_eq(f.blks[f.start_id].jmp.arg.call_val(), 1)
}

///|
test "win abi: fifth parameter is read from the incoming stack area" {
  let src =
    #|function l $f(w %a, w %b, w %c, w %d, l %e) {
    #|@start
    #|  %x =l add %e, 1
    #|  ret %x
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let params = win_test_param_refs(f)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut e_from_slot = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Copy && ins.to.eq(params[4]) {
      if ins.arg1 == win_test_slot_ref(-12) {
        e_from_slot = true
      }
    }
  }
  assert_true(e_from_slot)
}

///|
test "win abi: fifth struct parameter is loaded as a pointer from the stack" {
  let src =
    #|type :mem = { b 17 }
    #|function l $f(w %a, w %b, w %c, w %d, :mem %m) {
    #|@start
    #|  %x =l load %m
    #|  ret %x
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let params = win_test_param_refs(f)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut m_from_slot = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Load && ins.to.eq(params[4]) && ins.cls == @types.Kl {
      if ins.arg1 == win_test_slot_ref(-12) {
        m_from_slot = true
      }
    }
  }
  assert_true(m_from_slot)
}

///|
test "win abi: fifth small struct parameter is copied out of the stack" {
  let src =
    #|type :st2 = { w }
    #|function l $f(w %a, w %b, w %c, w %d, :st2 %m) {
    #|@start
    #|  %x =l load %m
    #|  ret %x
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let params = win_test_param_refs(f)
  ignore(abi_win(f, typs, false, interner, typs))
  // the parameter gets an alloca of its size, filled by a copy of the incoming
  // stack slot
  let mut alloc_for_m = false
  let mut copy_from_slot = false
  let mut store_into_m = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Alloc8 && ins.to.eq(params[4]) && ins.arg1.is_con() {
      if win_test_con_i(f, ins.arg1) == 4L {
        alloc_for_m = true
      }
    }
    if ins.op == @types.Copy && ins.arg1 == win_test_slot_ref(-12) {
      copy_from_slot = true
    }
    if ins.op == @types.Storel && ins.arg2.eq(params[4]) {
      store_into_m = true
    }
  }
  assert_true(alloc_for_m)
  assert_true(copy_from_slot)
  assert_true(store_into_m)
}

///|
test "win abi: void function with an empty block lowers cleanly" {
  let src =
    #|export function $f() {
    #|@start
    #|  ret
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let dbg = abi_win(f, typs, true, interner, typs)
  assert_true(dbg.contains("ret0"))
  assert_eq(f.blks[f.start_id].jmp.kind, @types.Jret0)
}

///|
test "win abi: no debug output when print_dbg is false" {
  let src =
    #|function w $f(w %a) {
    #|@start
    #|  ret %a
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let dbg = abi_win(f, typs, false, interner, typs)
  assert_eq(dbg, "")
}

///|
test "win abi: lowering consumes all argument and parameter instructions" {
  let src =
    #|export function w $main(w %a) {
    #|@start
    #|  %r =w call $g(w 1, w %a)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  for bid in f.def_order {
    for ins in f.blks[bid].ins {
      assert_true(!ins.op.is_par())
      assert_true(!ins.op.is_arg())
    }
  }
}

///|
test "win abi: fifth large struct argument is passed by pointer on the stack" {
  let src =
    #|type :mem = { b 17 }
    #|export function w $main(l %p) {
    #|@start
    #|  %r =w call $g(w 1, w 2, w 3, w 4, :mem %p)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi_win(f, typs, false, interner, typs))
  let mut call_ca = -1
  let mut copy_ref = @types.Ref::none()
  let mut salloc48 = false
  let mut add32 = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Call {
      call_ca = ins.arg2.call_val()
    }
    if ins.op == @types.Alloc8 && ins.arg1.is_con() {
      if win_test_con_i(f, ins.arg1) == 17L {
        copy_ref = ins.to
      }
    }
    if ins.op == @types.Salloc && ins.arg1.is_con() {
      if win_test_con_i(f, ins.arg1) == 48L {
        salloc48 = true
      }
    }
    if ins.op == @types.Add && ins.arg2.is_con() {
      if win_test_con_i(f, ins.arg2) == 32L {
        add32 = true
      }
    }
  }
  // four int registers are passed, rax is returned (the struct itself is a
  // pointer on the stack, not a register)
  assert_eq(call_ca, 0xf1)
  assert_true(!copy_ref.is_none())
  assert_true(salloc48)
  assert_true(add32)
  // the pointer to the copy is stored in the first stack slot
  let mut stored_copy = false
  for ins in f.blks[f.start_id].ins {
    if ins.op == @types.Storel && ins.arg1.eq(copy_ref) {
      stored_copy = true
    }
  }
  assert_true(stored_copy)
}

///|
test "win abi: align_up and align_down use C unsigned arithmetic" {
  assert_eq(align_down(17U, 16U), 16U)
  assert_eq(align_down(32U, 16U), 32U)
  assert_eq(align_up(0U, 16U), 0U)
  assert_eq(align_up(1U, 16U), 16U)
  assert_eq(align_up(16U, 16U), 16U)
  assert_eq(align_up(17U, 16U), 32U)
}

///|
test "win abi: env with varargs is rejected" {
  let src =
    #|function l $f(l %e) {
    #|@start
    #|  %r =l call $g(env %e, ...)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  let mut raised = false
  ignore(abi_win(f, typs, false, interner, typs)) catch {
    _ => raised = true
  }
  assert_true(raised)
}
