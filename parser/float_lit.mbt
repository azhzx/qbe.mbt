///|
// QBE floating literals (C parse.c lex uses fscanf("%f") / fscanf("%lf")).
//
// Decimal forms, exponents and inf/nan are handed to @string.parse_double.
// C99 hexadecimal floats (0x1.8p3) are not supported by parse_double, so they
// are converted bit-exactly here, with round-to-nearest-even directly to the
// target precision (single for s_, double for d_) exactly like glibc strtof.
//
// Returns (value as double, value as single, error message). The message is
// empty on success.

///|
fn is_hex_char(c : Char) -> Bool {
  (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn hex_val(c : Char) -> Int32 {
  if c >= '0' && c <= '9' {
    c.to_int() - 48
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 87
  } else {
    c.to_int() - 55
  }
}

///|
fn bitlen64(x : UInt64) -> Int32 {
  if x == 0UL {
    return 0
  }
  let mut n = 0
  let mut v = x
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
// Round mant * 2^exp (plus a sticky fraction below mant's LSB) to IEEE bits
// with mbits mantissa bits and ebits exponent bits. No sign is applied.
fn round_ieee(
  mant : UInt64,
  exp2 : Int32,
  sticky : Bool,
  mbits : Int32,
  ebits : Int32,
) -> UInt64 {
  if mant == 0UL {
    return 0UL
  }
  let bias = (1 << (ebits - 1)) - 1
  let emin = 1 - bias
  let emax = bias
  let target = mbits + 1
  let mut keep = mant
  let mut exp = exp2
  let mut st = sticky
  let bl = bitlen64(keep)
  if bl > target {
    let sh = bl - target
    let rem = keep & ((1UL << sh) - 1UL)
    let half = 1UL << (sh - 1)
    let lsb = (keep >> sh) & 1UL
    keep = keep >> sh
    exp = exp + sh
    if rem > half || (rem == half && (st || lsb == 1UL)) {
      keep = keep + 1UL
    }
    st = false
    if bitlen64(keep) > target {
      keep = keep >> 1
      exp = exp + 1
    }
  }
  while bitlen64(keep) < target {
    keep = keep << 1
    exp = exp - 1
  }
  let e = exp + mbits
  if e > emax {
    return ((1UL << ebits) - 1UL) << mbits
  }
  if e >= emin {
    return ((e + bias).to_uint64() << mbits) | (keep & ((1UL << mbits) - 1UL))
  }
  // subnormal: value / 2^(emin-mbits) rounds to the mantissa field
  let k = emin - mbits - exp
  if k >= 64 {
    return 0UL
  }
  if k <= 0 {
    return keep
  }
  let rem = keep & ((1UL << k) - 1UL)
  let half = 1UL << (k - 1)
  let lsb = (keep >> k) & 1UL
  keep = keep >> k
  if rem > half || (rem == half && (st || lsb == 1UL)) {
    keep = keep + 1UL
  }
  keep
}

///|
// Convert a hexadecimal float (optional sign, 0x prefix, hex mantissa,
// optional p exponent) to raw IEEE bits of the given precision.
fn hex_float_bits(
  chars : Array[Char],
  mbits : Int32,
  ebits : Int32,
) -> (UInt64, Bool) {
  let n = chars.length()
  let mut i = 0
  let mut neg = false
  if i < n && (chars[i] == '-' || chars[i] == '+') {
    neg = chars[i] == '-'
    i = i + 1
  }
  if i + 1 >= n ||
    chars[i] != '0' ||
    (chars[i + 1] != 'x' && chars[i + 1] != 'X') {
    return (0UL, false)
  }
  i = i + 2
  let mut mant = 0UL
  let mut exp2 = 0
  let mut sticky = false
  let mut any = false
  while i < n && is_hex_char(chars[i]) {
    let d = hex_val(chars[i])
    if mant < 1UL << 60 {
      mant = mant * 16UL + d.to_uint64()
    } else {
      exp2 = exp2 + 4
      if d != 0 {
        sticky = true
      }
    }
    any = true
    i = i + 1
  }
  if i < n && chars[i] == '.' {
    i = i + 1
    while i < n && is_hex_char(chars[i]) {
      let d = hex_val(chars[i])
      if mant < 1UL << 60 {
        mant = mant * 16UL + d.to_uint64()
        exp2 = exp2 - 4
      } else if d != 0 {
        sticky = true
      }
      any = true
      i = i + 1
    }
  }
  if !any {
    return (0UL, false)
  }
  if i < n && (chars[i] == 'p' || chars[i] == 'P') {
    let mut j = i + 1
    let mut eneg = false
    if j < n && (chars[j] == '-' || chars[j] == '+') {
      eneg = chars[j] == '-'
      j = j + 1
    }
    let mut e = 0
    let mut got = false
    while j < n && chars[j] >= '0' && chars[j] <= '9' {
      if e < 1000000 {
        e = e * 10 + (chars[j].to_int() - 48)
      }
      got = true
      j = j + 1
    }
    if !got {
      return (0UL, false)
    }
    if eneg {
      exp2 = exp2 - e
    } else {
      exp2 = exp2 + e
    }
    i = j
  }
  if i != n {
    return (0UL, false)
  }
  let mut bits = round_ieee(mant, exp2, sticky, mbits, ebits)
  if neg {
    bits = bits | (1UL << (mbits + ebits))
  }
  (bits, true)
}

///|
fn lower_ch(c : Char) -> Char {
  let n = c.to_int()
  if n >= 65 && n <= 90 {
    (n + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn ci_prefix(chars : Array[Char], at : Int32, lit : String) -> Bool {
  let ls = lit.to_array()
  if at + ls.length() > chars.length() {
    return false
  }
  for i in 0..<ls.length() {
    if lower_ch(chars[at + i]) != lower_ch(ls[i]) {
      return false
    }
  }
  true
}

///|
fn float_from_bits(bits : UInt64) -> Float {
  let u : UInt32 = (bits.reinterpret_as_int64() & 0xFFFFFFFF)
    .reinterpret_as_uint64()
    .to_uint()
  Float::reinterpret_from_uint(u)
}

///|
fn parse_float_literal(raw : String) -> (Double, Float, String) {
  if raw.length() < 3 {
    return (0.0, Float::from_double(0.0), "Invalid floating-point literal")
  }
  let single = raw[0] == 's'
  let text = raw[2:].to_owned()
  let chars = text.to_array()
  let mut k = 0
  if k < chars.length() && (chars[k] == '-' || chars[k] == '+') {
    k = k + 1
  }
  let neg = k == 1 && chars[0] == '-'
  // glibc's strtod/strtof use the canonical quiet-NaN payloads; MoonBit's
  // parser produces a NaN with payload 1, which would not match the
  // reference's emitted bits.
  if ci_prefix(chars, k, "nan") {
    let dbits : UInt64 = 0x7FF8000000000000UL |
      (if neg { 0x8000000000000000UL } else { 0UL })
    let fbits : UInt64 = 0x7FC00000UL | (if neg { 0x80000000UL } else { 0UL })
    let d = dbits.reinterpret_as_int64().reinterpret_as_double()
    return (d, float_from_bits(fbits), "")
  }
  if ci_prefix(chars, k, "infinity") || ci_prefix(chars, k, "inf") {
    let dbits : UInt64 = 0x7FF0000000000000UL |
      (if neg { 0x8000000000000000UL } else { 0UL })
    let fbits : UInt64 = 0x7F800000UL | (if neg { 0x80000000UL } else { 0UL })
    let d = dbits.reinterpret_as_int64().reinterpret_as_double()
    return (d, float_from_bits(fbits), "")
  }
  let is_hex = k + 1 < chars.length() &&
    chars[k] == '0' &&
    (chars[k + 1] == 'x' || chars[k + 1] == 'X')
  let (d, f) = if is_hex {
    if single {
      let (bits, ok) = hex_float_bits(chars, 23, 8)
      if !ok {
        return (0.0, Float::from_double(0.0), "Invalid floating-point literal")
      }
      let f = float_from_bits(bits)
      (f.to_double(), f)
    } else {
      let (bits, ok) = hex_float_bits(chars, 52, 11)
      if !ok {
        return (0.0, Float::from_double(0.0), "Invalid floating-point literal")
      }
      let d = bits.reinterpret_as_int64().reinterpret_as_double()
      (d, Float::from_double(d))
    }
  } else {
    let r = try @string.parse_double(text) catch {
      _ =>
        return (0.0, Float::from_double(0.0), "Invalid floating-point literal")
    } noraise {
      n => n
    }
    if single {
      let f = Float::from_double(r)
      (f.to_double(), f)
    } else {
      (r, Float::from_double(r))
    }
  }
  (d, f, "")
}
