///|
// ADD (shifted register): sf op S 01011 shift N Rm imm6 Rn Rd, with
// sf = 1, op = 0, S = 0, shift = 0, N = 0, imm6 = 0.
pub fn enc_add_reg_ref(
  rd : Int,
  rn : Int,
  rm : Int,
) -> Int where {
  proof_require: 0 <= rd && 0 <= rn && 0 <= rm,
  proof_ensure: result => {
    word(result) ==
    word(1)
    .shl(31)
    .bor(word(11).shl(24))
    .bor(word(rm).band(word(31)).shl(16))
    .bor(word(rn).band(word(31)).shl(5))
    .bor(word(rd).band(word(31)))
  },
} {
  bor(
    bor(bor(shl(1, 31), shl(11, 24)), shl(band(rm, 31), 16)),
    bor(shl(band(rn, 31), 5), band(rd, 31)),
  )
}

///|
// MOVZ (wide immediate): sf opc 100101 hw imm16 Rd, with sf = 1, opc = 10.
pub fn enc_movz_ref(
  rd : Int,
  imm16 : Int,
  hw : Int,
) -> Int where {
  proof_require: 0 <= rd && 0 <= imm16 && 0 <= hw,
  proof_ensure: result => {
    word(result) ==
    word(1)
    .shl(31)
    .bor(word(2).shl(29))
    .bor(word(0x25).shl(23))
    .bor(word(hw).band(word(3)).shl(21))
    .bor(word(imm16).band(word(0xFFFF)).shl(5))
    .bor(word(rd).band(word(31)))
  },
} {
  bor(
    bor(
      bor(bor(bor(shl(1, 31), shl(2, 29)), shl(0x25, 23)), shl(band(hw, 3), 21)),
      shl(band(imm16, 0xFFFF), 5),
    ),
    band(rd, 31),
  )
}
