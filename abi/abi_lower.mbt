///|
// ABI lowering driver: selcall, selpar, split, chpred, vaarg, vastart, abi.
// Corresponds to the remainder of sysv.c / amd64/sysv.c.

///|
fn selcall(
  st : AbiState,
  orig : Array[@types.Ins],
  i0 : Int,
  i1 : Int,
) -> Unit raise {
  let nargs = i1 - i0
  let ac : Array[AClass] = Array::new()
  for _ in 0..<nargs {
    ac.push(AClass::new())
  }
  let callins = orig[i1]
  let has_retty = !callins.arg2.is_none()
  let aret = if has_retty {
    typclass(st, AClass::new(), st.typs[callins.arg2.typ_val()])
  } else {
    AClass::new()
  }
  st.env = @types.ref_none()
  let mut ca = argsclass(
    st,
    orig,
    i0,
    i1,
    ac,
    @types.Arg,
    if has_retty {
      Some(aret)
    } else {
      None
    },
  )
  // compute stack size for in-memory arguments
  let mut stk = 0
  for a = nargs - 1; a >= 0; a = a - 1 {
    if ac[a].inmem != 0 {
      if ac[a].align > 4 {
        raise @util.QbeError::Ice("sysv abi requires alignments of 16 or less")
      }
      stk = stk + ac[a].size
      if ac[a].align == 4 {
        stk = stk + (stk & 15)
      }
    }
  }
  stk = stk + (stk & 15)
  if stk != 0 {
    let r = getcon(st, (-stk).to_int64())
    emit(st, @types.Salloc, @types.Kl, @types.ref_none(), r, @types.ref_none())
  }

  let ni = Ref::{ val: 0 }
  let ns = Ref::{ val: 0 }
  let reg : Array[@types.Ref] = Array::make(2, @types.ref_none())

  if has_retty {
    if aret.inmem != 0 {
      // get the return location from eax
      let r1 = abi_newtmp(st, @types.Kl)
      emit(
        st,
        @types.Copy,
        @types.Kl,
        callins.to,
        @types.Ref::tmp(@types.RAX),
        @types.ref_none(),
      )
      ca = ca + 1
      let al = if aret.align >= 2 { aret.align - 2 } else { 0 }
      let ra = RAlloc::{
        i: @types.Ins::new(
          alloc_op(al),
          @types.Kl,
          r1,
          getcon(st, aret.size.to_int64()),
          @types.ref_none(),
        ),
        link: st.ral,
      }
      st.ral = Some(ra)
    } else {
      if aret.size > 8 {
        let r = abi_newtmp(st, @types.Kl)
        let r1 = abi_newtmp(st, aret.cls[1])
        emit(st, @types.Storel, @types.Kw, @types.ref_none(), r1, r)
        emit(st, @types.Add, @types.Kl, r, callins.to, getcon(st, 8L))
        aret.r[1] = r1
      }
      let r0 = abi_newtmp(st, aret.cls[0])
      emit(st, @types.Storel, @types.Kw, @types.ref_none(), r0, callins.to)
      aret.r[0] = r0
      ca = ca + retr(reg, aret)
      if aret.size > 8 {
        emit(st, @types.Copy, aret.cls[1], aret.r[1], reg[1], @types.ref_none())
      }
      emit(st, @types.Copy, aret.cls[0], aret.r[0], reg[0], @types.ref_none())
      let al = if aret.align >= 2 { aret.align - 2 } else { 0 }
      let ra = RAlloc::{
        i: @types.Ins::new(
          alloc_op(al),
          @types.Kl,
          callins.to,
          getcon(st, aret.size.to_int64()),
          @types.ref_none(),
        ),
        link: st.ral,
      }
      st.ral = Some(ra)
    }
  } else if kbase(callins.cls) == 0 {
    emit(
      st,
      @types.Copy,
      callins.cls,
      callins.to,
      @types.Ref::tmp(@types.RAX),
      @types.ref_none(),
    )
    ca = ca + 1
  } else {
    emit(
      st,
      @types.Copy,
      callins.cls,
      callins.to,
      @types.Ref::tmp(@types.XMM0),
      @types.ref_none(),
    )
    ca = ca + (1 << 2)
  }

  let envc = !st.env.is_none()
  let varc = callins.op == @types.Vacall
  if varc && envc {
    raise @util.QbeError::Ice("sysv abi does not support variadic env calls")
  }
  ca = ca | ((if varc || envc { 1 } else { 0 }) << 12)
  emit(
    st,
    @types.Call,
    callins.cls,
    @types.ref_none(),
    callins.arg1,
    call_ref(ca),
  )
  if envc {
    emit(
      st,
      @types.Copy,
      @types.Kl,
      @types.Ref::tmp(@types.RAX),
      st.env,
      @types.ref_none(),
    )
  }
  if varc {
    emit(
      st,
      @types.Copy,
      @types.Kw,
      @types.Ref::tmp(@types.RAX),
      getcon(st, ((ca >> 8) & 15).to_int64()),
      @types.ref_none(),
    )
  }

  if has_retty && aret.inmem != 0 {
    // pass hidden argument (the return pad)
    let ra = st.ral.unwrap()
    emit(
      st,
      @types.Copy,
      @types.Kl,
      rarg(st, @types.Kl, ni, ns),
      ra.i.to,
      @types.ref_none(),
    )
  }
  for a in 0..<nargs {
    let i = orig[i0 + a]
    if ac[a].inmem != 0 {
      continue
    }
    let r1 = rarg(st, ac[a].cls[0], ni, ns)
    if i.op == @types.Argc {
      if ac[a].size > 8 {
        let r2 = rarg(st, ac[a].cls[1], ni, ns)
        let r = abi_newtmp(st, @types.Kl)
        emit(st, @types.Load, ac[a].cls[1], r2, r, @types.ref_none())
        emit(st, @types.Add, @types.Kl, r, i.arg2, getcon(st, 8L))
      }
      emit(st, @types.Load, ac[a].cls[0], r1, i.arg2, @types.ref_none())
    } else {
      emit(st, @types.Copy, i.cls, r1, i.arg1, @types.ref_none())
    }
  }

  if stk == 0 {
    return
  }
  let r = abi_newtmp(st, @types.Kl)
  let mut off = 0
  for a in 0..<nargs {
    let i = orig[i0 + a]
    if ac[a].inmem == 0 {
      continue
    }
    if i.op == @types.Argc {
      if ac[a].align == 4 {
        off = off + (off & 15)
      }
      blit(st, r, off, i.arg2, ac[a].size)
    } else {
      let r1 = abi_newtmp(st, @types.Kl)
      emit(st, @types.Storel, @types.Kw, @types.ref_none(), i.arg1, r1)
      emit(st, @types.Add, @types.Kl, r1, r, getcon(st, off.to_int64()))
    }
    off = off + ac[a].size
  }
  emit(
    st,
    @types.Salloc,
    @types.Kl,
    r,
    getcon(st, stk.to_int64()),
    @types.ref_none(),
  )
}

