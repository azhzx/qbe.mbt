///|
// Windows x64 ABI lowering for amd64 - a declaration-by-declaration
// transcription of vendor/qbe/amd64/winabi.c (C amd64_winabi_abi and its
// helpers): ArgPassStyle, ArgClass, ExtraAlloc, RegisterUsage,
// classify_arguments, type_is_by_copy, assign_register_or_stack,
// register_for_arg, lower_call, lower_block_return, lower_vastart,
// lower_vaarg, lower_args_for_block, find_end_of_func_parameters,
// lower_func_parameters, amd64_winabi_abi.
//
// The win-specific register tables/functions (C amd64_winabi_rsave/rclob/
// retregs/argregs) live in @types as rsave_win, rclob_win, win_retregs and
// win_argregs because live/spill/rega consume them through target_cfg; this
// file uses them instead of keeping a second copy (AGENTS.md rule 3).
//
// Emission convention: C emit/emiti prepend to a global buffer, so this port
// appends to `buf` and reverses it once when a block is written back.

///|
// C enum ArgPassStyle.
#derive(Eq)
priv enum ArgPassStyle {
  APSInvalid
  APSRegister
  APSInlineOnStack
  APSCopyAndPointerInRegister
  APSCopyAndPointerOnStack
  APSVarargsTag
  APSEnvTag
}

///|
// C struct ArgClass. (C also declares `Typ *type` here but never reads it;
// the dead field is omitted.)
priv struct ArgClass {
  mut style : ArgPassStyle
  mut align : Int32
  mut size : UInt32 // C `uint size` (truncates Typ.size)
  mut cls : @types.Class
  mut arg_ref : @types.Ref // C `Ref ref`
}

///|
fn ArgClass::new() -> ArgClass {
  ArgClass::{
    style: APSInvalid,
    align: 0,
    size: 0U,
    cls: @types.Kw,
    arg_ref: @types.Ref::none(),
  }
}

///|
// C struct ExtraAlloc: an instruction to prepend to the start block.
priv struct ExtraAlloc {
  i : @types.Ins
  link : ExtraAlloc?
}

///|
// C struct RegisterUsage.
priv struct RegisterUsage {
  mut num_regs_passed : Int32
  // Indexed first by 0=int, 1=float, then by register slot (0=RCX/XMM0 ..).
  regs_passed : Array[Array[Bool]]
  mut rax_returned : Bool
  mut xmm0_returned : Bool
  mut num_named_args_passed : Int32
  mut is_varargs_call : Bool
  mut has_env : Bool
}

///|
fn RegisterUsage::new() -> RegisterUsage {
  RegisterUsage::{
    num_regs_passed: 0,
    regs_passed: [[false, false, false, false], [false, false, false, false]],
    rax_returned: false,
    xmm0_returned: false,
    num_named_args_passed: 0,
    is_varargs_call: false,
    has_env: false,
  }
}

///|
// Number of stack bytes required to be reserved for the callee
// (C SHADOW_SPACE_SIZE).
const SHADOW_SPACE_SIZE : UInt32 = 32U

///|
// C ALIGN_DOWN(n, a): clear the low bits below a (a is a power of two).
fn align_down(n : UInt32, a : UInt32) -> UInt32 {
  n & (0U - a)
}

///|
// C ALIGN_UP(n, a) = ALIGN_DOWN(n + a - 1, a).
fn align_up(n : UInt32, a : UInt32) -> UInt32 {
  align_down(n + (a - 1U), a)
}

///|
// Truncate a 64-bit type size to C's `uint` (ArgClass.size).
fn c_uint(n : Int64) -> UInt32 {
  n.to_int().reinterpret_as_uint()
}

///|
// C SLOT(-slot_offset) with slot_offset a uint.
fn slot_ref(slot_offset : UInt32) -> @types.Ref {
  @types.Ref::slot((0U - slot_offset).reinterpret_as_int())
}

///|
// C INT(x).
fn int_ref(v : Int32) -> @types.Ref {
  @types.Ref::rint(v)
}

///|
// State threaded through the lowering (C's globals in winabi.c: `func`,
// `typ`, `curi`/insb, and the ExtraAlloc list).
priv struct WinAbi {
  fn_ : @types.Fn
  typs : Array[@types.Typ]
  buf : Array[@types.Ins]
  mut extra : ExtraAlloc?
}

