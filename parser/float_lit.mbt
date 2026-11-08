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
  let bl = bitlen64(mant)
  let e = exp2 + bl - 1
  if e < emin {
    // Subnormal result: choose the subnormal quantum first and round once.
    // Rounding to normal precision first (as the old code did) would round
    // a value just below the smallest normal twice.
    let shift = emin - mbits - exp2
    if shift <= 0 {
      return mant << -shift
    }
    if shift == 64 {
      let half = 1UL << 63
      if mant > half || (mant == half && sticky) {
        return 1UL
      }
      return 0UL
    }
    if shift > 64 {
      return 0UL
    }
    let rem = mant & ((1UL << shift) - 1UL)
    let half = 1UL << (shift - 1)
    let mut q = mant >> shift
    if rem > half || (rem == half && (sticky || (q & 1UL) == 1UL)) {
      q = q + 1UL
    }
    if q >= 1UL << mbits {
      return 1UL << mbits
    }
    return q
  }
  let mut keep = mant
  let mut exp = exp2
  if bl > target {
    let sh = bl - target
    let rem = keep & ((1UL << sh) - 1UL)
    let half = 1UL << (sh - 1)
    let lsb = (keep >> sh) & 1UL
    keep = keep >> sh
    exp = exp + sh
    if rem > half || (rem == half && (sticky || lsb == 1UL)) {
      keep = keep + 1UL
    }
    if bitlen64(keep) > target {
      keep = keep >> 1
      exp = exp + 1
    }
  } else {
    keep = keep << (target - bl)
    exp = exp - (target - bl)
  }
  let e2 = exp + mbits
  if e2 > emax {
    return ((1UL << ebits) - 1UL) << mbits
  }
  ((e2 + bias).to_uint64() << mbits) | (keep & ((1UL << mbits) - 1UL))
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
fn pow10_big(n : Int32) -> @bigint.BigInt {
  let sb = StringBuilder::new()
  sb.write_char('1')
  for _ in 0..<n {
    sb.write_char('0')
  }
  @bigint.BigInt::from_string(sb.to_string(), radix=10)
}

///|
// Split a decimal literal into (negative, significant digits, decimal
// exponent, sticky). The digit string is value / 10^exp10; at most 60 digits
// are kept and any nonzero dropped digit sets sticky.
fn decimal_digits(text : Array[Char]) -> (Bool, String, Int32, Bool)? {
  let n = text.length()
  let mut i = 0
  let mut neg = false
  if i < n && (text[i] == '-' || text[i] == '+') {
    neg = text[i] == '-'
    i = i + 1
  }
  let db = StringBuilder::new()
  let mut frac = 0
  let mut any = false
  while i < n && text[i] >= '0' && text[i] <= '9' {
    db.write_char(text[i])
    i = i + 1
    any = true
  }
  if i < n && text[i] == '.' {
    i = i + 1
    while i < n && text[i] >= '0' && text[i] <= '9' {
      db.write_char(text[i])
      frac = frac + 1
      i = i + 1
      any = true
    }
  }
  if !any {
    return None
  }
  let mut e10 = 0
  if i < n && (text[i] == 'e' || text[i] == 'E') {
    i = i + 1
    let mut eneg = false
    if i < n && (text[i] == '-' || text[i] == '+') {
      eneg = text[i] == '-'
      i = i + 1
    }
    let mut got = false
    while i < n && text[i] >= '0' && text[i] <= '9' {
      if e10 < 1000000 {
        e10 = e10 * 10 + (text[i].to_int() - 48)
      }
      got = true
      i = i + 1
    }
    if !got {
      return None
    }
    if eneg {
      e10 = -e10
    }
  }
  if i != n {
    return None
  }
  let digits = db.to_string()
  let mut s = 0
  let mut t = digits.length()
  while s < t && digits[s] == '0' {
    s = s + 1
  }
  let mut exp10 = e10 - frac
  while t > s && digits[t - 1] == '0' {
    t = t - 1
    exp10 = exp10 + 1
  }
  if s == t {
    return Some((neg, "", 0, false))
  }
  let mut ds = digits[s:t].to_owned()
  let mut sticky = false
  if ds.length() > 60 {
    for k in 60..<ds.length() {
      if ds[k] != '0' {
        sticky = true
      }
    }
    exp10 = exp10 + (ds.length() - 60)
    ds = ds[0:60].to_owned()
  }
  Some((neg, ds, exp10, sticky))
}

