///|
// Minimal Mach-O 64-bit object writer (arm64, MH_OBJECT).
//
// Only what qbe.mbt needs: a handful of sections, defined/undefined symbols and
// external relocations. Everything is little-endian.

///|
// Mach-O constants (see <mach-o/loader.h>, <mach-o/nlist.h>, <mach-o/reloc.h>).
const MH_MAGIC_64 = 0xFEEDFACF

///|
const CPU_TYPE_ARM64 = 0x0100000C

///|
const CPU_SUBTYPE_ARM64_ALL = 0

///|
const MH_OBJECT = 1

///|
const LC_SEGMENT_64 = 0x19

///|
const LC_SYMTAB = 0x2

///|
const LC_BUILD_VERSION = 0x32

///|
const PLATFORM_MACOS = 1

///|
const S_REGULAR = 0x0

///|
const S_CSTRING_LITERALS = 0x2

///|
const S_4BYTE_LITERALS = 0x3

///|
const S_8BYTE_LITERALS = 0x4

///|
const S_ATTR_PURE_INSTRUCTIONS = 0x80000000

///|
const S_ATTR_SOME_INSTRUCTIONS = 0x00000400

///|
const N_UNDF = 0x0

///|
const N_SECT = 0x0E

///|
const N_EXT = 0x01

///|
pub fn section_flags_text() -> Int {
  S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS | S_REGULAR
}

///|
pub fn section_flags_data() -> Int {
  S_REGULAR
}

///|
pub fn section_flags_cstring() -> Int {
  S_CSTRING_LITERALS
}

///|
pub fn section_flags_literal4() -> Int {
  S_4BYTE_LITERALS
}

///|
pub fn section_flags_literal8() -> Int {
  S_8BYTE_LITERALS
}

///|
// ARM64 relocation types (mach-o/arm64/reloc.h).
pub const ARM64_RELOC_UNSIGNED = 0

///|
pub const ARM64_RELOC_SUBTRACTOR = 1

///|
pub const ARM64_RELOC_BRANCH26 = 2

///|
pub const ARM64_RELOC_PAGE21 = 3

///|
pub const ARM64_RELOC_PAGEOFF12 = 4

///|
pub const ARM64_RELOC_GOT_LOAD_PAGE21 = 5

///|
pub const ARM64_RELOC_GOT_LOAD_PAGEOFF12 = 6

///|
pub const ARM64_RELOC_POINTER_TO_GOT = 7

///|
pub(all) struct MachoReloc {
  offset : Int // r_address: byte offset in the section
  sym : Int // symbol table index
  pcrel : Bool
  length : Int // 2 => 4 bytes
  rtype : Int
}

///|
pub(all) struct MachoSection {
  name : String // e.g. "__text"
  seg : String // e.g. "__TEXT"
  data : Bytes
  align : Int // log2 of the required alignment
  flags : Int
  relocs : Array[MachoReloc]
}

///|
pub(all) struct MachoSym {
  name : String // Mach-O name, including the leading underscore
  sect : Int // 1-based section index, 0 when undefined
  value : Int // offset within the section
  is_ext : Bool
}

///|
fn push_u8(a : Array[Byte], v : Int) -> Unit {
  a.push((v & 0xFF).to_byte())
}

///|
fn push_u16(a : Array[Byte], v : Int) -> Unit {
  push_u8(a, v & 0xFF)
  push_u8(a, (v >> 8) & 0xFF)
}

///|
fn push_u32(a : Array[Byte], v : Int) -> Unit {
  push_u8(a, v & 0xFF)
  push_u8(a, (v >> 8) & 0xFF)
  push_u8(a, (v >> 16) & 0xFF)
  push_u8(a, (v >> 24) & 0xFF)
}

///|
fn push_u64(a : Array[Byte], v : Int64) -> Unit {
  for i in 0..<8 {
    push_u8(a, ((v >> (i * 8)) & 0xFFL).to_int())
  }
}

///|
fn push_pad(a : Array[Byte], n : Int) -> Unit {
  for _ in 0..<n {
    a.push((0).to_byte())
  }
}

///|
fn push_name16(a : Array[Byte], s : String) -> Unit {
  let b = @utf8.encode(s)
  for i in 0..<16 {
    if i < b.length() {
      a.push(b[i])
    } else {
      a.push((0).to_byte())
    }
  }
}

///|
fn push_bytes(a : Array[Byte], b : Bytes) -> Unit {
  for i in 0..<b.length() {
    a.push(b[i])
  }
}

///|
fn align_up(n : Int, al : Int) -> Int {
  (n + al - 1) & -al
}

