///|
// Every encoder form is checked against clang's own encoding of the same
// instruction. Reference words were produced by `clang -c` + `otool`.

///|
fn check_word(actual : Int, expected : Int64) -> Unit raise {
  assert_eq(actual.to_int64() & 0xFFFFFFFFL, expected)
}

///|
test "arm64 enc: integer data processing" {
  check_word(enc_add_reg(0, 1, 2), 0x8B020020L)
  check_word(enc_add_imm(0, 1, 100), 0x91019020L)
  check_word(enc_sub_reg(0, 1, 2), 0xCB020020L)
  check_word(enc_sub_imm(0, 1, 100), 0xD1019020L)
  check_word(enc_and_reg(0, 1, 2), 0x8A020020L)
  check_word(enc_orr_reg(0, 1, 2), 0xAA020020L)
  check_word(enc_eor_reg(0, 1, 2), 0xCA020020L)
  check_word(enc_asr(0, 1, 2), 0x9AC22820L)
  check_word(enc_lsr(0, 1, 2), 0x9AC22420L)
  check_word(enc_lsl(0, 1, 2), 0x9AC22020L)
  check_word(enc_mul(0, 1, 2), 0x9B027C20L)
  check_word(enc_sdiv(0, 1, 2), 0x9AC20C20L)
  check_word(enc_udiv(0, 1, 2), 0x9AC20820L)
  check_word(enc_msub(0, 1, 2, 3), 0x9B028C20L)
  check_word(enc_mov_reg(0, 1), 0xAA0103E0L)
  check_word(enc_movz(0, 42, 0), 0xD2800540L)
  check_word(enc_movk(0, 1, 1), 0xF2A00020L)
  check_word(enc_cmp(0, 1), 0xEB01001FL)
  check_word(enc_cmn(0, 1), 0xAB01001FL)
  check_word(enc_sxtb(0, 1), 0x93401C20L)
  check_word(enc_sxth(0, 1), 0x93403C20L)
  check_word(enc_sxtw(0, 1), 0x93407C20L)
  check_word(enc_uxtb(0, 1), 0x53001C20L)
  check_word(enc_uxth(0, 1), 0x53003C20L)
  check_word(enc_add_imm(31, 31, 16), 0x910043FFL)
  check_word(enc_sub_imm(31, 31, 16), 0xD10043FFL)
}

///|
test "arm64 enc: loads and stores" {
  check_word(enc_ldr_x(0, 1, 0), 0xF9400020L)
  check_word(enc_ldr_x(0, 1, 8), 0xF9400420L)
  check_word(enc_str_x(0, 1, 8), 0xF9000420L)
  check_word(enc_ldrb(0, 1, 0), 0x39400020L)
  check_word(enc_strb(0, 1, 0), 0x39000020L)
  check_word(enc_ldrsw(0, 1, 0), 0xB9800020L)
  check_word(enc_ldp(0, 1, 2, 0), 0xA9400440L)
  check_word(enc_stp_pre(0, 1, 2, -16), 0xA9BF0440L)
  check_word(enc_ldp_post(0, 1, 2, 16), 0xA8C10440L)
}

///|
test "arm64 enc: branches and misc" {
  check_word(enc_ret(), 0xD65F03C0L)
  check_word(enc_hint(34), 0xD503245FL)
  check_word(enc_nop(), 0xD503201FL)
}

///|
test "arm64 enc: floating point" {
  check_word(enc_fadd_d(0, 1, 2), 0x1E622820L)
  check_word(enc_fsub_d(0, 1, 2), 0x1E623820L)
  check_word(enc_fmul_d(0, 1, 2), 0x1E620820L)
  check_word(enc_fdiv_d(0, 1, 2), 0x1E621820L)
  check_word(enc_fcmp_d(0, 1), 0x1E612000L)
  check_word(enc_fcvtzs_x_d(0, 0), 0x9E780000L)
  check_word(enc_scvtf_d_x(0, 0), 0x9E620000L)
  check_word(enc_fmov_d(0, 1), 0x1E604020L)
  check_word(enc_fmov_x_d(0, 0), 0x9E660000L)
  check_word(enc_fcvt_d_s(0, 1), 0x1E22C020L)
}
