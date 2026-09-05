///|
// RISC-V 64 (rv64) GAS assembly emission - corresponds to rv64/emit.c in QBE.

///|
// Size codes (C SLong..SByte).
const SLONG : Int = 0

///|
const SWORD : Int = 1

///|
const SSHORT : Int = 2

///|
const SBYTE : Int = 3

///|
// Class match codes (C Ki/Ka).
const KI : Int = -1

///|
const KA : Int = -2

///|
const KW : Int = 0

///|
const KL : Int = 1

///|
const KS : Int = 2

///|
const KD : Int = 3

///|
// Temp registers for scratch.
const T6 : Int = 62

///|
const FT11 : Int = 63

///|
// Map a class code to the "w/l/s/d" suffix (C clschr).
let clschr : Array[String] = ["w", "l", "s", "d"]

///|
// Map a class code to the size code (C clstosz).
let clstosz : Array[Int] = [SWORD, SLONG, SSHORT, SBYTE]

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
priv struct Rv64EmitState {
  fn_ : @types.Fn
  interner : @util.Interner
  sb : StringBuilder
}

///|
fn rv64_emit_new(
  fn_ : @types.Fn,
  interner : @util.Interner,
  sb : StringBuilder,
) -> Rv64EmitState {
  Rv64EmitState::{ fn_, interner, sb, }
}

///|
// RISC-V instruction format table (C omap in rv64/emit.c).
// (op index, cls code, format string)
let rv64_omap : Array[(Int, Int, String)] = [
  (@types.Add.index(), KI, "add%k %=, %0, %1"),
  (@types.Add.index(), KA, "fadd.%k %=, %0, %1"),
  (@types.Sub.index(), KI, "sub%k %=, %0, %1"),
  (@types.Sub.index(), KA, "fsub.%k %=, %0, %1"),
  (@types.Div.index(), KI, "div%k %=, %0, %1"),
  (@types.Div.index(), KA, "fdiv.%k %=, %0, %1"),
  (@types.Rem.index(), KI, "rem%k %=, %0, %1"),
  (@types.Rem.index(), KL, "rem %=, %0, %1"),
  (@types.Udiv.index(), KI, "divu%k %=, %0, %1"),
  (@types.Urem.index(), KI, "remu%k %=, %0, %1"),
  (@types.Mul.index(), KI, "mul%k %=, %0, %1"),
  (@types.Mul.index(), KA, "fmul.%k %=, %0, %1"),
  (@types.And.index(), KI, "and %=, %0, %1"),
  (@types.Or.index(), KI, "or %=, %0, %1"),
  (@types.Xor.index(), KI, "xor %=, %0, %1"),
  (@types.Sar.index(), KI, "sra%k %=, %0, %1"),
  (@types.Shr.index(), KI, "srl%k %=, %0, %1"),
  (@types.Shl.index(), KI, "sll%k %=, %0, %1"),
  (@types.Csltl.index(), KI, "slt %=, %0, %1"),
  (@types.Cultl.index(), KI, "sltu %=, %0, %1"),
  (@types.Ceqs.index(), KI, "feq.s %=, %0, %1"),
  (@types.Cges.index(), KI, "fge.s %=, %0, %1"),
  (@types.Cgts.index(), KI, "fgt.s %=, %0, %1"),
  (@types.Cles.index(), KI, "fle.s %=, %0, %1"),
  (@types.Clts.index(), KI, "flt.s %=, %0, %1"),
  (@types.Ceqd.index(), KI, "feq.d %=, %0, %1"),
  (@types.Cged.index(), KI, "fge.d %=, %0, %1"),
  (@types.Cgtd.index(), KI, "fgt.d %=, %0, %1"),
  (@types.Cled.index(), KI, "fle.d %=, %0, %1"),
  (@types.Cltd.index(), KI, "flt.d %=, %0, %1"),
  (@types.Storeb.index(), KW, "sb %0, %M1"),
  (@types.Storeh.index(), KW, "sh %0, %M1"),
  (@types.Storew.index(), KW, "sw %0, %M1"),
  (@types.Storel.index(), KI, "sd %0, %M1"),
  (@types.Stores.index(), KW, "fsw %0, %M1"),
  (@types.Stored.index(), KW, "fsd %0, %M1"),
  (@types.Loadsb.index(), KI, "lb %=, %M0"),
  (@types.Loadub.index(), KI, "lbu %=, %M0"),
  (@types.Loadsh.index(), KI, "lh %=, %M0"),
  (@types.Loaduh.index(), KI, "lhu %=, %M0"),
  (@types.Loadsw.index(), KI, "lw %=, %M0"),
  (@types.Loaduw.index(), KW, "lw %=, %M0"),
  (@types.Loaduw.index(), KL, "lwu %=, %M0"),
  (@types.Load.index(), KW, "lw %=, %M0"),
  (@types.Load.index(), KL, "ld %=, %M0"),
  (@types.Load.index(), KS, "flw %=, %M0"),
  (@types.Load.index(), KD, "fld %=, %M0"),
  (@types.Extsb.index(), KI, "sext.b %=, %0"),
  (@types.Extub.index(), KI, "zext.b %=, %0"),
  (@types.Extsh.index(), KI, "sext.h %=, %0"),
  (@types.Extuh.index(), KI, "zext.h %=, %0"),
  (@types.Extsw.index(), KL, "sext.w %=, %0"),
  (@types.Extuw.index(), KL, "zext.w %=, %0"),
  (@types.Truncd.index(), KS, "fcvt.s.d %=, %0"),
  (@types.Exts.index(), KD, "fcvt.d.s %=, %0"),
  (@types.Stosi.index(), KW, "fcvt.w.s %=, %0, rtz"),
  (@types.Stosi.index(), KL, "fcvt.l.s %=, %0, rtz"),
  (@types.Dtosi.index(), KW, "fcvt.w.d %=, %0, rtz"),
  (@types.Dtosi.index(), KL, "fcvt.l.d %=, %0, rtz"),
  (@types.Swtof.index(), KA, "fcvt.%k.w %=, %0"),
  (@types.Sltof.index(), KA, "fcvt.%k.l %=, %0"),
  (@types.Cast.index(), KW, "fmv.x.w %=, %0"),
  (@types.Cast.index(), KL, "fmv.x.d %=, %0"),
  (@types.Cast.index(), KS, "fmv.w.x %=, %0"),
  (@types.Cast.index(), KD, "fmv.d.x %=, %0"),
  (@types.Copy.index(), KI, "mv %=, %0"),
  (@types.Copy.index(), KA, "fmv.%k %=, %0"),
  (@types.Swap.index(), KI, "mv %?, %0\n\tmv %0, %1\n\tmv %1, %?"),
  (@types.Swap.index(), KA, "fmv.%k %?, %0\n\tfmv.%k %0, %1\n\tfmv.%k %1, %?"),
  (@types.Call.index(), KW, "jalr %0"),
]

