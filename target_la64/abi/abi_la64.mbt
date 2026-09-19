///|
// LoongArch 64 (la64) ABI lowering - LP64D ABI.
// Mirrors abi_rv64.mbt; the LP64D parameter classification is register-wise
// identical to RISC-V lp64d (8 GPR + 8 FPR argument registers, small
// aggregates classified all-int/all-float/mixed), so only the register
// numbering and names differ.

///|
// Classification constants for the LoongArch ABI (same roles as rv64).
const Cptr : Int = 1

///|
const Cstk1 : Int = 2

///|
const Cstk2 : Int = 4

///|
const Cstk : Int = 6

///|
const Cfpint : Int = 8

///|
// Map a return jump kind to its class code (Jretw=0, Jretl=1, Jrets=2, Jretd=3).
fn ret_class(j : @types.JumpKind) -> Int {
  match j {
    @types.Jretw => 0
    @types.Jretl => 1
    @types.Jrets => 2
    @types.Jretd => 3
    _ => -1
  }
}

///|
// LoongArch ABI classification for parameters
priv struct La64Class {
  mut class_ : Int
  mut typ : @types.Typ?
  reg : Array[Int] // 2 slots
  cls : Array[@types.Class] // 2 slots
  off : Array[Int] // 2 slots
  mut ngp : Int
  mut nfp : Int
  mut nreg : Int
}

///|
fn La64Class::new() -> La64Class {
  La64Class::{
    class_: 0,
    typ: None,
    reg: [0, 0],
    cls: [@types.Kx, @types.Kx],
    off: [0, 0],
    ngp: 0,
    nfp: 0,
    nreg: 0,
  }
}

///|
// LoongArch ABI state
priv struct La64AbiState {
  fn_ : @types.Fn
  typs : Array[@types.Typ]
  buf : Array[@types.Ins]
}

///|
fn la64_abi_new(fn_ : @types.Fn, typs : Array[@types.Typ]) -> La64AbiState {
  La64AbiState::{ fn_, typs, buf: Array::new(), }
}

///|
fn la64_emit(
  st : La64AbiState,
  op : @types.Op,
  k : @types.Class,
  to : @types.Ref,
  a0 : @types.Ref,
  a1 : @types.Ref,
) -> Unit {
  st.buf.push(@types.Ins::new(op, k, to, a0, a1))
}

///|
fn la64_emiti(st : La64AbiState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
fn la64_emit_block(st : La64AbiState) -> Array[@types.Ins] {
  let r : Array[@types.Ins] = Array::new()
  for k in (st.buf.length() - 1)>=..0 {
    r.push(st.buf[k])
  }
  r
}

///|
fn la64_newtmp(st : La64AbiState, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp("abi", k))
}

///|
fn la64_getcon(st : La64AbiState, v : Int64) -> @types.Ref {
  @types.Ref::con(st.fn_.get_con(v))
}

///|
fn la64_call_ref(ca : Int) -> @types.Ref {
  @types.Ref::call(ca)
}

///|
// Copy sz bytes from rsrc to rstk in 8-byte chunks.
fn la64_blit(
  st : La64AbiState,
  rstk : @types.Ref,
  rsrc : @types.Ref,
  sz : Int64,
) -> Unit {
  let mut off = 0L
  while off < sz {
    let r = la64_newtmp(st, @types.Kl)
    let r1 = la64_newtmp(st, @types.Kl)
    la64_emit(st, @types.Storel, @types.Kw, @types.Ref::none(), r, r1)
    la64_emit(st, @types.Add, @types.Kl, r1, rstk, la64_getcon(st, off))
    let r2 = la64_newtmp(st, @types.Kl)
    la64_emit(st, @types.Load, @types.Kl, r, r2, @types.Ref::none())
    la64_emit(st, @types.Add, @types.Kl, r2, rsrc, la64_getcon(st, off))
    off = off + 8L
  }
}