///|
fn win_emit(
  st : WinAbi,
  op : @types.Op,
  k : @types.Class,
  to : @types.Ref,
  a0 : @types.Ref,
  a1 : @types.Ref,
) -> Unit {
  st.buf.push(@types.Ins::new(op, k, to, a0, a1))
}

///|
fn win_emiti(st : WinAbi, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
// Reverse the append-only buffer into the final instruction order
// (C `idup(block, curi, n)` with curi pointing into the prepend buffer).
fn win_flush(st : WinAbi) -> Array[@types.Ins] {
  let r : Array[@types.Ins] = []
  for k in (st.buf.length() - 1)>=..0 {
    r.push(st.buf[k])
  }
  r
}

///|
// C newtmp(prfx, k, func), returning the ref (TMP(t)).
fn win_newtmp(st : WinAbi, prfx : String, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp(prfx, k))
}

///|
// C getcon(v, func).
fn win_getcon(st : WinAbi, v : Int64) -> @types.Ref {
  @types.Ref::con(st.fn_.get_con(v))
}

///|
// C CALL(x).
fn win_call(ca : Int32) -> @types.Ref {
  @types.Ref::call(ca)
}

///|
// C register_usage_to_call_arg_value: pack the RCall value documented at the
// top of winabi.c.
fn register_usage_to_call_arg_value(ru : RegisterUsage) -> Int32 {
  let int_bit = fn(is_float : Bool, i : Int32) -> Int32 {
    if ru.regs_passed[if is_float { 1 } else { 0 }][i] {
      1
    } else {
      0
    }
  }
  (if ru.rax_returned { 1 } else { 0 }) |
  ((if ru.xmm0_returned { 1 } else { 0 }) << 1) |
  (int_bit(false, 0) << 4) |
  (int_bit(false, 1) << 5) |
  (int_bit(false, 2) << 6) |
  (int_bit(false, 3) << 7) |
  (int_bit(true, 0) << 8) |
  (int_bit(true, 1) << 9) |
  (int_bit(true, 2) << 10) |
  (int_bit(true, 3) << 11) |
  ((if ru.has_env { 1 } else { 0 }) << 12)
}

///|
// C assign_register_or_stack: take the next register slot (int and float
// share one counter on Windows) or mark the argument for the stack.
fn assign_register_or_stack(
  ru : RegisterUsage,
  arg : ArgClass,
  is_float : Bool,
  by_copy : Bool,
) -> Unit {
  if ru.num_regs_passed == 4 {
    arg.style = if by_copy {
      APSCopyAndPointerOnStack
    } else {
      APSInlineOnStack
    }
  } else {
    ru.regs_passed[if is_float { 1 } else { 0 }][ru.num_regs_passed] = true
    ru.num_regs_passed = ru.num_regs_passed + 1
    arg.style = if by_copy { APSCopyAndPointerInRegister } else { APSRegister }
  }
  ru.num_named_args_passed = ru.num_named_args_passed + 1
}

///|
// C type_is_by_copy: sizes other than 1/2/4/8 (and dark types) are passed by
// pointer to a copy.
fn type_is_by_copy(type_ : @types.Typ) -> Bool {
  type_.dark != 0 ||
  (type_.size != 1L && type_.size != 2L && type_.size != 4L && type_.size != 8L)
}

///|
// C is_integer_type: ty is a Class code (Kw Kl Ks Kd = 0..3).
fn is_integer_type(ty : Int32) -> Bool {
  if ty < 0 || ty >= 4 {
    abort("winabi: expecting Kw Kl Ks Kd")
  }
  @types.Class::from_code(ty).base() == 0
}

///|
// C register_for_arg: the integer argument registers are not contiguous with
// the float ones, so they come from two different tables.
fn register_for_arg(cls : Int32, counter : Int32) -> @types.Ref {
  if counter >= 4 {
    abort("winabi: register counter out of range")
  }
  if is_integer_type(cls) {
    @types.Ref::tmp(@types.rsave_win[counter])
  } else {
    @types.Ref::tmp(@types.XMM0 + counter)
  }
}

