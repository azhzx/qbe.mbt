///|
// amd64 gas emission - corresponds to amd64/emit.c and gas.c in QBE.

///|
priv struct EmitState {
  fn_ : @types.Fn
  interner : @util.Interner
  gasloc : String
  gassym : String
  apple : Bool
  windows : Bool
  sb : StringBuilder
  mut fp : String // frame pointer: "%rbp" or "%rsp" (C E.fp)
  mut fsz : Int64 // frame size (C E.fsz, uint64_t; nonnegative)
  mut nclob : Int32 // number of pushed callee-saved registers (C E.nclob)
}

///|
// Size codes (C SLong..SByte).
const SLONG = 0

///|
const SWORD = 1

///|
const SSHORT = 2

///|
const SBYTE = 3

///|
// Class match codes (C Ki/Ka).
const KI = -1

///|
const KA = -2

///|
// Map a class code to the "l/q/ss/sd" suffix (C clstoa).
let clstoa : Array[String] = ["l", "q", "ss", "sd"]

///|
// Register names per size (C rname), indexed by register number.
let rname : Array[Array[String]] = [
  ["", "", "", ""],
  ["rax", "eax", "ax", "al"],
  ["rcx", "ecx", "cx", "cl"],
  ["rdx", "edx", "dx", "dl"],
  ["rsi", "esi", "si", "sil"],
  ["rdi", "edi", "di", "dil"],
  ["r8", "r8d", "r8w", "r8b"],
  ["r9", "r9d", "r9w", "r9b"],
  ["r10", "r10d", "r10w", "r10b"],
  ["r11", "r11d", "r11w", "r11b"],
  ["rbx", "ebx", "bx", "bl"],
  ["r12", "r12d", "r12w", "r12b"],
  ["r13", "r13d", "r13w", "r13b"],
  ["r14", "r14d", "r14w", "r14b"],
  ["r15", "r15d", "r15w", "r15b"],
  ["rbp", "ebp", "bp", "bpl"],
  ["rsp", "esp", "sp", "spl"],
]

///|
// Instruction format table (C omap in amd64/emit.c). (op index, cls code, asm)
let omap : Array[(Int32, Int32, String)] = [
  (@types.Add.index(), KA, "+add%k %1, %="),
  (@types.Sub.index(), KA, "-sub%k %1, %="),
  (@types.And.index(), KI, "+and%k %1, %="),
  (@types.Or.index(), KI, "+or%k %1, %="),
  (@types.Xor.index(), KI, "+xor%k %1, %="),
  (@types.Sar.index(), KI, "-sar%k %B1, %="),
  (@types.Shr.index(), KI, "-shr%k %B1, %="),
  (@types.Shl.index(), KI, "-shl%k %B1, %="),
  (@types.Mul.index(), KI, "+imul%k %1, %="),
  (@types.Mul.index(), 2, "+mulss %1, %="),
  (@types.Mul.index(), 3, "+mulsd %1, %="),
  (@types.Div.index(), KA, "-div%k %1, %="),
  (@types.Storel.index(), KA, "movq %L0, %M1"),
  (@types.Storew.index(), KA, "movl %W0, %M1"),
  (@types.Storeh.index(), KA, "movw %H0, %M1"),
  (@types.Storeb.index(), KA, "movb %B0, %M1"),
  (@types.Stores.index(), KA, "movss %S0, %M1"),
  (@types.Stored.index(), KA, "movsd %D0, %M1"),
  (@types.Load.index(), KA, "mov%k %M0, %="),
  (@types.Loadsw.index(), 1, "movslq %M0, %L="),
  (@types.Loadsw.index(), 0, "movl %M0, %W="),
  (@types.Loaduw.index(), KI, "movl %M0, %W="),
  (@types.Loadsh.index(), KI, "movsw%k %M0, %="),
  (@types.Loaduh.index(), KI, "movzw%k %M0, %="),
  (@types.Loadsb.index(), KI, "movsb%k %M0, %="),
  (@types.Loadub.index(), KI, "movzb%k %M0, %="),
  (@types.Extsw.index(), 1, "movslq %W0, %L="),
  (@types.Extuw.index(), 1, "movl %W0, %W="),
  (@types.Extsh.index(), KI, "movsw%k %H0, %="),
  (@types.Extuh.index(), KI, "movzw%k %H0, %="),
  (@types.Extsb.index(), KI, "movsb%k %B0, %="),
  (@types.Extub.index(), KI, "movzb%k %B0, %="),
  (@types.Exts.index(), 3, "cvtss2sd %0, %="),
  (@types.Truncd.index(), 2, "cvtsd2ss %0, %="),
  (@types.Stosi.index(), KI, "cvttss2si%k %0, %="),
  (@types.Dtosi.index(), KI, "cvttsd2si%k %0, %="),
  (@types.Swtof.index(), KA, "cvtsi2%k %W0, %="),
  (@types.Sltof.index(), KA, "cvtsi2%k %L0, %="),
  (@types.Cast.index(), KI, "movq %D0, %L="),
  (@types.Cast.index(), KA, "movq %L0, %D="),
  (@types.Addr.index(), KI, "lea%k %M0, %="),
  (@types.Swap.index(), KI, "xchg%k %0, %1"),
  (@types.Sign.index(), 1, "cqto"),
  (@types.Sign.index(), 0, "cltd"),
  (@types.Xdiv.index(), KI, "div%k %0"),
  (@types.Xidiv.index(), KI, "idiv%k %0"),
  (@types.Xcmp.index(), 2, "ucomiss %S0, %S1"),
  (@types.Xcmp.index(), 3, "ucomisd %D0, %D1"),
  (@types.Xcmp.index(), KI, "cmp%k %0, %1"),
  (@types.Xtest.index(), KI, "test%k %0, %1"),
  (@types.Flagieq.index() + 8, KI, "setbe %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 9, KI, "setb %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 4, KI, "setle %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 5, KI, "setl %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 3, KI, "setg %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 2, KI, "setge %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 7, KI, "seta %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 6, KI, "setae %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 0, KI, "setz %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 1, KI, "setnz %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 13, KI, "setbe %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 14, KI, "setb %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 12, KI, "seta %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 11, KI, "setae %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 10, KI, "setz %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 15, KI, "setnz %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 16, KI, "setnp %B=\n\tmovzb%k %B=, %="),
  (@types.Flagieq.index() + 17, KI, "setp %B=\n\tmovzb%k %B=, %="),
]