///|
// Classify aggregate type according to the LoongArch LP64D ABI
fn la64_fpstruct(
  st : La64AbiState,
  c : La64Class,
  t : @types.Typ,
  off : Int,
) -> Int {
  let mut off = off
  let fields = t.fields
  let mut member_start = 0
  for _ in 0..<t.nunion {
    let mut fi = member_start
    while fi < fields.length() && fields[fi].kind != @types.FEnd {
      let f = fields[fi]
      fi = fi + 1
      match f.kind {
        @types.FPad => off = off + f.len
        @types.Fs | @types.Fd => {
          let n = c.nfp + c.ngp
          if n == 2 {
            return -1
          }
          c.cls[n] = if f.kind == @types.Fs { @types.Ks } else { @types.Kd }
          c.off[n] = off
          c.nfp = c.nfp + 1
          off = off + f.len
        }
        @types.Fb | @types.Fh | @types.Fw | @types.Fl => {
          let n = c.nfp + c.ngp
          if n == 2 {
            return -1
          }
          c.cls[n] = @types.Kl
          c.off[n] = off
          c.ngp = c.ngp + 1
          off = off + f.len
        }
        @types.FTyp => {
          let nested = st.typs[f.len]
          let result = la64_fpstruct(st, c, nested, off)
          if result == -1 {
            return -1
          }
          off = off + nested.size.to_int()
        }
        _ => ()
      }
    }
    while fi < fields.length() && fields[fi].kind == @types.FEnd {
      fi = fi + 1
    }
    member_start = fi
  }
  c.nfp
}

///|
// Classify type for the LoongArch ABI
fn la64_typclass(
  st : La64AbiState,
  c : La64Class,
  t : @types.Typ,
  fpabi : Bool,
) -> La64Class {
  c.typ = Some(t)
  c.class_ = 0
  c.ngp = 0
  c.nfp = 0

  if t.align > 4 {
    // alignments larger than 16 are not supported
    c.class_ = c.class_ | Cptr
    c.cls[0] = @types.Kl
    c.off[0] = 0
    c.ngp = 1
  } else if !fpabi || la64_fpstruct(st, c, t, 0) <= 0 {
    let mut n = 0
    while 8 * n < t.size.to_int() {
      c.cls[n] = @types.Kl
      c.off[n] = 8 * n
      n = n + 1
    }
    c.nfp = 0
    c.ngp = n
  }

  c.nreg = c.nfp + c.ngp
  c
}

///|
// Load parameters from registers (C ldregs)
fn la64_ldregs(st : La64AbiState, c : La64Class, mem : @types.Ref) -> Unit {
  for i in 0..<c.nreg {
    let r = la64_newtmp(st, @types.Kl)
    la64_emit(
      st,
      @types.Load,
      c.cls[i],
      @types.Ref::tmp(c.reg[i]),
      r,
      @types.Ref::none(),
    )
    la64_emit(
      st,
      @types.Add,
      @types.Kl,
      r,
      mem,
      la64_getcon(st, c.off[i].to_int64()),
    )
  }
}

///|
// Store temporary values (C sttmps)
fn la64_sttmps(
  st : La64AbiState,
  tmp : Array[@types.Ref],
  ntmp : Int,
  c : La64Class,
  mem : @types.Ref,
) -> Unit {
  let store_ops = [@types.Storew, @types.Storel, @types.Stores, @types.Stored]
  for i in 0..<ntmp {
    tmp[i] = la64_newtmp(st, c.cls[i])
    let r = la64_newtmp(st, @types.Kl)
    la64_emit(
      st,
      store_ops[c.cls[i].code()],
      @types.Kw,
      @types.Ref::none(),
      tmp[i],
      r,
    )
    la64_emit(
      st,
      @types.Add,
      @types.Kl,
      r,
      mem,
      la64_getcon(st, c.off[i].to_int64()),
    )
  }
}