///|
// Slot offset calculation (C slot in emit.c).
fn rv64_slot(st : Rv64EmitState, s : Int) -> Int {
  let x = sign_ext29(s)
  if x < 0 {
    8 * -x
  } else {
    -4 * (st.fn_.slot - x)
  }
}

///|
// Emit an address (C emitaddr).
fn rv64_emitaddr(st : Rv64EmitState, con : @types.Con) -> Unit {
  match con.kind {
    @types.CAddr => {
      st.sb.write_string(st.interner.get(con.label))
      if con.bits.i != 0L {
        st.sb.write_string("+")
        st.sb.write_string(con.bits.i.to_string())
      }
    }
    _ => abort("invalid address constant")
  }
}

///|
// Format and emit an instruction (C emitf).
fn rv64_emitf(st : Rv64EmitState, fmt : String, i : @types.Ins) -> Unit {
  st.sb.write_char('\t')
  let mut idx = 0
  while idx < fmt.length() {
    let c = fmt[idx]
    if c != '%' {
      st.sb.write_char(c.unsafe_to_char())
      idx = idx + 1
      continue
    }
    idx = idx + 1
    if idx >= fmt.length() {
      break
    }
    let esc = fmt[idx]
    idx = idx + 1
    match esc {
      '?' =>
        if i.cls.base() == 0 {
          st.sb.write_string("t6")
        } else {
          st.sb.write_string("ft11")
        }
      'k' => if i.cls != @types.Kl { st.sb.write_string(clschr[i.cls.code()]) }
      '=' =>
        if i.to.is_tmp() {
          st.sb.write_string(@types.rv64_reg_name(i.to.tmp_val()))
        }
      '0' =>
        if i.arg1.is_tmp() {
          st.sb.write_string(@types.rv64_reg_name(i.arg1.tmp_val()))
        }
      '1' =>
        if i.arg2.is_tmp() {
          st.sb.write_string(@types.rv64_reg_name(i.arg2.tmp_val()))
        } else if i.arg2.is_con() {
          let con = st.fn_.cons[i.arg2.con_val()]
          match con.kind {
            @types.CBits => st.sb.write_string(con.bits.i.to_string())
            _ => abort("invalid constant for immediate")
          }
        }
      'M' =>
        if idx < fmt.length() {
          let c0 = fmt[idx]
          idx = idx + 1
          let r = if c0 == '0' { i.arg1 } else { i.arg2 }
          if r.is_tmp() {
            st.sb.write_string("0(")
            st.sb.write_string(@types.rv64_reg_name(r.tmp_val()))
            st.sb.write_string(")")
          } else if r.is_con() {
            let con = st.fn_.cons[r.con_val()]
            match con.kind {
              @types.CAddr => rv64_emitaddr(st, con)
              _ => abort("invalid address")
            }
          } else if r.is_slot() {
            let off = rv64_slot(st, r.slot_val())
            st.sb.write_string(off.to_string())
            st.sb.write_string("(fp)")
          }
        }
      'B' =>
        if idx < fmt.length() {
          let c0 = fmt[idx]
          idx = idx + 1
          let r = if c0 == '=' { i.to } else { i.arg1 }
          if r.is_tmp() {
            st.sb.write_string(@types.rv64_reg_name(r.tmp_val()))
          }
        }
      'W' =>
        if idx < fmt.length() {
          let c0 = fmt[idx]
          idx = idx + 1
          let r = if c0 == '=' { i.to } else { i.arg1 }
          if r.is_tmp() {
            st.sb.write_string(@types.rv64_reg_name(r.tmp_val()))
          }
        }
      'H' =>
        if idx < fmt.length() {
          let c0 = fmt[idx]
          idx = idx + 1
          let r = if c0 == '=' { i.to } else { i.arg1 }
          if r.is_tmp() {
            st.sb.write_string(@types.rv64_reg_name(r.tmp_val()))
          }
        }
      'L' =>
        if idx < fmt.length() {
          let c0 = fmt[idx]
          idx = idx + 1
          let r = if c0 == '=' { i.to } else { i.arg1 }
          if r.is_tmp() {
            st.sb.write_string(@types.rv64_reg_name(r.tmp_val()))
          }
        }
      'S' =>
        if idx < fmt.length() {
          let c0 = fmt[idx]
          idx = idx + 1
          let r = if c0 == '=' { i.to } else { i.arg1 }
          if r.is_tmp() {
            st.sb.write_string(@types.rv64_reg_name(r.tmp_val()))
          }
        }
      'D' =>
        if idx < fmt.length() {
          let c0 = fmt[idx]
          idx = idx + 1
          let r = if c0 == '=' { i.to } else { i.arg1 }
          if r.is_tmp() {
            st.sb.write_string(@types.rv64_reg_name(r.tmp_val()))
          }
        }
      _ => ()
    }
  }
  st.sb.write_char('\n')
}

