///|
// ARM64 (AArch64) ABI lowering - AAPCS64, ELF flavor.
// Ported 1:1 from vendor/qbe/arm64/abi.c (C arm64_abi): argsclass/
// typclass/selpar/selcall/selret/selvaarg/selvastart keep the same structure
// and logic as the C functions so the two can be reviewed side by side.
//
// Deviations from the C:
// - C Oblit0/Oblit1 aggregate copies do not exist here; the reference
//   snapshot's blit() (util.c) is expanded into explicit "blt."-prefixed
//   load/store chunks.
// - C Oparsb..Oparuh narrow-parameter ops do not exist in this port.

///|
// Classification constants (C enum in arm64/abi.c).
const Arm64Cstk : Int = 1 // pass on the stack

///|
const Arm64Cptr : Int = 2 // replaced by a pointer

///|
// ARM64 ABI classification for one parameter (C struct Class).
// Aggregates use up to 4 registers (HFA of <= 4 float/double elements, or
// 8-byte blocks).
priv struct Arm64Class {
  mut class_ : Int
  mut ishfa : Bool
  mut hfa_base : @types.Class
  mut hfa_size : Int
  mut size : Int
  mut typ : @types.Typ?
  reg : Array[Int] // 4 slots
  cls : Array[@types.Class] // 4 slots
  mut ngp : Int
  mut nfp : Int
  mut nreg : Int
}

///|
fn Arm64Class::new() -> Arm64Class {
  Arm64Class::{
    class_: 0,
    ishfa: false,
    hfa_base: @types.Kx,
    hfa_size: 0,
    size: 0,
    typ: None,
    reg: [0, 0, 0, 0],
    cls: [@types.Kx, @types.Kx, @types.Kx, @types.Kx],
    ngp: 0,
    nfp: 0,
    nreg: 0,
  }
}

///|
// Stack-parameter layout produced by selpar (C struct Params).
priv struct Arm64Params {
  mut ngp : Int
  mut nfp : Int
  mut nstk : Int
}

///|
// ARM64 ABI state
priv struct Arm64AbiState {
  fn_ : @types.Fn
  typs : Array[@types.Typ]
  buf : Array[@types.Ins]
  // stack-parameter layout of the current function, filled by selpar and
  // consumed by vastart
  params : Arm64Params
}

///|
fn arm64_abi_new(fn_ : @types.Fn, typs : Array[@types.Typ]) -> Arm64AbiState {
  Arm64AbiState::{
    fn_,
    typs,
    buf: [],
    params: Arm64Params::{ ngp: 0, nfp: 0, nstk: 0, },
  }
}

///|
fn arm64_emit(
  st : Arm64AbiState,
  op : @types.Op,
  k : @types.Class,
  to : @types.Ref,
  a0 : @types.Ref,
  a1 : @types.Ref,
) -> Unit {
  st.buf.push(@types.Ins::new(op, k, to, a0, a1))
}

///|
fn arm64_emiti(st : Arm64AbiState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
fn arm64_emit_block(st : Arm64AbiState) -> Array[@types.Ins] {
  // the buffer is filled in C emit() order (reverse program order)
  let r : Array[@types.Ins] = []
  for k in (st.buf.length() - 1)>=..0 {
    r.push(st.buf[k])
  }
  r
}

///|
fn arm64_newtmp(st : Arm64AbiState, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp("abi", k))
}

///|
fn arm64_newblt(st : Arm64AbiState, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp("blt", k))
}

///|
fn arm64_getcon(st : Arm64AbiState, v : Int64) -> @types.Ref {
  @types.Ref::con(st.fn_.get_con(v))
}

///|
fn arm64_call_ref(ca : Int) -> @types.Ref {
  @types.Ref::call(ca)
}

///|
// The integer/float argument register sequences (C gpreg/fpreg). C sizes
// these arrays at 12 with the tail zero-initialized; typclass may index past
// the 8 real registers before argsclass decides to pass on the stack.
let arm64_gpreg : Array[Int] = [
  @types.ARM64_R0,
  @types.ARM64_R1,
  @types.ARM64_R2,
  @types.ARM64_R3,
  @types.ARM64_R4,
  @types.ARM64_R5,
  @types.ARM64_R6,
  @types.ARM64_R7,
  0,
  0,
  0,
  0,
]

///|
let arm64_fpreg : Array[Int] = [
  @types.ARM64_V0,
  @types.ARM64_V1,
  @types.ARM64_V2,
  @types.ARM64_V3,
  @types.ARM64_V4,
  @types.ARM64_V5,
  @types.ARM64_V6,
  @types.ARM64_V7,
  0,
  0,
  0,
  0,
]