///|
// Classify function arguments (C argsclass)
fn la64_argsclass(
  st : La64AbiState,
  orig : Array[@types.Ins],
  i0 : Int,
  i1 : Int,
  carg : Array[La64Class],
  retptr : Bool,
) -> Int {
  let mut ngp = 8
  let mut nfp = 8
  let mut envc = 0
  let mut gpi = 0
  let mut fpi = 0

  if retptr {
    gpi = gpi + 1
    ngp = ngp - 1
  }

  let mut a = 0
  for i in i0..<i1 {
    let cur = orig[i]
    let c = carg[a]
    match cur.op {
      @types.Par | @types.Arg => {
        c.cls[0] = cur.cls
        if cur.cls.base() == 1 && nfp > 0 {
          nfp = nfp - 1
          c.reg[0] = @types.LA_FA0 + fpi
          fpi = fpi + 1
        } else if ngp > 0 {
          if cur.cls.base() == 1 {
            c.class_ = c.class_ | Cfpint
          }
          ngp = ngp - 1
          c.reg[0] = @types.LA_A0 + gpi
          gpi = gpi + 1
        } else {
          c.class_ = c.class_ | Cstk1
        }
      }
      @types.Argc | @types.Parc => {
        let t = st.typs[cur.arg1.typ_val()]
        let _ = la64_typclass(st, c, t, true)
        if c.nfp > 0 {
          if c.nfp >= nfp || c.ngp >= ngp {
            let _ = la64_typclass(st, c, t, false)
          }
        }
        if c.nfp <= nfp {
          ngp = ngp - c.ngp
          nfp = nfp - c.nfp
          gpi = gpi + c.ngp
          fpi = fpi + c.nfp
        } else if ngp > 0 {
          c.class_ = c.class_ | Cstk2
          c.nreg = 1
          ngp = ngp - 1
          gpi = gpi + 1
        } else {
          c.class_ = c.class_ | Cstk1
          if c.nreg > 1 {
            c.class_ = c.class_ | Cstk2
          }
          c.nreg = 0
        }
      }
      @types.Pare | @types.Arge => {
        c.reg[0] = @types.LA_T8
        c.cls[0] = @types.Kl
        envc = 1
      }
      _ => ()
    }
    a = a + 1
  }
  (envc << 12) | ((gpi - (if retptr { 1 } else { 0 })) << 4) | (fpi << 8)
}

///|
// Allocate blob on stack (C stkblob)
fn la64_stkblob(st : La64AbiState, r : @types.Ref, t : @types.Typ) -> Unit {
  let al = if t.align - 2 >= 0 { t.align - 2 } else { 0 }
  let sz = (t.size.to_int() + 7) & -8
  let op = @types.Op::from_index(@types.Alloc4.index() + al)
  la64_emit(
    st,
    op,
    @types.Kl,
    r,
    la64_getcon(st, sz.to_int64()),
    @types.Ref::none(),
  )
}

///|
// Select return value handling (C selret)
fn la64_selret(st : La64AbiState, bid : Int) -> Unit {
  let b = st.fn_.blks[bid]
  let j = b.jmp.kind
  if !j.is_ret() || j == @types.Jret0 {
    return
  }
  let r0 = b.jmp.arg
  b.jmp.kind = @types.Jret0
  let mut ca = 0
  if j == @types.Jretc {
    let mut cr = La64Class::new()
    cr = la64_typclass(st, cr, st.typs[st.fn_.ret_ty], true)
    if (cr.class_ & Cptr) != 0 {
      la64_blit(st, st.fn_.retr, r0, cr.typ.unwrap().size)
      ca = 0
    } else {
      la64_ldregs(st, cr, r0)
      ca = (cr.nfp << 2) | cr.ngp
    }
  } else {
    let k = @types.Class::from_code(ret_class(j))
    if k.base() == 0 {
      la64_emit(
        st,
        @types.Copy,
        k,
        @types.Ref::tmp(@types.LA_A0),
        r0,
        @types.Ref::none(),
      )
      ca = 1
    } else {
      la64_emit(
        st,
        @types.Copy,
        k,
        @types.Ref::tmp(@types.LA_FA0),
        r0,
        @types.Ref::none(),
      )
      ca = 1 << 2
    }
  }
  b.jmp.arg = la64_call_ref(ca)
}

