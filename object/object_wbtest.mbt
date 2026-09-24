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

///|
fn read_u32(b : Bytes, off : Int) -> Int {
  b[off].to_int() |
  (b[off + 1].to_int() << 8) |
  (b[off + 2].to_int() << 16) |
  (b[off + 3].to_int() << 24)
}

///|
fn read_u64(b : Bytes, off : Int) -> Int64 {
  let mut v = 0L
  for i in 0..<8 {
    v = v | (b[off + i].to_int().to_int64() << (8 * i))
  }
  v
}

///|
// Section addrs are in-segment offsets and symbol n_values are segment
// addresses; some linkers (GNU ld via gcc) reject all-zero addrs.
test "object: section addresses and symbol values are segment-relative" {
  let text = words_to_bytes([enc_add_imm(0, 0, 1), enc_ret()]) // 8 bytes
  let data = Bytes::from_array([(7).to_byte(), (0).to_byte()]) // 2 bytes
  let sections : Array[MachoSection] = [
    MachoSection::{
      name: "__text",
      seg: "__TEXT",
      data: text,
      align: 2,
      flags: section_flags_text(),
      relocs: [],
    },
    MachoSection::{
      name: "__data",
      seg: "__DATA",
      data,
      align: 3,
      flags: section_flags_data(),
      relocs: [],
    },
  ]
  let syms : Array[MachoSym] = [
    MachoSym::{ name: "_t", sect: 1, value: 0, is_ext: true, },
    MachoSym::{ name: "_d", sect: 2, value: 0, is_ext: false, },
  ]
  let obj = write_object(sections, syms)
  // LC_SEGMENT_64 at 32, sections 72 bytes in, 80 bytes each, addr at +32.
  assert_eq(read_u64(obj, 32 + 72 + 32), 0L) // __text addr
  assert_eq(read_u64(obj, 32 + 72 + 80 + 32), 8L) // __data addr (aligned up)
  // Segment vmsize at command offset +32: 8 content bytes + 2, aligned to 8.
  assert_eq(read_u64(obj, 32 + 32), 10L)
  // LC_SYMTAB follows the segment (72+160) and build-version (24) commands.
  let sym_off = read_u32(obj, 32 + 232 + 24 + 8)
  // nlist_64[1].n_value: _d is at __data addr + 0.
  assert_eq(read_u64(obj, sym_off + 16 + 8), 8L)
}
