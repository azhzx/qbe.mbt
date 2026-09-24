///|
// ARM64 (AArch64) GAS assembly emission - ported 1:1 from
// vendor/qbe/arm64/emit.c. Emits the reference snapshot's syntax: bare
// `xN`/`vN`/`sp` register names, `[base, offset]` memory operands, indirect
// `blr` calls and `.L<id>` local labels.

///|
const ARM64_KI : Int = -1

///|
const ARM64_KA : Int = -2

///|
priv struct Arm64EmitState {
  fn_ : @types.Fn
  interner : @util.Interner
  sb : StringBuilder
  gasloc : String
  gassym : String
  apple : Bool
  mut frame : Int
  mut padding : Int
}

///|
// Module-wide label counter (C static int id0 in arm64/emit.c).
let arm64_emit_id0 : Array[Int] = Array::make(1, 0)

///|
// Reset the module-wide label counter (the C binary resets it per process).
pub fn arm64_emit_reset() -> Unit {
  arm64_emit_id0[0] = 0
}

///|
// Condition-code suffixes indexed by the QBE comparison code (C ctoa/omap).
let arm64_cond : Array[String] = [
  "eq", "ne", "ge", "gt", "le", "lt", "cs", "hi", "ls", "cc", "eq", "ge", "gt", "ls",
  "mi", "ne", "vc", "vs",
]

///|
// Negated branch-condition suffixes (C ctoa[c][1] in arm64/emit.c). These are
// not the suffixes of the negated comparison code for float conditions, so
// they are encoded separately.
let arm64_cond_neg : Array[String] = [
  "ne", "eq", "lt", "le", "gt", "ge", "cc", "ls", "hi", "cs", "ne", "lt", "le", "hi",
  "pl", "eq", "vs", "vc",
]

///|
// Negation of a comparison code (C cmpneg / cmptab[..][0]).
fn arm64_cmpneg(c : Int) -> Int {
  match c {
    0 => 1
    1 => 0
    2 => 5
    3 => 4
    4 => 3
    5 => 2
    6 => 9
    7 => 8
    8 => 7
    9 => 6
    10 => 15
    11 => 14
    12 => 13
    13 => 12
    14 => 11
    15 => 10
    16 => 17
    17 => 16
    _ => c
  }
}

///|
// Format a 32-bit unsigned immediate as decimal.
fn arm64_u32(n : Int64) -> Int64 {
  n & 0xFFFFFFFFL
}

///|
// Sign-extend the low 32 bits (C `(int32_t)n`).
fn arm64_s32(n : Int64) -> Int64 {
  ((n & 0xFFFFFFFFL) ^ 0x80000000L) - 0x80000000L
}

///|
// Register name for class k (C rname in arm64/emit.c).
fn arm64_rname(r : Int, k : @types.Class) -> String raise {
  if r == @types.ARM64_SP {
    "sp"
  } else if r >= @types.ARM64_R0 && r <= @types.ARM64_LR {
    let n = r - @types.ARM64_R0
    match k {
      @types.Kw => "w" + n.to_string()
      @types.Kx | @types.Kl => "x" + n.to_string()
      _ => raise @util.QbeError::Ice("invalid class r=\{r} k=\{k.code()}")
    }
  } else if r >= @types.ARM64_V0 && r <= @types.ARM64_V30 {
    let n = r - @types.ARM64_V0
    match k {
      @types.Ks => "s" + n.to_string()
      @types.Kx | @types.Kd => "d" + n.to_string()
      _ => raise @util.QbeError::Ice("invalid class r=\{r} k=\{k.code()}")
    }
  } else {
    raise @util.QbeError::Ice("invalid register r=\{r} k=\{k.code()}")
  }
}

///|
// Whether x is an encodable arm64 logical immediate (C arm64_logimm).
fn arm64_logimm(x : Int64, k : @types.Class) -> Bool {
  let mut x = x
  if k == @types.Kw {
    x = (x & 0xFFFFFFFFL) | (x << 32)
  }
  if (x & 1L) != 0L {
    x = x.lnot()
  }
  if x == 0L {
    return false
  }
  if x == 0xAAAAAAAAAAAAAAAAL {
    return true
  }
  let check = fn(n : Int64) -> Bool { (n & (n + (n & (0L - n)))) == 0L }
  let n0 = x & 0xFL
  if 0x1111111111111111L * n0 == x {
    return check(n0)
  }
  let n1 = x & 0xFFL
  if 0x0101010101010101L * n1 == x {
    return check(n1)
  }
  let n2 = x & 0xFFFFL
  if 0x0001000100010001L * n2 == x {
    return check(n2)
  }
  let n3 = x & 0xFFFFFFFFL
  if 0x0000000100000001L * n3 == x {
    return check(n3)
  }
  check(x)
}