///|
// C classify_arguments: used for both call arguments and function parameters.
// `begin` is the index of the first Oarg/Opar and `end` is one past the last
// one. Returns the environment ref (C's Ref *env out-parameter).
fn classify_arguments(
  st : WinAbi,
  ru : RegisterUsage,
  ins : Array[@types.Ins],
  begin : Int32,
  end : Int32,
  arg_classes : Array[ArgClass],
) -> @types.Ref raise {
  let mut env = @types.Ref::none()
  let mut a : Int32 = 0
  let mut i = begin
  while i < end {
    let instr = ins[i]
    let arg = arg_classes[a]
    match instr.op {
      @types.Arg | @types.Par => {
        assign_register_or_stack(ru, arg, instr.cls.base() == 1, false)
        arg.cls = instr.cls
        arg.align = 3
        arg.size = 8U
      }
      @types.Argc | @types.Parc => {
        // C reads instr->arg[0].val, a TYPE ref, for both ops.
        let type_ = st.typs[instr.arg1.typ_val()]
        let by_copy = type_is_by_copy(type_)
        assign_register_or_stack(ru, arg, false, by_copy)
        arg.cls = @types.Kl
        if !by_copy && type_.size <= 4L {
          arg.cls = @types.Kw
        }
        arg.align = 3
        arg.size = c_uint(type_.size)
      }
      @types.Arge => {
        env = instr.arg1
        arg.style = APSEnvTag
        ru.has_env = true
      }
      @types.Pare => {
        env = instr.to
        arg.style = APSEnvTag
        ru.has_env = true
      }
      @types.Argv => {
        ru.is_varargs_call = true
        arg.style = APSVarargsTag
      }
      _ => ()
    }
    i = i + 1
    a = a + 1
  }
  if ru.has_env && ru.is_varargs_call {
    raise @util.QbeError::Ice("can't use env with varargs")
  }
  // During a varargs call, float arguments have to be duplicated to their
  // associated integer register, so mark them as in-use too.
  if ru.is_varargs_call {
    for i in 0..<4 {
      if ru.regs_passed[1][i] {
        ru.regs_passed[0][i] = true
      }
    }
  }
  env
}