///|
fn selpar(st : AbiState, par_end : Int) -> Int raise {
  // par_end: index of the first non-par instruction in the start block
  let ins = st.fn_.blks[st.fn_.start_id].ins
  let npar = par_end
  let ac : Array[AClass] = Array::new()
  for _ in 0..<npar {
    ac.push(AClass::new())
  }
  st.buf.clear()
  let ni = Ref::{ val: 0 }
  let ns = Ref::{ val: 0 }
  let retty = st.fn_.ret_ty
  let has_retty = retty >= 0
  let aret = if has_retty {
    typclass(st, AClass::new(), st.typs[retty])
  } else {
    AClass::new()
  }
  st.env = @types.ref_none()
  let fa = argsclass(
    st,
    ins,
    0,
    npar,
    ac,
    @types.Par,
    if has_retty {
      Some(aret)
    } else {
      None
    },
  )

  // Allocate register-copied aggregates
  for a in 0..<npar {
    let i = ins[a]
    if i.op != @types.Parc || ac[a].inmem != 0 {
      continue
    }
    if ac[a].size > 8 {
      let r = abi_newtmp(st, @types.Kl)
      let r1 = abi_newtmp(st, @types.Kl)
      emit(st, @types.Storel, @types.Kw, @types.ref_none(), r1, r)
      emit(st, @types.Add, @types.Kl, r, i.to, getcon(st, 8L))
      ac[a].r[1] = r1
    }
    let r0 = abi_newtmp(st, @types.Kl)
    emit(st, @types.Storel, @types.Kw, @types.ref_none(), r0, i.to)
    ac[a].r[0] = r0
    let al = if ac[a].align >= 2 { ac[a].align - 2 } else { 0 }
    emit(
      st,
      alloc_op(al),
      @types.Kl,
      i.to,
      getcon(st, ac[a].size.to_int64()),
      @types.ref_none(),
    )
  }

  if has_retty && aret.inmem != 0 {
    let r = abi_newtmp(st, @types.Kl)
    emit(
      st,
      @types.Copy,
      @types.Kl,
      r,
      rarg(st, @types.Kl, ni, ns),
      @types.ref_none(),
    )
    st.fn_.retr = r
  }

  let mut s = 4
  for a in 0..<npar {
    let i = ins[a]
    match ac[a].inmem {
      1 => {
        if ac[a].align > 4 {
          raise @util.QbeError::Ice(
            "sysv abi requires alignments of 16 or less",
          )
        }
        if ac[a].align == 4 {
          s = (s + 3) & -4
        }
        st.fn_.tmps[i.to.tmp_val()].slot = -s
        s = s + ac[a].size / 4
      }
      2 => {
        emit(
          st,
          @types.Load,
          i.cls,
          i.to,
          @types.Ref::slot(-s),
          @types.ref_none(),
        )
        s = s + 2
      }
      _ => {
        let r = rarg(st, ac[a].cls[0], ni, ns)
        if i.op == @types.Parc {
          emit(st, @types.Copy, @types.Kl, ac[a].r[0], r, @types.ref_none())
          if ac[a].size > 8 {
            let r2 = rarg(st, ac[a].cls[1], ni, ns)
            emit(st, @types.Copy, @types.Kl, ac[a].r[1], r2, @types.ref_none())
          }
        } else {
          emit(st, @types.Copy, i.cls, i.to, r, @types.ref_none())
        }
      }
    }
  }

  if !st.env.is_none() {
    emit(
      st,
      @types.Copy,
      @types.Kl,
      st.env,
      @types.Ref::tmp(@types.RAX),
      @types.ref_none(),
    )
  }
  fa | ((s * 4) << 12)
}

