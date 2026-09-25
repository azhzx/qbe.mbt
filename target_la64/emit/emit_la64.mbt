///|
// LoongArch 64 (la64) GAS assembly emission - corresponds to a hypothetical
// upstream loongarch64/emit.c. Emits GNU-as LoongArch syntax: destination
// first, `$`-prefixed ABI register names, memory operands written as
// `$base, offset`.

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
// Map a class code to the "w/l/s/d" suffix (C clschr).
let clschr : Array[String] = ["w", "l", "s", "d"]

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
priv struct La64EmitState {
  fn_ : @types.Fn
  interner : @util.Interner
  gasloc : String
  gassym : String
  sb : StringBuilder
}

///|
fn la64_emit_new(
  fn_ : @types.Fn,
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  sb : StringBuilder,
) -> La64EmitState {
  La64EmitState::{ fn_, interner, gasloc, gassym, sb, }
}

///|
// LoongArch instruction format table (C omap).
// (op index, cls match code, format string). The emitf register handlers
// (`%=`, `%0`, `%1`, `%?`) print `$`-prefixed register names; literal `$`
// appears only for `$zero`/`$fcc0` scratch registers. All ALU operands are
// registers (isel materializes constants).
let la64_omap : Array[(Int, Int, String)] = [
  (@types.Add.index(), KI, "add.%k %=, %0, %1"),
  (@types.Add.index(), KA, "fadd.%k %=, %0, %1"),
  (@types.Sub.index(), KI, "sub.%k %=, %0, %1"),
  (@types.Sub.index(), KA, "fsub.%k %=, %0, %1"),
  (@types.Div.index(), KI, "div.%k %=, %0, %1"),
  (@types.Div.index(), KA, "fdiv.%k %=, %0, %1"),
  (@types.Rem.index(), KI, "mod.%k %=, %0, %1"),
  (@types.Udiv.index(), KI, "div.%ku %=, %0, %1"),
  (@types.Urem.index(), KI, "mod.%ku %=, %0, %1"),
  (@types.Mul.index(), KI, "mul.%k %=, %0, %1"),
  (@types.Mul.index(), KA, "fmul.%k %=, %0, %1"),
  (@types.And.index(), KI, "and %=, %0, %1"),
  (@types.Or.index(), KI, "or %=, %0, %1"),
  (@types.Xor.index(), KI, "xor %=, %0, %1"),
  (@types.Sar.index(), KI, "sra.%k %=, %0, %1"),
  (@types.Shr.index(), KI, "srl.%k %=, %0, %1"),
  (@types.Shl.index(), KI, "sll.%k %=, %0, %1"),
  (@types.Csltl.index(), KI, "slt %=, %0, %1"),
  (@types.Cultl.index(), KI, "sltu %=, %0, %1"),
  (@types.Ceqs.index(), KI, "fcmp.ceq.s $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (
    @types.Cnes.index(),
    KI,
    "fcmp.ceq.s $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0\n\txori %=, %=, 1",
  ),
  (@types.Cles.index(), KI, "fcmp.cle.s $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Clts.index(), KI, "fcmp.clt.s $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Cges.index(), KI, "fcmp.cge.s $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Cgts.index(), KI, "fcmp.cgt.s $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Cos.index(), KI, "fcmp.cor.s $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Cuos.index(), KI, "fcmp.cun.s $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Ceqd.index(), KI, "fcmp.ceq.d $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (
    @types.Cned.index(),
    KI,
    "fcmp.ceq.d $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0\n\txori %=, %=, 1",
  ),
  (@types.Cled.index(), KI, "fcmp.cle.d $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Cltd.index(), KI, "fcmp.clt.d $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Cged.index(), KI, "fcmp.cge.d $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Cgtd.index(), KI, "fcmp.cgt.d $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Cod.index(), KI, "fcmp.cor.d $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Cuod.index(), KI, "fcmp.cun.d $fcc0, %0, %1\n\tmovcf2gr %=, $fcc0"),
  (@types.Extsb.index(), KI, "ext.w.b %=, %0"),
  (@types.Extub.index(), KI, "andi %=, %0, 255"),
  (@types.Extsh.index(), KI, "ext.w.h %=, %0"),
  (@types.Extuh.index(), KI, "slli.d %=, %0, 48\n\tsrli.d %=, %=, 48"),
  (@types.Extsw.index(), KL, "addi.w %=, %0, 0"),
  (@types.Extuw.index(), KL, "slli.d %=, %0, 32\n\tsrli.d %=, %=, 32"),
  (@types.Truncd.index(), KS, "fcvt.s.d %=, %0"),
  (@types.Exts.index(), KD, "fcvt.d.s %=, %0"),
  (@types.Stosi.index(), KW, "ftintrz.w.s %=, %0"),
  (@types.Stosi.index(), KL, "ftintrz.l.s %=, %0"),
  (@types.Dtosi.index(), KW, "ftintrz.w.d %=, %0"),
  (@types.Dtosi.index(), KL, "ftintrz.l.d %=, %0"),
  (@types.Swtof.index(), KA, "ffint.%k.w %=, %0"),
  (@types.Sltof.index(), KA, "ffint.%k.l %=, %0"),
  (@types.Cast.index(), KW, "movfr2gr.s %=, %0"),
  (@types.Cast.index(), KL, "movfr2gr.d %=, %0"),
  (@types.Cast.index(), KS, "movgr2fr.w %=, %0"),
  (@types.Cast.index(), KD, "movgr2fr.d %=, %0"),
  (@types.Copy.index(), KI, "or %=, %0, $zero"),
  (@types.Copy.index(), KA, "fmov.%k %=, %0"),
  (
    @types.Swap.index(),
    KI,
    "or %?, %0, $zero\n\tor %0, %1, $zero\n\tor %1, %?, $zero",
  ),
  (
    @types.Swap.index(),
    KA,
    "fmov.%k %?, %0\n\tfmov.%k %0, %1\n\tfmov.%k %1, %?",
  ),
]

///|
// Load/store instruction names by (op, result class).
fn la64_load_name(op : @types.Op, k : @types.Class) -> String {
  match op {
    @types.Loadsb => "ld.b"
    @types.Loadub => "ld.bu"
    @types.Loadsh => "ld.h"
    @types.Loaduh => "ld.hu"
    @types.Loadsw => "ld.w"
    @types.Loaduw => if k == @types.Kl { "ld.wu" } else { "ld.w" }
    @types.Load =>
      match k {
        @types.Kw => "ld.w"
        @types.Ks => "fld.s"
        @types.Kd => "fld.d"
        _ => "ld.d"
      }
    _ => "ld.d"
  }
}

///|
fn la64_store_name(op : @types.Op, k : @types.Class) -> String {
  match op {
    @types.Storeb => "st.b"
    @types.Storeh => "st.h"
    @types.Storew => "st.w"
    @types.Storel => "st.d"
    @types.Stores => "fst.s"
    @types.Stored => "fst.d"
    _ => "st.d"
  }
}

///|
// Slot offset calculation (C slot in emit.c).
fn la64_slot(st : La64EmitState, s : Int) -> Int {
  let x = sign_ext29(s)
  if x < 0 {
    8 * -x
  } else {
    -4 * (st.fn_.slot - x)
  }
}

///|
// Emit a symbol reference (C emitaddr): `sym`, `sym+off`, or `sym-off`.
fn la64_emitaddr(st : La64EmitState, con : @types.Con) -> Unit {
  match con.kind {
    @types.CAddr => {
      st.sb.write_string(st.gassym)
      st.sb.write_string(st.interner.get(con.label))
      if con.bits.i != 0L {
        if con.bits.i > 0L {
          st.sb.write_string("+")
          st.sb.write_string(con.bits.i.to_string())
        } else {
          st.sb.write_string(con.bits.i.to_string())
        }
      }
    }
    _ => abort("invalid address constant")
  }
}

///|
// Emit `li.d $t8, imm` + `op $t8, $fp, $t8` for offsets that do not fit in
// a 12-bit immediate.
fn la64_far_slot(
  st : La64EmitState,
  ldname : String,
  dst : String,
  off : Int,
) -> Unit {
  st.sb.write_string("\tli.d $t8, ")
  st.sb.write_string(off.to_string())
  st.sb.write_char('\n')
  st.sb.write_string("\tadd.d $t8, $fp, $t8\n")
  st.sb.write_string("\t")
  st.sb.write_string(ldname)
  st.sb.write_string(" ")
  st.sb.write_string(dst)
  st.sb.write_string(", $t8, 0\n")
}

///|
// Emit a load instruction from various address forms (C mem-operand cases).
fn la64_emit_load(
  st : La64EmitState,
  ldname : String,
  dst : String,
  addr : @types.Ref,
) -> Unit {
  if addr.is_tmp() {
    st.sb.write_string("\t")
    st.sb.write_string(ldname)
    st.sb.write_string(" ")
    st.sb.write_string(dst)
    st.sb.write_string(", $")
    st.sb.write_string(@types.la64_reg_name(addr.tmp_val()))
    st.sb.write_string(", 0\n")
  } else if addr.is_slot() {
    let off = la64_slot(st, addr.slot_val())
    if off >= -2048 && off <= 2047 {
      st.sb.write_string("\t")
      st.sb.write_string(ldname)
      st.sb.write_string(" ")
      st.sb.write_string(dst)
      st.sb.write_string(", $fp, ")
      st.sb.write_string(off.to_string())
      st.sb.write_char('\n')
    } else {
      la64_far_slot(st, ldname, dst, off)
    }
  } else if addr.is_con() {
    let con = st.fn_.cons[addr.con_val()]
    match con.kind {
      @types.CAddr => {
        st.sb.write_string("\tla.local $t8, ")
        la64_emitaddr(st, con)
        st.sb.write_char('\n')
        st.sb.write_string("\t")
        st.sb.write_string(ldname)
        st.sb.write_string(" ")
        st.sb.write_string(dst)
        st.sb.write_string(", $t8, 0\n")
      }
      _ => abort("invalid load address")
    }
  } else if addr.is_mem() {
    // Float-constant stash reference: `la.local $t8, fpN` + load
    let m = st.fn_.mems[addr.mem_val()]
    match m.offset.kind {
      @types.CAddr => {
        st.sb.write_string("\tla.local $t8, ")
        la64_emitaddr(st, m.offset)
        st.sb.write_char('\n')
        st.sb.write_string("\t")
        st.sb.write_string(ldname)
        st.sb.write_string(" ")
        st.sb.write_string(dst)
        st.sb.write_string(", $t8, 0\n")
      }
      _ => abort("invalid stash address")
    }
  } else {
    abort("invalid load address operand")
  }
}

///|
// Emit a store instruction to various address forms.
fn la64_emit_store(
  st : La64EmitState,
  stname : String,
  val : String,
  addr : @types.Ref,
) -> Unit {
  if addr.is_tmp() {
    st.sb.write_string("\t")
    st.sb.write_string(stname)
    st.sb.write_string(" ")
    st.sb.write_string(val)
    st.sb.write_string(", $")
    st.sb.write_string(@types.la64_reg_name(addr.tmp_val()))
    st.sb.write_string(", 0\n")
  } else if addr.is_slot() {
    let off = la64_slot(st, addr.slot_val())
    if off >= -2048 && off <= 2047 {
      st.sb.write_string("\t")
      st.sb.write_string(stname)
      st.sb.write_string(" ")
      st.sb.write_string(val)
      st.sb.write_string(", $fp, ")
      st.sb.write_string(off.to_string())
      st.sb.write_char('\n')
    } else {
      // value must survive the scratch register use: st.d the value through
      // a computed address is fine because val is a register, not $t8.
      la64_far_slot(st, stname, val, off)
    }
  } else if addr.is_con() {
    let con = st.fn_.cons[addr.con_val()]
    match con.kind {
      @types.CAddr => {
        st.sb.write_string("\tla.local $t8, ")
        la64_emitaddr(st, con)
        st.sb.write_char('\n')
        st.sb.write_string("\t")
        st.sb.write_string(stname)
        st.sb.write_string(" ")
        st.sb.write_string(val)
        st.sb.write_string(", $t8, 0\n")
      }
      _ => abort("invalid store address")
    }
  } else {
    abort("invalid store address operand")
  }
}

///|
// Format and emit an instruction (C emitf).
fn la64_emitf(st : La64EmitState, fmt : String, i : @types.Ins) -> Unit {
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
          st.sb.write_string("$t8")
        } else {
          st.sb.write_string("$ft15")
        }
      'k' => st.sb.write_string(clschr[i.cls.code()])
      '=' =>
        if i.to.is_tmp() {
          st.sb.write_string("$")
          st.sb.write_string(@types.la64_reg_name(i.to.tmp_val()))
        }
      '0' =>
        if i.arg1.is_tmp() {
          st.sb.write_string("$")
          st.sb.write_string(@types.la64_reg_name(i.arg1.tmp_val()))
        } else if i.arg1.is_con() {
          let con = st.fn_.cons[i.arg1.con_val()]
          match con.kind {
            @types.CBits => st.sb.write_string(con.bits.i.to_string())
            _ => abort("invalid constant for immediate")
          }
        }
      '1' =>
        if i.arg2.is_tmp() {
          st.sb.write_string("$")
          st.sb.write_string(@types.la64_reg_name(i.arg2.tmp_val()))
        } else if i.arg2.is_con() {
          let con = st.fn_.cons[i.arg2.con_val()]
          match con.kind {
            @types.CBits => st.sb.write_string(con.bits.i.to_string())
            _ => abort("invalid constant for immediate")
          }
        }
      _ => ()
    }
  }
  st.sb.write_char('\n')
}