///|
// store opcode per class (C store[] map: Kw/Ostorew, Kl/Ostorel, ...).
fn arm64_store_op(k : @types.Class) -> @types.Op {
  let store_ops = [@types.Storew, @types.Storel, @types.Stores, @types.Stored]
  let c = k.code()
  if c < 0 || c >= store_ops.length() {
    @types.Storel // Kx/Ke: pointer-sized fallback
  } else {
    store_ops[c]
  }
}

///|
// Classify an aggregate type for the AAPCS64 (C typclass in arm64/abi.c).
// gpi/fpi are the current positions in gpreg/fpreg; typclass only *reads*
// them (C receives int* by value), the caller advances them.
fn arm64_typclass(
  st : Arm64AbiState,
  c : Arm64Class,
  t : @types.Typ,
  gpi : Int,
  fpi : Int,
) -> Unit raise {
  let sz = (t.size.to_int() + 7) & -8
  c.typ = Some(t)
  c.class_ = 0
  c.ngp = 0
  c.nfp = 0
  if t.align > 4 {
    raise @util.QbeError::Ice("alignments larger than 16 are not supported")
  }
  if t.dark != 0 || sz > 16 || sz == 0 {
    // large structs are replaced by a pointer to some
    // caller-allocated memory
    c.class_ = c.class_ | Arm64Cptr
    c.size = 8
    return
  }
  c.size = sz
  let (homog, base) = arm64_isfloatv(st, t, @types.Kx)
  c.hfa_base = base
  c.ishfa = homog
  let wide = if base == @types.Kd { 8 } else { 4 }
  c.hfa_size = t.size.to_int() / wide
  if c.ishfa {
    let mut n = 0
    while n < c.hfa_size {
      c.reg[n] = arm64_fpreg[fpi + n]
      c.cls[n] = c.hfa_base
      c.nfp = c.nfp + 1
      n = n + 1
    }
    c.nreg = n
  } else {
    let mut n = 0
    while n < sz / 8 {
      c.reg[n] = arm64_gpreg[gpi + n]
      c.cls[n] = @types.Kl
      c.ngp = c.ngp + 1
      n = n + 1
    }
    c.nreg = n
  }
}

///|
// Does the type contain only homogeneous float/double fields
// (C isfloatv in arm64/abi.c). Returns (homogeneous, element class).
fn arm64_isfloatv(
  st : Arm64AbiState,
  t : @types.Typ,
  cls0 : @types.Class,
) -> (Bool, @types.Class) {
  let mut cls = cls0
  let fields = t.fields
  let mut member_start = 0
  for _ in 0..<t.nunion {
    let mut fi = member_start
    while fi < fields.length() && fields[fi].kind != @types.FEnd {
      let f = fields[fi]
      fi = fi + 1
      match f.kind {
        @types.Fs => {
          if cls == @types.Kd {
            return (false, cls)
          }
          cls = @types.Ks
        }
        @types.Fd => {
          if cls == @types.Ks {
            return (false, cls)
          }
          cls = @types.Kd
        }
        @types.FTyp => {
          let (ok, next) = arm64_isfloatv(st, st.typs[f.len], cls)
          if !ok {
            return (false, cls)
          }
          cls = next
        }
        _ => return (false, cls)
      }
    }
    while fi < fields.length() && fields[fi].kind == @types.FEnd {
      fi = fi + 1
    }
    member_start = fi
  }
  (true, cls)
}

///|
// Store register-classified aggregate pieces into memory (C sttmps).
fn arm64_sttmps(
  st : Arm64AbiState,
  tmp : Array[@types.Ref],
  base : Int,
  c : Arm64Class,
  nreg : Int,
  mem : @types.Ref,
) -> Unit {
  let mut off = 0
  for n in 0..<nreg {
    tmp[base + n] = arm64_newtmp(st, c.cls[n])
    let r = arm64_newtmp(st, @types.Kl)
    arm64_emit(
      st,
      arm64_store_op(c.cls[n]),
      @types.Kw,
      @types.Ref::none(),
      tmp[base + n],
      r,
    )
    arm64_emit(
      st,
      @types.Add,
      @types.Kl,
      r,
      mem,
      arm64_getcon(st, off.to_int64()),
    )
    off = off + (if c.cls[n].wide() == 1 { 8 } else { 4 })
  }
}

