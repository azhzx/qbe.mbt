///|
// LoongArch 64 (la64) instruction selection - corresponds to a hypothetical
// upstream loongarch64/isel.c. Checks constants, materializes large
// immediates, lowers comparisons to slt/sltu sequences (LoongArch has no
// flags register), and assigns slots to fast allocs.
//
// The driver follows the amd64 pattern: blocks are processed with
// instructions in reverse order and the selection buffer is written back
// reversed, so helper instructions emitted during argument fixing end up
// before their consumers.

///|
// LoongArch instruction selection state
priv struct La64IselState {
  fn_ : @types.Fn
  buf : Array[@types.Ins]
  interner : @util.Interner
}

///|
fn la64_isel_new(fn_ : @types.Fn, interner : @util.Interner) -> La64IselState {
  La64IselState::{ fn_, buf: Array::new(), interner, }
}

///|
// Emission buffer: push, read back in reverse order (C curi/insb).
fn emit(
  st : La64IselState,
  op : @types.Op,
  k : @types.Class,
  to : @types.Ref,
  a0 : @types.Ref,
  a1 : @types.Ref,
) -> Unit {
  st.buf.push(@types.Ins::new(op, k, to, a0, a1))
}

///|
fn emiti(st : La64IselState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
// The emitted instructions in block order (reverse of push order).
fn emit_block(st : La64IselState) -> Array[@types.Ins] {
  let r : Array[@types.Ins] = Array::new()
  for k in (st.buf.length() - 1)>=..0 {
    r.push(st.buf[k])
  }
  r
}

///|
fn la64_isel_newtmp(st : La64IselState, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(st.fn_.new_tmp("isel", k))
}

///|
// Whether r is a machine register (C isreg).
fn isreg(r : @types.Ref) -> Bool {
  r.is_tmp() && r.tmp_val() < @types.La64Tmp0
}

///|
fn rslot(r : @types.Ref, fn_ : @types.Fn) -> Int {
  if !r.is_tmp() {
    return -1
  }
  fn_.tmps[r.tmp_val()].slot
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
//
// Differences from the rv64 port:
// - floating point constants are stashed AND loaded into a fresh FPR temp
//   right away, so no dangling RMem refs reach the emitter;
// - integer constants are materialized into registers for every non-Copy
//   operation: LoongArch ALU/compare instructions have no immediate forms
//   the emitter can rely on;
// - the helper instruction is emitted after the (already pushed) parent,
//   which the reversed write-back turns into correct order.
fn fixarg(
  st : La64IselState,
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
    // Load floating point constants from the stash into an FPR temp
    let bits = st.fn_.cons[r0.con_val()].raw_bits()
    let nfp = @types.gasstash(bits, 0L, if k.wide() == 1 { 8 } else { 4 })
    let label = st.interner.intern("fp\{nfp}")
    let n = st.fn_.mems.length()
    let a = @types.Addr::new()
    a.offset = @types.Con::{
      kind: @types.CAddr,
      label,
      bits: @types.ConBits::{ i: 0L, d: 0.0, s: 0.0, },
      flt: 0,
      is_local: true,
    }
    st.fn_.mems.push(a)
    let fpr = la64_isel_newtmp(st, k)
    emit(st, @types.Load, k, fpr, @types.Ref::mem(n), @types.Ref::none())
    r1 = fpr
  } else if !cpy &&
    r0.is_con() &&
    st.fn_.cons[r0.con_val()].kind == @types.CBits {
    // Materialize integer constants: ALU/compare instructions are
    // register-register only (Copy handles constants itself via li.d)
    r1 = la64_isel_newtmp(st, k)
    emit(st, @types.Copy, k, r1, r0, @types.Ref::none())
  } else if s != -1 {
    // Load fast locals' addresses into temporaries
    r1 = la64_isel_newtmp(st, @types.Kl)
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
    // Materialize address constants (la.local needs a register)
    r1 = la64_isel_newtmp(st, @types.Kl)
    emit(st, @types.Addr, @types.Kl, r1, r0, @types.Ref::none())
  } else if r0.is_mem() {
    // Materialize a memory base when it is empty
    let m = st.fn_.mems[r0.mem_val()]
    if m.base.is_none() {
      let n = st.fn_.cons.length()
      st.fn_.cons.push(m.offset)
      let r2 = la64_isel_newtmp(st, @types.Kl)
      emit(
        st,
        @types.Addr,
        @types.Kl,
        r2,
        @types.Ref::con(n),
        @types.Ref::none(),
      )
      m.base = r2
      m.offset = @types.Con::new()
    }
  }
  r1
}

///|
// Emit an instruction and fix its arguments (C Emit label in sel).
fn sel_emit(st : La64IselState, i : @types.Ins) -> Unit {
  emiti(st, i)
  let idx = st.buf.length() - 1
  st.buf[idx].arg1 = fixarg(st, st.buf[idx].arg1, argcls(i, 0), Some(i.op))
  st.buf[idx].arg2 = fixarg(st, st.buf[idx].arg2, argcls(i, 1), Some(i.op))
}

///|
// Select an integer comparison, lowering it to slt/sltu + xor sequences.
// Each sequence is pushed in reverse (the write-back reverses the buffer),
// so helper instructions emitted while fixing the compare land before it.
fn sel_int_cmp(st : La64IselState, i : @types.Ins) -> Unit {
  let to = i.to
  let con1 = @types.Ref::con(st.fn_.get_con(1L))
  let con0 = @types.Ref::con(st.fn_.get_con(0L))
  // Fix the compare's args at buffer index `idx` (helpers precede it after
  // the reversed write-back).
  fn fix_cmp(st : La64IselState, idx : Int, i : @types.Ins) -> Unit {
    st.buf[idx].arg1 = fixarg(st, st.buf[idx].arg1, argcls(i, 0), Some(i.op))
    st.buf[idx].arg2 = fixarg(st, st.buf[idx].arg2, argcls(i, 1), Some(i.op))
  }

  match i.op {
    // a < b (signed/unsigned), direct. Word compares are rewritten to their
    // long forms: QBE keeps Kw values sign-extended in registers and the
    // emitter only maps the long opcodes.
    @types.Csltl | @types.Csltw =>
      emit(st, @types.Csltl, @types.Kw, to, i.arg1, i.arg2)
    @types.Cultl | @types.Cultw =>
      emit(st, @types.Cultl, @types.Kw, to, i.arg1, i.arg2)
    // a >= b  ==  !(a < b)
    @types.Csgel | @types.Csgew | @types.Cugel | @types.Cugew => {
      let lt = if i.op is (@types.Csgel | @types.Csgew) {
        @types.Csltl
      } else {
        @types.Cultl
      }
      let r = la64_isel_newtmp(st, @types.Kw)
      let one = la64_isel_newtmp(st, @types.Kl)
      emit(st, @types.Xor, @types.Kw, to, r, one)
      emit(st, lt, @types.Kw, r, i.arg1, i.arg2)
      emit(st, @types.Copy, @types.Kl, one, con1, @types.Ref::none())
      fix_cmp(st, st.buf.length() - 2, i)
    }
    // a > b  ==  b < a
    @types.Csgtl | @types.Csgtw | @types.Cugtl | @types.Cugtw => {
      let lt = if i.op is (@types.Csgtl | @types.Csgtw) {
        @types.Csltl
      } else {
        @types.Cultl
      }
      emit(st, lt, @types.Kw, to, i.arg2, i.arg1)
      fix_cmp(st, st.buf.length() - 1, i)
    }
    // a <= b  ==  !(b < a)
    @types.Cslel | @types.Cslew | @types.Culel | @types.Culew => {
      let lt = if i.op is (@types.Cslel | @types.Cslew) {
        @types.Csltl
      } else {
        @types.Cultl
      }
      let r = la64_isel_newtmp(st, @types.Kw)
      let one = la64_isel_newtmp(st, @types.Kl)
      emit(st, @types.Xor, @types.Kw, to, r, one)
      emit(st, lt, @types.Kw, r, i.arg2, i.arg1)
      emit(st, @types.Copy, @types.Kl, one, con1, @types.Ref::none())
      fix_cmp(st, st.buf.length() - 2, i)
    }
    // a == b  ==  (a ^ b) <u 1
    @types.Ceql | @types.Ceqw => {
      let r = la64_isel_newtmp(st, @types.Kl)
      let one = la64_isel_newtmp(st, @types.Kl)
      emit(st, @types.Cultl, @types.Kw, to, r, one)
      emit(st, @types.Xor, @types.Kl, r, i.arg1, i.arg2)
      emit(st, @types.Copy, @types.Kl, one, con1, @types.Ref::none())
      fix_cmp(st, st.buf.length() - 2, i)
    }
    // a != b  ==  0 <u (a ^ b)
    @types.Cnel | @types.Cnew => {
      let r = la64_isel_newtmp(st, @types.Kl)
      let zero = la64_isel_newtmp(st, @types.Kl)
      emit(st, @types.Cultl, @types.Kw, to, zero, r)
      emit(st, @types.Xor, @types.Kl, r, i.arg1, i.arg2)
      emit(st, @types.Copy, @types.Kl, zero, con0, @types.Ref::none())
      fix_cmp(st, st.buf.length() - 2, i)
    }
    _ => abort("not an integer comparison")
  }
}

///|
// Select a single instruction (C sel).
fn sel(st : La64IselState, i : @types.Ins) -> Unit raise {
  if i.to.is_tmp() {
    if !isreg(i.to) && !isreg(i.arg1) && !isreg(i.arg2) {
      if st.fn_.tmps[i.to.tmp_val()].nuse == 0 {
        return
      }
    }
  }

  match i.op {
    // LoongArch has native divide/remainder instructions
    @types.Div | @types.Rem | @types.Udiv | @types.Urem => sel_emit(st, i)
    // LoongArch has flexible shift instructions
    @types.Sar | @types.Shr | @types.Shl => sel_emit(st, i)
    // Memory operations
    @types.Stored
    | @types.Stores
    | @types.Storel
    | @types.Storew
    | @types.Storeh
    | @types.Storeb => sel_emit(st, i)
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
    | @types.Cast => sel_emit(st, i)
    // Extensions need a register operand; materialize constants first.
    // The li helper is pushed after the parent so the reversed write-back
    // places it before.
    @types.Extsb
    | @types.Extub
    | @types.Extsh
    | @types.Extuh
    | @types.Extsw
    | @types.Extuw =>
      if i.arg1.is_con() {
        let r = la64_isel_newtmp(st, @types.Kl)
        let i1 = @types.Ins::new(i.op, i.cls, i.to, r, i.arg2)
        sel_emit(st, i1)
        emit(st, @types.Copy, @types.Kl, r, i.arg1, @types.Ref::none())
      } else {
        sel_emit(st, i)
      }
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
        // final order: salloc to = size; r1 = to + 15; to = r1 & -16
        let r1 = la64_isel_newtmp(st, @types.Kl)
        let m16 = @types.Ref::con(st.fn_.get_con(-16L))
        let c15 = @types.Ref::con(st.fn_.get_con(15L))
        emit(st, @types.And, @types.Kl, i.to, r1, m16)
        emit(st, @types.Add, @types.Kl, r1, i.to, c15)
        emit(st, @types.Salloc, @types.Kl, i.to, i.arg1, @types.Ref::none())
      }
    }
    // Integer comparisons - lowered to slt/sltu sequences
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
    | @types.Cultl => sel_int_cmp(st, i)
    // Floating point comparisons - fcmp + movcf2gr (see emit omap)
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
    // Flag-setting ops - skip (LoongArch doesn't use flags)
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
    // Parameter/argument ops - handled by abi_la64
    @types.Par
    | @types.Parc
    | @types.Pare
    | @types.Arg
    | @types.Argc
    | @types.Arge => ()
    // Variadic call - handled by abi_la64
    @types.Vacall => ()
    // Error/placeholder
    @types.Oxxx => ()
  }
}

///|
// Select a jump instruction (C seljmp).
fn seljmp(st : La64IselState, bid : Int) -> Unit {
  let b = st.fn_.blks[bid]
  // LoongArch uses conditional branches directly
  if b.jmp.kind == @types.Jjnz {
    let arg = b.jmp.arg
    b.jmp.arg = fixarg(st, arg, @types.Kw, None)
  }
}

///|
// Main LoongArch instruction selection entry point.
pub fn isel_la64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  print_dbg : Bool,
  all_typs : Array[@types.Typ],
) -> String raise {
  let st = la64_isel_new(fn_, interner)

  // Assign slots to fast allocs in the start block
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

  // Process basic blocks in definition order, instructions in reverse,
  // then write the selection buffer back reversed (C amd64_isel pattern).
  for k in 0..<fn_.def_order.length() {
    let bid = fn_.def_order[k]
    let b = fn_.blks[bid]
    st.buf.clear()
    // Fix phi arguments coming from this block
    for sbid in [b.jmp.s1, b.jmp.s2] {
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
    seljmp(st, bid)
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
    sb.write_string("> After LoongArch instruction selection:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}
