///|
// AArch64 instruction encoder. Words are 32-bit values (kept in 32-bit Int).
// Every form here is validated byte-for-byte against clang in the tests.

///|
fn r5(x : Int32) -> Int32 {
  x & 31
}

///|
fn sfbit(sf : Bool) -> Int32 {
  if sf {
    1
  } else {
    0
  }
}

///|
// ADD/SUB (immediate): sf op S 100010 sh imm12 Rn Rd.
fn dpr_addsub_imm(
  sf : Bool,
  sub : Bool,
  set_flags : Bool,
  rd : Int32,
  rn : Int32,
  sh : Int32,
  imm12 : Int32,
) -> Int32 {
  (sfbit(sf) << 31) |
  ((if sub { 1 } else { 0 }) << 30) |
  ((if set_flags { 1 } else { 0 }) << 29) |
  (0x22 << 23) |
  ((sh & 1) << 22) |
  ((imm12 & 0xFFF) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
// The binary emitter packs sh in bit 12 and imm12 in the low 12 bits.
fn dpr_addsub_imm_packed(
  sf : Bool,
  sub : Bool,
  set_flags : Bool,
  rd : Int32,
  rn : Int32,
  imm : Int32,
) -> Int32 {
  dpr_addsub_imm(sf, sub, set_flags, rd, rn, (imm >> 12) & 1, imm & 0xFFF)
}

///|
// ADD/SUB (shifted register): sf op S 01011 shift N Rm imm6 Rn Rd.
fn dpr_addsub(
  sf : Bool,
  sub : Bool,
  set_flags : Bool,
  rd : Int32,
  rn : Int32,
  rm : Int32,
) -> Int32 {
  (sfbit(sf) << 31) |
  ((if sub { 1 } else { 0 }) << 30) |
  ((if set_flags { 1 } else { 0 }) << 29) |
  (0x0B << 24) |
  (r5(rm) << 16) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_add_reg(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  dpr_addsub(true, false, false, rd, rn, rm)
}

///|
pub fn enc_sub_reg(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  dpr_addsub(true, true, false, rd, rn, rm)
}

///|
pub fn enc_cmp(rn : Int32, rm : Int32) -> Int32 {
  dpr_addsub(true, true, true, 31, rn, rm)
}

///|
pub fn enc_cmn(rn : Int32, rm : Int32) -> Int32 {
  dpr_addsub(true, false, true, 31, rn, rm)
}

///|
// ADD/SUB (immediate): sf op S 100010 sh imm12 Rn Rd.
pub fn enc_add_imm(rd : Int32, rn : Int32, imm12 : Int32) -> Int32 {
  (1 << 31) | (0x22 << 23) | ((imm12 & 0xFFF) << 10) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_sub_imm(rd : Int32, rn : Int32, imm12 : Int32) -> Int32 {
  (1 << 31) |
  (1 << 30) |
  (0x22 << 23) |
  ((imm12 & 0xFFF) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_add_imm32(rd : Int32, rn : Int32, imm12 : Int32) -> Int32 {
  (0x22 << 23) | ((imm12 & 0xFFF) << 10) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_sub_imm32(rd : Int32, rn : Int32, imm12 : Int32) -> Int32 {
  (1 << 30) | (0x22 << 23) | ((imm12 & 0xFFF) << 10) | (r5(rn) << 5) | r5(rd)
}

///|
// Class-aware immediate forms (32/64-bit) and the CMP/CMN aliases (Rd = ZR,
// S = 1), which the binary emitter needs for operands left as constants.
pub fn enc_add_imm_sf(
  sf : Bool,
  rd : Int32,
  rn : Int32,
  imm12 : Int32,
) -> Int32 {
  dpr_addsub_imm_packed(sf, false, false, rd, rn, imm12)
}

///|
pub fn enc_sub_imm_sf(
  sf : Bool,
  rd : Int32,
  rn : Int32,
  imm12 : Int32,
) -> Int32 {
  dpr_addsub_imm_packed(sf, true, false, rd, rn, imm12)
}

///|
pub fn enc_cmp_imm_sf(sf : Bool, rn : Int32, imm12 : Int32) -> Int32 {
  dpr_addsub_imm_packed(sf, true, true, 31, rn, imm12)
}

///|
pub fn enc_cmn_imm_sf(sf : Bool, rn : Int32, imm12 : Int32) -> Int32 {
  dpr_addsub_imm_packed(sf, false, true, 31, rn, imm12)
}

///|
// Logical (shifted register): sf opc 01010 shift N Rm imm6 Rn Rd.
pub fn enc_logic(opc : Int32, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  (1 << 31) |
  (opc << 29) |
  (0x0A << 24) |
  (r5(rm) << 16) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_and_reg(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_logic(0, rd, rn, rm)
}

///|
pub fn enc_orr_reg(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_logic(1, rd, rn, rm)
}

///|
pub fn enc_eor_reg(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_logic(2, rd, rn, rm)
}

///|
// MOV (register) = ORR Rd, XZR, Rm.
pub fn enc_mov_reg(rd : Int32, rm : Int32) -> Int32 {
  enc_orr_reg(rd, 31, rm)
}

///|
// Data-processing (2 source): sf 0 0 11010110 Rm opcode2 Rn Rd.
pub fn enc_dp2(opcode2 : Int32, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  (1 << 31) |
  (0xD6 << 21) |
  (r5(rm) << 16) |
  ((opcode2 & 0x3F) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_lsl(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2(0x08, rd, rn, rm)
}

///|
pub fn enc_lsr(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2(0x09, rd, rn, rm)
}

///|
pub fn enc_asr(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2(0x0A, rd, rn, rm)
}

///|
pub fn enc_sdiv(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2(0x03, rd, rn, rm)
}

///|
pub fn enc_udiv(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2(0x02, rd, rn, rm)
}

///|
// MADD/MSUB: sf 00 11011 000 Rm o0 Ra Rn Rd.
pub fn enc_madd(
  sf : Bool,
  o0 : Bool,
  rd : Int32,
  rn : Int32,
  rm : Int32,
  ra : Int32,
) -> Int32 {
  (sfbit(sf) << 31) |
  (0x1B << 24) |
  (r5(rm) << 16) |
  ((if o0 { 1 } else { 0 }) << 15) |
  (r5(ra) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_mul(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_madd(true, false, rd, rn, rm, 31)
}

///|
pub fn enc_msub(rd : Int32, rn : Int32, rm : Int32, ra : Int32) -> Int32 {
  enc_madd(true, true, rd, rn, rm, ra)
}

///|
// MOVZ / MOVK (64-bit): sf opc 100101 hw imm16 Rd.
pub fn enc_movz(rd : Int32, imm16 : Int32, hw : Int32) -> Int32 {
  (1 << 31) |
  (2 << 29) |
  (0x25 << 23) |
  ((hw & 3) << 21) |
  ((imm16 & 0xFFFF) << 5) |
  r5(rd)
}

///|
pub fn enc_movk(rd : Int32, imm16 : Int32, hw : Int32) -> Int32 {
  (1 << 31) |
  (3 << 29) |
  (0x25 << 23) |
  ((hw & 3) << 21) |
  ((imm16 & 0xFFFF) << 5) |
  r5(rd)
}

///|
// ADRP: PC-relative page address (op 1 immlo 10000 immhi Rd). `imm` is the
// signed page count (byte offset / 4096), i.e. the 21-bit value split across
// immlo:immhi.
pub fn enc_adrp(rd : Int32, imm : Int32) -> Int32 {
  (1 << 31) |
  ((imm & 3) << 29) |
  (0x10 << 24) |
  (((imm >> 2) & 0x7FFFF) << 5) |
  r5(rd)
}

///|
// CSINC (conditional select, increment): sf op S 11010100 Rm cond 01 Rn Rd.
pub fn enc_csinc(
  sf : Bool,
  rd : Int32,
  rn : Int32,
  rm : Int32,
  cond : Int32,
) -> Int32 {
  (sfbit(sf) << 31) |
  (0b11010100 << 21) |
  (r5(rm) << 16) |
  ((cond & 15) << 12) |
  (0b01 << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
// CSET Rd, cond is the alias CSINC Rd, ZR, ZR, invert(cond).
pub fn enc_cset(sf : Bool, rd : Int32, cond : Int32) -> Int32 {
  enc_csinc(sf, rd, 31, 31, cond ^ 1)
}

///|
// Class-aware variants: the text emitter selects w/x (and s/d) by class, so the
// binary emitter needs the same sf bit. The 64-bit wrappers above delegate here.
pub fn enc_logic_sf(
  sf : Bool,
  opc : Int32,
  rd : Int32,
  rn : Int32,
  rm : Int32,
) -> Int32 {
  (sfbit(sf) << 31) |
  (opc << 29) |
  (0x0A << 24) |
  (r5(rm) << 16) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_and_reg_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_logic_sf(sf, 0, rd, rn, rm)
}

///|
pub fn enc_orr_reg_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_logic_sf(sf, 1, rd, rn, rm)
}

///|
pub fn enc_eor_reg_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_logic_sf(sf, 2, rd, rn, rm)
}

///|
pub fn enc_mov_reg_sf(sf : Bool, rd : Int32, rm : Int32) -> Int32 {
  enc_orr_reg_sf(sf, rd, 31, rm)
}

///|
pub fn enc_dp2_sf(
  sf : Bool,
  opcode2 : Int32,
  rd : Int32,
  rn : Int32,
  rm : Int32,
) -> Int32 {
  (sfbit(sf) << 31) |
  (0xD6 << 21) |
  (r5(rm) << 16) |
  ((opcode2 & 0x3F) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_lsl_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2_sf(sf, 0x08, rd, rn, rm)
}

///|
pub fn enc_lsr_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2_sf(sf, 0x09, rd, rn, rm)
}

///|
pub fn enc_asr_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2_sf(sf, 0x0A, rd, rn, rm)
}

///|
pub fn enc_sdiv_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2_sf(sf, 0x03, rd, rn, rm)
}

///|
pub fn enc_udiv_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_dp2_sf(sf, 0x02, rd, rn, rm)
}

///|
pub fn enc_add_reg_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  dpr_addsub(sf, false, false, rd, rn, rm)
}

///|
pub fn enc_sub_reg_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  dpr_addsub(sf, true, false, rd, rn, rm)
}

///|
// ADD/SUB (extended register): sf op S 01011 001 Rm option imm3 Rn Rd.
// GAS uses this form whenever SP is an operand.
pub fn enc_addsub_ext(
  sf : Bool,
  sub : Bool,
  rd : Int32,
  rn : Int32,
  rm : Int32,
) -> Int32 {
  (sfbit(sf) << 31) |
  ((if sub { 1 } else { 0 }) << 30) |
  (0x0B << 24) |
  (1 << 21) |
  (r5(rm) << 16) |
  (3 << 13) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_add_ext(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_addsub_ext(true, false, rd, rn, rm)
}

///|
pub fn enc_sub_ext(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_addsub_ext(true, true, rd, rn, rm)
}

///|
pub fn enc_cmp_sf(sf : Bool, rn : Int32, rm : Int32) -> Int32 {
  dpr_addsub(sf, true, true, 31, rn, rm)
}

///|
pub fn enc_cmn_sf(sf : Bool, rn : Int32, rm : Int32) -> Int32 {
  dpr_addsub(sf, false, true, 31, rn, rm)
}

///|
pub fn enc_mul_sf(sf : Bool, rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  enc_madd(sf, false, rd, rn, rm, 31)
}

///|
pub fn enc_msub_sf(
  sf : Bool,
  rd : Int32,
  rn : Int32,
  rm : Int32,
  ra : Int32,
) -> Int32 {
  enc_madd(sf, true, rd, rn, rm, ra)
}

///|
// MOVZ/MOVK without the sf bit fixed to 1 (32-bit form uses 0x52.../0x72...).
pub fn enc_movz_sf(sf : Bool, rd : Int32, imm16 : Int32, hw : Int32) -> Int32 {
  (sfbit(sf) << 31) |
  (2 << 29) |
  (0x25 << 23) |
  ((hw & 3) << 21) |
  ((imm16 & 0xFFFF) << 5) |
  r5(rd)
}

///|
pub fn enc_movk_sf(sf : Bool, rd : Int32, imm16 : Int32, hw : Int32) -> Int32 {
  (sfbit(sf) << 31) |
  (3 << 29) |
  (0x25 << 23) |
  ((hw & 3) << 21) |
  ((imm16 & 0xFFFF) << 5) |
  r5(rd)
}

///|
// Bitfield: sf opc 100110 N immr imms Rn Rd (opc 0 = SBFM, 2 = UBFM).
pub fn enc_bitfield(
  sf : Bool,
  opc : Int32,
  n : Int32,
  rd : Int32,
  rn : Int32,
  immr : Int32,
  imms : Int32,
) -> Int32 {
  (sfbit(sf) << 31) |
  ((opc & 3) << 29) |
  (0x26 << 23) |
  ((n & 1) << 22) |
  ((immr & 0x3F) << 16) |
  ((imms & 0x3F) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_sxtb(rd : Int32, rn : Int32) -> Int32 {
  enc_bitfield(true, 0, 1, rd, rn, 0, 7)
}

///|
pub fn enc_sxth(rd : Int32, rn : Int32) -> Int32 {
  enc_bitfield(true, 0, 1, rd, rn, 0, 15)
}

///|
pub fn enc_sxtw(rd : Int32, rn : Int32) -> Int32 {
  enc_bitfield(true, 0, 1, rd, rn, 0, 31)
}

///|
pub fn enc_uxtb(rd : Int32, rn : Int32) -> Int32 {
  enc_bitfield(false, 2, 0, rd, rn, 0, 7)
}

///|
pub fn enc_uxth(rd : Int32, rn : Int32) -> Int32 {
  enc_bitfield(false, 2, 0, rd, rn, 0, 15)
}

///|
// Load/store (unsigned offset): size 111 0 01 opc 0 imm12 Rn Rt.
pub fn enc_ldst(
  size : Int32,
  opc : Int32,
  rt : Int32,
  rn : Int32,
  off : Int32,
) -> Int32 {
  let shift = if size == 3 {
    3
  } else if size == 2 {
    2
  } else if size == 1 {
    1
  } else {
    0
  }
  let scaled = off >> shift
  if scaled < 0 || scaled > 0xFFF {
    abort(
      "arm64 enc: load/store offset " +
      off.to_string() +
      " does not fit the 12-bit scaled field (size " +
      size.to_string() +
      ")",
    )
  }
  (size << 30) |
  (7 << 27) |
  (1 << 24) |
  ((opc & 3) << 22) |
  ((scaled & 0xFFF) << 10) |
  (r5(rn) << 5) |
  r5(rt)
}

///|
pub fn enc_ldr_x(rt : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldst(3, 1, rt, rn, off)
}

///|
pub fn enc_str_x(rt : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldst(3, 0, rt, rn, off)
}

///|
pub fn enc_ldrb(rt : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldst(0, 1, rt, rn, off)
}

///|
pub fn enc_strb(rt : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldst(0, 0, rt, rn, off)
}

///|
pub fn enc_ldrh(rt : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldst(1, 1, rt, rn, off)
}

///|
pub fn enc_strh(rt : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldst(1, 0, rt, rn, off)
}

///|
pub fn enc_ldrsw(rt : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldst(2, 2, rt, rn, off)
}

///|
pub fn enc_ldr_w(rt : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldst(2, 1, rt, rn, off)
}

///|
pub fn enc_str_w(rt : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldst(2, 0, rt, rn, off)
}

///|
// FP/SIMD load/store: the integer LDR/STR immediate with the V (bit 26) set.
pub fn enc_ldst_fp(
  size : Int32,
  opc : Int32,
  rt : Int32,
  rn : Int32,
  off : Int32,
) -> Int32 {
  enc_ldst(size, opc, rt, rn, off) | (1 << 26)
}

///|
// LDP/STP: the addressing mode selects the base; imm7 is scaled by 8.
pub fn enc_ldp_stp(
  is_load : Bool,
  is_store : Bool,
  rt : Int32,
  rt2 : Int32,
  rn : Int32,
  off : Int32,
  pre : Bool,
  post : Bool,
) -> Int32 {
  let base = if pre {
    0xA9800000
  } else if post {
    0xA8800000
  } else {
    0xA9000000
  }
  let load_bit = if is_load { 1 << 22 } else { 0 }
  let _ = is_store
  base |
  load_bit |
  (((off >> 3) & 0x7F) << 15) |
  (r5(rt2) << 10) |
  (r5(rn) << 5) |
  r5(rt)
}

///|
pub fn enc_ldp(rt : Int32, rt2 : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldp_stp(true, false, rt, rt2, rn, off, false, false)
}

///|
pub fn enc_stp_pre(rt : Int32, rt2 : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldp_stp(false, true, rt, rt2, rn, off, true, false)
}

///|
pub fn enc_ldp_post(rt : Int32, rt2 : Int32, rn : Int32, off : Int32) -> Int32 {
  enc_ldp_stp(true, false, rt, rt2, rn, off, false, true)
}

///|
// Branches. off is in bytes; imm26/imm19 are instruction counts.
pub fn enc_b(off : Int32) -> Int32 {
  (0x05 << 26) | ((off >> 2) & 0x3FFFFFF)
}

///|
pub fn enc_bl(off : Int32) -> Int32 {
  (0x25 << 26) | ((off >> 2) & 0x3FFFFFF)
}

///|
pub fn enc_bcond(cond : Int32, off : Int32) -> Int32 {
  (0x2A << 25) | (((off >> 2) & 0x7FFFF) << 5) | (cond & 0xF)
}

///|
pub fn enc_cbz(sf : Bool, nonzero : Bool, rt : Int32, off : Int32) -> Int32 {
  (sfbit(sf) << 31) |
  (0x1A << 25) |
  ((if nonzero { 1 } else { 0 }) << 24) |
  (((off >> 2) & 0x7FFFF) << 5) |
  r5(rt)
}

///|
pub fn enc_br(rn : Int32) -> Int32 {
  (0xD6 << 24) | (0x1F << 16) | (r5(rn) << 5)
}

///|
pub fn enc_blr(rn : Int32) -> Int32 {
  (0xD6 << 24) | (0x3F << 16) | (r5(rn) << 5)
}

///|
// MOVN (inverted wide immediate): sf 00 100101 hw imm16 Rd.
pub fn enc_movn_sf(sf : Bool, rd : Int32, imm16 : Int32, hw : Int32) -> Int32 {
  (sfbit(sf) << 31) |
  (0x25 << 23) |
  ((hw & 3) << 21) |
  ((imm16 & 0xFFFF) << 5) |
  r5(rd)
}

///|
// Logical (immediate): sf opc 100100 N immr imms Rn Rd (opc 0=AND 1=ORR 2=EOR).
pub fn enc_logimm_sf(
  sf : Bool,
  opc : Int32,
  rd : Int32,
  rn : Int32,
  n : Int32,
  immr : Int32,
  imms : Int32,
) -> Int32 {
  (sfbit(sf) << 31) |
  ((opc & 3) << 29) |
  (0x24 << 23) |
  ((n & 1) << 22) |
  ((immr & 0x3F) << 16) |
  ((imms & 0x3F) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_ret() -> Int32 {
  0xD65F03C0
}

///|
pub fn enc_hint(imm : Int32) -> Int32 {
  0xD503201F | ((imm & 0x7F) << 5)
}

///|
pub fn enc_nop() -> Int32 {
  0xD503201F
}

///|
// Floating point (double unless noted). Bases are the fixed opcode fields.
pub fn enc_fadd_d(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  0x1E602800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fsub_d(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  0x1E603800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmul_d(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  0x1E600800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fdiv_d(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  0x1E601800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fcmp_d(rn : Int32, rm : Int32) -> Int32 {
  0x1E602000 | (r5(rm) << 16) | (r5(rn) << 5)
}

///|
pub fn enc_fcvtzs_x_d(rd : Int32, rn : Int32) -> Int32 {
  0x9E780000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_scvtf_d_x(rd : Int32, rn : Int32) -> Int32 {
  0x9E620000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmov_d(rd : Int32, rn : Int32) -> Int32 {
  0x1E604000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmov_x_d(rd : Int32, rn : Int32) -> Int32 {
  0x9E660000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fcvt_d_s(rd : Int32, rn : Int32) -> Int32 {
  0x1E22C000 | (r5(rn) << 5) | r5(rd)
}

///|
// Single-precision FP arithmetic (bit 22 cleared vs the double forms).
pub fn enc_fadd_s(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  0x1E202800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fsub_s(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  0x1E203800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmul_s(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  0x1E200800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fdiv_s(rd : Int32, rn : Int32, rm : Int32) -> Int32 {
  0x1E201800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
// FCMPE: like FCMP but signals on quiet NaNs (QBE emits the e form).
pub fn enc_fcmpe_d(rn : Int32, rm : Int32) -> Int32 {
  0x1E602010 | (r5(rm) << 16) | (r5(rn) << 5)
}

///|
pub fn enc_fcmpe_s(rn : Int32, rm : Int32) -> Int32 {
  0x1E202010 | (r5(rm) << 16) | (r5(rn) << 5)
}

///|
pub fn enc_fcvtzs_w_d(rd : Int32, rn : Int32) -> Int32 {
  0x1E780000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fcvtzs_w_s(rd : Int32, rn : Int32) -> Int32 {
  0x1E380000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fcvtzs_x_s(rd : Int32, rn : Int32) -> Int32 {
  0x9E380000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_scvtf_d_w(rd : Int32, rn : Int32) -> Int32 {
  0x1E620000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_scvtf_s_w(rd : Int32, rn : Int32) -> Int32 {
  0x1E220000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_scvtf_s_x(rd : Int32, rn : Int32) -> Int32 {
  0x9E220000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fcvt_s_d(rd : Int32, rn : Int32) -> Int32 {
  0x1E624000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmov_s(rd : Int32, rn : Int32) -> Int32 {
  0x1E204000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmov_w_s(rd : Int32, rn : Int32) -> Int32 {
  0x1E260000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmov_s_w(rd : Int32, rn : Int32) -> Int32 {
  0x1E270000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmov_d_x(rd : Int32, rn : Int32) -> Int32 {
  0x9E670000 | (r5(rn) << 5) | r5(rd)
}

///|
// Sign/zero extension with an explicit sf (SBFM's N bit mirrors sf).
pub fn enc_sxtb_sf(sf : Bool, rd : Int32, rn : Int32) -> Int32 {
  enc_bitfield(sf, 0, sfbit(sf), rd, rn, 0, 7)
}

///|
pub fn enc_sxth_sf(sf : Bool, rd : Int32, rn : Int32) -> Int32 {
  enc_bitfield(sf, 0, sfbit(sf), rd, rn, 0, 15)
}

///|
pub fn enc_uxtb_sf(sf : Bool, rd : Int32, rn : Int32) -> Int32 {
  // N mirrors sf, as in SBFM: with N = 0 and sf = 1 the encoding is
  // unallocated and the CPU raises SIGILL.
  enc_bitfield(sf, 2, sfbit(sf), rd, rn, 0, 7)
}

///|
pub fn enc_uxth_sf(sf : Bool, rd : Int32, rn : Int32) -> Int32 {
  enc_bitfield(sf, 2, sfbit(sf), rd, rn, 0, 15)
}

///|
// Little-endian serialization of 32-bit instruction words.
pub fn words_to_bytes(words : Array[Int32]) -> Bytes {
  let a : Array[Byte] = []
  for w in words {
    push_u8(a, w & 0xFF)
    push_u8(a, (w >> 8) & 0xFF)
    push_u8(a, (w >> 16) & 0xFF)
    push_u8(a, (w >> 24) & 0xFF)
  }
  Bytes::from_array(a[:])
}

///|
// LDAR: load-acquire (sequentially consistent acquire semantics).
pub fn enc_ldar(sf : Bool, rt : Int32, rn : Int32) -> Int32 {
  (if sf { 0xC8DFFC00 } else { 0x88DFFC00 }) | (rn << 5) | rt
}

///|
// STLR: store-release.
pub fn enc_stlr(sf : Bool, rt : Int32, rn : Int32) -> Int32 {
  (if sf { 0xC89FFC00 } else { 0x889FFC00 }) | (rn << 5) | rt
}

///|
// DMB ISH: full barrier for the inner-shareable domain.
pub fn enc_dmb_ish() -> Int32 {
  0xD5033BBF
}