///|
// Load aggregate pieces from memory into registers (C ldregs).
fn arm64_ldregs(
  st : Arm64AbiState,
  c : Arm64Class,
  n : Int,
  mem : @types.Ref,
) -> Unit {
  let mut off = 0
  for i in 0..<n {
    let r = arm64_newtmp(st, @types.Kl)
    arm64_emit(
      st,
      @types.Load,
      c.cls[i],
      @types.Ref::tmp(c.reg[i]),
      r,
      @types.Ref::none(),
    )
    arm64_emit(
      st,
      @types.Add,
      @types.Kl,
      r,
      mem,
      arm64_getcon(st, off.to_int64()),
    )
    off = off + (if c.cls[i].wide() == 1 { 8 } else { 4 })
  }
}

///|
// Select return value handling (C selret in arm64/abi.c).
fn arm64_selret(st : Arm64AbiState, bid : Int) -> Unit raise {
  let b = st.fn_.blks[bid]
  let j = b.jmp.kind
  if !j.is_ret() || j == @types.Jret0 {
    return
  }
  let r = b.jmp.arg
  b.jmp.kind = @types.Jret0
  let mut cty = 0
  if j == @types.Jretc {
    let cr = Arm64Class::new()
    arm64_typclass(st, cr, st.typs[st.fn_.ret_ty], 0, 0)
    cty = (cr.nfp << 2) | cr.ngp
    if (cr.class_ & Arm64Cptr) != 0 {
      let size = cr.typ.unwrap().size.to_int()
      arm64_emit(
        st,
        @types.Blit1,
        @types.Kw,
        @types.Ref::none(),
        @types.Ref::rint(size),
        @types.Ref::none(),
      )
      arm64_emit(st, @types.Blit0, @types.Kw, @types.Ref::none(), r, st.fn_.retr)
    } else {
      arm64_ldregs(st, cr, cr.nreg, r)
    }
  } else {
    let k = match j {
      @types.Jretw => @types.Kw
      @types.Jretl => @types.Kl
      @types.Jrets => @types.Ks
      @types.Jretd => @types.Kd
      _ => @types.Kw
    }
    if k.base() == 0 {
      arm64_emit(
        st,
        @types.Copy,
        k,
        @types.Ref::tmp(@types.ARM64_R0),
        r,
        @types.Ref::none(),
      )
      cty = 1
    } else {
      arm64_emit(
        st,
        @types.Copy,
        k,
        @types.Ref::tmp(@types.ARM64_V0),
        r,
        @types.Ref::none(),
      )
      cty = 1 << 2
    }
  }
  b.jmp.arg = arm64_call_ref(cty)
}

///|
// Classify call arguments (C argsclass in arm64/abi.c).
// Returns the RCall encoding gpi<<5 | fpi<<9 and the env ref (R when none).
fn arm64_argsclass(
  st : Arm64AbiState,
  orig : Array[@types.Ins],
  i0 : Int,
  i1 : Int,
  carg : Array[Arm64Class],
) -> (Int, @types.Ref) raise {
  let mut gpi = 0
  let mut fpi = 0
  let mut ngp = 8
  let mut nfp = 8
  let mut env = @types.Ref::none()
  let mut a = 0
  for idx in i0..<i1 {
    let ins = orig[idx]
    let c = carg[a]
    match ins.op {
      @types.Par | @types.Arg => {
        c.cls[0] = ins.cls
        c.size = 8
        if ins.cls.base() == 0 && ngp > 0 {
          ngp = ngp - 1
          c.reg[0] = arm64_gpreg[gpi]
          gpi = gpi + 1
        } else if ins.cls.base() == 1 && nfp > 0 {
          nfp = nfp - 1
          c.reg[0] = arm64_fpreg[fpi]
          fpi = fpi + 1
        } else {
          c.class_ = c.class_ | Arm64Cstk
        }
      }
      @types.Parc | @types.Argc => {
        arm64_typclass(st, c, st.typs[ins.arg1.typ_val()], gpi, fpi)
        let mut stacked = true
        if (c.class_ & Arm64Cptr) != 0 {
          if ngp > 0 {
            ngp = ngp - 1
            c.reg[0] = arm64_gpreg[gpi]
            gpi = gpi + 1
            c.cls[0] = @types.Kl
            stacked = false
          }
        } else if c.ngp <= ngp {
          if c.nfp <= nfp {
            ngp = ngp - c.ngp
            nfp = nfp - c.nfp
            gpi = gpi + c.ngp
            fpi = fpi + c.nfp
            stacked = false
          } else {
            nfp = 0
          }
        } else {
          ngp = 0
        }
        if stacked {
          c.class_ = c.class_ | Arm64Cstk
        }
      }
      @types.Pare => env = ins.to
      @types.Arge => env = ins.arg1
      @types.Argv => ()
      _ => abort("unreachable")
    }
    a = a + 1
  }
  ((gpi << 5) | (fpi << 9), env)
}