///|
// The conditional jump suffixes indexed by ICmp code (C ctoa in emitfn).
let ctoa : Array[String] = [
  "z", // Cieq 0
   "nz", // Cine 1
   "ge", // Cisge 2
   "g", // Cisgt 3
   "le", // Cisle 4
   "l", // Cislt 5
   "ae", // Ciuge 6
   "a", // Ciugt 7
   "be", // Ciule 8
   "b", // Ciult 9
   "z", // NCmpI+Cfeq 10
   "ae", // NCmpI+Cfge 11
   "a", // NCmpI+Cfgt 12
   "be", // NCmpI+Cfle 13
   "b", // NCmpI+Cflt 14
   "nz", // NCmpI+Cfne 15
   "np", // NCmpI+Cfo 16
   "p", // NCmpI+Cfuo 17
]

///|
// Sign-extend a 29-bit slot value (C struct { int i:29; }).
fn sign_ext29(s : Int32) -> Int32 {
  if (s & (1 << 28)) != 0 {
    s - (1 << 29)
  } else {
    s
  }
}

///|
fn slot(st : EmitState, s : Int32) -> Int32 {
  let x = sign_ext29(s)
  if x < 0 {
    if st.fp == "%rsp" {
      ((4 * -x - 8).to_int64() + st.fsz + (st.nclob * 8).to_int64()).to_int()
    } else {
      -4 * x
    }
  } else if st.fp == "%rsp" {
    4 * x + st.nclob * 8
  } else if st.fn_.is_vararg {
    if st.windows {
      -4 * (st.fn_.slot - x)
    } else {
      -176 + -4 * (st.fn_.slot - x)
    }
  } else {
    -4 * (st.fn_.slot - x)
  }
}

///|
fn isreg(r : @types.Ref) -> Bool {
  r.is_tmp() && r.tmp_val() < @types.Tmp0
}

///|
// Format an int64 with a '+' prefix for non-negative values (C %+PRId64).
fn s64_plus(v : Int64) -> String {
  if v >= 0L {
    "+" + v.to_string()
  } else {
    v.to_string()
  }
}

///|
fn emitcon(st : EmitState, con : @types.Con) -> Unit {
  match con.kind {
    @types.CAddr => {
      // C emitcon: local-exec TLS symbols are printed relative to %fs.
      if con.sym_type == @types.SYM_THR {
        st.sb.write_string("%fs:")
      }
      // Local (fp-constant) symbols are interned by the isel without a
      // prefix; the reference prints them quoted, e.g. ".Lfp0" (C emitcon
      // checks l[0] == '"').
      if con.is_local {
        st.sb.write_string("\"")
        st.sb.write_string(st.gasloc)
        st.sb.write_string(st.interner.get(con.label))
        st.sb.write_string("\"")
      } else {
        let nm = st.interner.get(con.label)
        st.sb.write_string(@util.sym_prefix(st.gassym, nm))
        st.sb.write_string(nm)
      }
      if con.sym_type == @types.SYM_THR {
        st.sb.write_string("@tpoff")
      }
      if con.bits.i != 0L {
        st.sb.write_string(s64_plus(con.bits.i))
      }
    }
    @types.CBits => st.sb.write_string(con.raw_bits().to_string())
    _ => abort("unreachable")
  }
}

///|
fn regtoa(reg : Int32, sz : Int32) -> String {
  if reg >= @types.XMM0 {
    "xmm\{reg - @types.XMM0}"
  } else {
    rname[reg][sz]
  }
}

