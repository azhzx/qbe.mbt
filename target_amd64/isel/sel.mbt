///|
// The instruction selection driver - corresponds to the second half of
// amd64/isel.c (selcmp, sel, flagi, seljmp, amd64_isel).

///|
fn selcmp(
  st : IselState,
  a0 : @types.Ref,
  a1 : @types.Ref,
  k : @types.Class,
) -> Bool {
  let mut arg0 = a0
  let mut arg1 = a1
  let swap = arg0.is_con()
  if swap {
    let t = arg1
    arg1 = arg0
    arg0 = t
  }
  emit(st, @types.Xcmp, k, @types.Ref::none(), arg1, arg0)
  let idx = st.buf.length() - 1
  if arg0.is_con() {
    let r = isel_newtmp(st, k)
    st.buf[idx].arg1 = r
    emit(st, @types.Copy, k, r, arg0, @types.Ref::none())
  }
  st.buf[idx].arg1 = fixarg(st, st.buf[idx].arg1, k, Some(@types.Xcmp))
  st.buf[idx].arg2 = fixarg(st, st.buf[idx].arg2, k, Some(@types.Xcmp))
  swap
}

///|
// Emit an instruction and fix its arguments (C Emit label in sel).
fn sel_emit(st : IselState, i : @types.Ins) -> Unit {
  emiti(st, i)
  let idx = st.buf.length() - 1
  st.buf[idx].arg1 = fixarg(st, st.buf[idx].arg1, argcls(i, 0), Some(i.op))
  st.buf[idx].arg2 = fixarg(st, st.buf[idx].arg2, argcls(i, 1), Some(i.op))
}