///|
// Allocate a stack blob for an aggregate (C stkblob in arm64/abi.c).
fn arm64_stkblob(st : Arm64AbiState, r : @types.Ref, c : Arm64Class) -> Unit {
  let mut al = c.typ.unwrap().align - 2 // NAlign == 3
  if al < 0 {
    al = 0
  }
  // C stkblob: pointer types use the type size, others the rounded class size.
  let sz = if (c.class_ & Arm64Cptr) != 0 {
    c.typ.unwrap().size
  } else {
    c.size.to_int64()
  }
  let op = @types.Op::from_index(@types.Alloc4.index() + al)
  arm64_emit(st, op, @types.Kl, r, arm64_getcon(st, sz), @types.Ref::none())
}

///|
// Select call handling (C selcall in arm64/abi.c).
// Blob allocations for Cptr arguments are appended to `il`; the caller emits
// them at the top of the start block (C carries them in an Insl list).
fn arm64_selcall(
  st : Arm64AbiState,
  orig : Array[@types.Ins],
  i0 : Int,
  i1 : Int,
  il : Array[@types.Ins],
) -> Unit raise {
  let nargs = i1 - i0
  let ca : Array[Arm64Class] = []
  for _ in 0..<nargs {
    ca.push(Arm64Class::new())
  }
  let callins = orig[i1]
  let (cty0, env) = arm64_argsclass(st, orig, i0, i1, ca)
  let mut cty = cty0
  let has_retty = !callins.arg2.is_none()
  // rewrite pass (C 379-393): blobs for Cptr args, stack size accounting
  let mut stk = 0
  for a in 0..<nargs {
    let i = orig[i0 + a]
    let c = ca[a]
    if (c.class_ & Arm64Cptr) != 0 {
      i.arg1 = arm64_newtmp(st, @types.Kl)
      arm64_stkblob(st, i.arg1, c)
      let blob = st.buf[st.buf.length() - 1]
      ignore(st.buf.remove(st.buf.length() - 1))
      il.push(blob)
      i.op = @types.Arg
    }
    if (c.class_ & Arm64Cstk) != 0 {
      stk = stk + c.size
    }
  }
  stk = stk + (stk & 15)
  let rstk = arm64_getcon(st, stk.to_int64())
  if stk != 0 {
    arm64_emit(
      st,
      @types.Add,
      @types.Kl,
      @types.Ref::tmp(@types.ARM64_SP),
      @types.Ref::tmp(@types.ARM64_SP),
      rstk,
    )
  }
  // return value (C 395-421)
  let cr = Arm64Class::new()
  if has_retty {
    arm64_typclass(st, cr, st.typs[callins.arg2.typ_val()], 0, 0)
    arm64_stkblob(st, callins.to, cr)
    let blob = st.buf[st.buf.length() - 1]
    ignore(st.buf.remove(st.buf.length() - 1))
    il.push(blob)
    cty = cty | ((cr.nfp << 2) | cr.ngp)
    if (cr.class_ & Arm64Cptr) != 0 {
      // spill & rega expect calls to be followed by copies from regs,
      // so we emit a dummy
      cty = cty | (1 << 13)
      arm64_emit(
        st,
        @types.Copy,
        @types.Kw,
        @types.Ref::none(),
        @types.Ref::tmp(@types.ARM64_R0),
        @types.Ref::none(),
      )
    } else {
      let tmp : Array[@types.Ref] = Array::make(4, @types.Ref::none())
      arm64_sttmps(st, tmp, 0, cr, cr.nreg, callins.to)
      for n in 0..<cr.nreg {
        let r = @types.Ref::tmp(cr.reg[n])
        arm64_emit(st, @types.Copy, cr.cls[n], tmp[n], r, @types.Ref::none())
      }
    }
  } else if callins.cls.base() == 0 {
    arm64_emit(
      st,
      @types.Copy,
      callins.cls,
      callins.to,
      @types.Ref::tmp(@types.ARM64_R0),
      @types.Ref::none(),
    )
    cty = cty | 1
  } else {
    arm64_emit(
      st,
      @types.Copy,
      callins.cls,
      callins.to,
      @types.Ref::tmp(@types.ARM64_V0),
      @types.Ref::none(),
    )
    cty = cty | (1 << 2)
  }
  if !env.is_none() {
    raise @util.QbeError::Ice("todo (arm abi): env calls")
  }
  arm64_emit(
    st,
    @types.Call,
    @types.Kw,
    @types.Ref::none(),
    callins.arg1,
    arm64_call_ref(cty),
  )
  if (cty & (1 << 13)) != 0 {
    // struct return argument
    arm64_emit(
      st,
      @types.Copy,
      @types.Kl,
      @types.Ref::tmp(@types.ARM64_R8),
      callins.to,
      @types.Ref::none(),
    )
  }
  // move arguments into registers (C 429-436)
  for a in 0..<nargs {
    let i = orig[i0 + a]
    let c = ca[a]
    if (c.class_ & Arm64Cstk) != 0 {
      continue
    }
    if i.op == @types.Arg || i.op == @types.Arge {
      arm64_emit(
        st,
        @types.Copy,
        c.cls[0],
        @types.Ref::tmp(c.reg[0]),
        i.arg1,
        @types.Ref::none(),
      )
    }
    if i.op == @types.Argc {
      arm64_ldregs(st, c, c.nreg, i.arg2)
    }
  }
  // populate the stack (C 438-463)
  let mut off = 0
  for a in 0..<nargs {
    let i = orig[i0 + a]
    let c = ca[a]
    if (c.class_ & Arm64Cstk) == 0 {
      continue
    }
    if i.op != @types.Argc {
      let r = arm64_newtmp(st, @types.Kl)
      // C arm64/abi.c: storeb/storeh for sizes 1/2, else store[class].
      let k0 = c.cls[0]
      let op = if c.size == 1 {
        @types.Storeb
      } else if c.size == 2 {
        @types.Storeh
      } else {
        arm64_store_op(k0)
      }
      arm64_emit(st, op, @types.Kw, @types.Ref::none(), i.arg1, r)
      arm64_emit(
        st,
        @types.Add,
        @types.Kl,
        r,
        @types.Ref::tmp(@types.ARM64_SP),
        arm64_getcon(st, off.to_int64()),
      )
    } else {
      let r = arm64_newtmp(st, @types.Kl)
      arm64_emit(
        st,
        @types.Blit1,
        @types.Kw,
        @types.Ref::none(),
        @types.Ref::rint(c.size),
        @types.Ref::none(),
      )
      arm64_emit(st, @types.Blit0, @types.Kw, @types.Ref::none(), i.arg2, r)
      arm64_emit(
        st,
        @types.Add,
        @types.Kl,
        r,
        @types.Ref::tmp(@types.ARM64_SP),
        arm64_getcon(st, off.to_int64()),
      )
    }
    off = off + c.size
  }
  if stk != 0 {
    arm64_emit(
      st,
      @types.Sub,
      @types.Kl,
      @types.Ref::tmp(@types.ARM64_SP),
      @types.Ref::tmp(@types.ARM64_SP),
      rstk,
    )
  }
  // fill the Cptr blobs with the original aggregates (C 465-469)
  for a in 0..<nargs {
    let i = orig[i0 + a]
    let c = ca[a]
    if (c.class_ & Arm64Cptr) != 0 {
      let size = c.typ.unwrap().size.to_int()
      arm64_emit(
        st,
        @types.Blit1,
        @types.Kw,
        @types.Ref::none(),
        @types.Ref::rint(size),
        @types.Ref::none(),
      )
      arm64_emit(st, @types.Blit0, @types.Kw, @types.Ref::none(), i.arg2, i.arg1)
    }
  }
}

