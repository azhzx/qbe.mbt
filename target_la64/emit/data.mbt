///|
// LoongArch 64 (la64) data section and floating point constant pool emission.
// Directives use the portable ELF spellings (.byte/.half/.word/.quad and
// .balign, since LoongArch gas treats .align as a power-of-two).

///|
// Whether the last DStart needs a default alignment (C gasdat_align).
let la64_gasdat_align : Array[Bool] = [false]

///|
fn la64_s64_plus(v : Int64) -> String {
  if v >= 0L {
    "+\{v}"
  } else {
    "\{v}"
  }
}

///|
// Emit a data definition (C gasemitdat).
pub fn gasemitdat_la64(
  d : @types.Dat,
  _gasloc : String,
  gassym : String,
  sb : StringBuilder,
) -> Unit {
  match d.kind {
    @types.DStart => {
      la64_gasdat_align[0] = false
      sb.write_string(".data\n")
    }
    @types.DEnd => ()
    @types.DName => {
      if !la64_gasdat_align[0] {
        sb.write_string(".balign 8\n")
      }
      if d.is_export {
        sb.write_string(".globl \{gassym}\{d.str}\n")
      }
      sb.write_string("\{gassym}\{d.str}:\n")
    }
    @types.DZ => sb.write_string("\t.fill \{d.num},1,0\n")
    _ => {
      if d.kind == @types.DAlign {
        la64_gasdat_align[0] = true
      }
      let dtoa = match d.kind {
        @types.DAlign => ".balign"
        @types.DB => "\t.byte"
        @types.DH => "\t.half"
        @types.DW => "\t.word"
        @types.DL => "\t.quad"
        _ => ""
      }
      if d.is_str {
        sb.write_string("\t.ascii \"\{d.str}\"\n")
      } else if d.is_ref {
        sb.write_string(
          "\{dtoa} \{gassym}\{d.ref_name}\{la64_s64_plus(d.ref_offset)}\n",
        )
      } else {
        sb.write_string("\{dtoa} \{d.num}\n")
      }
    }
  }
}

///|
// Extract the 32-bit word at 4-byte offset p from the 16-byte little-endian
// value (b0, b1), as a signed integer.
fn la64_word_i32(b0 : Int64, b1 : Int64, p : Int) -> Int {
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
// Emit the floating point constant stash (C gasemitfin).
pub fn gasemitfin_la64(gasloc : String, sb : StringBuilder) -> Unit {
  if @types.fp_stash_len() == 0 {
    return
  }
  sb.write_string("/* floating point constants */\n.data\n")
  let sizes = [16, 8, 4]
  for sz in sizes {
    for i in 0..<@types.fp_stash_len() {
      let b = @types.fp_stash_at(i)
      if b.size == sz {
        sb.write_string(".balign \{sz}\n\{gasloc}fp\{i}:")
        let mut p = 0
        while p < sz {
          sb.write_string("\n\t.word \{la64_word_i32(b.b0, b.b1, p)}")
          p = p + 4
        }
        if sz <= 8 {
          let d = if sz == 4 {
            let u = (b.b0 & 0xFFFFFFFF).to_int().reinterpret_as_uint()
            Float::reinterpret_from_uint(u).to_double()
          } else {
            b.b0.reinterpret_as_double()
          }
          sb.write_string(" /* \{@util.fmt_fixed(d, 6)} */\n")
        } else {
          sb.write_string("\n")
        }
      }
    }
  }
}
