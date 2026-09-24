///|
// A tiny aarch64 instruction encoder: only the forms the object writer tests
// and the first self-contained codegen slice need. Words are 32-bit values.

///|
// ADD (immediate): sf=1, op=0, S=0, 100010, sh=0.
pub fn enc_add_imm(rd : Int, rn : Int, imm12 : Int) -> Int {
  (1 << 31) |
  (0x22 << 23) |
  ((imm12 & 0xFFF) << 10) |
  ((rn & 31) << 5) |
  (rd & 31)
}

///|
// MOVZ (64-bit): sf=1, opc=10, 100101.
pub fn enc_movz(rd : Int, imm16 : Int, hw : Int) -> Int {
  (1 << 31) |
  (2 << 29) |
  (0x25 << 23) |
  ((hw & 3) << 21) |
  ((imm16 & 0xFFFF) << 5) |
  (rd & 31)
}

///|
// MOVK (64-bit): sf=1, opc=11, 100101.
pub fn enc_movk(rd : Int, imm16 : Int, hw : Int) -> Int {
  (1 << 31) |
  (3 << 29) |
  (0x25 << 23) |
  ((hw & 3) << 21) |
  ((imm16 & 0xFFFF) << 5) |
  (rd & 31)
}

///|
// RET.
pub fn enc_ret() -> Int {
  0xD65F03C0
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
