///|
// Binary (machine-code) ARM64 emitter: the self-contained counterpart of
// emit_arm64.mbt. It consumes the same post-rega IR and produces 32-bit
// instruction words plus relocations, so it can feed object/macho.mbt and the
// in-memory JIT without an assembler or linker in the loop.
//
// Scope so far: leaf integer (and double) functions. Calls, global addresses,
// float constants and single-precision ops raise an ICE instead of silently
// miscompiling; later rounds extend the covered set and add Mach-O relocations.

///|
priv struct BinFix {
  word : Int
  kind : Int // 0 = b, 1 = bcond
  cond : Int
  label : Int
}

///|
priv struct Arm64BinState {
  fn_ : @types.Fn
  interner : @util.Interner
  apple : Bool
  words : Array[Int]
  labels : Map[Int, Int]
  fixups : Array[BinFix]
  // Direct calls: (word index of the bl, callee symbol name). Resolved either
  // by the module emitter (intra-module) or turned into relocations later.
  calls : Array[(Int, String)]
  // Global-address fixups: (adrp word, add word, dest reg, symbol, byte offset).
  addrs : Array[(Int, Int, Int, String, Int)]
  mut frame : Int
  mut padding : Int
}

///|
fn arm64_bin_new(
  fn_ : @types.Fn,
  interner : @util.Interner,
  apple : Bool,
) -> Arm64BinState {
  Arm64BinState::{
    fn_,
    interner,
    apple,
    words: [],
    labels: Map([]),
    fixups: [],
    calls: [],
    addrs: [],
    frame: 0,
    padding: 0,
  }
}

///|
// Map a QBE register id (ARM64_R0.., ARM64_V0.., ARM64_SP) to an AArch64
// register number.
fn arm64_bin_reg(r : Int) -> Int raise {
  if r == @types.ARM64_SP {
    31
  } else if r >= @types.ARM64_R0 && r <= @types.ARM64_LR {
    r - @types.ARM64_R0
  } else if r >= @types.ARM64_V0 && r <= @types.ARM64_V30 {
    r - @types.ARM64_V0
  } else {
    raise @util.QbeError::Ice("arm64 bin: bad register id \{r}")
  }
}

///|
// ARM condition codes for the QBE comparison codes (arm64_cond order).
let arm64_bin_cond : Array[Int] = [
  0, 1, 10, 12, 13, 11, 2, 8, 9, 3, 0, 10, 12, 9, 4, 1, 7, 6,
]

///|
let arm64_bin_cond_neg : Array[Int] = [
  1, 0, 11, 13, 12, 10, 3, 9, 8, 2, 1, 11, 13, 8, 5, 0, 6, 7,
]

///|
fn arm64_bin_emit(st : Arm64BinState, w : Int) -> Unit {
  st.words.push(w)
}

///|
fn arm64_bin_label(st : Arm64BinState, lid : Int) -> Unit {
  st.labels[lid] = st.words.length()
}

///|
fn arm64_bin_b(st : Arm64BinState, lid : Int) -> Unit {
  st.fixups.push(BinFix::{
    word: st.words.length(),
    kind: 0,
    cond: 0,
    label: lid,
  })
  st.words.push(0)
}

///|
fn arm64_bin_bcond(st : Arm64BinState, cond : Int, lid : Int) -> Unit {
  st.fixups.push(BinFix::{ word: st.words.length(), kind: 1, cond, label: lid, })
  st.words.push(0)
}

///|
fn arm64_bin_resolve(st : Arm64BinState) -> Unit raise {
  for fx in st.fixups {
    let target = match st.labels.get(fx.label) {
      Some(t) => t
      None =>
        raise @util.QbeError::Ice("arm64 bin: undefined label \{fx.label}")
    }
    let off = (target - fx.word) * 4
    st.words[fx.word] = if fx.kind == 0 {
      @object.enc_b(off)
    } else {
      @object.enc_bcond(fx.cond, off)
    }
  }
}

///|
// Resolve a %M memory operand to (base register, byte offset).
fn arm64_bin_mem(st : Arm64BinState, r : @types.Ref) -> (Int, Int) raise {
  if r.is_tmp() {
    (arm64_bin_reg(r.tmp_val()), 0)
  } else if r.is_slot() {
    (
      29,
      arm64_slot_off(
        st.frame,
        st.padding,
        st.fn_.is_vararg,
        st.apple,
        r.slot_val(),
      ),
    )
  } else {
    raise @util.QbeError::Ice("arm64 bin: unhandled memory operand")
  }
}

///|
// Materialize a constant into a register with movz/movk. The text emitter can
// pick a single MOV bitmask-immediate; movz+movk is functionally identical and
// is byte-identical whenever the constant fits one 16-bit chunk.
fn arm64_bin_popcount(x : Int64) -> Int {
  let mut v = x
  let mut c = 0
  while v != 0L {
    v = v & (v - 1L)
    c = c + 1
  }
  c
}

///|
fn arm64_bin_ror(x : Int64, r : Int, esize : Int) -> Int64 {
  // 1L << 64 wraps in MoonBit, so the full-width mask is explicit.
  let mask = if esize == 64 { -1L } else { (1L << esize) - 1L }
  if r == 0 {
    x & mask
  } else {
    ((x >> r) | (x << (esize - r))) & mask
  }
}