///|
// Select parameter handling (C selpar in arm64/abi.c).
fn arm64_selpar(st : Arm64AbiState, par_end : Int) -> Unit raise {
  let ins = st.fn_.blks[st.fn_.start_id].ins
  let npar = par_end
  let ca : Array[Arm64Class] = []
  for _ in 0..<npar {
    ca.push(Arm64Class::new())
  }
  st.buf.clear()
  let (cty, env) = arm64_argsclass(st, ins, 0, npar, ca)
  let tmp : Array[@types.Ref] = Array::make(16, @types.Ref::none())
  let mut t = 0
  let il : Array[@types.Ins] = []
  // register-classified aggregates get stores into a stack blob (C 489-498)
  for a in 0..<npar {
    let i = ins[a]
    let c = ca[a]
    if i.op != @types.Parc || (c.class_ & (Arm64Cptr | Arm64Cstk)) != 0 {
      continue
    }
    arm64_sttmps(st, tmp, t, c, c.nreg, i.to)
    t = t + c.nreg
    arm64_stkblob(st, i.to, c)
    let blob = st.buf[st.buf.length() - 1]
    ignore(st.buf.remove(st.buf.length() - 1))
    il.push(blob)
  }
  for k in (il.length() - 1)>=..0 {
    arm64_emiti(st, il[k])
  }
  if st.fn_.ret_ty >= 0 {
    let cr = Arm64Class::new()
    arm64_typclass(st, cr, st.typs[st.fn_.ret_ty], 0, 0)
    if (cr.class_ & Arm64Cptr) != 0 {
      st.fn_.retr = arm64_newtmp(st, @types.Kl)
      arm64_emit(
        st,
        @types.Copy,
        @types.Kl,
        st.fn_.retr,
        @types.Ref::tmp(@types.ARM64_R8),
        @types.Ref::none(),
      )
    }
  }
  // materialize parameters (C 509-532).  off is a byte offset; the slot of a
  // stack parameter is SLOT(-(off+2)) (C selpar).
  t = 0
  let mut off = 0
  for a in 0..<npar {
    let i = ins[a]
    let c = ca[a]
    if i.op == @types.Parc && (c.class_ & Arm64Cptr) == 0 {
      if (c.class_ & Arm64Cstk) != 0 {
        st.fn_.tmps[i.to.tmp_val()].slot = -(off + 2)
        off = off + c.size
      } else {
        for n in 0..<c.nreg {
          arm64_emit(
            st,
            @types.Copy,
            c.cls[n],
            tmp[t],
            @types.Ref::tmp(c.reg[n]),
            @types.Ref::none(),
          )
          t = t + 1
        }
      }
    } else if (c.class_ & Arm64Cstk) != 0 {
      arm64_emit(
        st,
        @types.Load,
        c.cls[0],
        i.to,
        @types.Ref::slot(-(off + 2)),
        @types.Ref::none(),
      )
      off = off + c.size
    } else {
      arm64_emit(
        st,
        @types.Copy,
        c.cls[0],
        i.to,
        @types.Ref::tmp(c.reg[0]),
        @types.Ref::none(),
      )
    }
  }
  if !env.is_none() {
    raise @util.QbeError::Ice("todo (arm abi): env calls")
  }
  st.params.ngp = (cty >> 5) & 15
  st.params.nfp = (cty >> 9) & 15
  // C Params.stk = align(off, 8); this port stores the byte value.
  st.params.nstk = (off + 7) & -8
}