///|
// Correctly rounded decimal-to-single conversion. C's fscanf("%f") rounds the
// exact decimal value once; converting a Double first rounds twice and can
// turn 1.0000000596046448 into 1.0 instead of 0x3f800001.
fn decimal_f32_bits(chars : Array[Char]) -> (UInt64, Bool) {
  match decimal_digits(chars) {
    None => (0UL, false)
    Some((neg, ds, exp10, sticky)) => {
      let sign : UInt64 = if neg { 0x80000000UL } else { 0UL }
      if ds.length() == 0 {
        return (sign, true)
      }
      let dex = ds.length() - 1 + exp10
      if dex > 38 {
        return (sign | 0x7F800000UL, true)
      }
      if dex < -46 {
        return (sign, true)
      }
      let one = @bigint.BigInt::from_int(1)
      let mut num = @bigint.BigInt::from_string(ds, radix=10)
      let mut den = one
      if exp10 > 0 {
        num = num.mul(pow10_big(exp10))
      } else if exp10 < 0 {
        den = pow10_big(-exp10)
      }
      let mut e = num.bit_length() - den.bit_length()
      let cmp = if e >= 0 {
        num.compare(den.shl(e))
      } else {
        num.shl(-e).compare(den)
      }
      if cmp < 0 {
        e = e - 1
      }
      let emin = -126
      let shift = if e >= emin { 23 - e } else { 23 - emin }
      let nn = if shift >= 0 { num.shl(shift) } else { num }
      let dd = if shift >= 0 { den } else { den.shl(-shift) }
      let q = nn.div(dd)
      let rem = nn.mod(dd)
      let c = rem.add(rem).compare(dd)
      let two = @bigint.BigInt::from_int(2)
      let odd = q.mod(two).compare_int(0) != 0
      let mut qq = q
      if c > 0 || (c == 0 && (sticky || odd)) {
        qq = qq.add(one)
      }
      if e >= emin {
        let mut e2 = e
        let mut m = qq
        if m.bit_length() > 24 {
          m = m.shr(1)
          e2 = e2 + 1
        }
        if e2 > 127 {
          return (sign | 0x7F800000UL, true)
        }
        let expf = (e2 + 127).to_uint64()
        let mant = m.to_uint64() & 0x7FFFFFUL
        (sign | (expf << 23) | mant, true)
      } else {
        if qq.equal_int(0) {
          return (sign, true)
        }
        if qq.bit_length() > 23 {
          return (sign | (1UL << 23), true)
        }
        (sign | qq.to_uint64(), true)
      }
    }
  }
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
  } else if single {
    let (bits, ok) = decimal_f32_bits(chars)
    if !ok {
      return (0.0, Float::from_double(0.0), "Invalid floating-point literal")
    }
    let f = float_from_bits(bits)
    (f.to_double(), f)
  } else {
    let mut failed = false
    let r = try @string.parse_double(text) catch {
      _ => {
        failed = true
        0.0
      }
    } noraise {
      n => n
    }
    if failed {
      // C strtod returns +-inf on overflow and +-0 on underflow.
      match decimal_digits(chars) {
        Some((neg2, ds, exp10, _)) => {
          let sign : UInt64 = if neg2 { 0x8000000000000000UL } else { 0UL }
          if ds.length() == 0 {
            (0.0, Float::from_double(0.0))
          } else {
            let dex = ds.length() - 1 + exp10
            if dex > 308 {
              let d = (sign | 0x7FF0000000000000UL)
                .reinterpret_as_int64()
                .reinterpret_as_double()
              (d, Float::from_double(d))
            } else if dex < -323 {
              let d = sign.reinterpret_as_int64().reinterpret_as_double()
              (d, Float::from_double(d))
            } else {
              return (
                0.0,
                Float::from_double(0.0),
                "Invalid floating-point literal",
              )
            }
          }
        }
        None =>
          return (
            0.0,
            Float::from_double(0.0),
            "Invalid floating-point literal",
          )
      }
    } else {
      (r, Float::from_double(r))
    }
  }
  (d, f, "")
}