///|
// Slot offset relative to the frame pointer (C slot in arm64/emit.c). Split from
// arm64_slot so the binary emitter can share the exact frame math.
fn arm64_slot_off(
  frame : Int,
  padding : Int,
  is_vararg : Bool,
  apple : Bool,
  s : Int,
) -> Int {
  let s = if (s & (1 << 28)) != 0 { s - (1 << 29) } else { s }
  if s == -1 {
    16 + frame
  } else if s < 0 {
    // C arm64/emit.c slot(): negative slots already carry a byte offset.
    if is_vararg && !apple {
      16 + frame + 192 - (s + 2)
    } else {
      16 + frame - (s + 2)
    }
  } else {
    16 + padding + 4 * s
  }
}

///|
fn arm64_slot(st : Arm64EmitState, s : Int) -> Int {
  arm64_slot_off(st.frame, st.padding, st.fn_.is_vararg, st.apple, s)
}

///|
// ARM64 instruction format table (C omap).
let arm64_omap : Array[(Int, Int, String)] = [
  (@types.Add.index(), ARM64_KI, "add %=, %0, %1"),
  (@types.Add.index(), ARM64_KA, "fadd %=, %0, %1"),
  (@types.Sub.index(), ARM64_KI, "sub %=, %0, %1"),
  (@types.Sub.index(), ARM64_KA, "fsub %=, %0, %1"),
  (@types.And.index(), ARM64_KI, "and %=, %0, %1"),
  (@types.Or.index(), ARM64_KI, "orr %=, %0, %1"),
  (@types.Xor.index(), ARM64_KI, "eor %=, %0, %1"),
  (@types.Sar.index(), ARM64_KI, "asr %=, %0, %1"),
  (@types.Shr.index(), ARM64_KI, "lsr %=, %0, %1"),
  (@types.Shl.index(), ARM64_KI, "lsl %=, %0, %1"),
  (@types.Mul.index(), ARM64_KI, "mul %=, %0, %1"),
  (@types.Mul.index(), ARM64_KA, "fmul %=, %0, %1"),
  (@types.Div.index(), ARM64_KI, "sdiv %=, %0, %1"),
  (@types.Div.index(), ARM64_KA, "fdiv %=, %0, %1"),
  (@types.Udiv.index(), ARM64_KI, "udiv %=, %0, %1"),
  (@types.Rem.index(), ARM64_KI, "sdiv %?, %0, %1\n\tmsub\t%=, %?, %1, %0"),
  (@types.Urem.index(), ARM64_KI, "udiv %?, %0, %1\n\tmsub\t%=, %?, %1, %0"),
  (@types.Copy.index(), ARM64_KI, "mov %=, %0"),
  (@types.Copy.index(), ARM64_KA, "fmov %=, %0"),
  (@types.Swap.index(), ARM64_KI, "mov %?, %0\n\tmov\t%0, %1\n\tmov\t%1, %?"),
  (@types.Swap.index(), ARM64_KA, "fmov %?, %0\n\tfmov\t%0, %1\n\tfmov\t%1, %?"),
  (@types.Storeb.index(), @types.Kw.code(), "strb %W0, %M1"),
  (@types.Storeh.index(), @types.Kw.code(), "strh %W0, %M1"),
  (@types.Storew.index(), @types.Kw.code(), "str %W0, %M1"),
  (@types.Storel.index(), @types.Kw.code(), "str %L0, %M1"),
  (@types.Stores.index(), @types.Kw.code(), "str %S0, %M1"),
  (@types.Stored.index(), @types.Kw.code(), "str %D0, %M1"),
  (@types.Loadsb.index(), ARM64_KI, "ldrsb %=, %M0"),
  (@types.Loadub.index(), ARM64_KI, "ldrb %W=, %M0"),
  (@types.Loadsh.index(), ARM64_KI, "ldrsh %=, %M0"),
  (@types.Loaduh.index(), ARM64_KI, "ldrh %W=, %M0"),
  (@types.Loadsw.index(), @types.Kw.code(), "ldr %=, %M0"),
  (@types.Loadsw.index(), @types.Kl.code(), "ldrsw %=, %M0"),
  (@types.Loaduw.index(), ARM64_KI, "ldr %W=, %M0"),
  (@types.Load.index(), ARM64_KA, "ldr %=, %M0"),
  (@types.Extsb.index(), ARM64_KI, "sxtb %=, %W0"),
  (@types.Extub.index(), ARM64_KI, "uxtb %W=, %W0"),
  (@types.Extsh.index(), ARM64_KI, "sxth %=, %W0"),
  (@types.Extuh.index(), ARM64_KI, "uxth %W=, %W0"),
  (@types.Extsw.index(), ARM64_KI, "sxtw %L=, %W0"),
  (@types.Extuw.index(), ARM64_KI, "mov %W=, %W0"),
  (@types.Exts.index(), @types.Kd.code(), "fcvt %=, %S0"),
  (@types.Truncd.index(), @types.Ks.code(), "fcvt %=, %D0"),
  (@types.Cast.index(), @types.Kw.code(), "fmov %=, %S0"),
  (@types.Cast.index(), @types.Kl.code(), "fmov %=, %D0"),
  (@types.Cast.index(), @types.Ks.code(), "fmov %=, %W0"),
  (@types.Cast.index(), @types.Kd.code(), "fmov %=, %L0"),
  (@types.Stosi.index(), ARM64_KA, "fcvtzs %=, %S0"),
  (@types.Dtosi.index(), ARM64_KA, "fcvtzs %=, %D0"),
  (@types.Swtof.index(), ARM64_KA, "scvtf %=, %W0"),
  (@types.Sltof.index(), ARM64_KA, "scvtf %=, %L0"),
  (@types.Call.index(), @types.Kw.code(), "blr %L0"),
  (@types.Acmp.index(), ARM64_KI, "cmp %0, %1"),
  (@types.Acmn.index(), ARM64_KI, "cmn %0, %1"),
  (@types.Afcmp.index(), ARM64_KA, "fcmpe %0, %1"),
]

