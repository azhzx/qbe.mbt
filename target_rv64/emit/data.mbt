///|
// RISC-V 64 (rv64) floating-point constant pool emission, mirroring the
// reference emit.c emitfin (the floating point constants come from the shared
// Asmbits stash) and elf_emitfin. Data definitions are emitted by the shared
// `gasdata` package, like every other GAS target; this file used to carry a
// second, unused copy of that algorithm (`gasemitdat_rv64`), which was removed.

// Extract the 32-bit word at 4-byte offset p from the 16-byte little-endian
// value (b0, b1), as a signed integer (C's union {int32_t,float}).
fn rv64_word_i32(b0 : Int64, b1 : Int64, p : Int32) -> Int32 {
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
    let sizes : Array[Int32] = [16, 8, 4]
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