///|
// C lower_call. Rewrites one Ocall (and its preceding Oarg* instructions) into
// register/stack moves plus the call itself. Returns the index of the
// instruction preceding the earliest argument consumed.
fn lower_call(st : WinAbi, block : @types.Blk, call_idx : Int32) -> Int32 raise {
  let ins = block.ins
  // Walk backwards over the argument instructions.
  let mut instr_past_args = call_idx - 1
  while instr_past_args >= 0 {
    if !ins[instr_past_args].op.is_arg() {
      break
    }
    instr_past_args = instr_past_args - 1
  }
  let earliest_arg_instr = instr_past_args + 1
  // One ArgClass per argument instruction (not for the call itself).
  let num_args = call_idx - earliest_arg_instr
  let arg_classes : Array[ArgClass] = []
  for _ in 0..<num_args {
    arg_classes.push(ArgClass::new())
  }
  let reg_usage = RegisterUsage::new()
  let ret_arg_class = ArgClass::new()
  let call_instr = ins[call_idx]
  // Ocall arg[1] holds the aggregate return type ref; C compares it against R,
  // which the port spells Ref::none().
  let il_has_struct_return = !call_instr.arg2.is_none()
  let mut is_struct_return = false
  if il_has_struct_return {
    let ret_type = st.typs[call_instr.arg2.typ_val()]
    is_struct_return = type_is_by_copy(ret_type)
    if is_struct_return {
      assign_register_or_stack(reg_usage, ret_arg_class, false, true)
    }
    ret_arg_class.size = c_uint(ret_type.size)
  }
  let env = classify_arguments(
    st, reg_usage, ins, earliest_arg_instr, call_idx, arg_classes,
  )

  // Stack space for the stack-located arguments. Large struct copies are
  // alloca'd separately; they only contribute (at most) 8 bytes here.
  let mut stack_usage : UInt32 = 0U
  for i in 0..<num_args {
    let arg = arg_classes[i]
    if arg.style == APSInlineOnStack {
      if arg.align > 4 {
        raise @util.QbeError::Ice("win abi cannot pass alignments > 16")
      }
      stack_usage = stack_usage + arg.size
    } else if arg.style == APSCopyAndPointerOnStack {
      stack_usage = stack_usage + 8U
    }
  }
  stack_usage = align_up(stack_usage, 16U)

  // Logically after the call (instructions are emitted in reverse), so this is
  // a negative stack allocation cleaning up after the call.
  let stack_size_ref = win_getcon(
    st,
    -(stack_usage + SHADOW_SPACE_SIZE).to_int64(),
  )
  win_emit(
    st,
    @types.Salloc,
    @types.Kl,
    @types.Ref::none(),
    stack_size_ref,
    @types.Ref::none(),
  )

  let mut return_pad : ExtraAlloc? = None
  if is_struct_return {
    let ret_pad_ref = win_newtmp(st, "abi.ret_pad", @types.Kl)
    let return_pad_alloc = ExtraAlloc::{
      i: @types.Ins::new(
        @types.Alloc8,
        @types.Kl,
        ret_pad_ref,
        win_getcon(st, ret_arg_class.size.to_int64()),
        @types.Ref::none(),
      ),
      link: st.extra,
    }
    st.extra = Some(return_pad_alloc)
    return_pad = Some(return_pad_alloc)
    reg_usage.rax_returned = true
    win_emit(
      st,
      @types.Copy,
      call_instr.cls,
      call_instr.to,
      @types.Ref::tmp(@types.RAX),
      @types.Ref::none(),
    )
  } else if il_has_struct_return {
    // The IL treats the return as a pointer, but the calling convention
    // returns it in RAX: store the value into an alloca pointed at by the
    // original call result.
    let return_copy = ExtraAlloc::{
      i: @types.Ins::new(
        @types.Alloc8,
        @types.Kl,
        call_instr.to,
        win_getcon(st, 8L),
        @types.Ref::none(),
      ),
      link: st.extra,
    }
    st.extra = Some(return_copy)
    let copy = win_newtmp(st, "abi.copy", @types.Kl)
    win_emit(
      st,
      @types.Storel,
      @types.Kw,
      @types.Ref::none(),
      copy,
      call_instr.to,
    )
    win_emit(
      st,
      @types.Copy,
      @types.Kl,
      copy,
      @types.Ref::tmp(@types.RAX),
      @types.Ref::none(),
    )
    reg_usage.rax_returned = true
  } else if is_integer_type(call_instr.cls.code()) {
    // Only a basic type returned from the call, integer.
    win_emit(
      st,
      @types.Copy,
      call_instr.cls,
      call_instr.to,
      @types.Ref::tmp(@types.RAX),
      @types.Ref::none(),
    )
    reg_usage.rax_returned = true
  } else {
    // Basic type, floating point.
    win_emit(
      st,
      @types.Copy,
      call_instr.cls,
      call_instr.to,
      @types.Ref::tmp(@types.XMM0),
      @types.Ref::none(),
    )
    reg_usage.xmm0_returned = true
  }

  // The return value has been lowered into register manipulation, so the call
  // has no destination; arg[1] is the packed RegisterUsage (see the comment at
  // the top of winabi.c, copied from SysV).
  win_emit(
    st,
    @types.Call,
    call_instr.cls,
    @types.Ref::none(),
    call_instr.arg1,
    win_call(register_usage_to_call_arg_value(reg_usage)),
  )

  if !env.is_none() {
    // An env argument is passed in RAX.
    win_emit(
      st,
      @types.Copy,
      @types.Kl,
      @types.Ref::tmp(@types.RAX),
      env,
      @types.Ref::none(),
    )
  }

  if reg_usage.is_varargs_call {
    // Any float arguments need to be duplicated to integer registers so a
    // valist callee can dump the shadow space without a prototype.
    if reg_usage.regs_passed[1][0] {
      win_emit(
        st,
        @types.Cast,
        @types.Kl,
        @types.Ref::tmp(@types.RCX),
        @types.Ref::tmp(@types.XMM0),
        @types.Ref::none(),
      )
    }
    if reg_usage.regs_passed[1][1] {
      win_emit(
        st,
        @types.Cast,
        @types.Kl,
        @types.Ref::tmp(@types.RDX),
        @types.Ref::tmp(@types.XMM1),
        @types.Ref::none(),
      )
    }
    if reg_usage.regs_passed[1][2] {
      win_emit(
        st,
        @types.Cast,
        @types.Kl,
        @types.Ref::tmp(@types.R8),
        @types.Ref::tmp(@types.XMM2),
        @types.Ref::none(),
      )
    }
    if reg_usage.regs_passed[1][3] {
      win_emit(
        st,
        @types.Cast,
        @types.Kl,
        @types.Ref::tmp(@types.R9),
        @types.Ref::tmp(@types.XMM3),
        @types.Ref::none(),
      )
    }
  }

  let mut reg_counter : Int32 = 0
  if is_struct_return {
    let first_reg = register_for_arg(@types.Kl.code(), reg_counter)
    reg_counter = reg_counter + 1
    win_emit(
      st,
      @types.Copy,
      @types.Kl,
      first_reg,
      return_pad.unwrap().i.to,
      @types.Ref::none(),
    )
  }

  // Load the argument values into registers or stack slots.
  let arg_stack_slots = win_newtmp(st, "abi.args", @types.Kl)
  let mut slot_offset : UInt32 = SHADOW_SPACE_SIZE
  let mut a : Int32 = 0
  let mut i = earliest_arg_instr
  while i < call_idx {
    let instr = ins[i]
    let arg = arg_classes[a]
    match arg.style {
      APSRegister => {
        let into = register_for_arg(arg.cls.code(), reg_counter)
        reg_counter = reg_counter + 1
        if instr.op == @types.Argc {
          // A small struct passed by value: the instruction holds a pointer
          // that has to be loaded into the register.
          win_emit(
            st,
            @types.Load,
            arg.cls,
            into,
            instr.arg2,
            @types.Ref::none(),
          )
        } else {
          win_emit(
            st,
            @types.Copy,
            instr.cls,
            into,
            instr.arg1,
            @types.Ref::none(),
          )
        }
      }
      APSInlineOnStack => {
        let slot = win_newtmp(st, "abi.off", @types.Kl)
        if instr.op == @types.Argc {
          // Small struct: copy it into the stack slot (emitted backwards, so
          // store first, then load).
          let smalltmp = win_newtmp(st, "abi.smalltmp", arg.cls)
          win_emit(
            st,
            @types.Storel,
            @types.Kw,
            @types.Ref::none(),
            smalltmp,
            slot,
          )
          win_emit(
            st,
            @types.Load,
            arg.cls,
            smalltmp,
            instr.arg2,
            @types.Ref::none(),
          )
        } else {
          win_emit(
            st,
            @types.Storel,
            @types.Kw,
            @types.Ref::none(),
            instr.arg1,
            slot,
          )
        }
        win_emit(
          st,
          @types.Add,
          @types.Kl,
          slot,
          arg_stack_slots,
          win_getcon(st, slot_offset.to_int64()),
        )
        slot_offset = slot_offset + arg.size
      }
      APSCopyAndPointerInRegister | APSCopyAndPointerOnStack => {
        // Alloca a space to copy into, then blit the value from the argument
        // to that copy.
        let copy_ref = win_newtmp(st, "abi.copy", @types.Kl)
        let arg_copy = ExtraAlloc::{
          i: @types.Ins::new(
            @types.Alloc8,
            @types.Kl,
            copy_ref,
            win_getcon(st, arg.size.to_int64()),
            @types.Ref::none(),
          ),
          link: st.extra,
        }
        st.extra = Some(arg_copy)
        win_emit(
          st,
          @types.Blit1,
          @types.Kw,
          @types.Ref::none(),
          int_ref(arg.size.reinterpret_as_int()),
          @types.Ref::none(),
        )
        win_emit(
          st,
          @types.Blit0,
          @types.Kw,
          @types.Ref::none(),
          instr.arg2,
          copy_ref,
        )
        // Load the pointer into the correct register or stack slot.
        if arg.style == APSCopyAndPointerInRegister {
          let into = register_for_arg(arg.cls.code(), reg_counter)
          reg_counter = reg_counter + 1
          win_emit(
            st,
            @types.Copy,
            @types.Kl,
            into,
            copy_ref,
            @types.Ref::none(),
          )
        } else {
          let slot = win_newtmp(st, "abi.off", @types.Kl)
          win_emit(
            st,
            @types.Storel,
            @types.Kw,
            @types.Ref::none(),
            copy_ref,
            slot,
          )
          win_emit(
            st,
            @types.Add,
            @types.Kl,
            slot,
            arg_stack_slots,
            win_getcon(st, slot_offset.to_int64()),
          )
          slot_offset = slot_offset + 8U
        }
      }
      APSEnvTag | APSVarargsTag => ()
      APSInvalid => abort("unreachable")
    }
    i = i + 1
    a = a + 1
  }

  if stack_usage != 0 {
    // Allocate the stack space we are going to fill with temporaries.
    win_emit(
      st,
      @types.Salloc,
      @types.Kl,
      arg_stack_slots,
      win_getcon(st, (stack_usage + SHADOW_SPACE_SIZE).to_int64()),
      @types.Ref::none(),
    )
  } else {
    // With no temporaries this can be folded into the other alloca but must
    // not be stored into a ref or it would be removed later as useless.
    win_emit(
      st,
      @types.Salloc,
      @types.Kl,
      @types.Ref::none(),
      win_getcon(st, SHADOW_SPACE_SIZE.to_int64()),
      @types.Ref::none(),
    )
  }
  instr_past_args
}