///|
// Select call handling (C selcall)
fn la64_selcall(
  st : La64AbiState,
  orig : Array[@types.Ins],
  i0 : Int,
  i1 : Int,
) -> Unit {
  let nargs = i1 - i0
  let ca : Array[La64Class] = Array::new()
  for _ in 0..<nargs {
    ca.push(La64Class::new())
  }
  let callins = orig[i1]
  let has_retty = !callins.arg2.is_none()
  let mut cr = La64Class::new()
  if has_retty {
    cr = la64_typclass(st, cr, st.typs[callins.arg2.typ_val()], true)
  }

  let cty = la64_argsclass(st, orig, i0, i1, ca, (cr.class_ & Cptr) != 0)
  let mut stk = 0
  for a in 0..<nargs {
    if (ca[a].class_ & Cstk1) != 0 {
      stk = stk + 8
    }
    if (ca[a].class_ & Cstk2) != 0 {
      stk = stk + 8
    }
  }
  stk = stk + (stk & 15)
  if stk != 0 {
    la64_emit(
      st,
      @types.Salloc,
      @types.Kl,
      @types.Ref::none(),
      la64_getcon(st, (-stk).to_int64()),
      @types.Ref::none(),
    )
  }

  if has_retty {
    if (cr.class_ & Cptr) != 0 {
      la64_stkblob(st, callins.to, cr.typ.unwrap())
      la64_emit(
        st,
        @types.Copy,
        @types.Kw,
        @types.Ref::none(),
        @types.Ref::tmp(@types.LA_A0),
        @types.Ref::none(),
      )
    } else {
      let tmp : Array[@types.Ref] = Array::make(2, @types.Ref::none())
      la64_sttmps(st, tmp, cr.nreg, cr, callins.to)
      for j in 0..<cr.nreg {
        let r = @types.Ref::tmp(cr.reg[j])
        la64_emit(st, @types.Copy, cr.cls[j], tmp[j], r, @types.Ref::none())
      }
    }
  } else if callins.cls.base() == 0 {
    la64_emit(
      st,
      @types.Copy,
      callins.cls,
      callins.to,
      @types.Ref::tmp(@types.LA_A0),
      @types.Ref::none(),
    )
  } else {
    la64_emit(
      st,
      @types.Copy,
      callins.cls,
      callins.to,
      @types.Ref::tmp(@types.LA_FA0),
      @types.Ref::none(),
    )
  }

  // Encode the returned-value register counts into the call ref so that
  // spill/rega know which registers the call defines (C abi selcall adds
  // retr(...)/ca before emitting Ocall).
  let mut cty2 = cty
  if has_retty {
    if (cr.class_ & Cptr) != 0 {
      // the hidden sret pointer comes back in a0
      cty2 = cty2 | 1
    } else {
      cty2 = cty2 | (cr.nfp << 2) | cr.ngp
    }
  } else if callins.cls.base() == 0 {
    cty2 = cty2 | 1
  } else {
    cty2 = cty2 | (1 << 2)
  }

  la64_emit(
    st,
    @types.Call,
    @types.Kw,
    @types.Ref::none(),
    callins.arg1,
    la64_call_ref(cty2),
  )

  // Move arguments into registers
  for a in 0..<nargs {
    let i = orig[i0 + a]
    if (ca[a].class_ & Cstk1) != 0 {
      continue
    }
    if i.op == @types.Argc {
      la64_ldregs(st, ca[a], i.arg2)
    } else if (ca[a].class_ & Cfpint) != 0 {
      let k = if ca[a].cls[0].wide() != 0 { @types.Kl } else { @types.Kw }
      let r = la64_newtmp(st, k)
      la64_emit(
        st,
        @types.Copy,
        k,
        @types.Ref::tmp(ca[a].reg[0]),
        r,
        @types.Ref::none(),
      )
      ca[a].reg[0] = r.tmp_val()
    } else {
      la64_emit(
        st,
        @types.Copy,
        ca[a].cls[0],
        @types.Ref::tmp(ca[a].reg[0]),
        i.arg1,
        @types.Ref::none(),
      )
    }
  }

  if stk == 0 {
    return
  }

  // Populate the stack
  let mut off = 0
  let r = la64_newtmp(st, @types.Kl)
  for a in 0..<nargs {
    let i = orig[i0 + a]
    if (ca[a].class_ & Cstk) == 0 {
      continue
    }
    if i.op == @types.Arg {
      let r1 = la64_newtmp(st, @types.Kl)
      let store_op = @types.Op::from_index(@types.Storew.index() + i.cls.code())
      la64_emit(st, store_op, @types.Kw, @types.Ref::none(), i.arg1, r1)
      la64_emit(
        st,
        @types.Add,
        @types.Kl,
        r1,
        r,
        la64_getcon(st, off.to_int64()),
      )
      off = off + 8
    }
    if i.op == @types.Argc {
      if (ca[a].class_ & Cstk1) != 0 {
        let r1 = la64_newtmp(st, @types.Kl)
        let r2 = la64_newtmp(st, @types.Kl)
        la64_emit(st, @types.Storel, @types.Kw, @types.Ref::none(), r2, r1)
        la64_emit(
          st,
          @types.Add,
          @types.Kl,
          r1,
          r,
          la64_getcon(st, off.to_int64()),
        )
        la64_emit(st, @types.Load, @types.Kl, r2, i.arg2, @types.Ref::none())
        off = off + 8
      }
      if (ca[a].class_ & Cstk2) != 0 {
        let r1 = la64_newtmp(st, @types.Kl)
        let r2 = la64_newtmp(st, @types.Kl)
        la64_emit(st, @types.Storel, @types.Kw, @types.Ref::none(), r2, r1)
        la64_emit(
          st,
          @types.Add,
          @types.Kl,
          r1,
          r,
          la64_getcon(st, off.to_int64()),
        )
        let r3 = la64_newtmp(st, @types.Kl)
        la64_emit(st, @types.Load, @types.Kl, r2, r3, @types.Ref::none())
        la64_emit(st, @types.Add, @types.Kl, r3, i.arg2, la64_getcon(st, 8L))
        off = off + 8
      }
    }
  }
  la64_emit(
    st,
    @types.Salloc,
    @types.Kl,
    r,
    la64_getcon(st, stk.to_int64()),
    @types.Ref::none(),
  )
}