///|
// Emit a constant into a register (C loadcon in arm64/emit.c).
fn arm64_loadcon(
  st : Arm64EmitState,
  con : @types.Con,
  r : Int,
  k : @types.Class,
) -> Unit raise {
  let sb = st.sb
  if con.kind == @types.CAddr {
    let rn = arm64_rname(r, @types.Kl)
    // Local (fp-constant) symbols use the flavor's local prefix and are
    // printed quoted, e.g. ".Lfp0" (ELF) or "Lfp0" (Mach-O); globals use the
    // symbol prefix, e.g. "glo1" (ELF) or "_glo1" (Mach-O).
    let p = if con.is_local { st.gasloc } else { st.gassym }
    let l = st.interner.get(con.label)
    let mut off = ""
    if con.bits.i != 0L {
      off = "+" + con.bits.i.to_string()
    }
    let q = if con.is_local { "\"" } else { "" }
    sb.write_string("\tadrp\t")
    sb.write_string(rn)
    sb.write_string(", ")
    sb.write_string(q)
    sb.write_string(p)
    sb.write_string(l)
    sb.write_string(off)
    sb.write_string(q)
    // Mach-O uses sym@page / sym@pageoff; ELF uses sym / #:lo12:sym.
    if st.apple {
      sb.write_string("@page\n")
    } else {
      sb.write_char('\n')
    }
    sb.write_string("\tadd\t")
    sb.write_string(rn)
    sb.write_string(", ")
    sb.write_string(rn)
    sb.write_string(", ")
    if !st.apple {
      sb.write_string("#:lo12:")
    }
    sb.write_string(q)
    sb.write_string(p)
    sb.write_string(l)
    sb.write_string(off)
    sb.write_string(q)
    if st.apple {
      sb.write_string("@pageoff\n")
    } else {
      sb.write_char('\n')
    }
    return
  }
  let rn = arm64_rname(r, k)
  let w = k.wide()
  let mut n = con.raw_bits()
  if w == 0 {
    n = arm64_s32(n)
  }
  if (n | 0xFFFFL) == -1L || arm64_logimm(n, k) {
    sb.write_string("\tmov\t")
    sb.write_string(rn)
    sb.write_string(", #")
    sb.write_string(n.to_string())
    sb.write_char('\n')
  } else {
    sb.write_string("\tmov\t")
    sb.write_string(rn)
    sb.write_string(", #")
    sb.write_string((n & 0xFFFFL).to_string())
    sb.write_char('\n')
    let mut sh = 16
    n = n >> 16
    while n != 0L {
      if (w == 0 && sh == 32) || sh == 64 {
        break
      }
      sb.write_string("\tmovk\t")
      sb.write_string(rn)
      sb.write_string(", #0x")
      sb.write_string((n & 0xFFFFL).to_int().to_string(radix=16))
      sb.write_string(", lsl #")
      sb.write_string(sh.to_string())
      sb.write_char('\n')
      n = n >> 16
      sh = sh + 16
    }
  }
}