///|
// C jmp_type - Jretw in terms of the C enum J order (Jxxx, retw, retl, rets,
// retd, retsb, retub, retsh, retuh, retc, ret0, ...). The port's JumpKind order
// is different, so the offset is mapped explicitly.
fn jret_delta(j : @types.JumpKind) -> Int32 {
  match j {
    @types.Jretw => 0
    @types.Jretl => 1
    @types.Jrets => 2
    @types.Jretd => 3
    @types.Jretsb => 4
    @types.Jretub => 5
    @types.Jretsh => 6
    @types.Jretuh => 7
    @types.Jretc => 8
    @types.Jret0 => 9
    _ => 10
  }
}

///|
// C lower_block_return: lower the block's return jump into register moves and
// set the block to a void return carrying the packed return-register usage.
fn lower_block_return(st : WinAbi, block : @types.Blk) -> Unit {
  let jmp_type = block.jmp.kind
  if !jmp_type.is_ret() || jmp_type == @types.Jret0 {
    return
  }
  // Save the argument, then make the block a void return.
  let ret_arg = block.jmp.arg
  block.jmp.kind = @types.Jret0
  let reg_usage = RegisterUsage::new()
  if jmp_type == @types.Jretc {
    let type_ = st.typs[st.fn_.ret_ty]
    if type_is_by_copy(type_) {
      if !st.fn_.retr.is_tmp() {
        abort("winabi: aggregate return pointer is not a temporary")
      }
      win_emit(
        st,
        @types.Copy,
        @types.Kl,
        @types.Ref::tmp(@types.RAX),
        st.fn_.retr,
        @types.Ref::none(),
      )
      win_emit(
        st,
        @types.Blit1,
        @types.Kw,
        @types.Ref::none(),
        int_ref(type_.size.to_int()),
        @types.Ref::none(),
      )
      win_emit(
        st,
        @types.Blit0,
        @types.Kw,
        @types.Ref::none(),
        ret_arg,
        st.fn_.retr,
      )
    } else {
      win_emit(
        st,
        @types.Load,
        @types.Kl,
        @types.Ref::tmp(@types.RAX),
        ret_arg,
        @types.Ref::none(),
      )
    }
    reg_usage.rax_returned = true
  } else {
    let k = jret_delta(jmp_type)
    if is_integer_type(k) {
      win_emit(
        st,
        @types.Copy,
        @types.Class::from_code(k),
        @types.Ref::tmp(@types.RAX),
        ret_arg,
        @types.Ref::none(),
      )
      reg_usage.rax_returned = true
    } else {
      win_emit(
        st,
        @types.Copy,
        @types.Class::from_code(k),
        @types.Ref::tmp(@types.XMM0),
        ret_arg,
        @types.Ref::none(),
      )
      reg_usage.xmm0_returned = true
    }
  }
  block.jmp.arg = win_call(register_usage_to_call_arg_value(reg_usage))
}

