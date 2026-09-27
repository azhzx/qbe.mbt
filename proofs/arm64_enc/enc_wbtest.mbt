///|
// Conformance: the proven reference encoders compute the same words as the
// runtime encoders in `object`. This ties the proof to the shipped code.
test "enc_add_reg_ref matches object" {
  for rd in 0..<32 {
    for rn in 0..<32 {
      for rm in 0..<32 {
        assert_eq(enc_add_reg_ref(rd, rn, rm), @object.enc_add_reg(rd, rn, rm))
      }
    }
  }
}

///|
test "enc_movz_ref matches object" {
  let imms = [0, 1, 2, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF]
  for rd in 0..<32 {
    for hw in 0..<4 {
      for imm in imms {
        assert_eq(enc_movz_ref(rd, imm, hw), @object.enc_movz(rd, imm, hw))
      }
    }
  }
}