///|
// Split the current block: move the emitted instructions into a new block
// inserted after b (C split). Returns the new block id.
fn split(st : AbiState, bid : Int) -> Int {
  let b = st.fn_.blks[bid]
  let nb = emit_block(st)
  st.buf.clear()
  b.visit = b.visit + 1
  let name = b.name + "." + b.visit.to_string()
  let bn_id = st.fn_.add_blk(name)
  let bn = st.fn_.blks[bn_id]
  bn.ins.clear()
  for x in nb {
    bn.ins.push(x)
  }
  bn.visit = b.visit
  bn.loop_depth = b.loop_depth
  // insert into def_order right after b
  let mut idx = 0
  while idx < st.fn_.def_order.length() {
    if st.fn_.def_order[idx] == bid {
      break
    }
    idx = idx + 1
  }
  st.fn_.def_order.insert(idx + 1, bn_id)
  bn_id
}

///|
// Update the phi args in block succ, replacing predecessor bp with bp1.
fn chpred(st : AbiState, succ : Int, bp : Int, bp1 : Int) -> Unit {
  for p in st.fn_.blks[succ].phi {
    for a in p.args {
      if a.blk_id == bp {
        a.blk_id = bp1
      }
    }
  }
}

///|
fn selvaarg(st : AbiState, bid : Int, va : @types.Ins) -> Unit {
  let b = st.fn_.blks[bid]
  let c4 = getcon(st, 4L)
  let c8 = getcon(st, 8L)
  let c16 = getcon(st, 16L)
  let ap = va.arg1
  let isint = kbase(va.cls) == 0

  let loc = abi_newtmp(st, @types.Kl)
  emit(st, @types.Load, va.cls, va.to, loc, @types.ref_none())
  let b0 = split(st, bid)
  // b0 inherits b's jump
  let b0b = st.fn_.blks[b0]
  b0b.jmp = b.jmp
  if b.jmp.s1 >= 0 {
    chpred(st, b.jmp.s1, bid, b0)
  }
  if b.jmp.s2 >= 0 && b.jmp.s2 != b.jmp.s1 {
    chpred(st, b.jmp.s2, bid, b0)
  }

  let lreg = abi_newtmp(st, @types.Kl)
  let nr = abi_newtmp(st, @types.Kl)
  let r0 = abi_newtmp(st, @types.Kw)
  let r1 = abi_newtmp(st, @types.Kl)
  emit(st, @types.Storew, @types.Kw, @types.ref_none(), r0, r1)
  emit(
    st,
    @types.Add,
    @types.Kl,
    r1,
    ap,
    if isint {
      @types.Ref::con(st.fn_.get_con(0))
    } else {
      c4
    },
  )
  emit(st, @types.Add, @types.Kw, r0, nr, if isint { c8 } else { c16 })
  let r2 = abi_newtmp(st, @types.Kl)
  let r3 = abi_newtmp(st, @types.Kl)
  emit(st, @types.Add, @types.Kl, lreg, r3, nr)
  emit(st, @types.Load, @types.Kl, r3, r2, @types.ref_none())
  emit(st, @types.Add, @types.Kl, r2, ap, c16)
  let breg = split(st, bid)
  st.fn_.blks[breg].jmp = @types.Jump::new(@types.Jjmp)
  st.fn_.blks[breg].jmp.s1 = b0

  let lstk = abi_newtmp(st, @types.Kl)
  let r4 = abi_newtmp(st, @types.Kl)
  let r5 = abi_newtmp(st, @types.Kl)
  emit(st, @types.Storel, @types.Kw, @types.ref_none(), r5, r4)
  emit(st, @types.Add, @types.Kl, r5, lstk, c8)
  emit(st, @types.Load, @types.Kl, lstk, r4, @types.ref_none())
  emit(st, @types.Add, @types.Kl, r4, ap, c8)
  let bstk = split(st, bid)
  st.fn_.blks[bstk].jmp = @types.Jump::new(@types.Jjmp)
  st.fn_.blks[bstk].jmp.s1 = b0

  // b0 gets a phi: %loc =l phi @bstk %lstk, @breg %lreg
  let phi = @types.Phi::new(loc, @types.Kl)
  phi.args.push(@types.PhiArg::{ value: lstk, blk_id: bstk })
  phi.args.push(@types.PhiArg::{ value: lreg, blk_id: breg })
  st.fn_.blks[b0].phi.insert(0, phi)

  let r6 = abi_newtmp(st, @types.Kl)
  let r7 = abi_newtmp(st, @types.Kw)
  b.jmp = @types.Jump::new(@types.Jjnz)
  b.jmp.arg = r7
  b.jmp.s1 = breg
  b.jmp.s2 = bstk
  let c = getcon(st, (if isint { 48 } else { 176 }).to_int64())
  emit(st, @types.Cultw, @types.Kw, r7, nr, c)
  emit(st, @types.Loadsw, @types.Kl, nr, r6, @types.ref_none())
  emit(
    st,
    @types.Add,
    @types.Kl,
    r6,
    ap,
    if isint {
      @types.Ref::con(st.fn_.get_con(0))
    } else {
      c4
    },
  )
}

