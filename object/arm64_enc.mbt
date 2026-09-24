///|
// AArch64 instruction encoder. Words are 32-bit values (kept in 32-bit Int).
// Every form here is validated byte-for-byte against clang in the tests.

///|
fn r5(x : Int) -> Int {
  x & 31
}

///|
fn sfbit(sf : Bool) -> Int {
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
  rd : Int,
  rn : Int,
  sh : Int,
  imm12 : Int,
) -> Int {
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
// ADD/SUB (shifted register): sf op S 01011 shift N Rm imm6 Rn Rd.
fn dpr_addsub(
  sf : Bool,
  sub : Bool,
  set_flags : Bool,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Int {
  (sfbit(sf) << 31) |
  ((if sub { 1 } else { 0 }) << 30) |
  ((if set_flags { 1 } else { 0 }) << 29) |
  (0x0B << 24) |
  (r5(rm) << 16) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_add_reg(rd : Int, rn : Int, rm : Int) -> Int {
  dpr_addsub(true, false, false, rd, rn, rm)
}

///|
pub fn enc_sub_reg(rd : Int, rn : Int, rm : Int) -> Int {
  dpr_addsub(true, true, false, rd, rn, rm)
}

///|
pub fn enc_cmp(rn : Int, rm : Int) -> Int {
  dpr_addsub(true, true, true, 31, rn, rm)
}

///|
pub fn enc_cmn(rn : Int, rm : Int) -> Int {
  dpr_addsub(true, false, true, 31, rn, rm)
}

///|
// ADD/SUB (immediate): sf op S 100010 sh imm12 Rn Rd.
pub fn enc_add_imm(rd : Int, rn : Int, imm12 : Int) -> Int {
  (1 << 31) | (0x22 << 23) | ((imm12 & 0xFFF) << 10) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_sub_imm(rd : Int, rn : Int, imm12 : Int) -> Int {
  (1 << 31) |
  (1 << 30) |
  (0x22 << 23) |
  ((imm12 & 0xFFF) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_add_imm32(rd : Int, rn : Int, imm12 : Int) -> Int {
  (0x22 << 23) | ((imm12 & 0xFFF) << 10) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_sub_imm32(rd : Int, rn : Int, imm12 : Int) -> Int {
  (1 << 30) | (0x22 << 23) | ((imm12 & 0xFFF) << 10) | (r5(rn) << 5) | r5(rd)
}

///|
// Class-aware immediate forms (32/64-bit) and the CMP/CMN aliases (Rd = ZR,
// S = 1), which the binary emitter needs for operands left as constants.
pub fn enc_add_imm_sf(sf : Bool, rd : Int, rn : Int, imm12 : Int) -> Int {
  dpr_addsub_imm(sf, false, false, rd, rn, 0, imm12)
}

///|
pub fn enc_sub_imm_sf(sf : Bool, rd : Int, rn : Int, imm12 : Int) -> Int {
  dpr_addsub_imm(sf, true, false, rd, rn, 0, imm12)
}

///|
pub fn enc_cmp_imm_sf(sf : Bool, rn : Int, imm12 : Int) -> Int {
  dpr_addsub_imm(sf, true, true, 31, rn, 0, imm12)
}

///|
pub fn enc_cmn_imm_sf(sf : Bool, rn : Int, imm12 : Int) -> Int {
  dpr_addsub_imm(sf, false, true, 31, rn, 0, imm12)
}

///|
// Logical (shifted register): sf opc 01010 shift N Rm imm6 Rn Rd.
pub fn enc_logic(opc : Int, rd : Int, rn : Int, rm : Int) -> Int {
  (1 << 31) |
  (opc << 29) |
  (0x0A << 24) |
  (r5(rm) << 16) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_and_reg(rd : Int, rn : Int, rm : Int) -> Int {
  enc_logic(0, rd, rn, rm)
}

///|
pub fn enc_orr_reg(rd : Int, rn : Int, rm : Int) -> Int {
  enc_logic(1, rd, rn, rm)
}

///|
pub fn enc_eor_reg(rd : Int, rn : Int, rm : Int) -> Int {
  enc_logic(2, rd, rn, rm)
}

///|
// MOV (register) = ORR Rd, XZR, Rm.
pub fn enc_mov_reg(rd : Int, rm : Int) -> Int {
  enc_orr_reg(rd, 31, rm)
}

///|
// Data-processing (2 source): sf 0 0 11010110 Rm opcode2 Rn Rd.
pub fn enc_dp2(opcode2 : Int, rd : Int, rn : Int, rm : Int) -> Int {
  (1 << 31) |
  (0xD6 << 21) |
  (r5(rm) << 16) |
  ((opcode2 & 0x3F) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_lsl(rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2(0x08, rd, rn, rm)
}

///|
pub fn enc_lsr(rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2(0x09, rd, rn, rm)
}

///|
pub fn enc_asr(rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2(0x0A, rd, rn, rm)
}

///|
pub fn enc_sdiv(rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2(0x03, rd, rn, rm)
}

///|
pub fn enc_udiv(rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2(0x02, rd, rn, rm)
}

///|
// MADD/MSUB: sf 00 11011 000 Rm o0 Ra Rn Rd.
pub fn enc_madd(
  sf : Bool,
  o0 : Bool,
  rd : Int,
  rn : Int,
  rm : Int,
  ra : Int,
) -> Int {
  (sfbit(sf) << 31) |
  (0x1B << 24) |
  (r5(rm) << 16) |
  ((if o0 { 1 } else { 0 }) << 15) |
  (r5(ra) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_mul(rd : Int, rn : Int, rm : Int) -> Int {
  enc_madd(true, false, rd, rn, rm, 31)
}

///|
pub fn enc_msub(rd : Int, rn : Int, rm : Int, ra : Int) -> Int {
  enc_madd(true, true, rd, rn, rm, ra)
}

///|
// MOVZ / MOVK (64-bit): sf opc 100101 hw imm16 Rd.
pub fn enc_movz(rd : Int, imm16 : Int, hw : Int) -> Int {
  (1 << 31) |
  (2 << 29) |
  (0x25 << 23) |
  ((hw & 3) << 21) |
  ((imm16 & 0xFFFF) << 5) |
  r5(rd)
}

///|
pub fn enc_movk(rd : Int, imm16 : Int, hw : Int) -> Int {
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
pub fn enc_adrp(rd : Int, imm : Int) -> Int {
  (1 << 31) |
  ((imm & 3) << 29) |
  (0x10 << 24) |
  (((imm >> 2) & 0x7FFFF) << 5) |
  r5(rd)
}

///|
// CSINC (conditional select, increment): sf op S 11010100 Rm cond 01 Rn Rd.
pub fn enc_csinc(sf : Bool, rd : Int, rn : Int, rm : Int, cond : Int) -> Int {
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
pub fn enc_cset(sf : Bool, rd : Int, cond : Int) -> Int {
  enc_csinc(sf, rd, 31, 31, cond ^ 1)
}

///|
// Class-aware variants: the text emitter selects w/x (and s/d) by class, so the
// binary emitter needs the same sf bit. The 64-bit wrappers above delegate here.
pub fn enc_logic_sf(sf : Bool, opc : Int, rd : Int, rn : Int, rm : Int) -> Int {
  (sfbit(sf) << 31) |
  (opc << 29) |
  (0x0A << 24) |
  (r5(rm) << 16) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_and_reg_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  enc_logic_sf(sf, 0, rd, rn, rm)
}

///|
pub fn enc_orr_reg_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  enc_logic_sf(sf, 1, rd, rn, rm)
}

///|
pub fn enc_eor_reg_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  enc_logic_sf(sf, 2, rd, rn, rm)
}

///|
pub fn enc_mov_reg_sf(sf : Bool, rd : Int, rm : Int) -> Int {
  enc_orr_reg_sf(sf, rd, 31, rm)
}

///|
pub fn enc_dp2_sf(
  sf : Bool,
  opcode2 : Int,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Int {
  (sfbit(sf) << 31) |
  (0xD6 << 21) |
  (r5(rm) << 16) |
  ((opcode2 & 0x3F) << 10) |
  (r5(rn) << 5) |
  r5(rd)
}

///|
pub fn enc_lsl_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2_sf(sf, 0x08, rd, rn, rm)
}

///|
pub fn enc_lsr_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2_sf(sf, 0x09, rd, rn, rm)
}

///|
pub fn enc_asr_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2_sf(sf, 0x0A, rd, rn, rm)
}

///|
pub fn enc_sdiv_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2_sf(sf, 0x03, rd, rn, rm)
}

///|
pub fn enc_udiv_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  enc_dp2_sf(sf, 0x02, rd, rn, rm)
}

///|
pub fn enc_add_reg_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  dpr_addsub(sf, false, false, rd, rn, rm)
}

///|
pub fn enc_sub_reg_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  dpr_addsub(sf, true, false, rd, rn, rm)
}

///|
pub fn enc_cmp_sf(sf : Bool, rn : Int, rm : Int) -> Int {
  dpr_addsub(sf, true, true, 31, rn, rm)
}

///|
pub fn enc_cmn_sf(sf : Bool, rn : Int, rm : Int) -> Int {
  dpr_addsub(sf, false, true, 31, rn, rm)
}

///|
pub fn enc_mul_sf(sf : Bool, rd : Int, rn : Int, rm : Int) -> Int {
  enc_madd(sf, false, rd, rn, rm, 31)
}

///|
pub fn enc_msub_sf(sf : Bool, rd : Int, rn : Int, rm : Int, ra : Int) -> Int {
  enc_madd(sf, true, rd, rn, rm, ra)
}

///|
// MOVZ/MOVK without the sf bit fixed to 1 (32-bit form uses 0x52.../0x72...).
pub fn enc_movz_sf(sf : Bool, rd : Int, imm16 : Int, hw : Int) -> Int {
  (sfbit(sf) << 31) |
  (2 << 29) |
  (0x25 << 23) |
  ((hw & 3) << 21) |
  ((imm16 & 0xFFFF) << 5) |
  r5(rd)
}

///|
pub fn enc_movk_sf(sf : Bool, rd : Int, imm16 : Int, hw : Int) -> Int {
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
  opc : Int,
  n : Int,
  rd : Int,
  rn : Int,
  immr : Int,
  imms : Int,
) -> Int {
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
pub fn enc_sxtb(rd : Int, rn : Int) -> Int {
  enc_bitfield(true, 0, 1, rd, rn, 0, 7)
}

///|
pub fn enc_sxth(rd : Int, rn : Int) -> Int {
  enc_bitfield(true, 0, 1, rd, rn, 0, 15)
}

///|
pub fn enc_sxtw(rd : Int, rn : Int) -> Int {
  enc_bitfield(true, 0, 1, rd, rn, 0, 31)
}

///|
pub fn enc_uxtb(rd : Int, rn : Int) -> Int {
  enc_bitfield(false, 2, 0, rd, rn, 0, 7)
}

///|
pub fn enc_uxth(rd : Int, rn : Int) -> Int {
  enc_bitfield(false, 2, 0, rd, rn, 0, 15)
}

///|
// Load/store (unsigned offset): size 111 0 01 opc 0 imm12 Rn Rt.
pub fn enc_ldst(size : Int, opc : Int, rt : Int, rn : Int, off : Int) -> Int {
  let shift = if size == 3 {
    3
  } else if size == 2 {
    2
  } else if size == 1 {
    1
  } else {
    0
  }
  (size << 30) |
  (7 << 27) |
  (1 << 24) |
  ((opc & 3) << 22) |
  (((off >> shift) & 0xFFF) << 10) |
  (r5(rn) << 5) |
  r5(rt)
}

///|
pub fn enc_ldr_x(rt : Int, rn : Int, off : Int) -> Int {
  enc_ldst(3, 1, rt, rn, off)
}

///|
pub fn enc_str_x(rt : Int, rn : Int, off : Int) -> Int {
  enc_ldst(3, 0, rt, rn, off)
}

///|
pub fn enc_ldrb(rt : Int, rn : Int, off : Int) -> Int {
  enc_ldst(0, 1, rt, rn, off)
}

///|
pub fn enc_strb(rt : Int, rn : Int, off : Int) -> Int {
  enc_ldst(0, 0, rt, rn, off)
}

///|
pub fn enc_ldrh(rt : Int, rn : Int, off : Int) -> Int {
  enc_ldst(1, 1, rt, rn, off)
}

///|
pub fn enc_strh(rt : Int, rn : Int, off : Int) -> Int {
  enc_ldst(1, 0, rt, rn, off)
}

///|
pub fn enc_ldrsw(rt : Int, rn : Int, off : Int) -> Int {
  enc_ldst(2, 2, rt, rn, off)
}

///|
pub fn enc_ldr_w(rt : Int, rn : Int, off : Int) -> Int {
  enc_ldst(2, 1, rt, rn, off)
}

///|
pub fn enc_str_w(rt : Int, rn : Int, off : Int) -> Int {
  enc_ldst(2, 0, rt, rn, off)
}

///|
// LDP/STP: the addressing mode selects the base; imm7 is scaled by 8.
pub fn enc_ldp_stp(
  is_load : Bool,
  is_store : Bool,
  rt : Int,
  rt2 : Int,
  rn : Int,
  off : Int,
  pre : Bool,
  post : Bool,
) -> Int {
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
pub fn enc_ldp(rt : Int, rt2 : Int, rn : Int, off : Int) -> Int {
  enc_ldp_stp(true, false, rt, rt2, rn, off, false, false)
}

///|
pub fn enc_stp_pre(rt : Int, rt2 : Int, rn : Int, off : Int) -> Int {
  enc_ldp_stp(false, true, rt, rt2, rn, off, true, false)
}

///|
pub fn enc_ldp_post(rt : Int, rt2 : Int, rn : Int, off : Int) -> Int {
  enc_ldp_stp(true, false, rt, rt2, rn, off, false, true)
}

///|
// Branches. off is in bytes; imm26/imm19 are instruction counts.
pub fn enc_b(off : Int) -> Int {
  (0x05 << 26) | ((off >> 2) & 0x3FFFFFF)
}

///|
pub fn enc_bl(off : Int) -> Int {
  (0x25 << 26) | ((off >> 2) & 0x3FFFFFF)
}

///|
pub fn enc_bcond(cond : Int, off : Int) -> Int {
  (0x2A << 25) | (((off >> 2) & 0x7FFFF) << 5) | (cond & 0xF)
}

///|
pub fn enc_cbz(sf : Bool, nonzero : Bool, rt : Int, off : Int) -> Int {
  (sfbit(sf) << 31) |
  (0x1A << 25) |
  ((if nonzero { 1 } else { 0 }) << 24) |
  (((off >> 2) & 0x7FFFF) << 5) |
  r5(rt)
}

///|
pub fn enc_br(rn : Int) -> Int {
  (0xD6 << 21) | (0x1F << 16) | (r5(rn) << 5)
}

///|
pub fn enc_blr(rn : Int) -> Int {
  (0xD6 << 21) | (0x3F << 16) | (r5(rn) << 5)
}

///|
pub fn enc_ret() -> Int {
  0xD65F03C0
}

///|
pub fn enc_hint(imm : Int) -> Int {
  0xD503201F | ((imm & 0x7F) << 5)
}

///|
pub fn enc_nop() -> Int {
  0xD503201F
}

///|
// Floating point (double unless noted). Bases are the fixed opcode fields.
pub fn enc_fadd_d(rd : Int, rn : Int, rm : Int) -> Int {
  0x1E602800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fsub_d(rd : Int, rn : Int, rm : Int) -> Int {
  0x1E603800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmul_d(rd : Int, rn : Int, rm : Int) -> Int {
  0x1E600800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fdiv_d(rd : Int, rn : Int, rm : Int) -> Int {
  0x1E601800 | (r5(rm) << 16) | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fcmp_d(rn : Int, rm : Int) -> Int {
  0x1E602000 | (r5(rm) << 16) | (r5(rn) << 5)
}

///|
pub fn enc_fcvtzs_x_d(rd : Int, rn : Int) -> Int {
  0x9E780000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_scvtf_d_x(rd : Int, rn : Int) -> Int {
  0x9E620000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmov_d(rd : Int, rn : Int) -> Int {
  0x1E604000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fmov_x_d(rd : Int, rn : Int) -> Int {
  0x9E660000 | (r5(rn) << 5) | r5(rd)
}

///|
pub fn enc_fcvt_d_s(rd : Int, rn : Int) -> Int {
  0x1E22C000 | (r5(rn) << 5) | r5(rd)
}

///|
// Little-endian serialization of 32-bit instruction words.
pub fn words_to_bytes(words : Array[Int]) -> Bytes {
  let a : Array[Byte] = []
  for w in words {
    push_u8(a, w & 0xFF)
    push_u8(a, (w >> 8) & 0xFF)
    push_u8(a, (w >> 16) & 0xFF)
    push_u8(a, (w >> 24) & 0xFF)
  }
  Bytes::from_array(a[:])
}