///|
// Serialize a Mach-O object file (arm64, MH_OBJECT).
pub fn write_object(
  sections : Array[MachoSection],
  syms : Array[MachoSym],
) -> Bytes {
  let nsect = sections.length()
  let seg_cmd_size = 72 + 80 * nsect
  let build_size = 24
  let symtab_size = 24
  let cmds_size = seg_cmd_size + build_size + symtab_size
  let header_size = 32

  // Section file offsets and in-segment addresses. In MH_OBJECT each section
  // carries its offset from the start of the segment; linkers check these for
  // overlaps (GNU ld via gcc rejects all-zero addresses).
  let sec_off : Array[Int] = []
  let sec_addr : Array[Int] = []
  let mut cur = header_size + cmds_size
  let mut acur = 0
  for s in sections {
    cur = align_up(cur, 1 << s.align)
    acur = align_up(acur, 1 << s.align)
    sec_off.push(cur)
    sec_addr.push(acur)
    cur = cur + s.data.length()
    acur = acur + s.data.length()
  }
  let sec_end = cur
  // Relocation file offsets.
  let rel_off : Array[Int] = []
  let mut rcur = align_up(sec_end, 4)
  for s in sections {
    rel_off.push(rcur)
    rcur = rcur + 8 * s.relocs.length()
  }
  let sym_off = align_up(rcur, 8)
  let str_off = sym_off + 16 * syms.length()

  // String table: leading NUL, then each name NUL-terminated.
  let str_tab : Array[Byte] = [(0).to_byte()]
  let strx : Array[Int] = []
  for s in syms {
    strx.push(str_tab.length())
    push_bytes(str_tab, @utf8.encode(s.name))
    push_u8(str_tab, 0)
  }
  let str_size = str_tab.length()
  let total = str_off + str_size

  let out : Array[Byte] = []
  // ---- mach_header_64 ----
  push_u32(out, MH_MAGIC_64)
  push_u32(out, CPU_TYPE_ARM64)
  push_u32(out, CPU_SUBTYPE_ARM64_ALL)
  push_u32(out, MH_OBJECT)
  push_u32(out, 3) // ncmds: LC_SEGMENT_64 + LC_BUILD_VERSION + LC_SYMTAB
  push_u32(out, cmds_size)
  push_u32(out, 0) // flags
  push_u32(out, 0) // reserved

  // ---- LC_SEGMENT_64 ----
  push_u32(out, LC_SEGMENT_64)
  push_u32(out, seg_cmd_size)
  push_name16(out, "")
  push_u64(out, 0L) // vmaddr
  push_u64(out, acur.to_int64()) // vmsize (aligned section extent)
  push_u64(out, (if nsect > 0 { sec_off[0] } else { 0 }).to_int64()) // fileoff
  push_u64(out, acur.to_int64()) // filesize
  push_u32(out, 7) // maxprot
  push_u32(out, 7) // initprot
  push_u32(out, nsect)
  push_u32(out, 0) // flags
  for i in 0..<nsect {
    let s = sections[i]
    push_name16(out, s.name)
    push_name16(out, s.seg)
    push_u64(out, sec_addr[i].to_int64()) // addr
    push_u64(out, s.data.length().to_int64()) // size
    push_u32(out, sec_off[i]) // offset
    push_u32(out, s.align) // align (log2)
    push_u32(out, rel_off[i]) // reloff
    push_u32(out, s.relocs.length()) // nreloc
    push_u32(out, s.flags)
    push_u32(out, 0) // reserved1
    push_u32(out, 0) // reserved2
    push_u32(out, 0) // reserved3
  }

  // ---- LC_BUILD_VERSION ----
  push_u32(out, LC_BUILD_VERSION)
  push_u32(out, 24)
  push_u32(out, PLATFORM_MACOS)
  push_u32(out, 0x000B0000) // minos 11.0
  push_u32(out, 0x000B0000) // sdk
  push_u32(out, 0) // ntools

  // ---- LC_SYMTAB ----
  push_u32(out, LC_SYMTAB)
  push_u32(out, 24)
  push_u32(out, sym_off)
  push_u32(out, syms.length())
  push_u32(out, str_off)
  push_u32(out, str_size)

  // ---- section data ----
  for i in 0..<nsect {
    push_pad(out, sec_off[i] - out.length())
    push_bytes(out, sections[i].data)
  }

  // ---- relocations ----
  for i in 0..<nsect {
    push_pad(out, rel_off[i] - out.length())
    for r in sections[i].relocs {
      push_u32(out, r.offset)
      let info = (r.sym & 0xFFFFFF) |
        ((if r.pcrel { 1 } else { 0 }) << 24) |
        ((r.length & 3) << 25) |
        (1 << 27) |
        ((r.rtype & 0xF) << 28)
      push_u32(out, info)
    }
  }

  // ---- symbol table (nlist_64) ----
  push_pad(out, sym_off - out.length())
  for i in 0..<syms.length() {
    let s = syms[i]
    // For a section-based symbol n_value is its segment address (section
    // addr + section-relative offset); undefined symbols keep 0.
    let v = if s.sect > 0 && s.sect <= nsect {
      sec_addr[s.sect - 1] + s.value
    } else {
      s.value
    }
    push_u32(out, strx[i]) // n_strx
    let t = (if s.sect > 0 { N_SECT } else { N_UNDF }) |
      (if s.is_ext { N_EXT } else { 0 })
    push_u8(out, t)
    push_u8(out, s.sect) // n_sect
    push_u16(out, 0) // n_desc
    push_u64(out, v.to_int64()) // n_value
  }

  // ---- string table ----
  push_pad(out, str_off - out.length())
  push_bytes(out, Bytes::from_array(str_tab[:]))
  Bytes::from_array(out[:])
}
