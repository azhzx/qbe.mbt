///|
// ARM64 (AArch64) instruction selection.
// Ported 1:1 from vendor/qbe/arm64/isel.c (the reference snapshot): the
// comparison lowering folds 12-bit immediates into cmp/cmn, everything else
// is emitted verbatim with operands fixed by fixarg.

///|
// Immediate classification for comparisons (C enum Imm in arm64/isel.c).
const ARM64_ImmIother : Int = 0

///|
const ARM64_Iplo12 : Int = 1

///|
const ARM64_Iphi12 : Int = 2

///|
const ARM64_Inlo12 : Int = 4

///|
const ARM64_Inhi12 : Int = 5

///|
// ARM64 instruction selection state
priv struct Arm64IselState {
  fn_ : @types.Fn
  buf : Array[@types.Ins]
  interner : @util.Interner
}

///|
fn arm64_isel_new(fn_ : @types.Fn, interner : @util.Interner) -> Arm64IselState {
  Arm64IselState::{ fn_, buf: [], interner, }
}

///|
fn arm64_isel_emit(st : Arm64IselState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
fn arm64_isel_emit_block(st : Arm64IselState) -> Array[@types.Ins] {
  // the buffer is filled in C emit() order (reverse program order)
  let r : Array[@types.Ins] = []
  for k in (st.buf.length() - 1)>=..0 {
    r.push(st.buf[k])
  }
  r
}

///|
fn arm64_isel_newtmp(st : Arm64IselState, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp("isel", k))
}

///|
fn arm64_isel_getcon(st : Arm64IselState, v : Int64) -> @types.Ref {
  @types.Ref::con(st.fn_.get_con(v))
}

///|
// Argument class of instruction i's n-th arg (C argcls).
fn arm64_argcls(i : @types.Ins, n : Int) -> @types.Class {
  let info = @types.op_info(i.op)
  let arr = if n == 0 { info.a0 } else { info.a1 }
  let c = i.cls.code()
  let idx = if c < 0 { 0 } else { c }
  @types.Class::from_code(arr[idx])
}

///|
// Whether op is a comparison; returns (ok, class, comparison code)
// (shared C iscmp, mirrored from isel/cmp.mbt).
fn arm64_iscmp(op : @types.Op) -> (Bool, @types.Class, Int) {
  let i = op.index()
  let w = @types.Ceqw.index()
  let l = @types.Ceql.index()
  let s = @types.Ceqs.index()
  let d = @types.Ceqd.index()
  if i >= w && i <= w + 9 {
    (true, @types.Kw, i - w)
  } else if i >= l && i <= l + 9 {
    (true, @types.Kl, i - l)
  } else if i >= s && i <= s + 7 {
    (true, @types.Ks, 10 + (i - s))
  } else if i >= d && i <= d + 7 {
    (true, @types.Kd, 10 + (i - d))
  } else {
    (false, @types.Kx, 0)
  }
}

///|
// The swap version of a comparison code (C cmpop).
fn arm64_cmpop(c : Int) -> Int {
  // CIEQ=0, CINE=1, CISGE=2, CISGT=3, CISLE=4, CISLT=5,
  // CIUGE=6, CIUGT=7, CIULE=8, CIULT=9; NCmpI(10)+: Cfle, Cflt, Cfgt, Cfge,
  // Cfne, Cfeq, Cfo, Cfuo
  match c {
    8 => 6 // CIULE -> CIUGE
    9 => 7 // CIULT -> CIUGT
    7 => 9 // CIUGT -> CIULT
    6 => 8 // CIUGE -> CIULE
    4 => 2 // CISLE -> CISGE
    5 => 3 // CISLT -> CISGT
    3 => 5 // CISGT -> CISLT
    2 => 4 // CISGE -> CISLE
    10 => 13 // Cfle -> Cfge
    11 => 12 // Cflt -> Cfgt
    12 => 11 // Cfgt -> Cflt
    13 => 10 // Cfge -> Cfle
    16 => 17 // Cfo -> Cfuo
    17 => 16 // Cfuo -> Cfo
    _ => 0 // eq/ne are self-inverse
  }
}