///|
// Format and emit an instruction (C emitf in arm64/emit.c).
fn arm64_emitf(st : Arm64EmitState, fmt : String, i : @types.Ins) -> Unit raise {
  let sb = st.sb
  sb.write_char('\t')
  let mut pos = 0
  let mut sp = false
  while pos < fmt.length() {
    let c = fmt[pos]
    pos = pos + 1
    if c != '%' {
      if c == ' ' && !sp {
        sb.write_char('\t')
        sp = true
      } else {
        sb.write_char(c.unsafe_to_char())
      }
      continue
    }
    let mut k = i.cls
    let mut go = true
    while go {
      let e = fmt[pos]
      pos = pos + 1
      match e {
        'W' => k = @types.Kw
        'L' => k = @types.Kl
        'S' => k = @types.Ks
        'D' => k = @types.Kd
        '?' =>
          if k.base() == 0 {
            sb.write_string(arm64_rname(@types.ARM64_IP1, k))
          } else if k == @types.Ks {
            sb.write_string("s31")
          } else {
            sb.write_string("d31")
          }
        '=' => sb.write_string(arm64_rname(i.to.tmp_val(), k))
        '0' => sb.write_string(arm64_rname(i.arg1.tmp_val(), k))
        '1' => {
          let r = i.arg2
          if r.is_tmp() {
            sb.write_string(arm64_rname(r.tmp_val(), k))
          } else if r.is_con() {
            // C arm64/emit.c: use the full 64-bit value for bitmask immediates.
            let pc = st.fn_.cons[r.con_val()]
            let n = pc.bits.i.reinterpret_as_uint64()
            if n >> 24 != 0UL {
              sb.write_string("#")
              sb.write_string(n.to_string())
            } else if (n & 0xFFF000UL) != 0UL {
              sb.write_string("#")
              sb.write_string((n >> 12).to_string())
              sb.write_string(", lsl #12")
            } else {
              sb.write_string("#")
              sb.write_string(n.to_string())
            }
          } else {
            raise @util.QbeError::Ice("invalid second argument")
          }
        }
        'M' => {
          let m = fmt[pos]
          pos = pos + 1
          let r = if m == '=' {
            i.to
          } else if m == '0' {
            i.arg1
          } else {
            i.arg2
          }
          if r.is_tmp() {
            sb.write_string("[")
            sb.write_string(arm64_rname(r.tmp_val(), @types.Kl))
            sb.write_string("]")
          } else if r.is_slot() {
            // C arm64/emit.c %M RSlot: [x29, slot]
            sb.write_string("[x29, ")
            sb.write_string(arm64_slot(st, r.slot_val()).to_string())
            sb.write_string("]")
          } else {
            raise @util.QbeError::Ice("todo (arm emit): unhandled ref")
          }
        }
        _ => raise @util.QbeError::Ice("invalid escape")
      }
      // width letters re-enter the switch; all other escapes are terminal
      if e == 'W' || e == 'L' || e == 'S' || e == 'D' {
        continue
      }
      go = false
    }
  }
  sb.write_char('\n')
}

///|
// Linear omap search (C `Table:` in emitins).
fn arm64_emit_table(st : Arm64EmitState, i : @types.Ins) -> Unit raise {
  for entry in arm64_omap {
    if entry.0 == i.op.index() {
      let mc = entry.1
      if mc == ARM64_KA ||
        mc == i.cls.code() ||
        (mc == ARM64_KI && i.cls.base() == 0) {
        arm64_emitf(st, entry.2, i)
        return
      }
    }
  }
  raise @util.QbeError::Ice("no match for " + i.op.name())
}

