///|
// SysV ABI lowering for amd64 - corresponds to sysv.c + amd64/sysv.c in QBE.
// Lowers parameter passing, calls, returns, and vararg handling.

///|
priv struct AClass {
  mut inmem : Int
  mut align : Int
  mut size : Int
  cls : Array[@types.Class] // 2 slots
  r : Array[@types.Ref] // 2 slots
}

///|
fn AClass::new() -> AClass {
  AClass::{
    inmem: 0,
    align: 0,
    size: 0,
    cls: [@types.Kx, @types.Kx],
    r: [@types.ref_none(), @types.ref_none()],
  }
}

///|
priv struct RAlloc {
  i : @types.Ins
  link : RAlloc?
}

///|
priv struct AbiState {
  fn_ : @types.Fn
  typs : Array[@types.Typ]
  buf : Array[@types.Ins]
  mut ral : RAlloc?
  mut env : @types.Ref
  mut fa : Int
}

///|
fn emit(
  st : AbiState,
  op : @types.Op,
  k : @types.Class,
  to : @types.Ref,
  a0 : @types.Ref,
  a1 : @types.Ref,
) -> Unit {
  st.buf.push(@types.Ins::new(op, k, to, a0, a1))
}

///|
fn emiti(st : AbiState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
fn emit_block(st : AbiState) -> Array[@types.Ins] {
  let r : Array[@types.Ins] = Array::new()
  for k = st.buf.length() - 1; k >= 0; k = k - 1 {
    r.push(st.buf[k])
  }
  r
}

///|
fn abi_newtmp(st : AbiState, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp("abi", k))
}

///|
fn blt_newtmp(st : AbiState, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp("blt", k))
}

///|
fn getcon(st : AbiState, v : Int64) -> @types.Ref {
  @types.Ref::con(st.fn_.get_con(v))
}

///|
fn call_ref(ca : Int) -> @types.Ref {
  @types.Ref::call(ca)
}

///|
fn alloc_op(al : Int) -> @types.Op {
  @types.op_from_index(@types.op_index(@types.Alloc4) + al)
}

///|
fn classify(
  a : AClass,
  typs : Array[@types.Typ],
  t : @types.Typ,
  s0 : Int,
) -> Unit {
  let fields = t.fields
  let mut member_start = 0
  for n = 0; n < t.nunion; n = n + 1 {
    let mut s = s0
    let mut fi = member_start
    while fi < fields.length() && fields[fi].kind != @types.FEnd {
      let f = fields[fi]
      fi = fi + 1
      let ci = s / 8
      match f.kind {
        @types.FPad => s = s + f.len
        @types.Fs | @types.Fd => {
          if a.cls[ci] == @types.Kx {
            a.cls[ci] = @types.Kd
          }
          s = s + f.len
        }
        @types.Fb | @types.Fh | @types.Fw | @types.Fl => {
          a.cls[ci] = @types.Kl
          s = s + f.len
        }
        @types.FTyp => {
          classify(a, typs, typs[f.len], s)
          s = s + typs[f.len].size.to_int()
        }
        _ => ()
      }
    }
    while fi < fields.length() && fields[fi].kind == @types.FEnd {
      fi = fi + 1
    }
    member_start = fi
  }
}

///|
fn typclass(st : AbiState, a : AClass, t : @types.Typ) -> AClass {
  let mut sz = t.size
  let mut al = 1 << t.align
  // the ABI requires sizes rounded up to a multiple of 8
  if al < 8 {
    al = 8
  }
  let al64 = al.to_int64()
  sz = (sz + al64 - 1L) & -al64
  a.size = sz.to_int()
  a.align = t.align
  if t.dark != 0 || sz > 16 || sz == 0 {
    a.inmem = 1
    return a
  }
  a.cls[0] = @types.Kx
  a.cls[1] = @types.Kx
  a.inmem = 0
  classify(a, st.typs, t, 0)
  a
}

///|
fn retr(reg : Array[@types.Ref], aret : AClass) -> Int {
  let mut nr0 = 0
  let mut nr1 = 0
  let mut ca = 0
  let mut n = 0
  while n * 8 < aret.size {
    let k = kbase(aret.cls[n])
    if k == 0 {
      // int return regs: RAX then RDX
      reg[n] = @types.Ref::tmp(if nr0 == 0 { @types.RAX } else { @types.RDX })
      nr0 = nr0 + 1
    } else {
      reg[n] = @types.Ref::tmp(@types.XMM0 + nr1)
      nr1 = nr1 + 1
    }
    ca = ca + (1 << (2 * k))
    n = n + 1
  }
  ca
}

///|
fn kbase(k : @types.Class) -> Int {
  @types.kbase(k)
}