///|
fn getarg(c : Char, i : @types.Ins) -> @types.Ref raise {
  if c == '0' {
    i.arg1
  } else if c == '1' {
    i.arg2
  } else if c == '=' {
    i.to
  } else {
    raise @util.QbeError::Ice("invalid arg letter")
  }
}

///|
fn emit_mem(st : EmitState, rf : @types.Ref) -> Unit {
  let m = st.fn_.mems[rf.mem_val()]
  if m.base.is_slot() {
    let off = @types.Con::int(slot(st, m.base.slot_val()).to_int64())
    m.offset = m.offset.add(off)
    // C emit_mem uses TMP(e->fp), which is RSP for leaf functions.
    m.base = @types.Ref::tmp(
      if st.fp == "%rbp" {
        @types.RBP
      } else {
        @types.RSP
      },
    )
  }
  if m.offset.kind != @types.CUndef {
    emitcon(st, m.offset)
  }
  st.sb.write_char('(')
  if m.base.is_none() {
    if m.offset.kind == @types.CAddr {
      st.sb.write_string("%rip")
    }
  } else {
    st.sb.write_string("%")
    st.sb.write_string(regtoa(m.base.tmp_val(), SLONG))
  }
  if !m.index.is_none() {
    st.sb.write_string(", %")
    st.sb.write_string(regtoa(m.index.tmp_val(), SLONG))
    st.sb.write_string(", \{m.scale}")
  }
  st.sb.write_char(')')
}

///|
// Emit a %0/%1/%= style reference with a size prefix (C Ref label in emitf).
fn emit_ref(st : EmitState, i : @types.Ins, c : Char, sz : Int32) -> Unit raise {
  let rf = getarg(c, i)
  if rf.is_tmp() {
    st.sb.write_string("%")
    st.sb.write_string(regtoa(rf.tmp_val(), sz))
  } else if rf.is_slot() {
    st.sb.write_string("\{slot(st, rf.slot_val())}(\{st.fp})")
  } else if rf.is_mem() {
    emit_mem(st, rf)
  } else if rf.is_con() {
    st.sb.write_string("$")
    emitcon(st, st.fn_.cons[rf.con_val()])
  } else {
    abort("unreachable")
  }
}

///|
// Expand an instruction format string (C emitf).
fn emitf(st : EmitState, fmt : String, i : @types.Ins) -> Unit raise {
  let mut s = fmt
  let ins = i
  if s.length() > 0 && (s[0] == '+' || s[0] == '-') {
    if s[0] == '+' {
      if ins.arg2.eq(ins.to) {
        let rf = ins.arg1
        ins.arg1 = ins.arg2
        ins.arg2 = rf
      }
    }
    emitcopy(st, ins.to, ins.arg1, ins.cls)
    s = s[1:].to_owned()
  }
  st.sb.write_char('\t')
  let mut pos = 0
  while true {
    while pos < s.length() && s[pos] != '%' {
      st.sb.write_char(s[pos].unsafe_to_char())
      pos = pos + 1
    }
    if pos >= s.length() {
      st.sb.write_char('\n')
      return
    }
    pos = pos + 1
    let c = s[pos]
    pos = pos + 1
    match c {
      '%' => st.sb.write_char('%')
      'k' => st.sb.write_string(clstoa[ins.cls.code()])
      '0' | '1' | '=' => {
        let sz = if ins.cls.wide() == 1 { SLONG } else { SWORD }
        emit_ref(st, ins, c.unsafe_to_char(), sz)
      }
      'D' | 'S' => {
        let c2 = s[pos]
        pos = pos + 1
        emit_ref(st, ins, c2.unsafe_to_char(), SLONG)
      }
      'L' => {
        let c2 = s[pos]
        pos = pos + 1
        emit_ref(st, ins, c2.unsafe_to_char(), SLONG)
      }
      'W' => {
        let c2 = s[pos]
        pos = pos + 1
        emit_ref(st, ins, c2.unsafe_to_char(), SWORD)
      }
      'H' => {
        let c2 = s[pos]
        pos = pos + 1
        emit_ref(st, ins, c2.unsafe_to_char(), SSHORT)
      }
      'B' => {
        let c2 = s[pos]
        pos = pos + 1
        emit_ref(st, ins, c2.unsafe_to_char(), SBYTE)
      }
      'M' => {
        let c2 = s[pos]
        pos = pos + 1
        let rf = getarg(c2.unsafe_to_char(), ins)
        if rf.is_mem() {
          emit_mem(st, rf)
        } else if rf.is_slot() {
          st.sb.write_string("\{slot(st, rf.slot_val())}(\{st.fp})")
        } else if rf.is_con() {
          let c = st.fn_.cons[rf.con_val()]
          emitcon(st, c)
          if c.kind == @types.CAddr && c.sym_type != @types.SYM_THR {
            st.sb.write_string("(%rip)")
          }
        } else if rf.is_tmp() {
          st.sb.write_string("(%")
          st.sb.write_string(regtoa(rf.tmp_val(), SLONG))
          st.sb.write_string(")")
        } else {
          abort("unreachable")
        }
      }
      _ => abort("invalid format specifier")
    }
  }
}