///|
// Emit a single instruction (C emitins).
fn rv64_emitins(st : Rv64EmitState, i : @types.Ins) -> Unit {
  match i.op {
    @types.Nop => ()
    @types.Copy => {
      if i.to.eq(i.arg1) {
        return
      }
      if i.arg1.is_con() {
        let con = st.fn_.cons[i.arg1.con_val()]
        match con.kind {
          @types.CAddr => {
            let rn = @types.rv64_reg_name(i.to.tmp_val())
            st.sb.write_string("\tlla ")
            st.sb.write_string(rn)
            st.sb.write_string(", ")
            rv64_emitaddr(st, con)
            st.sb.write_char('\n')
          }
          @types.CBits => {
            let rn = @types.rv64_reg_name(i.to.tmp_val())
            let n = con.bits.i
            st.sb.write_string("\tli ")
            st.sb.write_string(rn)
            st.sb.write_string(", ")
            st.sb.write_string(n.to_string())
            st.sb.write_char('\n')
          }
          _ => ()
        }
      } else if i.arg1.is_tmp() {
        let rn = @types.rv64_reg_name(i.to.tmp_val())
        let rm = @types.rv64_reg_name(i.arg1.tmp_val())
        st.sb.write_string("\tmv ")
        st.sb.write_string(rn)
        st.sb.write_string(", ")
        st.sb.write_string(rm)
        st.sb.write_char('\n')
      }
    }
    @types.Addr =>
      if i.arg1.is_slot() {
        let rn = @types.rv64_reg_name(i.to.tmp_val())
        let s = rv64_slot(st, i.arg1.slot_val())
        if s >= -2048 && s <= 2047 {
          st.sb.write_string("\tadd ")
          st.sb.write_string(rn)
          st.sb.write_string(", fp, ")
          st.sb.write_string(s.to_string())
          st.sb.write_char('\n')
        } else {
          st.sb.write_string("\tli ")
          st.sb.write_string(rn)
          st.sb.write_string(", ")
          st.sb.write_string(s.to_string())
          st.sb.write_char('\n')
          st.sb.write_string("\tadd ")
          st.sb.write_string(rn)
          st.sb.write_string(", fp, ")
          st.sb.write_string(rn)
          st.sb.write_char('\n')
        }
      }
    @types.Salloc =>
      if i.arg1.is_con() {
        let con = st.fn_.cons[i.arg1.con_val()]
        let sz = con.bits.i
        st.sb.write_string("\tsub sp, sp, ")
        st.sb.write_string(sz.to_string())
        st.sb.write_char('\n')
        if !i.to.is_none() {
          let rn = @types.rv64_reg_name(i.to.tmp_val())
          st.sb.write_string("\tmv ")
          st.sb.write_string(rn)
          st.sb.write_string(", sp\n")
        }
      }
    @types.Call =>
      if i.arg1.is_con() {
        let con = st.fn_.cons[i.arg1.con_val()]
        match con.kind {
          @types.CAddr => {
            st.sb.write_string("\tcall ")
            st.sb.write_string(st.interner.get(con.label))
            st.sb.write_char('\n')
          }
          _ => abort("invalid call target")
        }
      } else if i.arg1.is_tmp() {
        let rn = @types.rv64_reg_name(i.arg1.tmp_val())
        st.sb.write_string("\tjalr ")
        st.sb.write_string(rn)
        st.sb.write_char('\n')
      }
    _ => {
      let mut found = false
      for entry in rv64_omap {
        if entry.0 == i.op.index() {
          if entry.1 == KA ||
            entry.1 == i.cls.code() ||
            (entry.1 == KI && i.cls.base() == 0) {
            rv64_emitf(st, entry.2, i)
            found = true
            break
          }
        }
      }
      if !found {
        st.sb.write_string("# unknown instruction: ")
        st.sb.write_string(i.op.name())
        st.sb.write_char('\n')
      }
    }
  }
}