///|
fn arm64_bin_log2(e : Int) -> Int {
  match e {
    2 => 1
    4 => 2
    8 => 3
    16 => 4
    32 => 5
    64 => 6
    _ => 0
  }
}

///|
// Encode a 32/64-bit value as an AArch64 bitmask immediate (N, immr, imms).
fn arm64_bin_encode_logimm(value : Int64, wide : Bool) -> (Int, Int, Int)? {
  let bits = if wide { 64 } else { 32 }
  let mask = if wide { -1L } else { 0xFFFFFFFFL }
  let v = value & mask
  if v == 0L || v == mask {
    return None
  }
  let mut esize = 2
  while esize <= bits {
    if bits % esize == 0 {
      let emask = if esize == 64 { -1L } else { (1L << esize) - 1L }
      let pattern = v & emask
      let mut rep = 0L
      let mut i = 0
      while i < bits {
        rep = rep | (pattern << i)
        i = i + esize
      }
      if rep == v && pattern != 0L {
        let ones = arm64_bin_popcount(pattern)
        let contiguous = (1L << ones) - 1L
        let mut r = 0
        while r < esize {
          if arm64_bin_ror(contiguous, r, esize) == pattern {
            let d = arm64_bin_log2(esize)
            let n = if esize == 64 { 1 } else { 0 }
            let not_imms = (1 << d) | (((ones - 1) ^ -1) & ((1 << d) - 1))
            let imms = (not_imms ^ -1) & 0x3F
            return Some((n, r, imms))
          }
          r = r + 1
        }
      }
    }
    esize = esize * 2
  }
  None
}

///|
// A value encodable as a single MOVZ/MOVN: (imm16, hw), or None.
fn arm64_bin_movz_single(value : Int64, bits : Int) -> (Int, Int)? {
  if value == 0L {
    return Some((0, 0))
  }
  let mut hw = 0
  while hw < bits / 16 {
    let chunk = (value >> (16 * hw)) & 0xFFFFL
    if chunk != 0L {
      // Guard the last chunk: value >> 64 would wrap in MoonBit.
      if hw + 1 < bits / 16 && value >> (16 * (hw + 1)) != 0L {
        return None
      }
      return Some((chunk.to_int(), hw))
    }
    hw = hw + 1
  }
  None
}

///|
fn arm64_bin_loadcon(
  st : Arm64BinState,
  con : @types.Con,
  r : Int,
  k : @types.Class,
) -> Unit raise {
  if con.kind == @types.CAddr {
    // adrp/add with a placeholder page/offset; the module emitter patches both
    // once the data section is laid out.
    let rd = arm64_bin_reg(r)
    st.addrs.push(
      (
        st.words.length(),
        st.words.length() + 1,
        rd,
        st.interner.get(con.label),
        con.bits.i.to_int(),
      ),
    )
    st.words.push(@object.enc_adrp(rd, 0))
    st.words.push(@object.enc_add_imm(rd, rd, 0))
    return
  }
  let w = k.wide()
  let sf = w != 0
  let bits = if sf { 64 } else { 32 }
  let mask = if sf { -1L } else { 0xFFFFFFFFL }
  let mut n = con.raw_bits()
  if w == 0 {
    n = arm64_s32(n)
  }
  let rd = arm64_bin_reg(r)
  let li = arm64_bin_encode_logimm(n, sf)
  // The text emitter prints a single MOV when (n | 0xFFFF) == -1 (negative
  // values with the low half set) or n is a logical immediate.
  if (n | 0xFFFFL) == -1L || li.is_some() {
    // The text emitter prints one MOV for these; mirror GAS's encoding choice
    // (MOVZ, else MOVN, else the ORR bitmask immediate).
    match arm64_bin_movz_single(n, bits) {
      Some(p) => arm64_bin_emit(st, @object.enc_movz_sf(sf, rd, p.0, p.1))
      None =>
        match arm64_bin_movz_single((n ^ -1L) & mask, bits) {
          Some(p) => arm64_bin_emit(st, @object.enc_movn_sf(sf, rd, p.0, p.1))
          None =>
            match li {
              Some(t) =>
                arm64_bin_emit(
                  st,
                  @object.enc_logimm_sf(sf, 1, rd, 31, t.0, t.1, t.2),
                )
              None => raise @util.QbeError::Ice("arm64 bin: unencodable MOV")
            }
        }
    }
    return
  }
  arm64_bin_emit(st, @object.enc_movz_sf(sf, rd, (n & 0xFFFFL).to_int(), 0))
  let mut sh = 16
  let mut m = n >> 16
  while m != 0L {
    if (w == 0 && sh == 32) || sh == 64 {
      break
    }
    arm64_bin_emit(
      st,
      @object.enc_movk_sf(sf, rd, (m & 0xFFFFL).to_int(), sh / 16),
    )
    m = m >> 16
    sh = sh + 16
  }
}