///|
// The flag-setting op for a comparison code (C Oflag + x).
fn arm64_flag_op(x : Int) -> @types.Op {
  @types.Op::from_index(@types.Flagieq.index() + x)
}

///|
// The conditional jump kind for a comparison code (C Jjf + x).
fn arm64_jjf_op(x : Int) -> @types.JumpKind {
  @types.JumpKind::from_index(@types.Jjfieq.index() + x)
}

///|
// Classify a constant as an encodable cmp/cmn immediate
// (C imm in arm64/isel.c). Returns (kind, magnitude).
fn arm64_imm(c : @types.Con, k : @types.Class) -> (Int, Int64) {
  if c.kind != @types.CBits {
    return (ARM64_ImmIother, 0L)
  }
  let mut n = c.bits.i
  if k == @types.Kw {
    // C: n = (int32_t)n — truncate to the low 32 bits, sign-extended
    n = n.to_int().to_int64()
  }
  let mut kind = ARM64_Iplo12
  if n < 0L {
    kind = ARM64_Inlo12
    n = -n
  }
  if (n & 0x000fffL) == n {
    (kind, n)
  } else if (n & 0xfff000L) == n {
    (kind + 1, n)
  } else if (n & 0xffffffL) == n {
    (kind + 2, n)
  } else {
    (ARM64_ImmIother, n)
  }
}

///|
// Rewrite an argument so it can be used as an operand
// (C fixarg in arm64/isel.c). phi marks phi arguments, where integer
// constants are left in place.
fn arm64_fixarg(
  st : Arm64IselState,
  r : @types.Ref,
  k : @types.Class,
  phi : Bool,
) -> @types.Ref raise {
  let r0 = r
  if r0.is_con() {
    let c = st.fn_.cons[r0.con_val()]
    if k.base() == 0 && phi {
      return r0
    }
    let r1 = arm64_isel_newtmp(st, k)
    if k.base() == 0 {
      arm64_isel_emit(
        st,
        @types.Ins::new(@types.Copy, k, r1, r0, @types.Ref::none()),
      )
    } else {
      // float constants are loaded from the rodata stash
      let bits = c.raw_bits()
      let nfp = @types.gasstash(bits, 0L, if k.wide() == 1 { 8 } else { 4 })
      let label = st.interner.intern("fp\{nfp}")
      let caddr = @types.Con::{
        kind: @types.CAddr,
        label,
        bits: @types.ConBits::{ i: 0L, d: 0.0, s: 0.0, },
        flt: 0,
        is_local: true,
      }
      let idx = st.fn_.cons.length()
      st.fn_.cons.push(caddr)
      let r2 = arm64_isel_newtmp(st, @types.Kl)
      arm64_isel_emit(
        st,
        @types.Ins::new(@types.Load, k, r1, r2, @types.Ref::none()),
      )
      arm64_isel_emit(
        st,
        @types.Ins::new(
          @types.Copy,
          @types.Kl,
          r2,
          @types.Ref::con(idx),
          @types.Ref::none(),
        ),
      )
    }
    return r1
  }
  if r0.is_tmp() {
    let s = st.fn_.tmps[r0.tmp_val()].slot
    if s == -1 {
      return r0
    }
    let r1 = arm64_isel_newtmp(st, @types.Kl)
    arm64_isel_emit(
      st,
      @types.Ins::new(
        @types.Addr,
        @types.Kl,
        r1,
        @types.Ref::slot(s),
        @types.Ref::none(),
      ),
    )
    return r1
  }
  r0
}

