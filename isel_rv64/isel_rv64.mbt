///|
// RISC-V 64 (rv64) instruction selection - corresponds to rv64/isel.c in QBE.
// Checks constants, materializes large immediates, exposes machine register
// constraints, assigns slots to fast allocs.

///|
// RISC-V instruction selection state
priv struct Rv64IselState {
  fn_ : @types.Fn
  buf : Array[@types.Ins]
  interner : @util.Interner
}

///|
fn rv64_isel_new(fn_ : @types.Fn, interner : @util.Interner) -> Rv64IselState {
  Rv64IselState::{ fn_, buf: Array::new(), interner, }
}

///|
fn rv64_isel_emit(st : Rv64IselState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
// Emission buffer: push, read back in reverse order (C curi/insb).
fn emit(
  st : Rv64IselState,
  op : @types.Op,
  k : @types.Class,
  to : @types.Ref,
  a0 : @types.Ref,
  a1 : @types.Ref,
) -> Unit {
  st.buf.push(@types.Ins::new(op, k, to, a0, a1))
}

///|
fn emiti(st : Rv64IselState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
fn rv64_isel_newtmp(st : Rv64IselState, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp("isel", k))
}

///|
// Whether r is a machine register (C isreg).
fn isreg(r : @types.Ref) -> Bool {
  r.is_tmp() && r.tmp_val() < @types.Rv64Tmp0
}

///|
fn rslot(r : @types.Ref, fn_ : @types.Fn) -> Int {
  if !r.is_tmp() {
    return -1
  }
  fn_.tmps[r.tmp_val()].slot
}

///|
// Check if a constant is too large for RISC-V immediate (C noimm).
fn noimm(r : @types.Ref, fn_ : @types.Fn) -> Int {
  if !r.is_con() {
    return 0
  }
  match fn_.cons[r.con_val()].kind {
    @types.CAddr => 0
    @types.CBits => {
      let val = fn_.cons[r.con_val()].raw_bits()
      if val < -2048L || val > 2047L {
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
  let c = i.cls.code()
  let idx = if c < 0 { 0 } else { c }
  @types.Class::from_code(arr[idx])
}

///|
// Rewrite an argument so it can be used as an operand (C fixarg).
// op is the enclosing instruction, None for phi args.
fn fixarg(
  st : Rv64IselState,
  r : @types.Ref,
  k : @types.Class,
  op : @types.Op?,
) -> @types.Ref {
  let r0 = r
  let mut r1 = r0
  let s = rslot(r0, st.fn_)
  let cpy = op is None || op == Some(@types.Copy)
  let mem = op is Some(o) && (o.is_store() || o.is_load() || o == @types.Call)

  if k.base() == 1 && r0.is_con() {
    // Load floating point constants from memory slots
    let n = st.fn_.mems.length()
    let bits = st.fn_.cons[r0.con_val()].raw_bits()
    let nfp = @types.gasstash(bits, 0L, if k.wide() == 1 { 8 } else { 4 })
    let label = st.interner.intern("fp\{nfp}")
    let a = @types.Addr::new()
    a.offset = @types.Con::{
      kind: @types.CAddr,
      label,
      bits: @types.ConBits::{ i: 0L, d: 0.0, s: 0.0, },
      flt: 0,
      is_local: true,
    }
    st.fn_.mems.push(a)
    r1 = @types.Ref::mem(n)
  } else if !cpy && k == @types.Kl && noimm(r0, st.fn_) != 0 {
    // Load constants that do not fit in a 12-bit signed integer
    r1 = rv64_isel_newtmp(st, @types.Kl)
    emit(st, @types.Copy, @types.Kl, r1, r0, @types.Ref::none())
  } else if s != -1 {
    // Load fast locals' addresses into temporaries
    r1 = rv64_isel_newtmp(st, @types.Kl)
    emit(
      st,
      @types.Addr,
      @types.Kl,
      r1,
      @types.Ref::slot(s),
      @types.Ref::none(),
    )
  } else if !mem &&
    r0.is_con() &&
    st.fn_.cons[r0.con_val()].kind == @types.CAddr {
    // Materialize address constant
    r1 = rv64_isel_newtmp(st, @types.Kl)
    emit(st, @types.Addr, @types.Kl, r1, r0, @types.Ref::none())
  } else if r0.is_mem() {
    // Materialize a memory base when it is empty
    let m = st.fn_.mems[r0.mem_val()]
    if m.base.is_none() {
      let n = st.fn_.cons.length()
      st.fn_.cons.push(m.offset)
      let r0 = rv64_isel_newtmp(st, @types.Kl)
      emit(
        st,
        @types.Addr,
        @types.Kl,
        r0,
        @types.Ref::con(n),
        @types.Ref::none(),
      )
      m.base = r0
      m.offset = @types.Con::new()
    }
  }
  r1
}

///|
// Emit an instruction and fix its arguments (C Emit label in sel).
fn sel_emit(st : Rv64IselState, i : @types.Ins) -> Unit {
  emiti(st, i)
  let idx = st.buf.length() - 1
  st.buf[idx].arg1 = fixarg(st, st.buf[idx].arg1, argcls(i, 0), Some(i.op))
  st.buf[idx].arg2 = fixarg(st, st.buf[idx].arg2, argcls(i, 1), Some(i.op))
}

///|
// Select a single instruction (C sel).
fn sel(st : Rv64IselState, i : @types.Ins) -> Unit raise {
  if i.to.is_tmp() {
    if !isreg(i.to) && !isreg(i.arg1) && !isreg(i.arg2) {
      if st.fn_.tmps[i.to.tmp_val()].nuse == 0 {
        return
      }
    }
  }

  match i.op {
    // RISC-V uses different divide/remainder instructions
    @types.Div | @types.Rem | @types.Udiv | @types.Urem =>
      // RISC-V has native divide/remainder instructions
      sel_emit(st, i)
    // RISC-V has flexible shift instructions
    @types.Sar | @types.Shr | @types.Shl => sel_emit(st, i)
    // Memory operations
    @types.Stored
    | @types.Stores
    | @types.Storel
    | @types.Storew
    | @types.Storeh
    | @types.Storeb => {
      let i1 = i
      sel_emit(st, i1)
    }
    // Direct passthrough for most instructions
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
    | @types.Cast
    | @types.Extsb
    | @types.Extub
    | @types.Extsh
    | @types.Extuh
    | @types.Extsw
    | @types.Extuw => sel_emit(st, i)
    // Stack allocation
    @types.Alloc4 | @types.Alloc8 | @types.Alloc16 => {
      st.fn_.has_dynalloc = true
      if i.arg1.is_con() {
        let mut sz = st.fn_.cons[i.arg1.con_val()].raw_bits()
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
        let r0 = rv64_isel_newtmp(st, @types.Kl)
        let r1 = rv64_isel_newtmp(st, @types.Kl)
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
          r0,
          @types.Ref::con(st.fn_.get_con(15L)),
        )
      }
    }
    // Comparisons - RISC-V uses slt/sltu instructions
    @types.Ceqw
    | @types.Cnew
    | @types.Csgew
    | @types.Csgtw
    | @types.Cslew
    | @types.Csltw
    | @types.Cugew
    | @types.Cugtw
    | @types.Culew
    | @types.Cultw
    | @types.Ceql
    | @types.Cnel
    | @types.Csgel
    | @types.Csgtl
    | @types.Cslel
    | @types.Csltl
    | @types.Cugel
    | @types.Cugtl
    | @types.Culel
    | @types.Cultl =>
      // Integer comparisons
      sel_emit(st, i)
    // Floating point comparisons
    @types.Ceqs
    | @types.Cges
    | @types.Cgts
    | @types.Cles
    | @types.Clts
    | @types.Cnes
    | @types.Cos
    | @types.Cuos
    | @types.Ceqd
    | @types.Cged
    | @types.Cgtd
    | @types.Cled
    | @types.Cltd
    | @types.Cned
    | @types.Cod
    | @types.Cuod => sel_emit(st, i)
    // Load operations
    @types.Load
    | @types.Loadsb
    | @types.Loadub
    | @types.Loadsh
    | @types.Loaduh
    | @types.Loadsw
    | @types.Loaduw => sel_emit(st, i)
    // No-op
    @types.Nop => ()
    // Internal ops - skip (amd64-specific)
    @types.Swap
    | @types.Sign
    | @types.Xidiv
    | @types.Xdiv
    | @types.Xcmp
    | @types.Acmp
    | @types.Acmn
    | @types.Afcmp
    | @types.Addr => ()
    // Flag-setting ops - skip (RISC-V doesn't use flags)
    @types.Flagieq
    | @types.Flagine
    | @types.Flagisge
    | @types.Flagisgt
    | @types.Flagisle
    | @types.Flagislt
    | @types.Flagiuge
    | @types.Flagiugt
    | @types.Flagiule
    | @types.Flagiult
    | @types.Flagfeq
    | @types.Flagfne
    | @types.Flagfge
    | @types.Flagfgt
    | @types.Flagfle
    | @types.Flagflt
    | @types.Flagfo
    | @types.Flagfuo => ()
    // Vararg ops
    @types.Vaarg | @types.Vastart => ()
    // Parameter/argument ops - handled by abi_rv64
    @types.Par
    | @types.Parc
    | @types.Pare
    | @types.Arg
    | @types.Argc
    | @types.Arge => ()
    // Variadic call - handled by abi_rv64
    @types.Vacall => ()
    // Error/placeholder
    @types.Oxxx => ()
  }
}

///|
// Select a jump instruction (C seljmp).
fn seljmp(st : Rv64IselState, bid : Int) -> Unit {
  let b = st.fn_.blks[bid]
  // RISC-V uses conditional branches directly
  if b.jmp.kind == @types.Jjnz {
    let arg = b.jmp.arg
    b.jmp.arg = fixarg(st, arg, @types.Kw, None)
  }
}

///|
// Main RISC-V instruction selection entry point.
pub fn isel_rv64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  print_dbg : Bool,
  all_typs : Array[@types.Typ],
) -> String raise {
  let st = rv64_isel_new(fn_, interner)

  // Assign slots to fast allocs
  let start = fn_.blks[fn_.start_id]
  for i in 0..<start.ins.length() {
    let ins = start.ins[i]
    if ins.op == @types.Alloc4 ||
      ins.op == @types.Alloc8 ||
      ins.op == @types.Alloc16 {
      if ins.arg1.is_con() {
        let mut sz = fn_.cons[ins.arg1.con_val()].raw_bits()
        let n = if ins.op == @types.Alloc4 {
          4
        } else if ins.op == @types.Alloc8 {
          8
        } else {
          16
        }
        sz = (sz + n.to_int64() - 1L) & (-n).to_int64()
        sz = sz / 4
        if sz > 2147483647L - fn_.slot.to_int64() {
          abort("alloc too large")
        }
        fn_.tmps[ins.to.tmp_val()].slot = fn_.slot
        fn_.slot = fn_.slot + sz.to_int()
        start.ins[i] = @types.Ins::new_void(
          @types.Nop,
          ins.cls,
          @types.Ref::none(),
          @types.Ref::none(),
        )
      }
    }
  }

  // Process all blocks
  for bid in fn_.def_order {
    let blk = fn_.blks[bid]

    // Fix phi arguments
    for sbid in [blk.jmp.s1, blk.jmp.s2] {
      if sbid >= 0 {
        let succ = fn_.blks[sbid]
        for phi in succ.phi {
          for arg in phi.args {
            if arg.blk_id == bid {
              arg.value = fixarg(st, arg.value, phi.cls, None)
            }
          }
        }
      }
    }

    // Select jump
    seljmp(st, bid)

    // Select instructions
    for i in 0..<blk.ins.length() {
      sel(st, blk.ins[i])
    }
  }

  if print_dbg {
    let out = StringBuilder::new()
    out.write_string("> After RISC-V instruction selection:\n")
    out.to_string()
  } else {
    ""
  }
}