///|
fn emitcopy(
  st : EmitState,
  r1 : @types.Ref,
  r2 : @types.Ref,
  k : @types.Class,
) -> Unit raise {
  let icp = @types.Ins::new(@types.Copy, k, r1, r2, @types.Ref::none())
  emitins(st, icp)
}

///|
// Find the format for an instruction in the omap table (C Table label).
fn find_omap(op : @types.Op, cls : @types.Class) -> String raise {
  let oi = op.index()
  let ccode = cls.code()
  for o in 0..<omap.length() {
    if omap[o].0 == oi {
      if omap[o].1 == ccode ||
        (omap[o].1 == KI && cls.base() == 0) ||
        omap[o].1 == KA {
        return omap[o].2
      }
    }
  }
  raise @util.QbeError::Ice("no match for instruction")
}

///|
fn emit_omap(st : EmitState, i : @types.Ins) -> Unit raise {
  emitf(st, find_omap(i.op, i.cls), i)
}

///|
// The 16-byte sign mask for float negation (C negmask).
fn neg_mask(cls : @types.Class) -> Int64 {
  if cls == @types.Ks {
    0x0000000080000000L
  } else {
    0x8000000000000000L
  }
}

///|

///|
// cmov condition suffixes indexed by the ICmp code (C cmov[] in amd64/emit.c).
let amd64_cmov_s0 : Array[String] = [
  "z", "nz", "ge", "g", "le", "l", "ae", "a", "be", "b", "?", "ae", "a", "?", "?",
  "?", "np", "p",
]

///|
let amd64_cmov_s1 : Array[String] = [
  "nz", "z", "l", "le", "g", "ge", "b", "be", "a", "ae", "?", "b", "be", "?", "?",
  "?", "p", "np",
]

///|
// Emit a conditional move (C case_Oxsel in amd64/emit.c).
fn emit_xsel(st : EmitState, i : @types.Ins) -> Unit raise {
  let c = i.op.index() - @types.Xselieq.index()
  if i.to.eq(i.arg2) {
    emitf(st, "cmov\{amd64_cmov_s0[c]} %0, %=", i)
  } else {
    if !i.to.eq(i.arg1) {
      emitf(st, "mov %0, %=", i)
    }
    emitf(st, "cmov\{amd64_cmov_s1[c]} %1, %=", i)
  }
}