///|
// C lower_vastart. In a varargs function the integer registers are dumped to
// the shadow space and the float ones duplicated into them, so the va_list is
// just rbp indexed past the named arguments.
fn lower_vastart(
  st : WinAbi,
  param_reg_usage : RegisterUsage,
  valist : @types.Ref,
) -> Unit {
  if !st.fn_.is_vararg {
    abort("winabi: vastart in a non-variadic function")
  }
  let offset = win_newtmp(st, "abi.vastart", @types.Kl)
  win_emit(st, @types.Storel, @types.Kw, @types.Ref::none(), offset, valist)
  // *8 for sizeof(u64), +16 for the return address and rbp pushed by the
  // callee prologue.
  win_emit(
    st,
    @types.Add,
    @types.Kl,
    offset,
    @types.Ref::tmp(@types.RBP),
    win_getcon(st, (param_reg_usage.num_named_args_passed * 8 + 16).to_int64()),
  )
}

///|
// C lower_vaarg: a va_list is a void** on winx64, so load the pointer, load
// the argument from it, then bump the pointer (all emitted backwards).
fn lower_vaarg(st : WinAbi, vaarg_instr : @types.Ins) -> Unit {
  let inc = win_newtmp(st, "abi.vaarg.inc", @types.Kl)
  let ptr = win_newtmp(st, "abi.vaarg.ptr", @types.Kl)
  win_emit(
    st,
    @types.Storel,
    @types.Kw,
    @types.Ref::none(),
    inc,
    vaarg_instr.arg1,
  )
  win_emit(st, @types.Add, @types.Kl, inc, ptr, win_getcon(st, 8L))
  win_emit(
    st,
    @types.Load,
    vaarg_instr.cls,
    vaarg_instr.to,
    ptr,
    @types.Ref::none(),
  )
  win_emit(
    st,
    @types.Load,
    @types.Kl,
    ptr,
    vaarg_instr.arg1,
    @types.Ref::none(),
  )
}