///|
// Emit a comparison; folds small immediates, swaps constant operands
// (C selcmp in arm64/isel.c). Returns true when the operands were swapped
// (the caller must negate the condition).
fn arm64_selcmp(
  st : Arm64IselState,
  a0 : @types.Ref,
  a1 : @types.Ref,
  k : @types.Class,
) -> Bool raise {
  if k.base() == 1 {
    arm64_isel_emit(
      st,
      @types.Ins::new(@types.Afcmp, k, @types.Ref::none(), a0, a1),
    )
    let idx = st.buf.length() - 1
    st.buf[idx].arg1 = arm64_fixarg(st, st.buf[idx].arg1, k, false)
    st.buf[idx].arg2 = arm64_fixarg(st, st.buf[idx].arg2, k, false)
    return false
  }
  let swap = a0.is_con()
  let mut arg0 = a0
  let mut arg1 = a1
  if swap {
    arg0 = a1
    arg1 = a0
  }
  let mut fix = true
  let mut cmp = @types.Acmp
  let mut r = arg1
  if r.is_con() {
    let (kind, n) = arm64_imm(st.fn_.cons[r.con_val()], k)
    if kind == ARM64_Iplo12 || kind == ARM64_Iphi12 {
      fix = false
    } else if kind == ARM64_Inlo12 || kind == ARM64_Inhi12 {
      cmp = @types.Acmn
      r = arm64_isel_getcon(st, n)
      fix = false
    }
  }
  arm64_isel_emit(st, @types.Ins::new(cmp, k, @types.Ref::none(), arg0, r))
  let idx = st.buf.length() - 1
  st.buf[idx].arg1 = arm64_fixarg(st, st.buf[idx].arg1, k, false)
  if fix {
    st.buf[idx].arg2 = arm64_fixarg(st, st.buf[idx].arg2, k, false)
  }
  swap
}

///|
// Whether a call target can be used directly (C callable in arm64/isel.c):
// register temps and address constants with zero offset.
fn arm64_callable(r : @types.Ref, fn_ : @types.Fn) -> Bool {
  if r.is_tmp() {
    return true
  }
  if r.is_con() {
    let c = fn_.cons[r.con_val()]
    if c.kind == @types.CAddr && c.bits.i == 0L {
      return true
    }
  }
  false
}

///|
// Select one instruction (C sel in arm64/isel.c).
fn arm64_sel(st : Arm64IselState, i : @types.Ins) -> Unit raise {
  let (is_cmp, ck, cc) = arm64_iscmp(i.op)
  if is_cmp {
    // emit the flag op with condition code 0, then adjust the code
    arm64_isel_emit(
      st,
      @types.Ins::new(
        arm64_flag_op(0),
        i.cls,
        i.to,
        @types.Ref::none(),
        @types.Ref::none(),
      ),
    )
    let idx = st.buf.length() - 1
    if arm64_selcmp(st, i.arg1, i.arg2, ck) {
      st.buf[idx].op = arm64_flag_op(arm64_cmpop(cc))
    } else {
      st.buf[idx].op = arm64_flag_op(cc)
    }
    return
  }
  if i.op == @types.Alloc4 || i.op == @types.Alloc8 || i.op == @types.Alloc16 {
    // C arm64/isel.c sel(): dynamic allocs lower via salloc().
    st.fn_.has_dynalloc = true
    let r0 = arm64_isel_newtmp(st, @types.Kl)
    let r1 = arm64_isel_newtmp(st, @types.Kl)
    let m16 = arm64_isel_getcon(st, -16L)
    let c15 = arm64_isel_getcon(st, 15L)
    arm64_isel_emit(
      st,
      @types.Ins::new(@types.Salloc, @types.Kl, i.to, r0, @types.Ref::none()),
    )
    arm64_isel_emit(st, @types.Ins::new(@types.And, @types.Kl, r0, r1, m16))
    arm64_isel_emit(st, @types.Ins::new(@types.Add, @types.Kl, r1, i.arg1, c15))
    let aidx = st.buf.length() - 1
    st.buf[aidx].arg1 = arm64_fixarg(st, st.buf[aidx].arg1, @types.Kl, false)
    return
  }
  if i.op == @types.Call && arm64_callable(i.arg1, st.fn_) {
    arm64_isel_emit(st, i)
    return
  }
  if i.op != @types.Nop {
    arm64_isel_emit(st, i)
    let idx = st.buf.length() - 1
    // fixarg() can invalidate the index by pushing new instructions
    let iarg0 = st.buf[idx].arg1
    let iarg1 = st.buf[idx].arg2
    st.buf[idx].arg1 = arm64_fixarg(st, iarg0, arm64_argcls(i, 0), false)
    st.buf[idx].arg2 = arm64_fixarg(st, iarg1, arm64_argcls(i, 1), false)
  }
}