///|
fn emitins(st : EmitState, i : @types.Ins) -> Unit raise {
  // C emitins receives Ins by value; rewrites must not mutate the caller.
  let ins = @types.Ins::new(i.op, i.cls, i.to, i.arg1, i.arg2)
  let oi = ins.op.index()
  if oi >= @types.Xselieq.index() && oi <= @types.Xselfuo.index() {
    emit_xsel(st, ins)
    return
  }
  match ins.op {
    @types.Nop => ()
    @types.Dbgloc =>
      @util.emit_dbgloc(ins.arg1.rint_val(), ins.arg2.rint_val(), st.sb)
    @types.Mul => {
      if ins.arg2.is_con() {
        let r = ins.arg1
        ins.arg1 = ins.arg2
        ins.arg2 = r
      }
      if ins.cls.base() == 0 && ins.arg1.is_con() && ins.arg2.is_tmp() {
        emitf(st, "imul%k %0, %1, %=", ins)
      } else {
        emit_omap(st, ins)
      }
    }
    @types.Neg => {
      if !ins.to.eq(ins.arg1) {
        emitf(st, "mov%k %0, %=", ins)
      }
      if ins.cls.base() == 0 {
        emitf(st, "neg%k %=", ins)
      } else {
        let n = @types.gasstash(neg_mask(ins.cls), 0L, 16)
        st.sb.write_string("\txorp")
        st.sb.write_string(if ins.cls == @types.Ks { "s" } else { "d" })
        st.sb.write_string(" \{st.gasloc}fp\{n}(%rip), %")
        st.sb.write_string(regtoa(ins.to.tmp_val(), SLONG))
        st.sb.write_string("\n")
      }
    }
    @types.Sub =>
      if ins.to.eq(ins.arg2) && !ins.arg1.eq(ins.to) {
        if ins.cls.base() == 0 {
          emitf(st, "neg%k %=", ins)
        } else {
          let n = @types.gasstash(neg_mask(ins.cls), 0L, 16)
          st.sb.write_string("\txorp")
          st.sb.write_string(if ins.cls == @types.Ks { "s" } else { "d" })
          st.sb.write_string(" \{st.gasloc}fp\{n}(%rip), %")
          st.sb.write_string(regtoa(ins.to.tmp_val(), SLONG))
          st.sb.write_string("\n")
        }
        emitf(st, "add%k %0, %=", ins)
      } else {
        emit_omap(st, ins)
      }
    @types.Div => {
      if ins.to.eq(ins.arg2) {
        ins.arg2 = @types.Ref::tmp(@types.XMM0 + 15)
        emitf(st, "mov%k %=, %1", ins)
        emitf(st, "mov%k %0, %=", ins)
        ins.arg1 = ins.to
      }
      emit_omap(st, ins)
    }
    @types.Copy => {
      if ins.to.is_none() || ins.arg1.is_none() || ins.to.eq(ins.arg1) {
        return
      }
      if ins.cls == @types.Kl &&
        ins.arg1.is_con() &&
        st.fn_.cons[ins.arg1.con_val()].kind == @types.CBits {
        let val = st.fn_.cons[ins.arg1.con_val()].raw_bits()
        if isreg(ins.to) && val >= 0L && val <= 4294967295L {
          emitf(st, "movl %W0, %W=", ins)
          return
        }
        if ins.to.is_slot() && (val < -2147483648L || val > 2147483647L) {
          emitf(st, "movl %0, %=", ins)
          emitf(st, "movl %0>>32, 4+%=", ins)
          return
        }
      }
      if isreg(ins.to) &&
        ins.arg1.is_con() &&
        st.fn_.cons[ins.arg1.con_val()].kind == @types.CAddr {
        emitf(st, "lea%k %M0, %=", ins)
      } else if ins.to.is_slot() && (ins.arg1.is_slot() || ins.arg1.is_mem()) {
        ins.cls = if ins.cls.wide() == 1 { @types.Kd } else { @types.Ks }
        ins.arg2 = @types.Ref::tmp(@types.XMM15)
        emitf(st, "mov%k %0, %1", ins)
        emitf(st, "mov%k %1, %=", ins)
      } else {
        emitf(st, "mov%k %0, %=", ins)
      }
    }
    @types.Call =>
      if ins.arg1.is_con() {
        let c = st.fn_.cons[ins.arg1.con_val()]
        st.sb.write_string("\tcallq ")
        emitcon(st, c)
        if c.kind == @types.CAddr && c.is_ext() && !st.apple {
          st.sb.write_string("@plt")
        }
        st.sb.write_string("\n")
      } else if ins.arg1.is_tmp() {
        emitf(st, "callq *%L0", ins)
      } else {
        raise @util.QbeError::Ice("invalid call argument")
      }
    @types.Salloc => {
      emitf(st, "subq %L0, %%rsp", ins)
      if !ins.to.is_none() {
        emitcopy(st, ins.to, @types.Ref::tmp(@types.RSP), @types.Kl)
      }
    }
    @types.Addr => {
      // C amd64 emit.c case Oaddr: GOT/TLS address materialization.
      let a0 = ins.arg1
      if !a0.is_con() {
        emit_omap(st, ins)
      } else {
        let con = st.fn_.cons[a0.con_val()]
        if con.kind != @types.CAddr {
          emit_omap(st, ins)
        } else if st.windows && con.sym_type != 0 {
          raise @util.QbeError::Ice("extern/thread unsupported on amd64_win")
        } else if st.apple && con.is_thr() {
          let nm = st.interner.get(con.label)
          st.sb.write_string(
            "\tmovq \{@util.sym_prefix(st.gassym, nm)}\{nm}@tlvp(%rip), %\{regtoa(ins.to.tmp_val(), SLONG)}\n",
          )
        } else if con.sym_type == @types.SYM_THR {
          let to = regtoa(ins.to.tmp_val(), SLONG)
          st.sb.write_string("	movq %fs:0, %")
          st.sb.write_string(to)
          st.sb.write_string("\n")
          let nm = st.interner.get(con.label)
          let pfx = @util.sym_prefix(st.gassym, nm)
          st.sb.write_string("	leaq ")
          st.sb.write_string(pfx)
          st.sb.write_string(nm)
          st.sb.write_string("@tpoff")
          if con.bits.i != 0L {
            st.sb.write_string(s64_plus(con.bits.i))
          }
          st.sb.write_string("(%")
          st.sb.write_string(to)
          st.sb.write_string("), %")
          st.sb.write_string(to)
          st.sb.write_string("\n")
        } else if con.sym_type == (2 | 1) {
          // initial-exec TLS
          let to = regtoa(ins.to.tmp_val(), SLONG)
          st.sb.write_string("	movq %fs:0, %")
          st.sb.write_string(to)
          st.sb.write_string("\n")
          let nm = st.interner.get(con.label)
          let pfx = @util.sym_prefix(st.gassym, nm)
          st.sb.write_string("	addq ")
          st.sb.write_string(pfx)
          st.sb.write_string(nm)
          st.sb.write_string("@gottpoff(%rip), %")
          st.sb.write_string(to)
          st.sb.write_string("\n")
        } else if con.is_ext() {
          let to = regtoa(ins.to.tmp_val(), SLONG)
          let nm = st.interner.get(con.label)
          let pfx = @util.sym_prefix(st.gassym, nm)
          st.sb.write_string("	movq ")
          st.sb.write_string(pfx)
          st.sb.write_string(nm)
          st.sb.write_string("@gotpcrel(%rip), %")
          st.sb.write_string(to)
          st.sb.write_string("\n")
        } else {
          emit_omap(st, ins)
        }
      }
    }
    @types.Swap =>
      if ins.cls.base() == 0 {
        emit_omap(st, ins)
      } else {
        emitcopy(st, @types.Ref::tmp(@types.XMM0 + 15), ins.arg1, ins.cls)
        emitcopy(st, ins.arg1, ins.arg2, ins.cls)
        emitcopy(st, ins.arg2, @types.Ref::tmp(@types.XMM0 + 15), ins.cls)
      }
    _ => emit_omap(st, ins)
  }
}