///|
// C lower_args_for_block: walk one block backwards, rewriting calls, returns
// and vararg instructions; everything else is copied unchanged.
fn lower_args_for_block(
  st : WinAbi,
  bid : Int32,
  param_reg_usage : RegisterUsage,
) -> Unit raise {
  let block = st.fn_.blks[bid]
  st.buf.clear()
  lower_block_return(st, block)
  let nins = block.ins.length()
  if nins > 0 {
    let mut idx = nins - 1
    while idx >= 0 {
      let instr = block.ins[idx]
      match instr.op {
        @types.Call => idx = lower_call(st, block, idx)
        @types.Vastart => {
          lower_vastart(st, param_reg_usage, instr.arg1)
          idx = idx - 1
        }
        @types.Vaarg => {
          lower_vaarg(st, instr)
          idx = idx - 1
        }
        @types.Arg | @types.Argc => abort("unreachable")
        _ => {
          win_emiti(st, instr)
          idx = idx - 1
        }
      }
    }
  }
  // The start block also gets the allocas other blocks needed.
  if bid == st.fn_.start_id {
    let mut ea = st.extra
    while ea is Some(e) {
      win_emiti(st, e.i)
      ea = e.link
    }
  }
  let nb = win_flush(st)
  st.buf.clear()
  block.ins.clear()
  for x in nb {
    block.ins.push(x)
  }
}

///|
// C find_end_of_func_parameters: index of the first non-parameter
// instruction in the start block.
fn find_end_of_func_parameters(block : @types.Blk) -> Int32 {
  let mut i = 0
  while i < block.ins.length() {
    if !block.ins[i].op.is_par() {
      break
    }
    i = i + 1
  }
  i
}

