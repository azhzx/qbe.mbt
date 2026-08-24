///|
// amd64 gas emission - corresponds to amd64/emit.c and gas.c in QBE.

///|
priv struct EmitState {
  fn_ : @types.Fn
  interner : @util.Interner
  gasloc : String
  gassym : String
  sb : StringBuilder
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
let omap : Array[(Int, Int, String)] = [
  (@types.op_index(@types.Add), KA, "+add%k %1, %="),
  (@types.op_index(@types.Sub), KA, "-sub%k %1, %="),
  (@types.op_index(@types.And), KI, "+and%k %1, %="),
  (@types.op_index(@types.Or), KI, "+or%k %1, %="),
  (@types.op_index(@types.Xor), KI, "+xor%k %1, %="),
  (@types.op_index(@types.Sar), KI, "-sar%k %B1, %="),
  (@types.op_index(@types.Shr), KI, "-shr%k %B1, %="),
  (@types.op_index(@types.Shl), KI, "-shl%k %B1, %="),
  (@types.op_index(@types.Mul), KI, "+imul%k %1, %="),
  (@types.op_index(@types.Mul), 2, "+mulss %1, %="),
  (@types.op_index(@types.Mul), 3, "+mulsd %1, %="),
  (@types.op_index(@types.Div), KA, "-div%k %1, %="),
  (@types.op_index(@types.Storel), KA, "movq %L0, %M1"),
  (@types.op_index(@types.Storew), KA, "movl %W0, %M1"),
  (@types.op_index(@types.Storeh), KA, "movw %H0, %M1"),
  (@types.op_index(@types.Storeb), KA, "movb %B0, %M1"),
  (@types.op_index(@types.Stores), KA, "movss %S0, %M1"),
  (@types.op_index(@types.Stored), KA, "movsd %D0, %M1"),
  (@types.op_index(@types.Load), KA, "mov%k %M0, %="),
  (@types.op_index(@types.Loadsw), 1, "movslq %M0, %L="),
  (@types.op_index(@types.Loadsw), 0, "movl %M0, %W="),
  (@types.op_index(@types.Loaduw), KI, "movl %M0, %W="),
  (@types.op_index(@types.Loadsh), KI, "movsw%k %M0, %="),
  (@types.op_index(@types.Loaduh), KI, "movzw%k %M0, %="),
  (@types.op_index(@types.Loadsb), KI, "movsb%k %M0, %="),
  (@types.op_index(@types.Loadub), KI, "movzb%k %M0, %="),
  (@types.op_index(@types.Extsw), 1, "movslq %W0, %L="),
  (@types.op_index(@types.Extuw), 1, "movl %W0, %W="),
  (@types.op_index(@types.Extsh), KI, "movsw%k %H0, %="),
  (@types.op_index(@types.Extuh), KI, "movzw%k %H0, %="),
  (@types.op_index(@types.Extsb), KI, "movsb%k %B0, %="),
  (@types.op_index(@types.Extub), KI, "movzb%k %B0, %="),
  (@types.op_index(@types.Exts), 3, "cvtss2sd %0, %="),
  (@types.op_index(@types.Truncd), 2, "cvttsd2ss %0, %="),
  (@types.op_index(@types.Stosi), KI, "cvttss2si%k %0, %="),
  (@types.op_index(@types.Dtosi), KI, "cvttsd2si%k %0, %="),
  (@types.op_index(@types.Swtof), KA, "cvtsi2%k %W0, %="),
  (@types.op_index(@types.Sltof), KA, "cvtsi2%k %L0, %="),
  (@types.op_index(@types.Cast), KI, "movq %D0, %L="),
  (@types.op_index(@types.Cast), KA, "movq %L0, %D="),
  (@types.op_index(@types.Addr), KI, "lea%k %M0, %="),
  (@types.op_index(@types.Swap), KI, "xchg%k %0, %1"),
  (@types.op_index(@types.Sign), 1, "cqto"),
  (@types.op_index(@types.Sign), 0, "cltd"),
  (@types.op_index(@types.Xdiv), KI, "div%k %0"),
  (@types.op_index(@types.Xidiv), KI, "idiv%k %0"),
  (@types.op_index(@types.Xcmp), 2, "comiss %S0, %S1"),
  (@types.op_index(@types.Xcmp), 3, "comisd %D0, %D1"),
  (@types.op_index(@types.Xcmp), KI, "cmp%k %0, %1"),
  (@types.op_index(@types.Xtest), KI, "test%k %0, %1"),
  (@types.op_index(@types.Flagieq) + 8, KI, "setbe %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 9, KI, "setb %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 4, KI, "setle %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 5, KI, "setl %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 3, KI, "setg %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 2, KI, "setge %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 7, KI, "seta %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 6, KI, "setae %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 0, KI, "setz %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 1, KI, "setnz %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 13, KI, "setbe %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 14, KI, "setb %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 12, KI, "seta %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 11, KI, "setae %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 10, KI, "setz %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 15, KI, "setnz %B=\n\tmovzb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 16, KI, "setnp %B=\n\tmovsb%k %B=, %="),
  (@types.op_index(@types.Flagieq) + 17, KI, "setp %B=\n\tmovsb%k %B=, %="),
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
fn sign_ext29(s : Int) -> Int {
  if (s & (1 << 28)) != 0 {
    s - (1 << 29)
  } else {
    s
  }
}

///|
fn slot(st : EmitState, s : Int) -> Int {
  let x = sign_ext29(s)
  if x < 0 {
    -4 * x
  } else if st.fn_.is_vararg {
    -176 + -4 * (st.fn_.slot - x)
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
      let p = if con.is_local { st.gasloc } else { st.gassym }
      st.sb.write_string(p)
      st.sb.write_string(st.interner.get(con.label))
      if con.bits.i != 0L {
        st.sb.write_string(s64_plus(con.bits.i))
      }
    }
    @types.CBits => st.sb.write_string(con.bits.i.to_string())
    _ => abort("unreachable")
  }
}

///|
fn regtoa(reg : Int, sz : Int) -> String {
  if reg >= @types.XMM0 {
    "xmm\{reg - @types.XMM0}"
  } else {
    rname[reg][sz]
  }
}

///|
fn getarg(c : Char, i : @types.Ins) -> @types.Ref {
  if c == '0' {
    i.arg1
  } else if c == '1' {
    i.arg2
  } else if c == '=' {
    i.to
  } else {
    abort("invalid arg letter")
  }
}

///|
fn emit_mem(st : EmitState, rf : @types.Ref) -> Unit {
  let m = st.fn_.mems[rf.mem_val()]
  if m.base.is_slot() {
    let off = @types.Con::int(slot(st, m.base.slot_val()).to_int64())
    m.offset = @types.addcon(m.offset, off)
    m.base = @types.Ref::tmp(@types.RBP)
  }
  if m.offset.kind != @types.CUndef {
    emitcon(st, m.offset)
  }
  st.sb.write_char('(')
  if m.base.is_none() {
    st.sb.write_string("%rip")
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
fn emit_ref(st : EmitState, i : @types.Ins, c : Char, sz : Int) -> Unit {
  let rf = getarg(c, i)
  if rf.is_tmp() {
    st.sb.write_string("%")
    st.sb.write_string(regtoa(rf.tmp_val(), sz))
  } else if rf.is_slot() {
    st.sb.write_string("\{slot(st, rf.slot_val())}(%rbp)")
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
fn emitf(st : EmitState, fmt : String, i : @types.Ins) -> Unit {
  let mut s = fmt
  let ins = i
  if s.length() > 0 && (s[0] == '+' || s[0] == '-') {
    if s[0] == '+' {
      if @types.req(ins.arg2, ins.to) {
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
      'k' => st.sb.write_string(clstoa[@types.kcode(ins.cls)])
      '0' | '1' | '=' => {
        let sz = if @types.kwide(ins.cls) == 1 { SLONG } else { SWORD }
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
          st.sb.write_string("\{slot(st, rf.slot_val())}(%rbp)")
        } else if rf.is_con() {
          emitcon(st, st.fn_.cons[rf.con_val()])
          st.sb.write_string("(%rip)")
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
) -> Unit {
  let icp = @types.Ins::new(@types.Copy, k, r1, r2, @types.ref_none())
  emitins(st, icp)
}

///|
// Find the format for an instruction in the omap table (C Table label).
fn find_omap(op : @types.Op, cls : @types.Class) -> String {
  let oi = @types.op_index(op)
  let ccode = @types.kcode(cls)
  for o = 0; o < omap.length(); o = o + 1 {
    if omap[o].0 == oi {
      if omap[o].1 == ccode ||
        (omap[o].1 == KI && @types.kbase(cls) == 0) ||
        omap[o].1 == KA {
        return omap[o].2
      }
    }
  }
  abort("no match for instruction")
}

///|
fn emit_omap(st : EmitState, i : @types.Ins) -> Unit {
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
fn emitins(st : EmitState, i : @types.Ins) -> Unit {
  let ins = i
  match ins.op {
    @types.Nop => ()
    @types.Mul => {
      if ins.arg2.is_con() {
        let r = ins.arg1
        ins.arg1 = ins.arg2
        ins.arg2 = r
      }
      if @types.kbase(ins.cls) == 0 && ins.arg1.is_con() && ins.arg2.is_tmp() {
        emitf(st, "imul%k %0, %1, %=", ins)
      } else {
        emit_omap(st, ins)
      }
    }
    @types.Sub =>
      if @types.req(ins.to, ins.arg2) {
        if @types.kbase(ins.cls) == 0 {
          emitf(st, "neg%k %=", ins)
        } else {
          let n = @types.gasstash(neg_mask(ins.cls), 0L, 16)
          st.sb.write_string("\txorp")
          st.sb.write_string(if ins.cls == @types.Ks { "s" } else { "d" })
          st.sb.write_string("\{st.gasloc}fp\{n}(%rip), %")
          st.sb.write_string(regtoa(ins.to.tmp_val(), SLONG))
          st.sb.write_string("\n")
        }
        emitf(st, "add%k %0, %=", ins)
      } else {
        emit_omap(st, ins)
      }
    @types.Div => {
      if @types.req(ins.to, ins.arg2) {
        ins.arg2 = @types.Ref::tmp(@types.XMM0 + 15)
        emitf(st, "mov%k %=, %1", ins)
        emitf(st, "mov%k %0, %=", ins)
        ins.arg1 = ins.to
      }
      emit_omap(st, ins)
    }
    @types.Copy =>
      if ins.to.is_none() || ins.arg1.is_none() {
        ()
      } else if isreg(ins.to) &&
        ins.arg1.is_con() &&
        ins.cls == @types.Kl &&
        st.fn_.cons[ins.arg1.con_val()].kind == @types.CBits {
        let val = st.fn_.cons[ins.arg1.con_val()].bits.i
        if val >= 0L && val <= 4294967295L {
          emitf(st, "movl %W0, %W=", ins)
        } else {
          emitf(st, "mov%k %0, %=", ins)
        }
      } else if isreg(ins.to) &&
        ins.arg1.is_con() &&
        st.fn_.cons[ins.arg1.con_val()].kind == @types.CAddr {
        emitf(st, "lea%k %M0, %=", ins)
      } else if !@types.req(ins.arg1, ins.to) {
        emitf(st, "mov%k %0, %=", ins)
      }
    @types.Call =>
      if ins.arg1.is_con() {
        st.sb.write_string("\tcallq ")
        emitcon(st, st.fn_.cons[ins.arg1.con_val()])
        st.sb.write_string("\n")
      } else if ins.arg1.is_tmp() {
        emitf(st, "callq *%L0", ins)
      } else {
        abort("invalid call argument")
      }
    @types.Salloc => {
      emitf(st, "subq %L0, %%rsp", ins)
      if !ins.to.is_none() {
        emitcopy(st, ins.to, @types.Ref::tmp(@types.RSP), @types.Kl)
      }
    }
    @types.Swap =>
      if @types.kbase(ins.cls) == 0 {
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
fn framesz(st : EmitState) -> Int {
  let mut o = 0
  for r in @types.rclob {
    o = o ^ ((st.fn_.reg >> r) & 1UL).to_int()
  }
  let mut f = st.fn_.slot
  f = (f + 3) & -4
  4 * f + 8 * o + (if st.fn_.is_vararg { 176 } else { 0 })
}

///|
// Module-wide label counter (C static int id0 in emitfn).
let emit_id0 : Array[Int] = Array::make(1, 0)

///|
// Emit one function's assembly (C amd64_emitfn).
pub fn emitfn(
  fn_ : @types.Fn,
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  sb : StringBuilder,
) -> Unit {
  let st = EmitState::{ fn_, interner, gasloc, gassym, sb }
  st.sb.write_string(".text\n")
  if fn_.is_export {
    st.sb.write_string(".globl \{gassym}\{fn_.name}\n")
  }
  st.sb.write_string("\{gassym}\{fn_.name}:\n")
  st.sb.write_string("\tpushq %rbp\n\tmovq %rsp, %rbp\n")
  let mut fs = framesz(st)
  if fs != 0 {
    st.sb.write_string("\tsub $\{fs}, %rsp\n")
  }
  if fn_.is_vararg {
    let mut o = -176
    for r = 0; r < 6; r = r + 1 {
      st.sb.write_string("\tmovq %\{rname[@types.rsave[r]][0]}, \{o}(%rbp)\n")
      o = o + 8
    }
    for n = 0; n < 8; n = n + 1 {
      st.sb.write_string("\tmovaps %xmm\{n}, \{o}(%rbp)\n")
      o = o + 16
    }
  }
  for r in @types.rclob {
    if (fn_.reg & (1UL << r)) != 0 {
      let itmp = @types.Ins::new(
        @types.Copy,
        @types.Kx,
        @types.ref_none(),
        @types.Ref::tmp(r),
        @types.ref_none(),
      )
      emitf(st, "pushq %L0", itmp)
      fs = fs + 8
    }
  }

  let mut lbl = false
  for idx = 0; idx < fn_.rpo.length(); idx = idx + 1 {
    let bid = fn_.rpo[idx]
    let b = fn_.blks[bid]
    let next = if idx + 1 < fn_.rpo.length() { fn_.rpo[idx + 1] } else { -1 }
    if lbl || b.npred > 1 {
      st.sb.write_string("\{gasloc}bb\{emit_id0[0] + b.rpo_id}:\n")
    }
    for ins in b.ins {
      emitins(st, ins)
    }
    lbl = true
    match b.jmp.kind {
      @types.Jret0 => {
        if fn_.has_dynalloc {
          st.sb.write_string("\tmovq %rbp, %rsp\n\tsubq $\{fs}, %rsp\n")
        }
        for ri = @types.rclob.length() - 1; ri >= 0; ri = ri - 1 {
          if (fn_.reg & (1UL << @types.rclob[ri])) != 0 {
            let itmp = @types.Ins::new(
              @types.Copy,
              @types.Kx,
              @types.ref_none(),
              @types.Ref::tmp(@types.rclob[ri]),
              @types.ref_none(),
            )
            emitf(st, "popq %L0", itmp)
          }
        }
        st.sb.write_string("\tleave\n\tret\n")
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
        let mut c = @types.jump_index(b.jmp.kind) -
          @types.jump_index(@types.Jjfieq)
        if c >= 0 && c <= 18 {
          let mut s1 = b.jmp.s1
          let mut s2 = b.jmp.s2
          if next == s2 {
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
          abort("unhandled jump")
        }
      }
    }
  }
  emit_id0[0] = emit_id0[0] + fn_.rpo.length()
}

///|
// Emit a data item (C gasemitdat in gas.c).
let gasdat_align : Array[Int] = Array::make(1, 0)

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
        sb.write_string(".align 8\n")
      }
      if d.is_export {
        sb.write_string(".globl \{gassym}\{d.str}\n")
      }
      sb.write_string("\{gassym}\{d.str}:\n")
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
        sb.write_string("\{dtoa} \{d.ref_name}\{s64_plus(d.ref_offset)}\n")
      } else {
        sb.write_string("\{dtoa} \{d.num}\n")
      }
    }
  }
}

///|
// Extract the int32 word at byte offset p of a 16-byte little-endian value.
fn word_i32(b0 : Int64, b1 : Int64, p : Int) -> Int {
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
pub fn gasemitfin(gasloc : String, sb : StringBuilder) -> Unit {
  if @types.fp_stash_len() == 0 {
    return
  }
  sb.write_string("/* floating point constants */\n.data\n")
  let sizes = [16, 8, 4]
  for sz in sizes {
    for i = 0; i < @types.fp_stash_len(); i = i + 1 {
      let b = @types.fp_stash_at(i)
      if b.size == sz {
        sb.write_string(".align \{sz}\n\{gasloc}fp\{i}:")
        let mut p = 0
        while p < sz {
          sb.write_string("\n\t.int \{word_i32(b.b0, b.b1, p)}")
          p = p + 4
        }
        if sz <= 8 {
          let d = if sz == 4 {
            let u = (b.b0 & 0xFFFFFFFF).to_int().reinterpret_as_uint()
            Float::reinterpret_from_uint(u).to_double()
          } else {
            b.b0.reinterpret_as_double()
          }
          sb.write_string(" /* \{@util.fmt_fixed(d, 6)} */\n")
        } else {
          sb.write_string("\n")
        }
      }
    }
  }
}
