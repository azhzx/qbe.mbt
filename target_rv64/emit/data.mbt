///|
// RISC-V 64 (rv64) data section and floating-point constant pool emission,
// mirroring vendor/qbe emit.c (emitdat / emitfin).

///|
// Pending zero run and linkage information for the data block being emitted
// (C emitdat's static `zero` plus the current Dat's name/align/export).
let rv64_dat_zero : Array[Int64] = [0L]

///|
let rv64_dat_align : Array[Int64] = [0L]

///|
let rv64_dat_name : Array[String] = [""]

///|
let rv64_dat_export : Array[Bool] = [false]

///|
// Signed 64-bit operand suffix: "+N" or "-N" (C's "%+"PRId64).
fn rv64_s64_plus(v : Int64) -> String {
  if v >= 0L {
    "+\{v}"
  } else {
    "\{v}"
  }
}

///|
// Data directive for a kind (C di[] table).
fn rv64_dtoa(kind : @types.DatKind) -> String {
  match kind {
    @types.DB => "\t.byte"
    @types.DH => "\t.short"
    @types.DW => "\t.int"
    @types.DL => "\t.quad"
    _ => ""
  }
}

///|
// Mask a data operand to its declared width (C di[].mask).
fn rv64_dmask(kind : @types.DatKind) -> Int64 {
  match kind {
    @types.DB => 0xffL
    @types.DH => 0xffffL
    @types.DW => 0xffffffffL
    _ => -1L
  }
}

///|
// Emit a section + linkage header (C emitlnk): .data/.bss, .balign, .globl,
// name:.
fn rv64_emitlnk(sec : String, gassym : String, sb : StringBuilder) -> Unit {
  sb.write_string(".\{sec}\n")
  if rv64_dat_align[0] != 0L {
    sb.write_string(".balign \{rv64_dat_align[0]}\n")
  }
  if rv64_dat_export[0] {
    sb.write_string(".globl \{gassym}\{rv64_dat_name[0]}\n")
  }
  sb.write_string("\{gassym}\{rv64_dat_name[0]}:\n")
}

///|
// Emit a data definition (C emitdat). The port's item stream is
// DStart, [DAlign], DName, values..., DEnd.
pub fn gasemitdat_rv64(
  d : @types.Dat,
  _gasloc : String,
  gassym : String,
  sb : StringBuilder,
) -> Unit {
  match d.kind {
    @types.DStart => {
      rv64_dat_zero[0] = 0L
      // C parse.c parsedat: default data alignment is 8.
      rv64_dat_align[0] = 8L
      rv64_dat_name[0] = ""
      rv64_dat_export[0] = d.is_export
    }
    @types.DAlign => rv64_dat_align[0] = d.num
    @types.DName => {
      rv64_dat_name[0] = d.str
      rv64_dat_export[0] = d.is_export
    }
    @types.DEnd =>
      if rv64_dat_zero[0] != -1L {
        rv64_emitlnk("bss", gassym, sb)
        sb.write_string("\t.fill \{rv64_dat_zero[0]},1,0\n")
      }
    @types.DZ =>
      if rv64_dat_zero[0] != -1L {
        rv64_dat_zero[0] = rv64_dat_zero[0] + d.num
      } else {
        sb.write_string("\t.fill \{d.num},1,0\n")
      }
    _ => {
      if rv64_dat_zero[0] != -1L {
        rv64_emitlnk("data", gassym, sb)
        if rv64_dat_zero[0] > 0L {
          sb.write_string("\t.fill \{rv64_dat_zero[0]},1,0\n")
        }
        rv64_dat_zero[0] = -1L
      }
      if d.is_str {
        sb.write_string("\t.ascii \"\{d.str}\"\n")
      } else if d.is_ref {
        sb.write_string(
          "\{rv64_dtoa(d.kind)} \{gassym}\{d.ref_name}\{rv64_s64_plus(d.ref_offset)}\n",
        )
      } else {
        sb.write_string("\{rv64_dtoa(d.kind)} \{d.num & rv64_dmask(d.kind)}\n")
      }
    }
  }
}

///|
// Extract the 32-bit word at 4-byte offset p from the 16-byte little-endian
// value (b0, b1), as a signed integer (C's union {int32_t,float}).
fn rv64_word_i32(b0 : Int64, b1 : Int64, p : Int) -> Int {
  let u = if p == 0 {
    b0 & 0xFFFFFFFF
  } else if p == 4 {
    (b0 >> 32) & 0xFFFFFFFF
  } else if p == 8 {
    b1 & 0xFFFFFFFF
  } else {
    (b1 >> 32) & 0xFFFFFFFF
  }
  if u >= 0x80000000L {
    (u - 0x100000000L).to_int()
  } else {
    u.to_int()
  }
}

///|
// Emit the floating-point constant stash and the ELF note section
// (C gasemitfin / elf_emitfin).
pub fn gasemitfin_rv64(gasloc : String, sb : StringBuilder) -> Unit {
  if @types.fp_stash_len() > 0 {
    sb.write_string("/* floating point constants */\n")
    let sizes : Array[Int] = [16, 8, 4]
    for sz in sizes {
      for i in 0..<@types.fp_stash_len() {
        let b = @types.fp_stash_at(i)
        if b.size == sz {
          let lg = if sz == 16 { 4 } else if sz == 8 { 3 } else { 2 }
          sb.write_string(".section .rodata\n.p2align \{lg}\n\{gasloc}fp\{i}:")
          if sz == 16 {
            sb.write_string("\n\t.quad \{b.b0}\n\t.quad 0\n\n")
          } else if sz == 8 {
            let d = b.b0.reinterpret_as_double()
            sb.write_string(
              "\n\t.quad \{b.b0} /* \{@util.fmt_fixed(d, 6)} */\n\n",
            )
          } else {
            let u = (b.b0 & 0xFFFFFFFF).to_int().reinterpret_as_uint()
            let f = Float::reinterpret_from_uint(u).to_double()
            sb.write_string(
              "\n\t.int \{rv64_word_i32(b.b0, b.b1, 0)} /* \{@util.fmt_fixed(f, 6)} */\n\n",
            )
          }
        }
      }
    }
  }
  sb.write_string(".section .note.GNU-stack,\"\",@progbits\n")
}