///|
// C lower_func_parameters: copy the incoming registers/stack slots into the
// named parameters and rebuild the start block.
fn lower_func_parameters(st : WinAbi) -> RegisterUsage raise {
  let start_block = st.fn_.blks[st.fn_.start_id]
  let start_of_params = 0
  let end_of_params = find_end_of_func_parameters(start_block)
  let num_params = end_of_params - start_of_params
  let arg_classes : Array[ArgClass] = []
  for _ in 0..<num_params {
    arg_classes.push(ArgClass::new())
  }
  let arg_ret = ArgClass::new()
  st.buf.clear()
  let mut reg_counter : Int32 = 0
  let reg_usage = RegisterUsage::new()
  if st.fn_.ret_ty >= 0 {
    let by_copy = type_is_by_copy(st.typs[st.fn_.ret_ty])
    if by_copy {
      assign_register_or_stack(reg_usage, arg_ret, false, true)
      let ret_ref = win_newtmp(st, "abi.ret", @types.Kl)
      win_emit(
        st,
        @types.Copy,
        @types.Kl,
        ret_ref,
        @types.Ref::tmp(@types.RCX),
        @types.Ref::none(),
      )
      st.fn_.retr = ret_ref
      reg_counter = reg_counter + 1
    }
  }
  let env = classify_arguments(
    st,
    reg_usage,
    start_block.ins,
    start_of_params,
    end_of_params,
    arg_classes,
  )
  let (argmask, _, _) = @types.win_argregs(
    win_call(register_usage_to_call_arg_value(reg_usage)),
  )
  st.fn_.reg = argmask

  // Copy from the registers or stack slots into the named parameters.
  let mut slot_offset : UInt32 = SHADOW_SPACE_SIZE / 4U + 4U
  let mut a : Int32 = 0
  let mut i = start_of_params
  while i < end_of_params {
    let instr = start_block.ins[i]
    let arg = arg_classes[a]
    match arg.style {
      APSRegister => {
        let from = register_for_arg(arg.cls.code(), reg_counter)
        reg_counter = reg_counter + 1
        // A struct at the IL level needs a copy in an alloca so there is
        // something to point at (same for InlineOnStack).
        if instr.op == @types.Parc {
          arg.arg_ref = win_newtmp(st, "abi", @types.Kl)
          win_emit(
            st,
            @types.Storel,
            @types.Kw,
            @types.Ref::none(),
            arg.arg_ref,
            instr.to,
          )
          win_emit(
            st,
            @types.Copy,
            instr.cls,
            arg.arg_ref,
            from,
            @types.Ref::none(),
          )
          win_emit(
            st,
            @types.Alloc8,
            @types.Kl,
            instr.to,
            win_getcon(st, arg.size.to_int64()),
            @types.Ref::none(),
          )
        } else {
          win_emit(
            st,
            @types.Copy,
            instr.cls,
            instr.to,
            from,
            @types.Ref::none(),
          )
        }
      }
      APSInlineOnStack => {
        if instr.op == @types.Parc {
          arg.arg_ref = win_newtmp(st, "abi", @types.Kl)
          win_emit(
            st,
            @types.Storel,
            @types.Kw,
            @types.Ref::none(),
            arg.arg_ref,
            instr.to,
          )
          win_emit(
            st,
            @types.Copy,
            instr.cls,
            arg.arg_ref,
            slot_ref(slot_offset),
            @types.Ref::none(),
          )
          win_emit(
            st,
            @types.Alloc8,
            @types.Kl,
            instr.to,
            win_getcon(st, arg.size.to_int64()),
            @types.Ref::none(),
          )
        } else {
          win_emit(
            st,
            @types.Copy,
            @types.Kl,
            instr.to,
            slot_ref(slot_offset),
            @types.Ref::none(),
          )
        }
        slot_offset = slot_offset + 2U
      }
      APSCopyAndPointerOnStack => {
        win_emit(
          st,
          @types.Load,
          @types.Kl,
          instr.to,
          slot_ref(slot_offset),
          @types.Ref::none(),
        )
        slot_offset = slot_offset + 2U
      }
      APSCopyAndPointerInRegister => {
        // The copy is owned, so copying the register to the target suffices.
        let from = register_for_arg(@types.Kl.code(), reg_counter)
        reg_counter = reg_counter + 1
        win_emit(st, @types.Copy, @types.Kl, instr.to, from, @types.Ref::none())
      }
      APSEnvTag => ()
      APSVarargsTag | APSInvalid => abort("unreachable")
    }
    i = i + 1
    a = a + 1
  }

  // An env parameter was passed in RAX.
  if !env.is_none() {
    win_emit(
      st,
      @types.Copy,
      @types.Kl,
      env,
      @types.Ref::tmp(@types.RAX),
      @types.Ref::none(),
    )
  }

  // Rebuild the start block: created instructions, then the original
  // instructions after the parameters.
  let created = win_flush(st)
  st.buf.clear()
  let new_ins : Array[@types.Ins] = []
  for x in created {
    new_ins.push(x)
  }
  for k in end_of_params..<start_block.ins.length() {
    new_ins.push(start_block.ins[k])
  }
  start_block.ins.clear()
  for x in new_ins {
    start_block.ins.push(x)
  }
  reg_usage
}

///|
// C amd64_winabi_abi: lower incoming parameters, then every block (the start
// block last so it can receive the allocas other blocks need).
// Returns the -dA debug text (empty when print_dbg is false).
pub fn abi_win(
  fn_ : @types.Fn,
  typs : Array[@types.Typ],
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String raise {
  let st = WinAbi::{ fn_, typs, buf: [], extra: None, }
  let param_reg_usage = lower_func_parameters(st)
  // C: for (block = func->start->link; block; block = block->link)
  let n = fn_.def_order.length()
  let mut start_pos = 0
  while start_pos < n && fn_.def_order[start_pos] != fn_.start_id {
    start_pos = start_pos + 1
  }
  let mut i = start_pos + 1
  while i < n {
    lower_args_for_block(st, fn_.def_order[i], param_reg_usage)
    i = i + 1
  }
  lower_args_for_block(st, fn_.start_id, param_reg_usage)
  if print_dbg {
    "\n> After ABI lowering:\n" +
    @parser.printfn(fn_, interner, all_typs) +
    "\n"
  } else {
    ""
  }
}
