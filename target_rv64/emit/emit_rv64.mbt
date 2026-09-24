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
// Module-global base for block labels (C rv64/emit.c static id0); advances by
// fn->nblk after each function so labels stay unique across the module.
let rv64_id0 : Array[Int] = [0]

///|
// Reset the block-label base (called once per module).
pub fn rv64_emit_reset() -> Unit {
  rv64_id0[0] = 0
}

///|
priv struct Rv64EmitState {
  fn_ : @types.Fn
  interner : @util.Interner
  gasloc : String
  gassym : String
  sb : StringBuilder
}

///|
fn rv64_emit_new(
  fn_ : @types.Fn,
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  sb : StringBuilder,
) -> Rv64EmitState {
  Rv64EmitState::{ fn_, interner, gasloc, gassym, sb, }
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
  (@types.Reqz.index(), KI, "seqz %=, %0"),
  (@types.Rnez.index(), KI, "snez %=, %0"),
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
      // Local (fp-constant) symbols are printed quoted, e.g. ".Lfp0".
      let p = if con.is_local { st.gasloc } else { st.gassym }
      let q = if con.is_local { "\"" } else { "" }
      st.sb.write_string(q)
      st.sb.write_string(p)
      st.sb.write_string(st.interner.get(con.label))
      if con.bits.i != 0L {
        if con.bits.i > 0L {
          st.sb.write_string("+")
          st.sb.write_string(con.bits.i.to_string())
        } else {
          st.sb.write_string(con.bits.i.to_string())
        }
      }
      st.sb.write_string(q)
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
// Load/store instruction names by (op, result class).
fn rv64_load_name(op : @types.Op, k : @types.Class) -> String {
  match op {
    @types.Loadsb => "lb"
    @types.Loadub => "lbu"
    @types.Loadsh => "lh"
    @types.Loaduh => "lhu"
    @types.Loadsw => "lw"
    @types.Loaduw => if k == @types.Kl { "lwu" } else { "lw" }
    @types.Load =>
      match k {
        @types.Kw => "lw"
        @types.Ks => "flw"
        @types.Kd => "fld"
        _ => "ld"
      }
    _ => "ld"
  }
}

///|
fn rv64_store_name(op : @types.Op) -> String {
  match op {
    @types.Storeb => "sb"
    @types.Storeh => "sh"
    @types.Storew => "sw"
    @types.Storel => "sd"
    @types.Stores => "fsw"
    @types.Stored => "fsd"
    _ => "sd"
  }
}

///|
// Emit `li t6, off` + `add t6, fp, t6` for slots beyond a 12-bit offset.
fn rv64_far_slot(
  st : Rv64EmitState,
  ldname : String,
  dst : String,
  off : Int,
) -> Unit {
  st.sb.write_string("\tli t6, ")
  st.sb.write_string(off.to_string())
  st.sb.write_char('\n')
  st.sb.write_string("\tadd t6, fp, t6\n")
  st.sb.write_string("\t")
  st.sb.write_string(ldname)
  st.sb.write_string(" ")
  st.sb.write_string(dst)
  st.sb.write_string(", 0(t6)\n")
}

///|
// Emit a load instruction from various address forms (C mem-operand cases).
fn rv64_emit_load(
  st : Rv64EmitState,
  ldname : String,
  dst : String,
  addr : @types.Ref,
  is_float : Bool,
) -> Unit {
  if addr.is_tmp() {
    st.sb.write_string("\t")
    st.sb.write_string(ldname)
    st.sb.write_string(" ")
    st.sb.write_string(dst)
    st.sb.write_string(", 0(")
    st.sb.write_string(@types.rv64_reg_name(addr.tmp_val()))
    st.sb.write_string(")\n")
  } else if addr.is_slot() {
    let off = rv64_slot(st, addr.slot_val())
    if off >= -2048 && off <= 2047 {
      st.sb.write_string("\t")
      st.sb.write_string(ldname)
      st.sb.write_string(" ")
      st.sb.write_string(dst)
      st.sb.write_string(", ")
      st.sb.write_string(off.to_string())
      st.sb.write_string("(fp)\n")
    } else {
      rv64_far_slot(st, ldname, dst, off)
    }
  } else if addr.is_con() {
    let con = st.fn_.cons[addr.con_val()]
    match con.kind {
      @types.CAddr => {
        if is_float {
          // C rv64/emit.c %M: float loads from a symbol need a scratch reg.
          st.sb.write_string("\t")
          st.sb.write_string(ldname)
          st.sb.write_string(" ")
          st.sb.write_string(dst)
          st.sb.write_string(", ")
          rv64_emitaddr(st, con)
          st.sb.write_string(", t6\n")
        } else {
          // C %M: integer loads from a symbol use the bare "lw dst, sym" form.
          st.sb.write_string("\t")
          st.sb.write_string(ldname)
          st.sb.write_string(" ")
          st.sb.write_string(dst)
          st.sb.write_string(", ")
          rv64_emitaddr(st, con)
          st.sb.write_char('\n')
        }
      }
      _ => abort("invalid load address")
    }
  } else if addr.is_mem() {
    // Float-constant stash reference: `lla t6, fpN` + load
    let m = st.fn_.mems[addr.mem_val()]
    match m.offset.kind {
      @types.CAddr => {
        // fp-constant stash: float load with the scratch register.
        st.sb.write_string("\t")
        st.sb.write_string(ldname)
        st.sb.write_string(" ")
        st.sb.write_string(dst)
        st.sb.write_string(", ")
        rv64_emitaddr(st, m.offset)
        st.sb.write_string(", t6\n")
      }
      _ => abort("invalid stash address")
    }
  } else {
    abort("invalid load address operand")
  }
}

///|
// Emit a store instruction to various address forms.
fn rv64_emit_store(
  st : Rv64EmitState,
  stname : String,
  val : String,
  addr : @types.Ref,
) -> Unit {
  if addr.is_tmp() {
    st.sb.write_string("\t")
    st.sb.write_string(stname)
    st.sb.write_string(" ")
    st.sb.write_string(val)
    st.sb.write_string(", 0(")
    st.sb.write_string(@types.rv64_reg_name(addr.tmp_val()))
    st.sb.write_string(")\n")
  } else if addr.is_slot() {
    let off = rv64_slot(st, addr.slot_val())
    if off >= -2048 && off <= 2047 {
      st.sb.write_string("\t")
      st.sb.write_string(stname)
      st.sb.write_string(" ")
      st.sb.write_string(val)
      st.sb.write_string(", ")
      st.sb.write_string(off.to_string())
      st.sb.write_string("(fp)\n")
    } else {
      rv64_far_slot(st, stname, val, off)
    }
  } else if addr.is_con() {
    let con = st.fn_.cons[addr.con_val()]
    match con.kind {
      @types.CAddr => {
        st.sb.write_string("\t")
        st.sb.write_string(stname)
        st.sb.write_string(" ")
        st.sb.write_string(val)
        st.sb.write_string(", ")
        rv64_emitaddr(st, con)
        st.sb.write_string(", t6\n")
      }
      _ => abort("invalid store address")
    }
  } else {
    abort("invalid store address operand")
  }
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
        if i.cls.base() == 0 {
          st.sb.write_string("\tmv ")
        } else {
          st.sb.write_string("\tfmv.")
          st.sb.write_string(clschr[i.cls.code()])
          st.sb.write_string(" ")
        }
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
      } else if i.arg1.is_con() {
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
          _ => abort("invalid address")
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
      } else if i.arg1.is_tmp() {
        // dynamic stack allocation: the size lives in a register
        let rm = @types.rv64_reg_name(i.arg1.tmp_val())
        st.sb.write_string("\tsub sp, sp, ")
        st.sb.write_string(rm)
        st.sb.write_char('\n')
        if !i.to.is_none() {
          let rn = @types.rv64_reg_name(i.to.tmp_val())
          st.sb.write_string("\tmv ")
          st.sb.write_string(rn)
          st.sb.write_string(", sp\n")
        }
      }
    @types.Load
    | @types.Loadsb
    | @types.Loadub
    | @types.Loadsh
    | @types.Loaduh
    | @types.Loadsw
    | @types.Loaduw =>
      if i.to.is_tmp() {
        let rn = @types.rv64_reg_name(i.to.tmp_val())
        rv64_emit_load(
          st,
          rv64_load_name(i.op, i.cls),
          rn,
          i.arg1,
          i.cls.base() == 1,
        )
      }
    @types.Stored
    | @types.Stores
    | @types.Storel
    | @types.Storew
    | @types.Storeh
    | @types.Storeb =>
      if i.arg1.is_tmp() {
        let vn = @types.rv64_reg_name(i.arg1.tmp_val())
        rv64_emit_store(st, rv64_store_name(i.op), vn, i.arg2)
      }
    @types.Call =>
      if i.arg1.is_con() {
        let con = st.fn_.cons[i.arg1.con_val()]
        match con.kind {
          @types.CAddr => {
            st.sb.write_string("\tcall ")
            st.sb.write_string(st.gassym)
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

  // C emitfnlnk: section, .balign (default 16), .globl, label.
  st.sb.write_string(".text\n.balign 16\n")
  if fn_.is_export {
    st.sb.write_string(".globl \{st.gassym}\{fn_.name}\n")
  }
  st.sb.write_string("\{st.gassym}\{fn_.name}:\n")

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
  // main.c rebuilds the link chain in RPO order after rega; emit in that order.
  for idx in 0..<fn_.rpo.length() {
    let bid = fn_.rpo[idx]
    let b = fn_.blks[bid]
    let next = if idx + 1 < fn_.rpo.length() { fn_.rpo[idx + 1] } else { -1 }
    if lbl || b.npred > 1 {
      st.sb.write_string(st.gasloc)
      st.sb.write_string((rv64_id0[0] + b.rpo_id).to_string())
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
        if b.jmp.s1 >= 0 && b.jmp.s1 != next {
          st.sb.write_string("\tj \{st.gasloc}")
          st.sb.write_string((rv64_id0[0] + fn_.blks[b.jmp.s1].rpo_id).to_string())
          st.sb.write_char('\n')
        } else {
          lbl = false
        }
      @types.Jjnz =>
        if b.jmp.arg.is_tmp() {
          let rn = @types.rv64_reg_name(b.jmp.arg.tmp_val())
          if b.jmp.s2 >= 0 && b.jmp.s2 == next {
            // the false target is the next block: branch on true and
            // fall through
            st.sb.write_string("\tbnez ")
            st.sb.write_string(rn)
            st.sb.write_string(", \{st.gasloc}")
            st.sb.write_string((rv64_id0[0] + fn_.blks[b.jmp.s1].rpo_id).to_string())
            st.sb.write_char('\n')
            // C Jmp: b->s1 (now the fallthrough) == b->link -> no label next.
            lbl = false
          } else {
            st.sb.write_string("\tbeqz ")
            st.sb.write_string(rn)
            st.sb.write_string(", \{st.gasloc}")
            st.sb.write_string((rv64_id0[0] + fn_.blks[b.jmp.s2].rpo_id).to_string())
            st.sb.write_char('\n')
            if b.jmp.s1 >= 0 && b.jmp.s1 == next {
              // the true target is the next block: fall through
              lbl = false
            } else {
              // the true target is not the next block: jump to it
              st.sb.write_string("\tj \{st.gasloc}")
              st.sb.write_string((rv64_id0[0] + fn_.blks[b.jmp.s1].rpo_id).to_string())
              st.sb.write_char('\n')
            }
          }
        }
      _ => ()
    }
  }

  // C elf_emitfnfin emits the function type/size after each function.
  st.sb.write_string(".type \{st.gassym}\{fn_.name}, @function\n")
  st.sb.write_string(".size \{st.gassym}\{fn_.name}, .-\{st.gassym}\{fn_.name}\n")
  rv64_id0[0] = rv64_id0[0] + fn_.nblk()
}

///|
// Main RISC-V emission entry point.
pub fn emit_rv64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  print_dbg : Bool,
  all_typs : Array[@types.Typ],
) -> String {
  let _ = (gasloc, gassym)
  let sb = StringBuilder()
  let st = rv64_emit_new(fn_, interner, gasloc, gassym, sb)

  rv64_emitfn(st)

  if print_dbg {
    let out = StringBuilder()
    out.write_string("> After RISC-V code generation:\n")
    out.to_string()
  } else {
    st.sb.to_string()
  }
}
