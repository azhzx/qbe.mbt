///|
// Mach-O writer + encoder round-trip.

///|
fn add1_object() -> Bytes {
  let text = words_to_bytes([enc_add_imm(0, 0, 1), enc_ret()])
  let sections : Array[MachoSection] = [
    MachoSection::{
      name: "__text",
      seg: "__TEXT",
      data: text,
      align: 2,
      flags: section_flags_text(),
      relocs: [],
    },
  ]
  let syms : Array[MachoSym] = [
    MachoSym::{ name: "_add1", sect: 1, value: 0, is_ext: true, },
  ]
  write_object(sections, syms)
}

///|
test "object: encoder matches the reference encoding" {
  let text = words_to_bytes([enc_add_imm(0, 0, 1), enc_ret()])
  // add x0, x0, #1 ; ret  (little-endian)
  assert_eq(text.length(), 8)
  assert_eq(text[0].to_int(), 0x00)
  assert_eq(text[1].to_int(), 0x04)
  assert_eq(text[2].to_int(), 0x00)
  assert_eq(text[3].to_int(), 0x91)
  assert_eq(text[4].to_int(), 0xC0)
  assert_eq(text[5].to_int(), 0x03)
  assert_eq(text[6].to_int(), 0x5F)
  assert_eq(text[7].to_int(), 0xD6)
}

///|
test "object: writes a Mach-O header, section and symbol" {
  let obj = add1_object()
  // MH_MAGIC_64 = 0xfeedfacf, little-endian
  assert_eq(obj[0].to_int(), 0xCF)
  assert_eq(obj[1].to_int(), 0xFA)
  assert_eq(obj[2].to_int(), 0xED)
  assert_eq(obj[3].to_int(), 0xFE)
  // cputype ARM64 = 0x0100000c
  assert_eq(obj[4].to_int(), 0x0C)
  assert_eq(obj[5].to_int(), 0x00)
  assert_eq(obj[6].to_int(), 0x00)
  assert_eq(obj[7].to_int(), 0x01)
  // filetype MH_OBJECT = 1
  assert_eq(obj[12].to_int(), 1)
}