///|
// Decode an immediate operand that must fit one 12-bit ADD/SUB immediate.
fn arm64_bin_imm12(st : Arm64BinState, r : @types.Ref) -> Int raise {
  if r.is_con() {
    let n = st.fn_.cons[r.con_val()].bits.i.reinterpret_as_uint64()
    if n >> 12 == 0UL {
      n.to_int()
    } else if (n & 0xFFFUL) == 0UL && n >> 24 == 0UL {
      raise @util.QbeError::Ice(
        "arm64 bin: imm12 with lsl #12 not supported yet",
      )
    } else {
      raise @util.QbeError::Ice("arm64 bin: immediate does not fit #imm12")
    }
  } else {
    raise @util.QbeError::Ice("arm64 bin: expected an immediate operand")
  }
}

///|
fn arm64_bin_r(st : Arm64BinState, r : @types.Ref) -> Int raise {
  if r.is_tmp() {
    arm64_bin_reg(r.tmp_val())
  } else {
    raise @util.QbeError::Ice("arm64 bin: expected a register operand")
  }
}

///|
fn arm64_bin_table(st : Arm64BinState, i : @types.Ins) -> Unit raise {
  // Flag-setting ops (Acmp/Acmn/Afcmp) and stores have no destination.
  let rd = if i.to.is_tmp() { arm64_bin_reg(i.to.tmp_val()) } else { 0 }
  let sf = i.cls == @types.Kl
  let is_d = i.cls == @types.Kd
  let is_s = i.cls == @types.Ks
  if is_s {
    // Single-precision arithmetic has its own opcodes; handle it before the
    // integer fallthrough so it can never be silently miscompiled.
    match i.op {
      @types.Add => {
        arm64_bin_emit(
          st,
          @object.enc_fadd_s(
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
        return
      }
      @types.Sub => {
        arm64_bin_emit(
          st,
          @object.enc_fsub_s(
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
        return
      }
      @types.Mul => {
        arm64_bin_emit(
          st,
          @object.enc_fmul_s(
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
        return
      }
      @types.Div => {
        arm64_bin_emit(
          st,
          @object.enc_fdiv_s(
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
        return
      }
      @types.Afcmp => {
        arm64_bin_emit(
          st,
          @object.enc_fcmpe_s(arm64_bin_r(st, i.arg1), arm64_bin_r(st, i.arg2)),
        )
        return
      }
      _ => ()
    }
  }
  match i.op {
    @types.Add =>
      if is_d {
        arm64_bin_emit(
          st,
          @object.enc_fadd_d(
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
      } else if i.arg2.is_con() {
        arm64_bin_emit(
          st,
          @object.enc_add_imm_sf(
            sf,
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_imm12(st, i.arg2),
          ),
        )
      } else {
        let rn = arm64_bin_r(st, i.arg1)
        let rm = arm64_bin_r(st, i.arg2)
        if rd == 31 || rn == 31 {
          arm64_bin_emit(st, @object.enc_add_ext(rd, rn, rm))
        } else {
          arm64_bin_emit(st, @object.enc_add_reg_sf(sf, rd, rn, rm))
        }
      }
    @types.Sub =>
      if is_d {
        arm64_bin_emit(
          st,
          @object.enc_fsub_d(
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
      } else if i.arg2.is_con() {
        arm64_bin_emit(
          st,
          @object.enc_sub_imm_sf(
            sf,
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_imm12(st, i.arg2),
          ),
        )
      } else {
        let rn = arm64_bin_r(st, i.arg1)
        let rm = arm64_bin_r(st, i.arg2)
        if rd == 31 || rn == 31 {
          arm64_bin_emit(st, @object.enc_sub_ext(rd, rn, rm))
        } else {
          arm64_bin_emit(st, @object.enc_sub_reg_sf(sf, rd, rn, rm))
        }
      }
    @types.Mul =>
      if is_d {
        arm64_bin_emit(
          st,
          @object.enc_fmul_d(
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
      } else {
        arm64_bin_emit(
          st,
          @object.enc_mul_sf(
            sf,
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
      }
    @types.Div =>
      if is_d {
        arm64_bin_emit(
          st,
          @object.enc_fdiv_d(
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
      } else {
        arm64_bin_emit(
          st,
          @object.enc_sdiv_sf(
            sf,
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
      }
    @types.Udiv =>
      arm64_bin_emit(
        st,
        @object.enc_udiv_sf(
          sf,
          rd,
          arm64_bin_r(st, i.arg1),
          arm64_bin_r(st, i.arg2),
        ),
      )
    @types.Rem | @types.Urem => {
      let rn = arm64_bin_r(st, i.arg1)
      let rm = arm64_bin_r(st, i.arg2)
      let ip1 = @types.ARM64_IP1 - @types.ARM64_R0
      if i.op == @types.Rem {
        arm64_bin_emit(st, @object.enc_sdiv_sf(sf, ip1, rn, rm))
      } else {
        arm64_bin_emit(st, @object.enc_udiv_sf(sf, ip1, rn, rm))
      }
      arm64_bin_emit(st, @object.enc_msub_sf(sf, rd, ip1, rm, rn))
    }
    @types.And | @types.Or | @types.Xor => {
      let rn = arm64_bin_r(st, i.arg1)
      let opc = match i.op {
        @types.And => 0
        @types.Or => 1
        _ => 2
      }
      if i.arg2.is_con() {
        let v = st.fn_.cons[i.arg2.con_val()].raw_bits()
        match arm64_bin_encode_logimm(v, sf) {
          Some(t) =>
            arm64_bin_emit(
              st,
              @object.enc_logimm_sf(sf, opc, rd, rn, t.0, t.1, t.2),
            )
          None =>
            raise @util.QbeError::Ice(
              "arm64 bin: unencodable logical immediate",
            )
        }
      } else {
        let rm = arm64_bin_r(st, i.arg2)
        match i.op {
          @types.And =>
            arm64_bin_emit(st, @object.enc_and_reg_sf(sf, rd, rn, rm))
          @types.Or =>
            arm64_bin_emit(st, @object.enc_orr_reg_sf(sf, rd, rn, rm))
          _ => arm64_bin_emit(st, @object.enc_eor_reg_sf(sf, rd, rn, rm))
        }
      }
    }
    @types.Shl =>
      arm64_bin_emit(
        st,
        @object.enc_lsl_sf(
          sf,
          rd,
          arm64_bin_r(st, i.arg1),
          arm64_bin_r(st, i.arg2),
        ),
      )
    @types.Shr =>
      arm64_bin_emit(
        st,
        @object.enc_lsr_sf(
          sf,
          rd,
          arm64_bin_r(st, i.arg1),
          arm64_bin_r(st, i.arg2),
        ),
      )
    @types.Sar =>
      arm64_bin_emit(
        st,
        @object.enc_asr_sf(
          sf,
          rd,
          arm64_bin_r(st, i.arg1),
          arm64_bin_r(st, i.arg2),
        ),
      )
    @types.Acmp =>
      if i.arg2.is_con() {
        arm64_bin_emit(
          st,
          @object.enc_cmp_imm_sf(
            sf,
            arm64_bin_r(st, i.arg1),
            arm64_bin_imm12(st, i.arg2),
          ),
        )
      } else {
        arm64_bin_emit(
          st,
          @object.enc_cmp_sf(
            sf,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
      }
    @types.Acmn =>
      if i.arg2.is_con() {
        arm64_bin_emit(
          st,
          @object.enc_cmn_imm_sf(
            sf,
            arm64_bin_r(st, i.arg1),
            arm64_bin_imm12(st, i.arg2),
          ),
        )
      } else {
        arm64_bin_emit(
          st,
          @object.enc_cmn_sf(
            sf,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
      }
    @types.Afcmp =>
      if is_d {
        arm64_bin_emit(
          st,
          @object.enc_fcmpe_d(arm64_bin_r(st, i.arg1), arm64_bin_r(st, i.arg2)),
        )
      } else {
        raise @util.QbeError::Ice("arm64 bin: unsupported fp compare class")
      }
    @types.Extsb =>
      arm64_bin_emit(st, @object.enc_sxtb_sf(sf, rd, arm64_bin_r(st, i.arg1)))
    @types.Extsh =>
      arm64_bin_emit(st, @object.enc_sxth_sf(sf, rd, arm64_bin_r(st, i.arg1)))
    @types.Extsw =>
      arm64_bin_emit(st, @object.enc_sxtw(rd, arm64_bin_r(st, i.arg1)))
    @types.Extub =>
      arm64_bin_emit(st, @object.enc_uxtb_sf(sf, rd, arm64_bin_r(st, i.arg1)))
    @types.Extuh =>
      arm64_bin_emit(st, @object.enc_uxth_sf(sf, rd, arm64_bin_r(st, i.arg1)))
    @types.Extuw =>
      // Zero-extend word to long: a 32-bit mov clears the upper half.
      arm64_bin_emit(
        st,
        @object.enc_mov_reg_sf(false, rd, arm64_bin_r(st, i.arg1)),
      )
    @types.Exts =>
      arm64_bin_emit(st, @object.enc_fcvt_d_s(rd, arm64_bin_r(st, i.arg1)))
    @types.Truncd =>
      arm64_bin_emit(st, @object.enc_fcvt_s_d(rd, arm64_bin_r(st, i.arg1)))
    @types.Stosi =>
      if sf {
        arm64_bin_emit(st, @object.enc_fcvtzs_x_s(rd, arm64_bin_r(st, i.arg1)))
      } else {
        arm64_bin_emit(st, @object.enc_fcvtzs_w_s(rd, arm64_bin_r(st, i.arg1)))
      }
    @types.Dtosi =>
      if sf {
        arm64_bin_emit(st, @object.enc_fcvtzs_x_d(rd, arm64_bin_r(st, i.arg1)))
      } else {
        arm64_bin_emit(st, @object.enc_fcvtzs_w_d(rd, arm64_bin_r(st, i.arg1)))
      }
    @types.Swtof =>
      if is_d {
        arm64_bin_emit(st, @object.enc_scvtf_d_w(rd, arm64_bin_r(st, i.arg1)))
      } else {
        arm64_bin_emit(st, @object.enc_scvtf_s_w(rd, arm64_bin_r(st, i.arg1)))
      }
    @types.Sltof =>
      if is_d {
        arm64_bin_emit(st, @object.enc_scvtf_d_x(rd, arm64_bin_r(st, i.arg1)))
      } else {
        arm64_bin_emit(st, @object.enc_scvtf_s_x(rd, arm64_bin_r(st, i.arg1)))
      }
    @types.Cast =>
      match i.cls {
        @types.Kw =>
          arm64_bin_emit(st, @object.enc_fmov_w_s(rd, arm64_bin_r(st, i.arg1)))
        @types.Kl =>
          arm64_bin_emit(st, @object.enc_fmov_x_d(rd, arm64_bin_r(st, i.arg1)))
        @types.Ks =>
          arm64_bin_emit(st, @object.enc_fmov_s_w(rd, arm64_bin_r(st, i.arg1)))
        @types.Kd =>
          arm64_bin_emit(st, @object.enc_fmov_d_x(rd, arm64_bin_r(st, i.arg1)))
        _ => raise @util.QbeError::Ice("arm64 bin: bad cast class")
      }
    @types.Load => {
      let (rn, off) = arm64_bin_mem(st, i.arg1)
      let size = if i.cls == @types.Kl || i.cls == @types.Kd { 3 } else { 2 }
      if i.cls == @types.Ks || i.cls == @types.Kd {
        arm64_bin_emit(st, @object.enc_ldst_fp(size, 1, rd, rn, off))
      } else {
        arm64_bin_emit(st, @object.enc_ldst(size, 1, rd, rn, off))
      }
    }
    @types.Loadub => {
      let (rn, off) = arm64_bin_mem(st, i.arg1)
      arm64_bin_emit(st, @object.enc_ldst(0, 1, rd, rn, off))
    }
    @types.Loaduh => {
      let (rn, off) = arm64_bin_mem(st, i.arg1)
      arm64_bin_emit(st, @object.enc_ldst(1, 1, rd, rn, off))
    }
    @types.Loaduw => {
      let (rn, off) = arm64_bin_mem(st, i.arg1)
      arm64_bin_emit(st, @object.enc_ldst(2, 1, rd, rn, off))
    }
    @types.Loadsw => {
      let (rn, off) = arm64_bin_mem(st, i.arg1)
      let opc = if i.cls == @types.Kl { 2 } else { 1 }
      arm64_bin_emit(st, @object.enc_ldst(2, opc, rd, rn, off))
    }
    @types.Loadsb | @types.Loadsh => {
      let (rn, off) = arm64_bin_mem(st, i.arg1)
      let size = if i.op == @types.Loadsb { 0 } else { 1 }
      let opc = if i.cls == @types.Kl { 2 } else { 3 }
      arm64_bin_emit(st, @object.enc_ldst(size, opc, rd, rn, off))
    }
    @types.Storeb
    | @types.Storeh
    | @types.Storew
    | @types.Storel
    | @types.Stores
    | @types.Stored => {
      let (rn, off) = arm64_bin_mem(st, i.arg2)
      let rt = arm64_bin_reg(i.arg1.tmp_val())
      let (size, opc) = match i.op {
        @types.Storeb => (0, 0)
        @types.Storeh => (1, 0)
        @types.Storew => (2, 0)
        @types.Stores => (2, 0)
        @types.Stored => (3, 0)
        _ => (3, 0)
      }
      if i.op == @types.Stores || i.op == @types.Stored {
        arm64_bin_emit(st, @object.enc_ldst_fp(size, opc, rt, rn, off))
      } else {
        arm64_bin_emit(st, @object.enc_ldst(size, opc, rt, rn, off))
      }
    }
    @types.Swap => {
      let r1 = arm64_bin_r(st, i.arg1)
      let r2 = arm64_bin_r(st, i.arg2)
      if is_d {
        // The text emitter's float scratch is s31/d31, not the integer IP1.
        arm64_bin_emit(st, @object.enc_fmov_d(31, r1))
        arm64_bin_emit(st, @object.enc_fmov_d(r1, r2))
        arm64_bin_emit(st, @object.enc_fmov_d(r2, 31))
      } else if is_s {
        arm64_bin_emit(st, @object.enc_fmov_s(31, r1))
        arm64_bin_emit(st, @object.enc_fmov_s(r1, r2))
        arm64_bin_emit(st, @object.enc_fmov_s(r2, 31))
      } else {
        let ip1 = @types.ARM64_IP1 - @types.ARM64_R0
        arm64_bin_emit(st, @object.enc_mov_reg_sf(sf, ip1, r1))
        arm64_bin_emit(st, @object.enc_mov_reg_sf(sf, r1, r2))
        arm64_bin_emit(st, @object.enc_mov_reg_sf(sf, r2, ip1))
      }
    }
    _ => raise @util.QbeError::Ice("arm64 bin: unsupported op " + i.op.name())
  }
}

///|
fn arm64_bin_ins(st : Arm64BinState, i : @types.Ins) -> Unit raise {
  let oi = i.op.index()
  let fi = @types.Flagieq.index()
  if oi >= fi && oi <= @types.Flagfuo.index() {
    let c = oi - fi
    let rd = arm64_bin_reg(i.to.tmp_val())
    arm64_bin_emit(
      st,
      @object.enc_cset(i.cls == @types.Kl, rd, arm64_bin_cond[c]),
    )
    return
  }
  match i.op {
    @types.Nop => ()
    @types.Copy =>
      if i.to.eq(i.arg1) {
        ()
      } else if i.arg1.is_con() {
        arm64_bin_loadcon(
          st,
          st.fn_.cons[i.arg1.con_val()],
          i.to.tmp_val(),
          i.cls,
        )
      } else if i.cls == @types.Kd {
        arm64_bin_emit(
          st,
          @object.enc_fmov_d(
            arm64_bin_reg(i.to.tmp_val()),
            arm64_bin_r(st, i.arg1),
          ),
        )
      } else if i.cls == @types.Ks {
        arm64_bin_emit(
          st,
          @object.enc_fmov_s(
            arm64_bin_reg(i.to.tmp_val()),
            arm64_bin_r(st, i.arg1),
          ),
        )
      } else {
        arm64_bin_emit(
          st,
          @object.enc_mov_reg_sf(
            i.cls == @types.Kl,
            arm64_bin_reg(i.to.tmp_val()),
            arm64_bin_r(st, i.arg1),
          ),
        )
      }
    @types.Addr =>
      if i.arg1.is_slot() {
        arm64_bin_emit(
          st,
          @object.enc_add_imm(
            arm64_bin_reg(i.to.tmp_val()),
            29,
            arm64_slot_off(
              st.frame,
              st.padding,
              st.fn_.is_vararg,
              st.apple,
              i.arg1.slot_val(),
            ),
          ),
        )
      } else {
        raise @util.QbeError::Ice("arm64 bin: invalid address")
      }
    @types.Call | @types.Vacall =>
      // The ABI pass has already placed the arguments in x0..x7, so a direct
      // call is just bl; the result is left in x0 for later copies.
      if i.arg1.is_con() {
        let c = st.fn_.cons[i.arg1.con_val()]
        if c.kind == @types.CAddr && !c.is_local {
          st.calls.push((st.words.length(), st.interner.get(c.label)))
          st.words.push(@object.enc_bl(0))
        } else {
          raise @util.QbeError::Ice("arm64 bin: unsupported call target")
        }
      } else {
        // Indirect call through a register.
        arm64_bin_emit(st, @object.enc_blr(arm64_bin_r(st, i.arg1)))
      }
    @types.Salloc => {
      let rn = arm64_bin_r(st, i.arg1)
      arm64_bin_emit(st, @object.enc_sub_ext(31, 31, rn))
      if !i.to.is_none() {
        arm64_bin_emit(
          st,
          @object.enc_add_imm(arm64_bin_reg(i.to.tmp_val()), 31, 0),
        )
      }
    }
    _ => arm64_bin_table(st, i)
  }
}

///|
fn arm64_bin_epilogue(st : Arm64BinState) -> Unit raise {
  let fn_ = st.fn_
  let mut o = st.frame + 16
  for r in @types.arm64_rclob {
    if (fn_.reg & (1UL << r)) != 0UL {
      o = o - 8
      let rr = arm64_bin_reg(r)
      if r >= @types.ARM64_V0 {
        arm64_bin_emit(st, @object.enc_ldst_fp(3, 1, rr, 29, o))
      } else {
        arm64_bin_emit(st, @object.enc_ldr_x(rr, 29, o))
      }
    }
  }
  if fn_.has_dynalloc {
    arm64_bin_emit(st, @object.enc_add_imm(31, 29, 0))
  }
  let mut oo = st.frame + 16
  if fn_.is_vararg && !st.apple {
    oo = oo + 192
  }
  if oo > 504 {
    arm64_bin_emit(st, @object.enc_ldp_post(29, 30, 31, 16))
    arm64_bin_emit(st, @object.enc_add_imm(31, 31, oo - 16))
  } else {
    arm64_bin_emit(st, @object.enc_ldp_post(29, 30, 31, oo))
  }
  arm64_bin_emit(st, @object.enc_ret())
}

///|
fn arm64_binfn(st : Arm64BinState) -> Unit raise {
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

  // prologue
  arm64_bin_emit(st, @object.enc_hint(34))
  if fn_.is_vararg && !st.apple {
    raise @util.QbeError::Ice("arm64 bin: vararg prologue not supported yet")
  }
  if st.frame + 16 > 512 {
    arm64_bin_emit(st, @object.enc_sub_imm(31, 31, st.frame))
    arm64_bin_emit(st, @object.enc_stp_pre(29, 30, 31, -16))
  } else {
    arm64_bin_emit(st, @object.enc_stp_pre(29, 30, 31, -(st.frame + 16)))
  }
  arm64_bin_emit(st, @object.enc_add_imm(29, 31, 0))
  o = st.frame + 16
  for r in @types.arm64_rclob {
    if (fn_.reg & (1UL << r)) != 0UL {
      o = o - 8
      let rr = arm64_bin_reg(r)
      if r >= @types.ARM64_V0 {
        arm64_bin_emit(st, @object.enc_ldst_fp(3, 0, rr, 29, o))
      } else {
        arm64_bin_emit(st, @object.enc_str_x(rr, 29, o))
      }
    }
  }

  // body
  let mut lbl = false
  for idx in 0..<fn_.rpo.length() {
    let bid = fn_.rpo[idx]
    let b = fn_.blks[bid]
    let next = if idx + 1 < fn_.rpo.length() { fn_.rpo[idx + 1] } else { -1 }
    if lbl || b.npred > 1 {
      arm64_bin_label(st, arm64_emit_id0[0] + b.rpo_id)
    }
    for ins in b.ins {
      arm64_bin_ins(st, ins)
    }
    lbl = true
    match b.jmp.kind {
      @types.Jret0 => arm64_bin_epilogue(st)
      @types.Jjmp =>
        if b.jmp.s1 >= 0 && b.jmp.s1 != next {
          arm64_bin_b(st, arm64_emit_id0[0] + fn_.blks[b.jmp.s1].rpo_id)
        } else {
          lbl = false
        }
      _ => {
        let c = b.jmp.kind.index() - @types.Jjfieq.index()
        if c < 0 || c > 17 {
          raise @util.QbeError::Ice("arm64 bin: unhandled jump")
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
        arm64_bin_bcond(
          st,
          if neg {
            arm64_bin_cond_neg[c]
          } else {
            arm64_bin_cond[c]
          },
          arm64_emit_id0[0] + fn_.blks[s2].rpo_id,
        )
        if s1 >= 0 && s1 != next {
          arm64_bin_b(st, arm64_emit_id0[0] + fn_.blks[s1].rpo_id)
        } else {
          lbl = false
        }
      }
    }
  }
  arm64_emit_id0[0] = arm64_emit_id0[0] + fn_.rpo.length()
  arm64_bin_resolve(st)
}

///|
// Emit one function as words plus its unresolved direct calls.
pub fn emit_arm64_bin_fn_ex(
  fn_ : @types.Fn,
  interner : @util.Interner,
  apple : Bool,
) -> (Array[Int], Array[(Int, String)], Array[(Int, Int, Int, String, Int)]) raise {
  let st = arm64_bin_new(fn_, interner, apple)
  arm64_binfn(st)
  (st.words, st.calls, st.addrs)
}

///|
// Emit one function as a flat array of 32-bit instruction words. Only valid for
// functions without direct calls (use the module emitter otherwise).
pub fn emit_arm64_bin_fn(
  fn_ : @types.Fn,
  interner : @util.Interner,
  apple : Bool,
) -> Array[Int] raise {
  let (words, calls, addrs) = emit_arm64_bin_fn_ex(fn_, interner, apple)
  if calls.length() > 0 || addrs.length() > 0 {
    raise @util.QbeError::Ice(
      "arm64 bin: function needs module linking; use emit_arm64_bin_module",
    )
  }
  words
}

///|
// Little-endian write of the low n bytes of v.
fn arm64_bin_put_le(buf : Array[Int], off : Int, v : Int64, n : Int) -> Unit {
  let mut x = v
  for i in 0..<n {
    buf[off + i] = (x & 0xFFL).to_int()
    x = x >> 8
  }
}

///|
fn arm64_bin_align_up(v : Int, a : Int) -> Int {
  if a <= 1 {
    v
  } else {
    (v + a - 1) / a * a
  }
}

///|
fn arm64_bin_dat_width(kind : @types.DatKind) -> Int {
  match kind {
    @types.DB => 1
    @types.DH => 2
    @types.DW => 4
    @types.DL => 8
    _ => 0
  }
}

///|
fn arm64_bin_dat_size(d : @types.Dat) -> Int {
  if d.is_str {
    @utf8.encode(d.str).length()
  } else {
    arm64_bin_dat_width(d.kind)
  }
}

///|
// Lay the module's data items out as a flat byte image, returning the address
// of every named global (byte offset within the image).
fn arm64_bin_layout_data(
  datas : Array[@types.Dat],
) -> (Array[(String, Int)], Array[Int]) {
  let addr_of : Array[(String, Int)] = []
  let mut off = 0
  let mut align = 8
  for d in datas {
    match d.kind {
      @types.DStart => align = 8
      @types.DAlign => align = d.num.to_int()
      @types.DName => {
        off = arm64_bin_align_up(off, align)
        addr_of.push((d.str, off))
      }
      @types.DEnd => ()
      @types.DZ => off = off + d.num.to_int()
      _ => off = off + arm64_bin_dat_size(d)
    }
  }
  let buf : Array[Int] = Array::make(off, 0)
  let mut cur = 0
  let mut align = 8
  for d in datas {
    match d.kind {
      @types.DStart => align = 8
      @types.DAlign => align = d.num.to_int()
      @types.DName => cur = arm64_bin_align_up(cur, align)
      @types.DEnd => ()
      @types.DZ => cur = cur + d.num.to_int()
      _ => {
        let w = arm64_bin_dat_size(d)
        if d.is_str {
          let b = @utf8.encode(d.str)
          for i in 0..<b.length() {
            buf[cur + i] = b[i].to_int()
          }
        } else if d.is_ref {
          let mut base = 0
          for p in addr_of {
            if p.0 == d.ref_name {
              base = p.1
            }
          }
          arm64_bin_put_le(
            buf,
            cur,
            (base + d.ref_offset.to_int()).to_int64(),
            w,
          )
        } else {
          let mut v = d.num
          if d.num == 0L && d.flts != 0.0 {
            v = d.flts.reinterpret_as_uint().to_int64()
          } else if d.num == 0L && d.fltd != 0.0 {
            v = d.fltd.reinterpret_as_int64()
          }
          arm64_bin_put_le(buf, cur, v, w)
        }
        cur = cur + w
      }
    }
  }
  (addr_of, buf)
}

///|
// Lay out the floating-point constant stash (fp0, fp1, ...) that the arm64 isel
// references as local rodata symbols. Returns (name -> byte offset, bytes).
fn arm64_fp_layout() -> (Array[(String, Int)], Array[Int]) {
  let syms : Array[(String, Int)] = []
  let buf : Array[Int] = []
  for i in 0..<@types.fp_stash_len() {
    let e = @types.fp_stash_at(i)
    let n = if e.size == 16 { 16 } else if e.size == 8 { 8 } else { 4 }
    let align = if n == 16 { 16 } else if n == 8 { 8 } else { 4 }
    while buf.length() % align != 0 {
      buf.push(0)
    }
    syms.push(("fp" + i.to_string(), buf.length()))
    let mut x = e.b0
    for _ in 0..<n {
      buf.push((x & 0xFFL).to_int())
      x = x >> 8
    }
  }
  (syms, buf)
}

///|
// A linked module image: text words plus a data byte image with every
// intra-module direct call and global address already patched.
pub(all) struct Arm64BinModule {
  words : Array[Int]
  data : Array[Int] // data bytes
  // function name -> word offset within the text
  fns : Array[(String, Int)]
  // global name -> byte offset within the data image
  datas : Array[(String, Int)]
  exports : Array[String]
  // Byte length of the executable code region. When the module has data this is
  // page-aligned so the data can stay writable while the code is mprotected RX.
  code_bytes : Int
}

///|
// The executable image: text bytes, padded to 16, then the data bytes. Global
// addresses were computed against exactly this layout.
pub fn Arm64BinModule::image(self : Arm64BinModule) -> Bytes {
  let a : Array[Byte] = []
  for w in self.words {
    a.push((w & 0xFF).to_byte())
    a.push(((w >> 8) & 0xFF).to_byte())
    a.push(((w >> 16) & 0xFF).to_byte())
    a.push(((w >> 24) & 0xFF).to_byte())
  }
  while a.length() < self.code_bytes {
    a.push((0).to_byte())
  }
  for b in self.data {
    a.push(b.to_byte())
  }
  Bytes::from_array(a[:])
}

///|
pub fn emit_arm64_bin_module(
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
  interner : @util.Interner,
  apple : Bool,
) -> Arm64BinModule raise {
  arm64_emit_reset()
  let words : Array[Int] = []
  let fns : Array[(String, Int)] = []
  let pending : Array[(Int, String)] = []
  let pending_addrs : Array[(Int, Int, Int, String, Int)] = []
  for fn_ in funcs {
    let (w, calls, addrs) = emit_arm64_bin_fn_ex(fn_, interner, apple)
    let off = words.length()
    fns.push((fn_.name, off))
    for x in w {
      words.push(x)
    }
    for c in calls {
      pending.push((off + c.0, c.1))
    }
    for a in addrs {
      pending_addrs.push((off + a.0, off + a.1, a.2, a.3, a.4))
    }
  }
  for c in pending {
    let mut target = -1
    for f in fns {
      if f.0 == c.1 {
        target = f.1
      }
    }
    if target < 0 {
      raise @util.QbeError::Ice("arm64 bin: call to undefined symbol " + c.1)
    }
    words[c.0] = @object.enc_bl((target - c.0) * 4)
  }
  let (datas_map0, data_bytes0) = arm64_bin_layout_data(datas)
  // Append the floating-point constant stash (fpN) after the data section.
  let (fp_map, fp_bytes) = arm64_fp_layout()
  let fp_base = arm64_bin_align_up(data_bytes0.length(), 16)
  let data_bytes = data_bytes0.copy()
  while data_bytes.length() < fp_base {
    data_bytes.push(0)
  }
  for b in fp_bytes {
    data_bytes.push(b)
  }
  let datas_map = datas_map0.copy()
  for p in fp_map {
    datas_map.push((p.0, fp_base + p.1))
  }
  let text_bytes = words.length() * 4
  // Keep the data region in its own page(s): mprotect() protects whole pages,
  // and the smallest page size the JIT might run on is 4KB while macOS/aarch64
  // uses 16KB, so align well above both.
  let code_bytes = if data_bytes.length() > 0 {
    arm64_bin_align_up(text_bytes, 65536)
  } else {
    text_bytes
  }
  let data_start = code_bytes
  for a in pending_addrs {
    let mut base = -1
    for p in datas_map {
      if p.0 == a.3 {
        base = p.1
      }
    }
    if base < 0 {
      raise @util.QbeError::Ice("arm64 bin: undefined data symbol " + a.3)
    }
    let target = data_start + base + a.4
    let pc = a.0 * 4
    words[a.0] = @object.enc_adrp(a.2, (target >> 12) - (pc >> 12))
    words[a.1] = @object.enc_add_imm(a.2, a.2, target & 0xFFF)
  }
  let exports : Array[String] = []
  for fn_ in funcs {
    if fn_.is_export {
      exports.push(fn_.name)
    }
  }
  Arm64BinModule::{
    words,
    data: data_bytes,
    fns,
    datas: datas_map,
    exports,
    code_bytes,
  }
}