///|
// Emit function prologue and epilogue (C rv64_emitfn).
fn rv64_emitfn(st : Rv64EmitState) -> Unit {
  let fn_ = st.fn_

  st.sb.write_string("\t.globl ")
  st.sb.write_string(fn_.name)
  st.sb.write_char('\n')
  st.sb.write_string("\t.type ")
  st.sb.write_string(fn_.name)
  st.sb.write_string(", @function\n")
  st.sb.write_string(fn_.name)
  st.sb.write_string(":\n")

  if fn_.is_vararg {
    st.sb.write_string("\tadd sp, sp, -64\n")
    for r in @types.A0..<(@types.A7 + 1) {
      st.sb.write_string("\tsd ")
      st.sb.write_string(@types.rv64_reg_name(r))
      st.sb.write_string(", ")
      st.sb.write_string(((r - @types.A0) * 8).to_string())
      st.sb.write_string("(sp)\n")
    }
  }

  st.sb.write_string("\tsd fp, -16(sp)\n")
  st.sb.write_string("\tsd ra, -8(sp)\n")
  st.sb.write_string("\tadd fp, sp, -16\n")

  let mut frame = (16 + 4 * fn_.slot + 15) & -16
  for pr in @types.rv64_rclob {
    if (fn_.reg & (1UL << pr)) != 0UL {
      frame = frame + 8
    }
  }
  frame = (frame + 15) & -16

  if frame <= 2048 {
    st.sb.write_string("\tadd sp, sp, -")
    st.sb.write_string(frame.to_string())
    st.sb.write_char('\n')
  } else {
    st.sb.write_string("\tli t6, ")
    st.sb.write_string(frame.to_string())
    st.sb.write_char('\n')
    st.sb.write_string("\tsub sp, sp, t6\n")
  }

  let mut off = 0
  for pr in @types.rv64_rclob {
    if (fn_.reg & (1UL << pr)) != 0UL {
      let reg_name = @types.rv64_reg_name(pr)
      if pr < @types.FT0 {
        st.sb.write_string("\tsd ")
        st.sb.write_string(reg_name)
        st.sb.write_string(", ")
        st.sb.write_string(off.to_string())
        st.sb.write_string("(sp)\n")
      } else {
        st.sb.write_string("\tfsd ")
        st.sb.write_string(reg_name)
        st.sb.write_string(", ")
        st.sb.write_string(off.to_string())
        st.sb.write_string("(sp)\n")
      }
      off = off + 8
    }
  }

  let mut lbl = false
  for bid in fn_.def_order {
    let b = fn_.blks[bid]
    if lbl || b.npred > 1 {
      st.sb.write_string(".L")
      st.sb.write_string(bid.to_string())
      st.sb.write_string(":\n")
    }
    for i in b.ins {
      rv64_emitins(st, i)
    }
    lbl = true

    match b.jmp.kind {
      @types.Jret0 => {
        off = 0
        for pr in @types.rv64_rclob {
          if (fn_.reg & (1UL << pr)) != 0UL {
            let reg_name = @types.rv64_reg_name(pr)
            if pr < @types.FT0 {
              st.sb.write_string("\tld ")
              st.sb.write_string(reg_name)
              st.sb.write_string(", ")
              st.sb.write_string(off.to_string())
              st.sb.write_string("(sp)\n")
            } else {
              st.sb.write_string("\tfld ")
              st.sb.write_string(reg_name)
              st.sb.write_string(", ")
              st.sb.write_string(off.to_string())
              st.sb.write_string("(sp)\n")
            }
            off = off + 8
          }
        }
        st.sb.write_string("\tadd sp, fp, ")
        st.sb.write_string(
          (16 + (if fn_.is_vararg { 64 } else { 0 })).to_string(),
        )
        st.sb.write_char('\n')
        st.sb.write_string("\tld ra, 8(fp)\n")
        st.sb.write_string("\tld fp, 0(fp)\n")
        st.sb.write_string("\tret\n")
      }
      @types.Jjmp =>
        if b.jmp.s1 >= 0 && b.jmp.s1 != bid + 1 {
          st.sb.write_string("\tj .L")
          st.sb.write_string(b.jmp.s1.to_string())
          st.sb.write_char('\n')
        } else {
          lbl = false
        }
      @types.Jjnz => {
        if b.jmp.s2 >= 0 && b.jmp.s2 == bid + 1 {
          let tmp = b.jmp.s1
          b.jmp.s1 = b.jmp.s2
          b.jmp.s2 = tmp
        }
        if b.jmp.arg.is_tmp() {
          let rn = @types.rv64_reg_name(b.jmp.arg.tmp_val())
          st.sb.write_string("\tbeqz ")
          st.sb.write_string(rn)
          st.sb.write_string(", .L")
          st.sb.write_string(b.jmp.s2.to_string())
          st.sb.write_char('\n')
          st.sb.write_string("\tj .L")
          st.sb.write_string(b.jmp.s1.to_string())
          st.sb.write_char('\n')
        }
      }
      _ => ()
    }
  }

  st.sb.write_string("\t.size ")
  st.sb.write_string(fn_.name)
  st.sb.write_string(", .-")
  st.sb.write_string(fn_.name)
  st.sb.write_char('\n')
}

///|
// Main RISC-V emission entry point.
pub fn emit_rv64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  print_dbg : Bool,
  all_typs : Array[@types.Typ],
) -> String {
  let sb = StringBuilder()
  let st = rv64_emit_new(fn_, interner, sb)

  rv64_emitfn(st)

  if print_dbg {
    let out = StringBuilder()
    out.write_string("> After RISC-V code generation:\n")
    out.to_string()
  } else {
    st.sb.to_string()
  }
}