///|
// Emit a single instruction (C emitins in arm64/emit.c).
fn arm64_emitins(st : Arm64EmitState, i : @types.Ins) -> Unit raise {
  let sb = st.sb
  let oi = i.op.index()
  let fi = @types.Flagieq.index()
  if oi >= fi && oi <= @types.Flagfuo.index() {
    arm64_emitf(st, "cset %=, " + arm64_cond[oi - fi], i)
    return
  }
  match i.op {
    @types.Nop => ()
    @types.Copy =>
      if i.to.eq(i.arg1) {
        ()
      } else if i.arg1.is_con() {
        let c = st.fn_.cons[i.arg1.con_val()]
        arm64_loadcon(st, c, i.to.tmp_val(), i.cls)
      } else {
        arm64_emit_table(st, i)
      }
    @types.Addr =>
      if i.arg1.is_slot() {
        sb.write_string("\tadd\t")
        sb.write_string(arm64_rname(i.to.tmp_val(), @types.Kl))
        sb.write_string(", x29, #")
        sb.write_string(arm64_slot(st, i.arg1.slot_val()).to_string())
        sb.write_char('\n')
      } else {
        raise @util.QbeError::Ice("invalid address")
      }
    @types.Call =>
      // Direct call to a global symbol (C arm64/emit.c case Ocall): emit
      // `bl sym` when the target is an offset-zero address constant.
      if i.arg1.is_con() {
        let c = st.fn_.cons[i.arg1.con_val()]
        if c.kind == @types.CAddr && c.bits.i == 0L && !c.is_local {
          sb.write_string("\tbl\t")
          sb.write_string(st.gassym)
          sb.write_string(st.interner.get(c.label))
          sb.write_char('\n')
        } else {
          arm64_emit_table(st, i)
        }
      } else {
        arm64_emit_table(st, i)
      }
    @types.Salloc => {
      // C arm64/emit.c: sub sp, sp, %0; mov %=, sp (when to != R).
      sb.write_string("\tsub\tsp, sp, ")
      if i.arg1.is_tmp() {
        sb.write_string(arm64_rname(i.arg1.tmp_val(), @types.Kl))
      } else {
        raise @util.QbeError::Ice("unexpected salloc operand")
      }
      sb.write_char('\n')
      if !i.to.is_none() {
        sb.write_string("\tmov\t")
        sb.write_string(arm64_rname(i.to.tmp_val(), @types.Kl))
        sb.write_string(", sp\n")
      }
    }
    _ => arm64_emit_table(st, i)
  }
}