///|
// Select a single instruction (C sel).
fn sel(st : IselState, i : @types.Ins) -> Unit raise {
  if i.to.is_tmp() {
    if !isreg(i.to) && !isreg(i.arg1) && !isreg(i.arg2) {
      if st.fn_.tmps[i.to.tmp_val()].nuse == 0 {
        chuse(st, i.arg1, -1)
        chuse(st, i.arg2, -1)
        return
      }
    }
  }
  let k = i.cls
  match i.op {
    @types.Div | @types.Rem | @types.Udiv | @types.Urem =>
      if k.base() == 1 {
        sel_emit(st, i)
      } else {
        let mut r0 = @types.Ref::none()
        let mut r1 = @types.Ref::none()
        if i.op == @types.Div || i.op == @types.Udiv {
          r0 = @types.Ref::tmp(@types.RAX)
          r1 = @types.Ref::tmp(@types.RDX)
        } else {
          r0 = @types.Ref::tmp(@types.RDX)
          r1 = @types.Ref::tmp(@types.RAX)
        }
        emit(st, @types.Copy, k, i.to, r0, @types.Ref::none())
        emit(st, @types.Copy, k, @types.Ref::none(), r1, @types.Ref::none())
        if i.arg2.is_con() {
          r0 = isel_newtmp(st, k)
        } else {
          r0 = i.arg2
        }
        if i.op == @types.Div || i.op == @types.Rem {
          emit(st, @types.Xidiv, k, @types.Ref::none(), r0, @types.Ref::none())
          emit(
            st,
            @types.Sign,
            k,
            @types.Ref::tmp(@types.RDX),
            @types.Ref::tmp(@types.RAX),
            @types.Ref::none(),
          )
        } else {
          emit(st, @types.Xdiv, k, @types.Ref::none(), r0, @types.Ref::none())
          emit(
            st,
            @types.Copy,
            k,
            @types.Ref::tmp(@types.RDX),
            @types.Ref::con(st.fn_.get_con(0L)),
            @types.Ref::none(),
          )
        }
        emit(
          st,
          @types.Copy,
          k,
          @types.Ref::tmp(@types.RAX),
          i.arg1,
          @types.Ref::none(),
        )
        let idx = st.buf.length() - 1
        st.buf[idx].arg1 = fixarg(st, st.buf[idx].arg1, k, Some(@types.Copy))
        if i.arg2.is_con() {
          emit(st, @types.Copy, k, r0, i.arg2, @types.Ref::none())
        }
      }
    @types.Sar | @types.Shr | @types.Shl =>
      if i.arg2.is_con() {
        sel_emit(st, i)
      } else {
        let r0 = i.arg2
        let i1 = i
        i1.arg2 = @types.Ref::tmp(@types.RCX)
        emit(
          st,
          @types.Copy,
          @types.Kw,
          @types.Ref::none(),
          @types.Ref::tmp(@types.RCX),
          @types.Ref::none(),
        )
        emiti(st, i1)
        emit(
          st,
          @types.Copy,
          @types.Kw,
          @types.Ref::tmp(@types.RCX),
          r0,
          @types.Ref::none(),
        )
      }
    @types.Nop => ()
    @types.Stored
    | @types.Stores
    | @types.Storel
    | @types.Storew
    | @types.Storeh
    | @types.Storeb => {
      let i1 = i
      if i1.arg1.is_con() {
        if i1.op == @types.Stored {
          i1.op = @types.Storel
        }
        if i1.op == @types.Stores {
          i1.op = @types.Storew
        }
      }
      i1.arg2 = seladdr(st, i1.arg2)
      sel_emit(st, i1)
    }
    @types.Call
    | @types.Salloc
    | @types.Copy
    | @types.Add
    | @types.Sub
    | @types.Mul
    | @types.And
    | @types.Or
    | @types.Xor
    | @types.Xtest
    | @types.Stosi
    | @types.Dtosi
    | @types.Swtof
    | @types.Sltof
    | @types.Exts
    | @types.Truncd
    | @types.Cast => sel_emit(st, i)
    @types.Alloc4 | @types.Alloc8 | @types.Alloc16 => {
      st.fn_.has_dynalloc = true
      if i.arg1.is_con() {
        let mut sz = st.fn_.cons[i.arg1.con_val()].bits.i
        sz = (sz + 15L) & -16L
        emit(
          st,
          @types.Salloc,
          @types.Kl,
          i.to,
          @types.Ref::con(st.fn_.get_con(sz)),
          @types.Ref::none(),
        )
      } else {
        let r0 = isel_newtmp(st, @types.Kl)
        let r1 = isel_newtmp(st, @types.Kl)
        emit(st, @types.Salloc, @types.Kl, i.to, r0, @types.Ref::none())
        emit(
          st,
          @types.And,
          @types.Kl,
          r0,
          r1,
          @types.Ref::con(st.fn_.get_con(-16L)),
        )
        emit(
          st,
          @types.Add,
          @types.Kl,
          r1,
          i.arg1,
          @types.Ref::con(st.fn_.get_con(15L)),
        )
      }
    }
    _ =>
      if i.op.is_ext() {
        sel_emit(st, i)
      } else if i.op.is_load() {
        let i1 = i
        i1.arg1 = seladdr(st, i1.arg1)
        sel_emit(st, i1)
      } else {
        let (is_cmp, kc, x) = iscmp(i.op)
        if is_cmp {
          emit(st, flag_op(x), k, i.to, @types.Ref::none(), @types.Ref::none())
          let idx = st.buf.length() - 1
          if selcmp(st, i.arg1, i.arg2, kc) {
            st.buf[idx].op = flag_op(cmpop(x))
          }
        } else {
          raise @util.QbeError::Ice(
            "unknown instruction \{@types.op_info(i.op).name}",
          )
        }
      }
  }
}

///|
// Find the last instruction setting the zero flag (C flagi). Returns its
// index in the block, or -1.
fn flagi(ins : Array[@types.Ins], nins : Int) -> Int {
  let mut i = nins
  while i > 0 {
    i = i - 1
    let info = @types.op_info(ins[i].op)
    if info.zf != 0 {
      return i
    }
    if info.lf != 0 {
      continue
    }
    return -1
  }
  -1
}