///|
fn framesz(st : EmitState) -> Int64 {
  let mut o = 0
  // C sysv_framesz: only non-leaf functions account for the callee-saved
  // registers they push.
  let rclob = if st.windows { @types.rclob_win } else { @types.rclob }
  if !st.fn_.leaf {
    for r in rclob {
      o = o ^ ((st.fn_.reg >> r) & 1UL).to_int()
    }
  }
  let mut f = st.fn_.slot.to_int64()
  f = (f + 3L) & -4L
  // C sysv_framesz: a leaf using %rsp keeps the stack 16-byte aligned.
  if f > 0 && st.fp == "%rsp" && st.fn_.salign == 4 {
    f = f + 2
  }
  4L * f +
  8L * o.to_int64() +
  (if st.fn_.is_vararg && !st.windows { 176L } else { 0L })
}

///|
// Module-wide label counter (C static int id0 in emitfn).
let emit_id0 : Array[Int32] = Array::make(1, 0)

///|
// Emit one function's assembly (C amd64_emitfn).
pub fn emitfn(
  fn_ : @types.Fn,
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  apple : Bool,
  sb : StringBuilder,
  windows~ : Bool = false,
) -> Unit raise {
  let st = EmitState::{
    fn_,
    interner,
    gasloc,
    gassym,
    apple,
    windows,
    sb,
    fp: "%rbp",
    fsz: 0,
    nclob: 0,
  }
  // C emitlnk: section, .balign, .globl, label (shared emitter).
  @gasdata.emitfnlnk(fn_, gassym, st.sb)
  // DWARF CFI is opt-in (-g): the default output stays byte-identical to the
  // reference, which emits no .cfi directives.
  let dbg = @util.debug_info()
  if dbg {
    st.sb.write_string("\t.cfi_startproc\n")
  }
  // CET landing pad (C always emits it).
  st.sb.write_string("\tendbr64\n")
  // Win64 varargs: the four integer argument registers live in the callee's
  // shadow space (C amd64_winabi_emitfn).
  if fn_.is_vararg && windows {
    st.sb.write_string("\tmovq %rcx, 0x8(%rsp)\n")
    st.sb.write_string("\tmovq %rdx, 0x10(%rsp)\n")
    st.sb.write_string("\tmovq %r8, 0x18(%rsp)\n")
    st.sb.write_string("\tmovq %r9, 0x20(%rsp)\n")
  }
  // Leaf functions without varargs/dynalloc address locals off %rsp (C).
  let use_fp = !fn_.leaf || fn_.is_vararg || fn_.has_dynalloc
  st.fp = if use_fp { "%rbp" } else { "%rsp" }
  if use_fp {
    st.sb.write_string("\tpushq %rbp\n")
    if dbg {
      st.sb.write_string("\t.cfi_def_cfa_offset 16\n\t.cfi_offset %rbp, -16\n")
    }
    st.sb.write_string("\tmovq %rsp, %rbp\n")
    if dbg {
      st.sb.write_string("\t.cfi_def_cfa_register %rbp\n")
    }
  }
  let mut fs = framesz(st)
  st.fsz = fs
  if fs != 0 {
    st.sb.write_string("\tsubq $\{fs}, %rsp\n")
    if dbg && !use_fp {
      st.sb.write_string("\t.cfi_def_cfa_offset \{fs + 8}\n")
    }
  }
  if fn_.is_vararg && !windows {
    let mut o = -176
    for r in 0..<6 {
      st.sb.write_string("\tmovq %\{rname[@types.rsave[r]][0]}, \{o}(%rbp)\n")
      o = o + 8
    }
    for n in 0..<8 {
      st.sb.write_string("\tmovaps %xmm\{n}, \{o}(%rbp)\n")
      o = o + 16
    }
  }
  let rclob_pro = if windows { @types.rclob_win } else { @types.rclob }
  for r in rclob_pro {
    if (fn_.reg & (1UL << r)) != 0 {
      let itmp = @types.Ins::new(
        @types.Copy,
        @types.Kx,
        @types.Ref::none(),
        @types.Ref::tmp(r),
        @types.Ref::none(),
      )
      emitf(st, "pushq %L0", itmp)
      fs = fs + 8
      st.nclob = st.nclob + 1
      if dbg && use_fp {
        st.sb.write_string("\t.cfi_offset %")
        st.sb.write_string(rname[r][0])
        st.sb.write_string(", -")
        st.sb.write_string((16 + 8 * st.nclob).to_string())
        st.sb.write_string("\n")
      }
    }
  }

  let mut lbl = false
  for idx in 0..<fn_.rpo.length() {
    let bid = fn_.rpo[idx]
    let b = fn_.blks[bid]
    let next = if idx + 1 < fn_.rpo.length() { fn_.rpo[idx + 1] } else { -1 }
    if lbl || b.npred > 1 {
      // C: align loop headers (a predecessor with id >= this block's id).
      let mut p = 0
      while p < b.npred {
        if fn_.blks[b.pred[p]].rpo_id >= b.rpo_id {
          break
        }
        p = p + 1
      }
      if p != b.npred && !windows {
        st.sb.write_string(".p2align 4\n")
      }
      st.sb.write_string("\{gasloc}bb\{emit_id0[0] + b.rpo_id}:\n")
    }
    for ins in b.ins {
      emitins(st, ins)
    }
    lbl = true
    match b.jmp.kind {
      @types.Jhlt => st.sb.write_string("\tud2\n")
      @types.Jret0 => {
        if fn_.has_dynalloc {
          st.sb.write_string("\tmovq %rbp, %rsp\n\tsubq $\{fs}, %rsp\n")
        }
        for ri in (rclob_pro.length() - 1)>=..0 {
          if (fn_.reg & (1UL << rclob_pro[ri])) != 0 {
            let itmp = @types.Ins::new(
              @types.Copy,
              @types.Kx,
              @types.Ref::none(),
              @types.Ref::tmp(rclob_pro[ri]),
              @types.Ref::none(),
            )
            emitf(st, "popq %L0", itmp)
            if dbg {
              st.sb.write_string("\t.cfi_restore %")
              st.sb.write_string(rname[rclob_pro[ri]][0])
              st.sb.write_string("\n")
            }
          }
        }
        if use_fp {
          st.sb.write_string("\tleave\n")
          if dbg {
            st.sb.write_string("\t.cfi_def_cfa %rsp, 8\n\t.cfi_restore %rbp\n")
          }
        } else if st.fsz != 0 {
          st.sb.write_string("\taddq $\{st.fsz}, %rsp\n")
          if dbg {
            st.sb.write_string("\t.cfi_def_cfa_offset 8\n")
          }
        }
        st.sb.write_string("\tret\n")
      }
      @types.Jjmp =>
        if b.jmp.s1 >= 0 && b.jmp.s1 != next {
          st.sb.write_string(
            "\tjmp \{gasloc}bb\{emit_id0[0] + fn_.blks[b.jmp.s1].rpo_id}\n",
          )
        } else {
          lbl = false
        }
      _ => {
        let mut c = b.jmp.kind.index() - @types.Jjfieq.index()
        if c >= 0 && c <= 18 {
          let mut s1 = b.jmp.s1
          let mut s2 = b.jmp.s2
          // C amd64_winabi_emitfn also swaps (and keeps the positive
          // condition) for floating-point comparisons, unlike SysV.
          let swap = next == s2 || (windows && c >= 10)
          if swap {
            let t = s1
            s1 = s2
            s2 = t
          } else {
            c = @types.cmpneg(c)
          }
          st.sb.write_string(
            "\tj\{ctoa[c]} \{gasloc}bb\{emit_id0[0] + fn_.blks[s2].rpo_id}\n",
          )
          if s1 >= 0 && s1 != next {
            st.sb.write_string(
              "\tjmp \{gasloc}bb\{emit_id0[0] + fn_.blks[s1].rpo_id}\n",
            )
          } else {
            lbl = false
          }
        } else {
          raise @util.QbeError::Ice("unhandled jump")
        }
      }
    }
  }
  emit_id0[0] = emit_id0[0] + fn_.rpo.length()
  // C elf_emitfnfin emits the function type/size after each function; the
  // Mach-O and Windows flavours emit nothing.
  if !apple && !windows {
    st.sb.write_string(
      ".type \{@util.sym_prefix(gassym, fn_.name)}\{fn_.name}, @function\n",
    )
    st.sb.write_string(
      ".size \{@util.sym_prefix(gassym, fn_.name)}\{fn_.name}, .-\{@util.sym_prefix(gassym, fn_.name)}\{fn_.name}\n",
    )
  }
  if dbg {
    st.sb.write_string("\t.cfi_endproc\n")
  }
}