///|
// Emit function prologue, body, and epilogues (C arm64_emitfn).
fn arm64_emitfn(st : Arm64EmitState) -> Unit raise {
  let sb = st.sb
  let fn_ = st.fn_

  // framelayout (C framelayout)
  let mut o = 0
  for r in @types.arm64_rclob {
    if (fn_.reg & (1UL << r)) != 0UL {
      o = o + 1
    }
  }
  let mut f = fn_.slot
  f = (f + 3) & -4
  o = o + (o & 1)
  st.padding = 4 * (f - fn_.slot)
  st.frame = 4 * f + 8 * o

  // C arm64/emit.c forces the function alignment to 4 for the Mach-O flavor.
  if st.apple {
    sb.write_string(".text\n.balign 4\n")
  } else {
    sb.write_string(".text\n.balign 16\n")
  }
  if fn_.is_export {
    sb.write_string(".globl ")
    sb.write_string(st.gassym)
    sb.write_string(fn_.name)
    sb.write_char('\n')
  }
  sb.write_string(st.gassym)
  sb.write_string(fn_.name)
  sb.write_string(":\n")
  // BTI landing pad (C arm64_emitfn always emits it).
  sb.write_string("\thint\t#34\n")

  if fn_.is_vararg && !st.apple {
    for n in 7>=..0 {
      sb.write_string("\tstr\tq")
      sb.write_string(n.to_string())
      sb.write_string(", [sp, -16]!\n")
    }
    let mut gp = 7
    while gp >= 0 {
      // C: stp x(n-1), xn, [sp, -16]! for n = 7,5,3,1
      sb.write_string("\tstp\tx")
      sb.write_string((gp - 1).to_string())
      sb.write_string(", x")
      sb.write_string(gp.to_string())
      sb.write_string(", [sp, -16]!\n")
      gp = gp - 2
    }
  }

  if st.frame + 16 > 512 {
    sb.write_string("\tsub\tsp, sp, #")
    sb.write_string(st.frame.to_string())
    sb.write_char('\n')
    sb.write_string("\tstp\tx29, x30, [sp, -16]!\n")
  } else {
    sb.write_string("\tstp\tx29, x30, [sp, -")
    sb.write_string((st.frame + 16).to_string())
    sb.write_string("]!\n")
  }
  sb.write_string("\tmov\tx29, sp\n")
  o = st.frame + 16
  for r in @types.arm64_rclob {
    if (fn_.reg & (1UL << r)) != 0UL {
      o = o - 8
      sb.write_string("\tstr\t")
      sb.write_string(arm64_rname(r, @types.Kx))
      sb.write_string(", [x29, ")
      sb.write_string(o.to_string())
      sb.write_string("]\n")
    }
  }

  let mut lbl = false
  for idx in 0..<fn_.rpo.length() {
    let bid = fn_.rpo[idx]
    let b = fn_.blks[bid]
    let next = if idx + 1 < fn_.rpo.length() { fn_.rpo[idx + 1] } else { -1 }
    if lbl || b.npred > 1 {
      sb.write_string(st.gasloc)
      sb.write_string((arm64_emit_id0[0] + b.rpo_id).to_string())
      sb.write_string(":\n")
    }
    for ins in b.ins {
      arm64_emitins(st, ins)
    }
    lbl = true
    match b.jmp.kind {
      @types.Jret0 => {
        o = st.frame + 16
        for r in @types.arm64_rclob {
          if (fn_.reg & (1UL << r)) != 0UL {
            o = o - 8
            sb.write_string("\tldr\t")
            sb.write_string(arm64_rname(r, @types.Kx))
            sb.write_string(", [x29, ")
            sb.write_string(o.to_string())
            sb.write_string("]\n")
          }
        }
        if fn_.has_dynalloc {
          sb.write_string("\tmov sp, x29\n")
        }
        let mut oo = st.frame + 16
        if fn_.is_vararg && !st.apple {
          oo = oo + 192
        }
        if oo > 504 {
          sb.write_string("\tldp\tx29, x30, [sp], 16\n")
          sb.write_string("\tadd\tsp, sp, #")
          sb.write_string((oo - 16).to_string())
          sb.write_char('\n')
        } else {
          sb.write_string("\tldp\tx29, x30, [sp], ")
          sb.write_string(oo.to_string())
          sb.write_char('\n')
        }
        sb.write_string("\tret\n")
      }
      @types.Jjmp =>
        if b.jmp.s1 >= 0 && b.jmp.s1 != next {
          sb.write_string("\tb\t" + st.gasloc)
          sb.write_string(
            (arm64_emit_id0[0] + fn_.blks[b.jmp.s1].rpo_id).to_string(),
          )
          sb.write_char('\n')
        } else {
          lbl = false
        }
      _ => {
        let c = b.jmp.kind.index() - @types.Jjfieq.index()
        if c < 0 || c > 17 {
          raise @util.QbeError::Ice("unhandled jump")
        }
        let mut s1 = b.jmp.s1
        let mut s2 = b.jmp.s2
        let mut neg = false
        if next == b.jmp.s2 {
          let t = s1
          s1 = s2
          s2 = t
        } else {
          neg = true
        }
        sb.write_string("\tb")
        sb.write_string(if neg { arm64_cond_neg[c] } else { arm64_cond[c] })
        sb.write_string("\t" + st.gasloc)
        sb.write_string((arm64_emit_id0[0] + fn_.blks[s2].rpo_id).to_string())
        sb.write_char('\n')
        if s1 >= 0 && s1 != next {
          sb.write_string("\tb\t" + st.gasloc)
          sb.write_string((arm64_emit_id0[0] + fn_.blks[s1].rpo_id).to_string())
          sb.write_char('\n')
        } else {
          lbl = false
        }
      }
    }
  }
  arm64_emit_id0[0] = arm64_emit_id0[0] + fn_.rpo.length()
  // C elf_emitfnfin emits the function type/size after each function; the
  // Mach-O flavor emits nothing.
  if !st.apple {
    sb.write_string(".type ")
    sb.write_string(fn_.name)
    sb.write_string(", @function\n.size ")
    sb.write_string(fn_.name)
    sb.write_string(", .-")
    sb.write_string(fn_.name)
    sb.write_char('\n')
  }
}

///|
// Main ARM64 emission entry point for one function.
pub fn emit_arm64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
  gasloc : String,
  gassym : String,
  apple : Bool,
) -> String raise {
  let _ = all_typs
  let sb = StringBuilder()
  let st = Arm64EmitState::{
    fn_,
    interner,
    sb,
    gasloc,
    gassym,
    apple,
    frame: 0,
    padding: 0,
  }
  arm64_emitfn(st)
  sb.to_string()
}