///|
fn selvastart(st : AbiState, ap : @types.Ref) -> Unit {
  let fa = st.fa
  let gp = ((fa >> 4) & 15) * 8
  let fp = 48 + ((fa >> 8) & 15) * 16
  let sp = fa >> 12
  let r0 = abi_newtmp(st, @types.Kl)
  let r1 = abi_newtmp(st, @types.Kl)
  emit(st, @types.Storel, @types.Kw, @types.ref_none(), r1, r0)
  emit(
    st,
    @types.Add,
    @types.Kl,
    r1,
    @types.Ref::tmp(@types.RBP),
    getcon(st, -176L),
  )
  emit(st, @types.Add, @types.Kl, r0, ap, getcon(st, 16L))
  let r2 = abi_newtmp(st, @types.Kl)
  let r3 = abi_newtmp(st, @types.Kl)
  emit(st, @types.Storel, @types.Kw, @types.ref_none(), r3, r2)
  emit(
    st,
    @types.Add,
    @types.Kl,
    r3,
    @types.Ref::tmp(@types.RBP),
    getcon(st, sp.to_int64()),
  )
  emit(st, @types.Add, @types.Kl, r2, ap, getcon(st, 8L))
  let r4 = abi_newtmp(st, @types.Kl)
  emit(
    st,
    @types.Storew,
    @types.Kw,
    @types.ref_none(),
    getcon(st, fp.to_int64()),
    r4,
  )
  emit(st, @types.Add, @types.Kl, r4, ap, getcon(st, 4L))
  emit(
    st,
    @types.Storew,
    @types.Kw,
    @types.ref_none(),
    getcon(st, gp.to_int64()),
    ap,
  )
}