///|
// Lower a block's terminator (C seljmp in arm64/isel.c): a comparison whose
// only use is the branch becomes a flags-based conditional jump.
fn arm64_seljmp(st : Arm64IselState, b : @types.Blk) -> Unit raise {
  match b.jmp.kind {
    @types.Jret0 | @types.Jjmp => return
    @types.Jjnz => ()
    _ => return
  }
  let r = b.jmp.arg
  b.jmp.arg = @types.Ref::none()
  let mut found = -1
  let mut use_count = -1
  for k in (b.ins.length() - 1)>=..0 {
    if b.ins[k].to.is_tmp() && b.ins[k].to.eq(r) {
      use_count = st.fn_.tmps[r.tmp_val()].nuse
      found = k
      break
    }
  }
  if found >= 0 && use_count == 1 {
    let (is_cmp, ck, cc) = arm64_iscmp(b.ins[found].op)
    if is_cmp {
      let mut ncc = cc
      if arm64_selcmp(st, b.ins[found].arg1, b.ins[found].arg2, ck) {
        ncc = arm64_cmpop(cc)
      }
      b.jmp.kind = arm64_jjf_op(ncc)
      b.ins[found] = @types.Ins::new(
        @types.Nop,
        @types.Kx,
        @types.Ref::none(),
        @types.Ref::none(),
        @types.Ref::none(),
      )
      return
    }
  }
  let _ = arm64_selcmp(st, r, arm64_isel_getcon(st, 0L), @types.Kw)
  b.jmp.kind = @types.Jjfine
}

///|
// ARM64 instruction selection driver (C arm64_isel).
pub fn isel_arm64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  print_dbg : Bool,
  all_typs : Array[@types.Typ],
) -> String raise {
  let st = arm64_isel_new(fn_, interner)
  let _ = all_typs
  // assign slots to fast allocs in the start block (NAlign == 3)
  let sizes = [4, 8, 16]
  for s in 0..<3 {
    let n = sizes[s]
    let op = @types.Op::from_index(@types.Alloc4.index() + s)
    let start = fn_.blks[fn_.start_id]
    for idx in 0..<start.ins.length() {
      let i = start.ins[idx]
      if i.op == op {
        if !i.arg1.is_con() {
          break
        }
        let mut sz = fn_.cons[i.arg1.con_val()].bits.i
        if sz < 0L || sz >= 2147483632L {
          raise @util.QbeError::Ice("invalid alloc size \{sz}")
        }
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
  for bid in fn_.def_order {
    let b = fn_.blks[bid]
    st.buf.clear()
    // fix phi arguments coming from this block
    for sbid in [b.jmp.s1, b.jmp.s2] {
      if sbid >= 0 {
        let succ = fn_.blks[sbid]
        for p in succ.phi {
          for a in 0..<p.args.length() {
            if p.args[a].blk_id == bid {
              p.args[a].value = arm64_fixarg(st, p.args[a].value, p.cls, true)
            }
          }
        }
      }
    }
    arm64_seljmp(st, b)
    for k in (b.ins.length() - 1)>=..0 {
      arm64_sel(st, b.ins[k])
    }
    let nb = arm64_isel_emit_block(st)
    b.ins.clear()
    for x in nb {
      b.ins.push(x)
    }
  }
  if print_dbg {
    let sb = StringBuilder()
    sb.write_string("\n> After instruction selection:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}