///|
// Emit a data item (C gasemitdat in gas.c).
let gasdat_align : Array[Int32] = Array::make(1, 0)

///|
// Reset the per-module label and data-alignment bases (once per output
// stream, like the other GAS emitters' *_emit_reset).
pub fn amd64_emit_reset() -> Unit {
  emit_id0[0] = 0
  gasdat_align[0] = 0
}

///|
pub fn gasemitdat(
  d : @types.Dat,
  _gasloc : String,
  gassym : String,
  sb : StringBuilder,
) -> Unit {
  match d.kind {
    @types.DStart => {
      gasdat_align[0] = 0
      sb.write_string(".data\n")
    }
    @types.DEnd => ()
    @types.DName => {
      if gasdat_align[0] == 0 {
        // C emitlnk/emitdat use .balign for data alignment.
        sb.write_string(".balign 8\n")
      }
      if d.is_export {
        sb.write_string(".globl \{@util.sym_prefix(gassym, d.str)}\{d.str}\n")
      }
      sb.write_string("\{@util.sym_prefix(gassym, d.str)}\{d.str}:\n")
    }
    @types.DZ => sb.write_string("\t.fill \{d.num},1,0\n")
    _ => {
      if d.kind == @types.DAlign {
        gasdat_align[0] = 1
      }
      let dtoa = match d.kind {
        @types.DAlign => ".align"
        @types.DB => "\t.byte"
        @types.DH => "\t.short"
        @types.DW => "\t.int"
        @types.DL => "\t.quad"
        _ => ""
      }
      if d.is_str {
        sb.write_string("\t.ascii \"\{d.str}\"\n")
      } else if d.is_ref {
        // C gasemitdat prefixes referenced symbols with the gas symbol
        // prefix (empty for ELF, "_" for Mach-O).
        sb.write_string(
          "\{dtoa} \{@util.sym_prefix(gassym, d.ref_name)}\{d.ref_name}\{s64_plus(d.ref_offset)}\n",
        )
      } else {
        // C emitdat masks the value to the data item width.
        let mask = match d.kind {
          @types.DB => 0xffL
          @types.DH => 0xffffL
          @types.DW => 0xffffffffL
          _ => -1L
        }
        sb.write_string("\{dtoa} \{(d.num & mask).to_string()}\n")
      }
    }
  }
}