///|
// Copy sz bytes from rsrc to rstk+soff in 8-byte chunks (C blit).
fn blit(
  st : AbiState,
  rstk : @types.Ref,
  soff : Int,
  rsrc : @types.Ref,
  sz : Int,
) -> Unit {
  let mut soff = soff
  let mut sz = sz
  let mut boff = 0
  while sz > 0 {
    let r = blt_newtmp(st, @types.Kl)
    let r1 = blt_newtmp(st, @types.Kl)
    emit(st, @types.Storel, @types.Kw, @types.ref_none(), r, r1)
    emit(st, @types.Add, @types.Kl, r1, rstk, getcon(st, soff.to_int64()))
    let r2 = blt_newtmp(st, @types.Kl)
    emit(st, @types.Load, @types.Kl, r, r2, @types.ref_none())
    emit(st, @types.Add, @types.Kl, r2, rsrc, getcon(st, boff.to_int64()))
    sz = sz - 8
    soff = soff + 8
    boff = boff + 8
  }
}

///|
fn selret(st : AbiState, bid : Int) -> Unit {
  let b = st.fn_.blks[bid]
  let j = b.jmp.kind
  if !@types.is_ret(j) || j == @types.Jret0 {
    return
  }
  let r0 = b.jmp.arg
  b.jmp.kind = @types.Jret0
  let mut ca = 0
  if j == @types.Jretc {
    let aret = typclass(st, AClass::new(), st.typs[st.fn_.ret_ty])
    if aret.inmem != 0 {
      emit(
        st,
        @types.Copy,
        @types.Kl,
        @types.Ref::tmp(@types.RAX),
        st.fn_.retr,
        @types.ref_none(),
      )
      blit(st, st.fn_.retr, 0, r0, aret.size)
      ca = 1
    } else {
      let reg : Array[@types.Ref] = Array::make(2, @types.ref_none())
      ca = retr(reg, aret)
      if aret.size > 8 {
        let r = abi_newtmp(st, @types.Kl)
        emit(st, @types.Load, @types.Kl, reg[1], r, @types.ref_none())
        emit(st, @types.Add, @types.Kl, r, r0, getcon(st, 8L))
      }
      emit(st, @types.Load, @types.Kl, reg[0], r0, @types.ref_none())
    }
  } else {
    let k = @types.class_from_code(ret_class(j))
    if kbase(k) == 0 {
      emit(
        st,
        @types.Copy,
        k,
        @types.Ref::tmp(@types.RAX),
        r0,
        @types.ref_none(),
      )
      ca = 1
    } else {
      emit(
        st,
        @types.Copy,
        k,
        @types.Ref::tmp(@types.XMM0),
        r0,
        @types.ref_none(),
      )
      ca = 1 << 2
    }
  }
  b.jmp.arg = call_ref(ca)
}

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
fn argsclass(
  st : AbiState,
  orig : Array[@types.Ins],
  i0 : Int,
  i1 : Int,
  ac : Array[AClass],
  op : @types.Op,
  aret : AClass?,
) -> Int {
  let mut nint = if aret is Some(a) && a.inmem != 0 { 5 } else { 6 }
  let mut nsse = 8
  let par = op == @types.Par
  let mut a = 0
  for i = i0; i < i1; i = i + 1 {
    let cur = orig[i]
    if cur.op == @types.Arg || cur.op == @types.Par {
      let pn = kbase(cur.cls)
      if pn == 0 {
        if nint > 0 {
          nint = nint - 1
          ac[a].inmem = 0
        } else {
          ac[a].inmem = 2
        }
      } else if nsse > 0 {
        nsse = nsse - 1
        ac[a].inmem = 0
      } else {
        ac[a].inmem = 2
      }
      ac[a].align = 3
      ac[a].size = 8
      ac[a].cls[0] = cur.cls
    } else if cur.op == @types.Argc || cur.op == @types.Parc {
      let n = cur.arg1.typ_val()
      ac[a] = typclass(st, ac[a], st.typs[n])
      if ac[a].inmem == 0 {
        let mut ni = 0
        let mut ns = 0
        let mut nn = 0
        while nn * 8 < ac[a].size {
          if kbase(ac[a].cls[nn]) == 0 {
            ni = ni + 1
          } else {
            ns = ns + 1
          }
          nn = nn + 1
        }
        if nint >= ni && nsse >= ns {
          nint = nint - ni
          nsse = nsse - ns
        } else {
          ac[a].inmem = 1
        }
      }
    } else if cur.op == @types.Arge || cur.op == @types.Pare {
      if par {
        st.env = cur.to
      } else {
        st.env = cur.arg1
      }
    }
    a = a + 1
  }
  ((6 - nint) << 4) | ((8 - nsse) << 8)
}

///|
fn rarg(
  _st : AbiState,
  ty : @types.Class,
  ni : @ref.Ref[Int],
  ns : @ref.Ref[Int],
) -> @types.Ref {
  if kbase(ty) == 0 {
    let r = @types.Ref::tmp(rsave[ni.val])
    ni.val = ni.val + 1
    r
  } else {
    let r = @types.Ref::tmp(@types.XMM0 + ns.val)
    ns.val = ns.val + 1
    r
  }
}
