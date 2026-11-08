///|
// Constant type
#derive(Eq, Debug)
pub(all) enum ConType {
  CUndef
  CBits // Numeric constant
  CAddr // Symbol address
}

///|
// Constant value bits
#derive(Debug, Eq)
pub(all) struct ConBits {
  i : Int64 // Integer value
  d : Double // Double value
  s : Float // Single (float) value
}

///|
// Constant - corresponds to struct Con in QBE
#derive(Debug, Eq)
pub(all) struct Con {
  kind : ConType
  label : Int32 // Interned string label for CAddr
  bits : ConBits // Value bits
  flt : Int32 // 0=integer, 1=print as s, 2=print as d
  is_local : Bool // True if local symbol
  sym_type : Int32 // C Sym.type bits: 1 = thread (SThr), 2 = extern (SExt)
}

///|
pub const SYM_THR : Int32 = 1

///|
pub const SYM_EXT : Int32 = 2

///|
// C (sym.type & SExt)
pub fn Con::is_ext(self : Con) -> Bool {
  (self.sym_type & SYM_EXT) != 0
}

///|
// C (sym.type & SThr)
pub fn Con::is_thr(self : Con) -> Bool {
  (self.sym_type & SYM_THR) != 0
}

///|
pub fn Con::new() -> Con {
  Con::{
    kind: CUndef,
    label: 0,
    bits: ConBits::{ i: 0, d: 0.0, s: 0.0, },
    flt: 0,
    is_local: false,
    sym_type: 0,
  }
}

///|
pub fn Con::int(i : Int64) -> Con {
  Con::{
    kind: CBits,
    label: 0,
    bits: ConBits::{ i, d: 0.0, s: 0.0, },
    flt: 0,
    is_local: false,
    sym_type: 0,
  }
}

///|
pub fn Con::double(d : Double) -> Con {
  Con::{
    kind: CBits,
    label: 0,
    // bits.i mirrors C's Con.bits union view, so it always carries the raw
    // bits; the fold, gvn and the emitters read it directly.
    bits: ConBits::{ i: d.reinterpret_as_int64(), d, s: 0.0, },
    flt: 2,
    is_local: false,
    sym_type: 0,
  }
}

///|
pub fn Con::single(s : Float) -> Con {
  Con::{
    kind: CBits,
    label: 0,
    bits: ConBits::{ i: s.reinterpret_as_uint().to_int64(), d: 0.0, s, },
    flt: 1,
    is_local: false,
    sym_type: 0,
  }
}

///|
pub fn Con::addr(label : Int32) -> Con {
  Con::{
    kind: CAddr,
    label,
    bits: ConBits::{ i: 0, d: 0.0, s: 0.0, },
    flt: 0,
    is_local: false,
    sym_type: 0,
  }
}

///|
// Symbol address with C Sym.type bits (thread/extern operand prefixes).
pub fn Con::addr_sym(label : Int32, sym_type : Int32) -> Con {
  Con::{
    kind: CAddr,
    label,
    bits: ConBits::{ i: 0, d: 0.0, s: 0.0, },
    flt: 0,
    is_local: false,
    sym_type,
  }
}

///|
// Check if constant is zero
pub fn Con::is_zero(self : Con, wide : Bool) -> Bool {
  if self.kind != CBits {
    return false
  }
  if wide {
    self.bits.i == 0
  } else {
    (self.bits.i & 0xFFFFFFFF) == 0
  }
}

///|
// Add two constants (for address arithmetic), matching C addcon in util.c
pub fn Con::add(self : Con, other : Con) -> Con {
  if self.kind == CUndef {
    other
  } else {
    let kind = if other.kind == CAddr { CAddr } else { self.kind }
    let label = if other.kind == CAddr { other.label } else { self.label }
    Con::{
      kind,
      label,
      bits: ConBits::{
        i: self.bits.i + other.bits.i,
        d: self.bits.d,
        s: self.bits.s,
      },
      flt: self.flt,
      is_local: self.is_local,
      sym_type: if other.kind == CAddr {
        other.sym_type
      } else {
        self.sym_type
      },
    }
  }
}

///|
// Raw bit representation of a constant (for interning, like C's union)
pub fn Con::raw_bits(self : Con) -> Int64 {
  // ConBits is a struct rather than C's union, so bits.i is kept canonical.
  self.bits.i
}

///|
// Bit length of a 64-bit unsigned value.
fn f32_bitlen(x : UInt64) -> Int32 {
  let mut v = x
  let mut n = 0
  if v >> 32 != 0UL {
    n = n + 32
    v = v >> 32
  }
  if v >> 16 != 0UL {
    n = n + 16
    v = v >> 16
  }
  if v >> 8 != 0UL {
    n = n + 8
    v = v >> 8
  }
  if v >> 4 != 0UL {
    n = n + 4
    v = v >> 4
  }
  if v >> 2 != 0UL {
    n = n + 2
    v = v >> 2
  }
  if v >> 1 != 0UL {
    n = n + 1
  }
  n + 1
}

///|
// Round an integer magnitude to IEEE-754 single precision with one
// round-to-nearest-even step, like the C conversion. Converting through
// Double first would round twice (9007199791611905 is 0x5a000001 in C).
pub fn f32_bits_from_uint64(mag : UInt64, neg : Bool) -> UInt32 {
  let sgn : UInt32 = if neg { 0x80000000 } else { 0 }
  if mag == 0UL {
    return sgn
  }
  let mut bl = f32_bitlen(mag)
  let mut m = mag
  if bl > 24 {
    let sh = bl - 24
    let rem = m & ((1UL << sh) - 1UL)
    let half = 1UL << (sh - 1)
    m = m >> sh
    if rem > half || (rem == half && (m & 1UL) == 1UL) {
      m = m + 1UL
    }
    if m == 1UL << 24 {
      m = m >> 1
      bl = bl + 1
    }
  } else {
    m = m << (24 - bl)
  }
  let e = bl - 1
  let expf : UInt32 = (e + 127).to_uint()
  let mant : UInt32 = (m & 0x7FFFFFUL).to_uint()
  sgn | (expf << 23) | mant
}

///|
pub fn f32_from_uint64(v : UInt64) -> Float {
  Float::reinterpret_from_uint(f32_bits_from_uint64(v, false))
}

///|
pub fn f32_from_int64(v : Int64) -> Float {
  let u = v.reinterpret_as_uint64()
  if v < 0L {
    Float::reinterpret_from_uint(f32_bits_from_uint64(0UL - u, true))
  } else {
    Float::reinterpret_from_uint(f32_bits_from_uint64(u, false))
  }
}

///|
// Interning comparison: type + raw bits + label (ignores flt flag),
// matching C's `con[i].type == c.type && con[i].bits.i == c.bits.i`
fn con_eq(c : Con, other : Con) -> Bool {
  c.kind == other.kind &&
  c.raw_bits() == other.raw_bits() &&
  c.label == other.label &&
  c.sym_type == other.sym_type
}
