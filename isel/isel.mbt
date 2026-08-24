///|
// amd64 instruction selection - corresponds to amd64/isel.c in QBE.
// Checks constants, materializes large immediates, exposes machine register
// constraints (div, shifts), assigns slots to fast allocs, and recognizes
// complex addressing modes.

///|
priv struct IselState {
  fn_ : @types.Fn
  buf : Array[@types.Ins]
  an : Array[ANum]
  mut cur_ins : Array[@types.Ins]
  interner : @util.Interner
}

///|
// Emission buffer: push, read back in reverse order (C curi/insb).
fn emit(
  st : IselState,
  op : @types.Op,
  k : @types.Class,
  to : @types.Ref,
  a0 : @types.Ref,
  a1 : @types.Ref,
) -> Unit {
  st.buf.push(@types.Ins::new(op, k, to, a0, a1))
}

///|
fn emiti(st : IselState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
fn isel_newtmp(st : IselState, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp("isel", k))
}

///|
// Adjust the use count of a temporary (C chuse).
fn chuse(st : IselState, r : @types.Ref, du : Int) -> Unit {
  if r.is_tmp() {
    st.fn_.tmps[r.tmp_val()].nuse = st.fn_.tmps[r.tmp_val()].nuse + du
  }
}

///|
// Whether r is a machine register (C isreg).
fn isreg(r : @types.Ref) -> Bool {
  r.is_tmp() && r.tmp_val() < @types.Tmp0
}

///|
fn rslot(r : @types.Ref, fn_ : @types.Fn) -> Int {
  if !r.is_tmp() {
    return -1
  }
  fn_.tmps[r.tmp_val()].slot
}

///|
fn noimm(r : @types.Ref, fn_ : @types.Fn) -> Int {
  if !r.is_con() {
    return 0
  }
  match fn_.cons[r.con_val()].kind {
    @types.CAddr => 0
    @types.CBits => {
      let val = @types.con_raw_bits(fn_.cons[r.con_val()])
      if val < -2147483648L || val > 2147483647L {
        1
      } else {
        0
      }
    }
    _ => abort("invalid constant")
  }
}

///|
// Argument class of instruction i's n-th arg (C argcls).
fn argcls(i : @types.Ins, n : Int) -> @types.Class {
  let info = @types.op_info(i.op)
  let arr = if n == 0 { info.a0 } else { info.a1 }
  let c = @types.kcode(i.cls)
  let idx = if c < 0 { 0 } else { c }
  @types.class_from_code(arr[idx])
}

///|
// Rewrite an argument so it can be used as an operand (C fixarg).
// op is the enclosing instruction, None for phi args.
fn fixarg(
  st : IselState,
  r : @types.Ref,
  k : @types.Class,
  op : @types.Op?,
) -> @types.Ref {
  let r0 = r
  let mut r1 = r0
  let s = rslot(r0, st.fn_)
  let cpy = op is None || op == Some(@types.Copy)
  let mem = op is Some(o) &&
    (@types.is_store(o) || @types.is_load(o) || o == @types.Call)
  if @types.kbase(k) == 1 && r0.is_con() {
    // load floating point constants from memory slots
    let n = st.fn_.mems.length()
    let bits = @types.con_raw_bits(st.fn_.cons[r0.con_val()])
    let nfp = @types.gasstash(
      bits,
      0L,
      if @types.kwide(k) == 1 {
        8
      } else {
        4
      },
    )
    let label = st.interner.intern("fp\{nfp}")
    let a = @types.Addr::new()
    a.offset = @types.Con::{
      kind: @types.CAddr,
      label,
      bits: @types.ConBits::{ i: 0L, d: 0.0, s: 0.0 },
      flt: 0,
      is_local: true,
    }
    st.fn_.mems.push(a)
    r1 = @types.Ref::mem(n)
  } else if !cpy && k == @types.Kl && noimm(r0, st.fn_) != 0 {
    // load constants that do not fit in a 32bit signed integer
    r1 = isel_newtmp(st, @types.Kl)
    emit(st, @types.Copy, @types.Kl, r1, r0, @types.ref_none())
  } else if s != -1 {
    // load fast locals' addresses into temporaries
    r1 = isel_newtmp(st, @types.Kl)
    emit(st, @types.Addr, @types.Kl, r1, @types.Ref::slot(s), @types.ref_none())
  } else if !mem &&
    r0.is_con() &&
    st.fn_.cons[r0.con_val()].kind == @types.CAddr {
    // apple asm fix
    r1 = isel_newtmp(st, @types.Kl)
    emit(st, @types.Addr, @types.Kl, r1, r0, @types.ref_none())
  } else if r0.is_mem() {
    // apple asm fix: materialize a memory base when it is empty
    let m = st.fn_.mems[r0.mem_val()]
    if m.base.is_none() {
      let n = st.fn_.cons.length()
      st.fn_.cons.push(m.offset)
      let r0 = isel_newtmp(st, @types.Kl)
      emit(
        st,
        @types.Addr,
        @types.Kl,
        r0,
        @types.Ref::con(n),
        @types.ref_none(),
      )
      m.base = r0
      m.offset = @types.Con::new()
    }
  }
  r1
}

///|
// Recognize complex addressing modes (C seladdr).
fn seladdr(st : IselState, r : @types.Ref) -> @types.Ref {
  let r0 = r
  if r0.is_tmp() {
    let av = @types.Addr::new()
    amatch(st, av, r0, true)
    if @types.req(av.base, r0) {
      return r0
    }
    if av.offset.kind == @types.CAddr {
      if !av.base.is_none() {
        // apple asm fix
        if !av.index.is_none() {
          return r0
        } else {
          av.index = av.base
          av.scale = 1
          av.base = @types.ref_none()
        }
      }
    }
    chuse(st, r0, -1)
    let n = st.fn_.mems.length()
    st.fn_.mems.push(av)
    chuse(st, av.base, 1)
    chuse(st, av.index, 1)
    return @types.Ref::mem(n)
  }
  r0
}