///|
// Split the block being lowered right after its current buffer contents
// (C split in arm64/abi.c). Returns the new block id.
fn arm64_split(st : Arm64AbiState, bid : Int) -> Int {
  let b = st.fn_.blks[bid]
  b.visit = b.visit + 1
  let nb = st.fn_.add_blk("\{b.name}.\{b.visit}")
  let nb_blk = st.fn_.blks[nb]
  // the buffered instructions belong to the new block (program order)
  let prog = arm64_emit_block(st)
  st.buf.clear()
  for x in prog {
    nb_blk.ins.push(x)
  }
  nb_blk.visit = b.visit
  nb_blk.loop_depth = b.loop_depth
  // link: insert after b in def_order
  let mut pos = 0
  for k in 0..<st.fn_.def_order.length() {
    if st.fn_.def_order[k] == bid {
      pos = k
      break
    }
  }
  st.fn_.def_order.insert(pos + 1, nb)
  nb
}

///|
// Redirect phis of block bid from predecessor bp to bp1 (C chpred).
fn arm64_chpred(st : Arm64AbiState, bid : Int, bp : Int, bp1 : Int) -> Unit {
  let b = st.fn_.blks[bid]
  for p in b.phi {
    for a in p.args {
      if a.blk_id == bp {
        a.blk_id = bp1
      }
    }
  }
}