///|
// Select parameter handling (C selpar)
fn la64_selpar(st : La64AbiState, par_end : Int) -> Int {
  let ins = st.fn_.blks[st.fn_.start_id].ins
  let npar = par_end
  let ca : Array[La64Class] = Array::new()
  for _ in 0..<npar {
    ca.push(La64Class::new())
  }
  st.buf.clear()
  let retty = st.fn_.ret_ty
  let has_retty = retty >= 0
  let mut cr = La64Class::new()
  if has_retty {
    cr = la64_typclass(st, cr, st.typs[retty], true)
    if (cr.class_ & Cptr) != 0 {
      st.fn_.retr = la64_newtmp(st, @types.Kl)
      la64_emit(
        st,
        @types.Copy,
        @types.Kl,
        st.fn_.retr,
        @types.Ref::tmp(@types.LA_A0),
        @types.Ref::none(),
      )
    }
  }

  let cty = la64_argsclass(st, ins, 0, npar, ca, (cr.class_ & Cptr) != 0)

  // Allocate register-copied aggregates
  for a in 0..<npar {
    let i = ins[a]
    if i.op != @types.Parc || (ca[a].class_ & Cptr) != 0 {
      continue
    }
    if ca[a].nreg != 0 {
      let nt = ca[a].nreg
      if (ca[a].class_ & Cstk2) != 0 {
        ca[a].cls[1] = @types.Kl
        ca[a].off[1] = 8
      }
      let tmp : Array[@types.Ref] = Array::make(nt, @types.Ref::none())
      la64_sttmps(st, tmp, nt, ca[a], i.to)
    }
  }

  let mut s = 2 + (if st.fn_.is_vararg { 8 } else { 0 })
  for a in 0..<npar {
    let i = ins[a]
    if i.op == @types.Parc && (ca[a].class_ & Cptr) == 0 {
      if ca[a].nreg == 0 {
        st.fn_.tmps[i.to.tmp_val()].slot = -s
        s = s + (if (ca[a].class_ & Cstk2) != 0 { 2 } else { 1 })
        continue
      }
      for j in 0..<ca[a].nreg {
        let r = @types.Ref::tmp(ca[a].reg[j])
        la64_emit(
          st,
          @types.Copy,
          ca[a].cls[j],
          @types.Ref::tmp(i.to.tmp_val() + j),
          r,
          @types.Ref::none(),
        )
      }
    } else if (ca[a].class_ & Cstk1) != 0 {
      la64_emit(
        st,
        @types.Load,
        ca[a].cls[0],
        i.to,
        @types.Ref::slot(-s),
        @types.Ref::none(),
      )
      s = s + 1
    } else {
      la64_emit(
        st,
        @types.Copy,
        ca[a].cls[0],
        i.to,
        @types.Ref::tmp(ca[a].reg[0]),
        @types.Ref::none(),
      )
    }
  }

  st.fn_.reg = la64_call_ref(cty).la64_argregs().0
  cty | ((s * 4) << 12)
}