///|
// Emit a register-to-register copy (C emitcopy).
fn la64_emitcopy(
  st : La64EmitState,
  to : @types.Ref,
  from : @types.Ref,
  k : @types.Class,
) -> Unit {
  let ins = @types.Ins::new(@types.Copy, k, to, from, @types.Ref::none())
  la64_emitins(st, ins)
}

///|
// Emit a single instruction (C emitins).
fn la64_emitins(st : La64EmitState, i : @types.Ins) -> Unit {
  match i.op {
    @types.Nop => ()
    @types.Dbgloc =>
      @util.emit_dbgloc(i.arg1.rint_val(), i.arg2.rint_val(), st.sb)
    @types.Copy => {
      if i.to.eq(i.arg1) {
        return
      }
      if i.arg1.is_con() {
        let con = st.fn_.cons[i.arg1.con_val()]
        match con.kind {
          @types.CAddr => {
            let rn = "$" + @types.la64_reg_name(i.to.tmp_val())
            st.sb.write_string("\tla.local ")
            st.sb.write_string(rn)
            st.sb.write_string(", ")
            la64_emitaddr(st, con)
            st.sb.write_char('\n')
          }
          @types.CBits => {
            let rn = "$" + @types.la64_reg_name(i.to.tmp_val())
            st.sb.write_string("\tli.d ")
            st.sb.write_string(rn)
            st.sb.write_string(", ")
            st.sb.write_string(con.bits.i.to_string())
            st.sb.write_char('\n')
          }
          _ => ()
        }
      } else if i.arg1.is_tmp() {
        if i.cls.base() == 0 {
          la64_emitf(st, "or %=, %0, $zero", i)
        } else {
          la64_emitf(st, "fmov.%k %=, %0", i)
        }
      }
    }
    @types.Addr =>
      if i.arg1.is_slot() {
        let rn = "$" + @types.la64_reg_name(i.to.tmp_val())
        let s = la64_slot(st, i.arg1.slot_val())
        if s >= -2048 && s <= 2047 {
          st.sb.write_string("\taddi.d ")
          st.sb.write_string(rn)
          st.sb.write_string(", $fp, ")
          st.sb.write_string(s.to_string())
          st.sb.write_char('\n')
        } else {
          st.sb.write_string("\tli.d ")
          st.sb.write_string(rn)
          st.sb.write_string(", ")
          st.sb.write_string(s.to_string())
          st.sb.write_char('\n')
          st.sb.write_string("\tadd.d ")
          st.sb.write_string(rn)
          st.sb.write_string(", $fp, ")
          st.sb.write_string(rn)
          st.sb.write_char('\n')
        }
      } else if i.arg1.is_con() {
        let con = st.fn_.cons[i.arg1.con_val()]
        match con.kind {
          @types.CAddr => {
            let rn = "$" + @types.la64_reg_name(i.to.tmp_val())
            st.sb.write_string("\tla.local ")
            st.sb.write_string(rn)
            st.sb.write_string(", ")
            la64_emitaddr(st, con)
            st.sb.write_char('\n')
          }
          _ => abort("invalid address")
        }
      }
    @types.Salloc => {
      // The signed amount convention matches the rv64 port: positive
      // values allocate (sp decreases), negative values restore.
      if i.arg1.is_con() {
        let amt = st.fn_.cons[i.arg1.con_val()].bits.i
        if amt >= -2047L && amt <= 2048L {
          st.sb.write_string("\taddi.d $sp, $sp, ")
          st.sb.write_string((-amt).to_string())
          st.sb.write_char('\n')
        } else {
          st.sb.write_string("\tli.d $t8, ")
          st.sb.write_string(amt.to_string())
          st.sb.write_char('\n')
          st.sb.write_string("\tsub.d $sp, $sp, $t8\n")
        }
      } else if i.arg1.is_tmp() {
        let rm = "$" + @types.la64_reg_name(i.arg1.tmp_val())
        st.sb.write_string("\tsub.d $sp, $sp, ")
        st.sb.write_string(rm)
        st.sb.write_char('\n')
      }
      if !i.to.is_none() && !i.to.eq(@types.Ref::tmp(@types.LA_SP)) {
        la64_emitcopy(st, i.to, @types.Ref::tmp(@types.LA_SP), @types.Kl)
      }
    }
    @types.Call =>
      if i.arg1.is_con() {
        let con = st.fn_.cons[i.arg1.con_val()]
        match con.kind {
          @types.CAddr => {
            st.sb.write_string("\tbl ")
            st.sb.write_string(st.gassym)
            st.sb.write_string(st.interner.get(con.label))
            st.sb.write_char('\n')
          }
          _ => abort("invalid call target")
        }
      } else if i.arg1.is_tmp() {
        let rm = "$" + @types.la64_reg_name(i.arg1.tmp_val())
        st.sb.write_string("\tjirl $ra, ")
        st.sb.write_string(rm)
        st.sb.write_string(", 0\n")
      }
    @types.Load
    | @types.Loadsb
    | @types.Loadub
    | @types.Loadsh
    | @types.Loaduh
    | @types.Loadsw
    | @types.Loaduw => {
      let rn = "$" + @types.la64_reg_name(i.to.tmp_val())
      la64_emit_load(st, la64_load_name(i.op, i.cls), rn, i.arg1)
    }
    @types.Stored
    | @types.Stores
    | @types.Storel
    | @types.Storew
    | @types.Storeh
    | @types.Storeb => {
      let vn = "$" + @types.la64_reg_name(i.arg1.tmp_val())
      la64_emit_store(st, la64_store_name(i.op, i.cls), vn, i.arg2)
    }
    _ => {
      let mut found = false
      for entry in la64_omap {
        if entry.0 == i.op.index() {
          if entry.1 == KA ||
            entry.1 == i.cls.code() ||
            (entry.1 == KI && i.cls.base() == 0) {
            la64_emitf(st, entry.2, i)
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
// Emit function prologue, body, and epilogues (C emitfn).
fn la64_emitfn(st : La64EmitState) -> Unit {
  let fn_ = st.fn_

  st.sb.write_string("\t.globl ")
  st.sb.write_string(st.gassym)
  st.sb.write_string(fn_.name)
  st.sb.write_char('\n')
  st.sb.write_string("\t.type ")
  st.sb.write_string(st.gassym)
  st.sb.write_string(fn_.name)
  st.sb.write_string(", @function\n")
  st.sb.write_string(st.gassym)
  st.sb.write_string(fn_.name)
  st.sb.write_string(":\n")

  if fn_.is_vararg {
    // Save the argument registers into the register save area so that
    // va_arg can spill them (GPR part, matching the rv64 port).
    st.sb.write_string("\taddi.d $sp, $sp, -64\n")
    for r in @types.LA_A0..<(@types.LA_A7 + 1) {
      st.sb.write_string("\tst.d $")
      st.sb.write_string(@types.la64_reg_name(r))
      st.sb.write_string(", $sp, ")
      st.sb.write_string(((r - @types.LA_A0) * 8).to_string())
      st.sb.write_char('\n')
    }
  }

  st.sb.write_string("\tst.d $fp, $sp, -16\n")
  st.sb.write_string("\tst.d $ra, $sp, -8\n")
  st.sb.write_string("\taddi.d $fp, $sp, -16\n")

  let mut frame = (16 + 4 * fn_.slot + 15) & -16
  for pr in @types.la64_rclob {
    if (fn_.reg & (1UL << pr)) != 0UL {
      frame = frame + 8
    }
  }
  frame = (frame + 15) & -16

  if frame <= 2048 {
    st.sb.write_string("\taddi.d $sp, $sp, -")
    st.sb.write_string(frame.to_string())
    st.sb.write_char('\n')
  } else {
    st.sb.write_string("\tli.d $t8, ")
    st.sb.write_string(frame.to_string())
    st.sb.write_char('\n')
    st.sb.write_string("\tsub.d $sp, $sp, $t8\n")
  }

  let mut off = 0
  for pr in @types.la64_rclob {
    if (fn_.reg & (1UL << pr)) != 0UL {
      let reg_name = "$" + @types.la64_reg_name(pr)
      if pr < @types.LA_FT0 {
        st.sb.write_string("\tst.d ")
        st.sb.write_string(reg_name)
        st.sb.write_string(", $sp, ")
        st.sb.write_string(off.to_string())
        st.sb.write_char('\n')
      } else {
        st.sb.write_string("\tfst.d ")
        st.sb.write_string(reg_name)
        st.sb.write_string(", $sp, ")
        st.sb.write_string(off.to_string())
        st.sb.write_char('\n')
      }
      off = off + 8
    }
  }

  let mut lbl = false
  for bid in fn_.def_order {
    let b = fn_.blks[bid]
    if lbl || b.npred > 1 {
      st.sb.write_string(st.gasloc)
      st.sb.write_string(bid.to_string())
      st.sb.write_string(":\n")
    }
    for i in b.ins {
      la64_emitins(st, i)
    }
    lbl = true

    match b.jmp.kind {
      @types.Jret0 => {
        off = 0
        for pr in @types.la64_rclob {
          if (fn_.reg & (1UL << pr)) != 0UL {
            let reg_name = "$" + @types.la64_reg_name(pr)
            if pr < @types.LA_FT0 {
              st.sb.write_string("\tld.d ")
              st.sb.write_string(reg_name)
              st.sb.write_string(", $sp, ")
              st.sb.write_string(off.to_string())
              st.sb.write_char('\n')
            } else {
              st.sb.write_string("\tfld.d ")
              st.sb.write_string(reg_name)
              st.sb.write_string(", $sp, ")
              st.sb.write_string(off.to_string())
              st.sb.write_char('\n')
            }
            off = off + 8
          }
        }
        st.sb.write_string("\taddi.d $sp, $fp, ")
        st.sb.write_string(
          (16 + (if fn_.is_vararg { 64 } else { 0 })).to_string(),
        )
        st.sb.write_char('\n')
        st.sb.write_string("\tld.d $ra, $fp, 8\n")
        st.sb.write_string("\tld.d $fp, $fp, 0\n")
        st.sb.write_string("\tret\n")
      }
      @types.Jjmp =>
        if b.jmp.s1 >= 0 && b.jmp.s1 != bid + 1 {
          st.sb.write_string("\tb ")
          st.sb.write_string(st.gasloc)
          st.sb.write_string(b.jmp.s1.to_string())
          st.sb.write_char('\n')
        } else {
          lbl = false
        }
      @types.Jjnz =>
        if b.jmp.arg.is_tmp() {
          let rn = "$" + @types.la64_reg_name(b.jmp.arg.tmp_val())
          let l1 = "\{st.gasloc}\{b.jmp.s1}"
          let l2 = "\{st.gasloc}\{b.jmp.s2}"
          if b.jmp.s2 >= 0 && b.jmp.s2 == bid + 1 {
            // the false target is the next block: branch on true and
            // fall through
            st.sb.write_string("\tbnez ")
            st.sb.write_string(rn)
            st.sb.write_string(", ")
            st.sb.write_string(l1)
            st.sb.write_char('\n')
          } else {
            st.sb.write_string("\tbeqz ")
            st.sb.write_string(rn)
            st.sb.write_string(", ")
            st.sb.write_string(l2)
            st.sb.write_char('\n')
            if !(b.jmp.s1 >= 0 && b.jmp.s1 == bid + 1) {
              // the true target is not the next block: jump to it
              st.sb.write_string("\tb ")
              st.sb.write_string(l1)
              st.sb.write_char('\n')
            }
          }
        }
      _ => ()
    }
  }

  st.sb.write_string("\t.size ")
  st.sb.write_string(st.gassym)
  st.sb.write_string(fn_.name)
  st.sb.write_string(", .-")
  st.sb.write_string(st.gassym)
  st.sb.write_string(fn_.name)
  st.sb.write_char('\n')
}

///|
// Main LoongArch emission entry point for one function.
pub fn emit_la64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  all_typs : Array[@types.Typ],
) -> String {
  let _ = all_typs
  let sb = StringBuilder()
  let st = la64_emit_new(fn_, interner, gasloc, gassym, sb)
  la64_emitfn(st)
  sb.to_string()
}