///|
// Select va_arg lowering (C arm64_selvaarg in arm64/abi.c).
//
// @b    [...]
//       r0 =l add ap, (24 or 28)
//       nr =l loadsw r0
//       r1 =w csltw nr, 0
//       jnz r1, @breg, @bstk
// @breg
//       r0 =l add ap, (8 or 16)
//       r1 =l loadl r0
//       lreg =l add r1, nr
//       r0 =w add nr, (8 or 16)
//       r1 =l add ap, (24 or 28)
//       storew r0, r1
// @bstk
//       lstk =l loadl ap
//       r0 =l add lstk, 8
//       storel r0, ap
// @b0
//       %loc =l phi @bstk %lstk, @breg %lreg
//       i.to = load %loc
fn arm64_selvaarg(st : Arm64AbiState, bid : Int, i : @types.Ins) -> Unit {
  let c8 = arm64_getcon(st, 8L)
  let c16 = arm64_getcon(st, 16L)
  let c24 = arm64_getcon(st, 24L)
  let c28 = arm64_getcon(st, 28L)
  let ap = i.arg1
  let isgp = i.cls.base() == 0
  let loc = arm64_newtmp(st, @types.Kl)
  arm64_emit(st, @types.Load, i.cls, i.to, loc, @types.Ref::none())
  let b0 = arm64_split(st, bid)
  let s1 = st.fn_.blks[bid].jmp.s1
  let s2 = st.fn_.blks[bid].jmp.s2
  let b0b = st.fn_.blks[b0]
  b0b.jmp = @types.Jump::full(
    st.fn_.blks[bid].jmp.kind,
    st.fn_.blks[bid].jmp.arg,
    s1,
    s2,
  )
  if s1 >= 0 {
    arm64_chpred(st, s1, bid, b0)
  }
  if s2 >= 0 && s2 != s1 {
    arm64_chpred(st, s2, bid, b0)
  }
  let lreg = arm64_newtmp(st, @types.Kl)
  let nr = arm64_newtmp(st, @types.Kl)
  let r0 = arm64_newtmp(st, @types.Kw)
  let r1 = arm64_newtmp(st, @types.Kl)
  arm64_emit(st, @types.Storew, @types.Kw, @types.Ref::none(), r0, r1)
  arm64_emit(st, @types.Add, @types.Kl, r1, ap, if isgp { c24 } else { c28 })
  arm64_emit(st, @types.Add, @types.Kw, r0, nr, if isgp { c8 } else { c16 })
  let r0b = arm64_newtmp(st, @types.Kl)
  let r1b = arm64_newtmp(st, @types.Kl)
  arm64_emit(st, @types.Add, @types.Kl, lreg, r1b, nr)
  arm64_emit(st, @types.Load, @types.Kl, r1b, r0b, @types.Ref::none())
  arm64_emit(st, @types.Add, @types.Kl, r0b, ap, if isgp { c8 } else { c16 })
  let breg = arm64_split(st, bid)
  st.fn_.blks[breg].jmp = @types.Jump::new(@types.Jjmp)
  st.fn_.blks[breg].jmp.s1 = b0
  let lstk = arm64_newtmp(st, @types.Kl)
  let r0c = arm64_newtmp(st, @types.Kl)
  arm64_emit(st, @types.Storel, @types.Kw, @types.Ref::none(), r0c, ap)
  arm64_emit(st, @types.Add, @types.Kl, r0c, lstk, c8)
  arm64_emit(st, @types.Load, @types.Kl, lstk, ap, @types.Ref::none())
  let bstk = arm64_split(st, bid)
  st.fn_.blks[bstk].jmp = @types.Jump::new(@types.Jjmp)
  st.fn_.blks[bstk].jmp.s1 = b0
  // b0 gets a phi: %loc =l phi @bstk %lstk, @breg %lreg
  let phi = @types.Phi::new(loc, @types.Kl)
  phi.args.push(@types.PhiArg::{ value: lstk, blk_id: bstk, })
  phi.args.push(@types.PhiArg::{ value: lreg, blk_id: breg, })
  st.fn_.blks[b0].phi.insert(0, phi)
  let r0d = arm64_newtmp(st, @types.Kl)
  let r1c = arm64_newtmp(st, @types.Kw)
  let b = st.fn_.blks[bid]
  b.jmp = @types.Jump::new(@types.Jjnz)
  b.jmp.arg = r1c
  b.jmp.s1 = breg
  b.jmp.s2 = bstk
  arm64_emit(st, @types.Csltw, @types.Kw, r1c, nr, arm64_getcon(st, 0L))
  arm64_emit(st, @types.Loadsw, @types.Kl, nr, r0d, @types.Ref::none())
  arm64_emit(st, @types.Add, @types.Kl, r0d, ap, if isgp { c24 } else { c28 })
}