///|
// Main LoongArch ABI lowering entry point
pub fn abi_la64(
  fn_ : @types.Fn,
  typs : Array[@types.Typ],
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let st = la64_abi_new(fn_, typs)

  for id in fn_.def_order {
    fn_.blks[id].visit = 0
  }

  // Lower parameters
  let start = fn_.blks[fn_.start_id]
  let mut par_end = 0
  while par_end < start.ins.length() {
    let op = start.ins[par_end].op
    if !op.is_par() {
      break
    }
    par_end = par_end + 1
  }
  let _ = la64_selpar(st, par_end)

  // Rebuild the start block
  let emitted = la64_emit_block(st)
  st.buf.clear()
  let new_ins : Array[@types.Ins] = Array::new()
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

  // Lower calls, returns, and vararg instructions
  let mut i = 1
  while i < fn_.def_order.length() {
    let bid = fn_.def_order[i]
    i = i + 1
    if fn_.blks[bid].visit != 0 {
      continue
    }
    let b = fn_.blks[bid]
    let orig : Array[@types.Ins] = Array::new()
    for x in b.ins {
      orig.push(x)
    }
    st.buf.clear()
    la64_selret(st, bid)
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
          la64_selcall(st, orig, i0, j)
          j = i0
        }
        @types.Arg | @types.Argc | @types.Arge => abort("unreachable")
        _ => la64_emiti(st, ins)
      }
    }
    let nb = la64_emit_block(st)
    b.ins.clear()
    for x in nb {
      b.ins.push(x)
    }
  }

  // Process start block for calls/returns (done last, matching C code)
  let start_bid = fn_.start_id
  let start_b = fn_.blks[start_bid]
  let start_orig : Array[@types.Ins] = Array::new()
  for x in start_b.ins {
    start_orig.push(x)
  }
  st.buf.clear()
  la64_selret(st, start_bid)
  let mut j = start_orig.length()
  while j > 0 {
    j = j - 1
    let ins = start_orig[j]
    match ins.op {
      @types.Call | @types.Vacall => {
        let mut i0 = j
        while i0 > 0 {
          if !start_orig[i0 - 1].op.is_arg() {
            break
          }
          i0 = i0 - 1
        }
        la64_selcall(st, start_orig, i0, j)
        j = i0
      }
      @types.Vastart | @types.Vaarg => ()
      @types.Arg | @types.Argc | @types.Arge => abort("unreachable")
      _ => la64_emiti(st, ins)
    }
  }
  let nb = la64_emit_block(st)
  start_b.ins.clear()
  for x in nb {
    start_b.ins.push(x)
  }

  if print_dbg {
    let sb = StringBuilder()
    sb.write_string("\n> After LoongArch ABI lowering:\n")
    sb.to_string()
  } else {
    ""
  }
}