///|
// Lower a single block's calls/returns/vararg instructions (C abi inner loop).
fn process_block(st : AbiState, bid : Int) -> Unit raise {
  let b = st.fn_.blks[bid]
  let orig : Array[@types.Ins] = Array::new()
  for x in b.ins {
    orig.push(x)
  }
  st.buf.clear()
  selret(st, bid)
  let mut i = orig.length()
  while i > 0 {
    i = i - 1
    let ins = orig[i]
    match ins.op {
      @types.Call | @types.Vacall => {
        let mut i0 = i
        while i0 > 0 {
          if !@types.is_arg(orig[i0 - 1].op) {
            break
          }
          i0 = i0 - 1
        }
        selcall(st, orig, i0, i)
        i = i0
      }
      @types.Vastart => selvastart(st, ins.arg1)
      @types.Vaarg => selvaarg(st, bid, ins)
      @types.Arg | @types.Argc | @types.Arge => abort("unreachable")
      _ => emiti(st, ins)
    }
  }
  if bid == st.fn_.start_id {
    while st.ral is Some(ra) {
      emiti(st, ra.i)
      st.ral = ra.link
    }
  }
  let nb = emit_block(st)
  b.ins.clear()
  for x in nb {
    b.ins.push(x)
  }
}

///|
// SysV ABI lowering (C abi / amd64_sysv_abi).
// Returns the -dA debug text (empty when print_dbg is false).
pub fn abi(
  fn_ : @types.Fn,
  typs : Array[@types.Typ],
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String raise {
  let st = AbiState::{
    fn_,
    typs,
    buf: Array::new(),
    ral: None,
    env: @types.ref_none(),
    fa: 0,
  }
  for id in fn_.def_order {
    fn_.blks[id].visit = 0
  }
  // lower parameters
  let start = fn_.blks[fn_.start_id]
  let mut par_end = 0
  while par_end < start.ins.length() {
    let op = start.ins[par_end].op
    if !@types.is_par(op) {
      break
    }
    par_end = par_end + 1
  }
  st.fa = selpar(st, par_end)
  // rebuild the start block: emitted par lowerings ++ remaining instructions
  let emitted = emit_block(st)
  st.buf.clear()
  let new_ins : Array[@types.Ins] = Array::new()
  for x in emitted {
    new_ins.push(x)
  }
  for k = par_end; k < start.ins.length(); k = k + 1 {
    new_ins.push(start.ins[k])
  }
  start.ins.clear()
  for x in new_ins {
    start.ins.push(x)
  }
  // lower calls, returns, and vararg instructions (start processed last)
  let mut i = 1
  while i < fn_.def_order.length() {
    let bid = fn_.def_order[i]
    i = i + 1
    if fn_.blks[bid].visit != 0 {
      continue
    }
    process_block(st, bid)
  }
  process_block(st, fn_.start_id)
  if print_dbg {
    let sb = StringBuilder::new()
    sb.write_string("\n> After ABI lowering:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}