///|
// Select va_start lowering (C arm64_selvastart in arm64/abi.c).
fn arm64_selvastart(st : Arm64AbiState, ap : @types.Ref) -> Unit {
  let p = st.params
  let rsave = arm64_newtmp(st, @types.Kl)
  let r0 = arm64_newtmp(st, @types.Kl)
  arm64_emit(st, @types.Storel, @types.Kw, @types.Ref::none(), r0, ap)
  arm64_emit(
    st,
    @types.Add,
    @types.Kl,
    r0,
    rsave,
    arm64_getcon(st, (p.nstk + 192).to_int64()),
  )
  let r0b = arm64_newtmp(st, @types.Kl)
  let r1b = arm64_newtmp(st, @types.Kl)
  arm64_emit(st, @types.Storel, @types.Kw, @types.Ref::none(), r1b, r0b)
  arm64_emit(st, @types.Add, @types.Kl, r1b, rsave, arm64_getcon(st, 64L))
  arm64_emit(st, @types.Add, @types.Kl, r0b, ap, arm64_getcon(st, 8L))
  let r0c = arm64_newtmp(st, @types.Kl)
  let r1c = arm64_newtmp(st, @types.Kl)
  arm64_emit(st, @types.Storel, @types.Kw, @types.Ref::none(), r1c, r0c)
  arm64_emit(st, @types.Add, @types.Kl, r1c, rsave, arm64_getcon(st, 192L))
  arm64_emit(
    st,
    @types.Addr,
    @types.Kl,
    rsave,
    @types.Ref::slot(-1),
    @types.Ref::none(),
  )
  arm64_emit(st, @types.Add, @types.Kl, r0c, ap, arm64_getcon(st, 16L))
  let r0d = arm64_newtmp(st, @types.Kl)
  arm64_emit(
    st,
    @types.Storew,
    @types.Kw,
    @types.Ref::none(),
    arm64_getcon(
      st,
      (((p.ngp - 8).to_int64() & 0xFFFFFFFFL) * 8L) & 0xFFFFFFFFL,
    ),
    r0d,
  )
  arm64_emit(st, @types.Add, @types.Kl, r0d, ap, arm64_getcon(st, 24L))
  let r0e = arm64_newtmp(st, @types.Kl)
  arm64_emit(
    st,
    @types.Storew,
    @types.Kw,
    @types.Ref::none(),
    arm64_getcon(
      st,
      (((p.nfp - 8).to_int64() & 0xFFFFFFFFL) * 16L) & 0xFFFFFFFFL,
    ),
    r0e,
  )
  arm64_emit(st, @types.Add, @types.Kl, r0e, ap, arm64_getcon(st, 28L))
}

///|
// Main ARM64 ABI lowering entry point (C arm64_abi).
pub fn abi_arm64(
  fn_ : @types.Fn,
  typs : Array[@types.Typ],
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String raise {
  let st = arm64_abi_new(fn_, typs)
  for id in fn_.def_order {
    fn_.blks[id].visit = 0
  }
  // lower parameters
  let start = fn_.blks[fn_.start_id]
  let mut par_end = 0
  while par_end < start.ins.length() {
    let op = start.ins[par_end].op
    if !op.is_par() {
      break
    }
    par_end = par_end + 1
  }
  arm64_selpar(st, par_end)
  // rebuild the start block
  let emitted = arm64_emit_block(st)
  st.buf.clear()
  let new_ins : Array[@types.Ins] = []
  for x in emitted {
    new_ins.push(x)
  }
  for k in par_end..<start.ins.length() {
    new_ins.push(start.ins[k])
  }
  start.ins.clear()
  for x in new_ins {
    start.ins.push(x)
  }
  // lower calls, returns, and vararg instructions (start processed last)
  let il : Array[@types.Ins] = []
  let mut i = 1
  while i < fn_.def_order.length() {
    let bid = fn_.def_order[i]
    i = i + 1
    if fn_.blks[bid].visit != 0 {
      continue
    }
    arm64_process_block(st, bid, il)
  }
  arm64_process_block(st, fn_.start_id, il)
  if print_dbg {
    let sb = StringBuilder()
    sb.write_string("\n> After ABI lowering:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}

///|
// Lower one block's calls/returns/vararg instructions (shared by the main
// loop and the deferred start-block processing).
fn arm64_process_block(
  st : Arm64AbiState,
  bid : Int,
  il : Array[@types.Ins],
) -> Unit raise {
  if st.fn_.blks[bid].visit != 0 {
    return
  }
  let b = st.fn_.blks[bid]
  let orig : Array[@types.Ins] = []
  for x in b.ins {
    orig.push(x)
  }
  st.buf.clear()
  arm64_selret(st, bid)
  let mut j = orig.length()
  while j > 0 {
    j = j - 1
    let ins = orig[j]
    match ins.op {
      @types.Call | @types.Vacall => {
        let mut i0 = j
        while i0 > 0 {
          if !orig[i0 - 1].op.is_arg() {
            break
          }
          i0 = i0 - 1
        }
        arm64_selcall(st, orig, i0, j, il)
        j = i0
      }
      @types.Vastart => arm64_selvastart(st, ins.arg1)
      @types.Vaarg => arm64_selvaarg(st, bid, ins)
      @types.Arg | @types.Argc | @types.Arge => abort("unreachable")
      _ => arm64_emiti(st, ins)
    }
  }
  // blobs allocated for Cptr call arguments live in the start block;
  // C emits them first in program order (reverse of the creation list)
  if bid == st.fn_.start_id {
    for k in (il.length() - 1)>=..0 {
      arm64_emiti(st, il[k])
    }
    il.clear()
  }
  let nb = arm64_emit_block(st)
  b.ins.clear()
  for x in nb {
    b.ins.push(x)
  }
}