///|
// Extract the int32 word at byte offset p of a 16-byte little-endian value.
fn word_i32(b0 : Int64, b1 : Int64, p : Int32) -> Int32 {
  let u = if p == 0 {
    b0 & 0xFFFFFFFF
  } else if p == 4 {
    (b0 >> 32) & 0xFFFFFFFF
  } else if p == 8 {
    b1 & 0xFFFFFFFF
  } else {
    (b1 >> 32) & 0xFFFFFFFF
  }
  if u >= 0x80000000L {
    (u - 0x100000000L).to_int()
  } else {
    u.to_int()
  }
}

///|
// Emit the floating point constants table (C gasemitfin in gas.c).
pub fn gasemitfin(
  gasloc : String,
  apple : Bool,
  sb : StringBuilder,
  windows~ : Bool = false,
) -> Unit {
  if @types.fp_stash_len() > 0 {
    sb.write_string("/* floating point constants */\n")
    // Sizes are emitted largest first (C emitfin: lg 4,3,2 = 16,8,4 bytes).
    for lg in [4, 3, 2] {
      // Apple keeps floating point constants in Mach-O literal sections
      // (C macho_emitfin); ELF uses .rodata (C elf_emitfin).
      let sec = if apple {
        match lg {
          4 => "__TEXT,__literal16,16byte_literals"
          3 => "__TEXT,__literal8,8byte_literals"
          _ => "__TEXT,__literal4,4byte_literals"
        }
      } else {
        ".rodata"
      }
      for i in 0..<@types.fp_stash_len() {
        let b = @types.fp_stash_at(i)
        if b.size == 1 << lg {
          sb.write_string(".section \{sec}\n.p2align \{lg}\n\{gasloc}fp\{i}:")
          if lg == 4 {
            sb.write_string("\n\t.quad \{b.b0}\n\t.quad 0\n\n")
          } else if lg == 3 {
            sb.write_string(
              "\n\t.quad \{b.b0} /* \{@util.fmt_fixed(b.b0.reinterpret_as_double(), 6)} */\n\n",
            )
          } else {
            let u = (b.b0 & 0xFFFFFFFF).to_int().reinterpret_as_uint()
            let d = Float::reinterpret_from_uint(u).to_double()
            sb.write_string(
              "\n\t.int \{u.reinterpret_as_int()} /* \{@util.fmt_fixed(d, 6)} */\n\n",
            )
          }
        }
      }
    }
  }
  // C elf_emitfin always terminates with the GNU-stack note; the Mach-O and
  // PE flavours do not.
  if !apple && !windows {
    sb.write_string(".section .note.GNU-stack,\"\",@progbits\n")
  }
}

///|
// Resolve builder debug variables to DWARF locations (this target does not
// emit variable locations yet; the subprogram DIEs are still emitted).
pub fn debug_locs(fn_ : @types.Fn, apple : Bool) -> Array[@dwarf.DbgLoc] {
  let _ = fn_
  let _ = apple
  []
}