///|
// Select a jump (C seljmp).
fn seljmp(st : IselState, b : @types.Blk) -> Unit {
  if b.jmp.kind == @types.Jret0 || b.jmp.kind == @types.Jjmp {
    return
  }
  let r = b.jmp.arg
  let t = r.tmp_val()
  b.jmp.arg = @types.Ref::none()
  if b.jmp.s1 == b.jmp.s2 {
    chuse(st, r, -1)
    b.jmp.kind = @types.Jjmp
    b.jmp.s2 = -1
    return
  }
  let fi = flagi(b.ins, b.ins.length())
  if fi < 0 || !b.ins[fi].to.eq(r) {
    let c0 = @types.Ref::con(st.fn_.get_con(0L))
    ignore(selcmp(st, r, c0, @types.Kw))
    b.jmp.kind = jjf_op(1)
  } else {
    let (is_cmp, k, c) = iscmp(b.ins[fi].op)
    if is_cmp {
      if t >= 0 && st.fn_.tmps[t].nuse == 1 {
        let c1 = if selcmp(st, b.ins[fi].arg1, b.ins[fi].arg2, k) {
          cmpop(c)
        } else {
          c
        }
        b.ins[fi] = @types.Ins::new(
          @types.Nop,
          @types.Kx,
          @types.Ref::none(),
          @types.Ref::none(),
          @types.Ref::none(),
        )
        b.jmp.kind = jjf_op(c1)
      } else {
        b.jmp.kind = jjf_op(c)
      }
    } else if b.ins[fi].op == @types.And &&
      t >= 0 &&
      st.fn_.tmps[t].nuse == 1 &&
      (b.ins[fi].arg1.is_tmp() || b.ins[fi].arg2.is_tmp()) {
      let ins = b.ins[fi]
      ins.op = @types.Xtest
      ins.to = @types.Ref::none()
      if ins.arg2.is_con() {
        let rr = ins.arg2
        ins.arg2 = ins.arg1
        ins.arg1 = rr
      }
      b.ins[fi] = ins
      b.jmp.kind = jjf_op(1)
    } else {
      if t >= 0 && st.fn_.tmps[t].nuse == 1 {
        emit(
          st,
          @types.Copy,
          @types.Kw,
          @types.Ref::none(),
          r,
          @types.Ref::none(),
        )
      }
      b.jmp.kind = jjf_op(1)
    }
  }
}

///|
// amd64 instruction selection driver (C amd64_isel).
pub fn isel(
  fn_ : @types.Fn,
  interner : @util.Interner,
  print_dbg : Bool,
  all_typs : Array[@types.Typ],
) -> String raise {
  let st = IselState::{
    fn_,
    buf: Array::new(),
    an: Array::new(),
    cur_ins: Array::new(),
    interner,
  }

  // assign slots to fast allocs in the start block
  let start = fn_.blks[fn_.start_id]
  let sizes = [4, 8, 16]
  for s in 0..<3 {
    let n = sizes[s]
    let op = @types.Op::from_index(@types.Alloc4.index() + s)
    for idx in 0..<start.ins.length() {
      let i = start.ins[idx]
      if i.op == op {
        if !i.arg1.is_con() {
          break
        }
        let mut sz = fn_.cons[i.arg1.con_val()].bits.i
        sz = (sz + n.to_int64() - 1L) & -n.to_int64()
        sz = sz / 4L
        fn_.tmps[i.to.tmp_val()].slot = fn_.slot
        fn_.slot = fn_.slot + sz.to_int()
        start.ins[idx] = @types.Ins::new(
          @types.Nop,
          @types.Kx,
          @types.Ref::none(),
          @types.Ref::none(),
          @types.Ref::none(),
        )
      }
    }
  }

  // process basic blocks in definition order (the C link order)
  for k in 0..<fn_.def_order.length() {
    let bid = fn_.def_order[k]
    let b = fn_.blks[bid]
    st.buf.clear()
    st.cur_ins = b.ins
    // fix phi args coming from this block
    for sbid in [b.jmp.s1, b.jmp.s2] {
      if sbid >= 0 {
        let succ = fn_.blks[sbid]
        for p in succ.phi {
          let mut a = 0
          while a < p.args.length() {
            if p.args[a].blk_id == bid {
              break
            }
            a = a + 1
          }
          p.args[a].value = fixarg(st, p.args[a].value, p.cls, None)
        }
      }
    }
    st.an.clear()
    for _ in 0..<fn_.tmps.length() {
      st.an.push(ANum::new())
    }
    anumber(st, b)
    seljmp(st, b)
    let mut i = b.ins.length()
    while i > 0 {
      i = i - 1
      sel(st, b.ins[i])
    }
    let nb = emit_block(st)
    b.ins.clear()
    for x in nb {
      b.ins.push(x)
    }
  }

  if print_dbg {
    let sb = StringBuilder::new()
    sb.write_string("\n> After instruction selection:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}

///|
// The emitted instructions in block order (reverse of push order).
fn emit_block(st : IselState) -> Array[@types.Ins] {
  let r : Array[@types.Ins] = Array::new()
  for k in (st.buf.length() - 1)>=..0 {
    r.push(st.buf[k])
  }
  r
}
