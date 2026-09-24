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
fn arm64_bin_loadcon(
  st : Arm64BinState,
  con : @types.Con,
  r : Int,
  k : @types.Class,
) -> Unit raise {
  if con.kind == @types.CAddr {
    raise @util.QbeError::Ice(
      "arm64 bin: global address constants not supported yet",
    )
  }
  let w = k.wide()
  let sf = w != 0
  let mut n = con.raw_bits()
  if w == 0 {
    n = arm64_s32(n)
  }
  let rd = arm64_bin_reg(r)
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
        arm64_bin_emit(
          st,
          @object.enc_add_reg_sf(
            sf,
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
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
        arm64_bin_emit(
          st,
          @object.enc_sub_reg_sf(
            sf,
            rd,
            arm64_bin_r(st, i.arg1),
            arm64_bin_r(st, i.arg2),
          ),
        )
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
    @types.And =>
      arm64_bin_emit(
        st,
        @object.enc_and_reg_sf(
          sf,
          rd,
          arm64_bin_r(st, i.arg1),
          arm64_bin_r(st, i.arg2),
        ),
      )
    @types.Or =>
      arm64_bin_emit(
        st,
        @object.enc_orr_reg_sf(
          sf,
          rd,
          arm64_bin_r(st, i.arg1),
          arm64_bin_r(st, i.arg2),
        ),
      )
    @types.Xor =>
      arm64_bin_emit(
        st,
        @object.enc_eor_reg_sf(
          sf,
          rd,
          arm64_bin_r(st, i.arg1),
          arm64_bin_r(st, i.arg2),
        ),
      )
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
          @object.enc_fcmp_d(arm64_bin_r(st, i.arg1), arm64_bin_r(st, i.arg2)),
        )
      } else {
        raise @util.QbeError::Ice("arm64 bin: single-precision compare")
      }
    @types.Load => {
      let (rn, off) = arm64_bin_mem(st, i.arg1)
      let size = if i.cls == @types.Kl || i.cls == @types.Kd { 3 } else { 2 }
      arm64_bin_emit(st, @object.enc_ldst(size, 1, rd, rn, off))
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
      arm64_bin_emit(st, @object.enc_ldst(size, opc, rt, rn, off))
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
        raise @util.QbeError::Ice("arm64 bin: single-precision copy")
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
      raise @util.QbeError::Ice("arm64 bin: calls not supported yet")
    @types.Salloc => {
      let rn = arm64_bin_r(st, i.arg1)
      arm64_bin_emit(st, @object.enc_sub_reg(31, 31, rn))
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
      arm64_bin_emit(st, @object.enc_ldr_x(arm64_bin_reg(r), 29, o))
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
      arm64_bin_emit(st, @object.enc_str_x(arm64_bin_reg(r), 29, o))
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
// Emit one function as a flat array of 32-bit instruction words.
pub fn emit_arm64_bin_fn(
  fn_ : @types.Fn,
  interner : @util.Interner,
  apple : Bool,
) -> Array[Int] raise {
  let st = arm64_bin_new(fn_, interner, apple)
  arm64_binfn(st)
  st.words
}
