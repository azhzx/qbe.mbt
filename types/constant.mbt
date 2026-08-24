///|
// Constant type
pub(all) enum ConType {
  CUndef
  CBits // Numeric constant
  CAddr // Symbol address
} derive(Eq, Debug)

///|
// Constant value bits
pub(all) struct ConBits {
  i : Int64 // Integer value
  d : Double // Double value
  s : Float // Single (float) value
} derive(Debug)

///|
// Constant - corresponds to struct Con in QBE
pub(all) struct Con {
  kind : ConType
  label : Int // Interned string label for CAddr
  bits : ConBits // Value bits
  flt : Int // 0=integer, 1=print as s, 2=print as d
  is_local : Bool // True if local symbol
} derive(Debug)

///|
pub fn Con::new() -> Con {
  Con::{
    kind: CUndef,
    label: 0,
    bits: ConBits::{ i: 0, d: 0.0, s: 0.0 },
    flt: 0,
    is_local: false,
  }
}

///|
pub fn Con::int(i : Int64) -> Con {
  Con::{
    kind: CBits,
    label: 0,
    bits: ConBits::{ i, d: 0.0, s: 0.0 },
    flt: 0,
    is_local: false,
  }
}

///|
pub fn Con::double(d : Double) -> Con {
  Con::{
    kind: CBits,
    label: 0,
    bits: ConBits::{ i: 0, d, s: 0.0 },
    flt: 2,
    is_local: false,
  }
}

///|
pub fn Con::single(s : Float) -> Con {
  Con::{
    kind: CBits,
    label: 0,
    bits: ConBits::{ i: 0, d: 0.0, s },
    flt: 1,
    is_local: false,
  }
}

///|
pub fn Con::addr(label : Int) -> Con {
  Con::{
    kind: CAddr,
    label,
    bits: ConBits::{ i: 0, d: 0.0, s: 0.0 },
    flt: 0,
    is_local: false,
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
// Add two constants (for address arithmetic)
pub fn addcon(c : Con, other : Con) -> Con {
  if c.kind == CAddr && other.kind == CBits {
    Con::{
      kind: CAddr,
      label: c.label,
      bits: ConBits::{ i: c.bits.i + other.bits.i, d: 0.0, s: 0.0 },
      flt: 0,
      is_local: c.is_local,
    }
  } else if c.kind == CBits && other.kind == CBits {
    Con::int(c.bits.i + other.bits.i)
  } else {
    c
  }
}

///|
// Raw bit representation of a constant (for interning, like C's union)
pub fn con_raw_bits(c : Con) -> Int64 {
  if c.kind == CBits && c.flt == 1 {
    c.bits.s.reinterpret_as_uint().to_int64()
  } else if c.kind == CBits && c.flt == 2 {
    c.bits.d.reinterpret_as_int64()
  } else {
    c.bits.i
  }
}

///|
// Interning comparison: type + raw bits + label (ignores flt flag),
// matching C's `con[i].type == c.type && con[i].bits.i == c.bits.i`
pub fn con_eq(c : Con, other : Con) -> Bool {
  c.kind == other.kind &&
  con_raw_bits(c) == con_raw_bits(other) &&
  c.label == other.label
}
