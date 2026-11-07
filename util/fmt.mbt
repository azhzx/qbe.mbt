///|
// Decimal (base 10) little-endian digit helpers for exact %f formatting.

///|
fn dec_from_u64(x : UInt64) -> Array[Int32] {
  let a : Array[Int32] = []
  let mut v = x
  if v == 0UL {
    a.push(0)
    return a
  }
  while v != 0UL {
    a.push((v % 10UL).to_int())
    v = v / 10UL
  }
  a
}

///|
fn dec_mul_small(a : Array[Int32], m : Int32) -> Unit {
  let mut carry = 0
  for i in 0..<a.length() {
    let v = a[i] * m + carry
    a[i] = v % 10
    carry = v / 10
  }
  while carry > 0 {
    a.push(carry % 10)
    carry = carry / 10
  }
}

///|
fn dec_add_one(a : Array[Int32]) -> Unit {
  let mut i = 0
  let mut carry = 1
  while carry > 0 {
    if i >= a.length() {
      a.push(carry)
      carry = 0
    } else {
      let v = a[i] + carry
      a[i] = v % 10
      carry = v / 10
      i = i + 1
    }
  }
}

///|
// Multiply by 10^n (insert n zero digits at the low end).
fn dec_shift10(a : Array[Int32], n : Int32) -> Array[Int32] {
  let r : Array[Int32] = []
  for _ in 0..<n {
    r.push(0)
  }
  for d in a {
    r.push(d)
  }
  r
}

///|
// Render an integer (little-endian digits) as fixed point with prec digits
// after the point, truncating the integer's low digits into the fraction.
fn dec_to_fixed(a : Array[Int32], prec : Int32) -> String {
  let sb = StringBuilder::StringBuilder()
  let mut hi = a.length() - 1
  while hi >= prec && a[hi] == 0 {
    hi = hi - 1
  }
  if hi < prec {
    sb.write_char('0')
  } else {
    let mut i = hi
    while i >= prec {
      sb.write_char((48 + a[i]).unsafe_to_char())
      i = i - 1
    }
  }
  if prec > 0 {
    sb.write_char('.')
    let mut i = prec - 1
    while i >= 0 {
      let d = if i < a.length() { a[i] } else { 0 }
      sb.write_char((48 + d).unsafe_to_char())
      i = i - 1
    }
  }
  sb.to_string()
}

///|
// Format a double like C printf("%.<prec>f"): correct for any finite value
// (the old implementation converted to Int64 and saturated above 2^63, which
// printed FLT_MAX as 9223372036854.775807). Rounding is round-half-to-even,
// matching glibc. inf/nan print as C's %f does.
pub fn fmt_fixed(v : Double, prec : Int32) -> String {
  let bits = v.reinterpret_as_int64()
  let neg = bits < 0L
  let abits = bits.reinterpret_as_uint64() & 0x7FFFFFFFFFFFFFFFUL
  let exp_field = (abits >> 52).to_int() & 0x7FF
  let mant0 = abits & 0xFFFFFFFFFFFFFUL
  let sign = if neg { "-" } else { "" }
  if exp_field == 0x7FF {
    if mant0 != 0UL {
      return sign + "nan"
    }
    return sign + "inf"
  }
  if exp_field == 0 && mant0 == 0UL {
    // signed zero: C prints "-0.000000"
    let z = dec_to_fixed([0], prec)
    return sign + z
  }
  let m = if exp_field == 0 { mant0 } else { mant0 | 0x10000000000000UL }
  let e2 = if exp_field == 0 { -1074 } else { exp_field - 1023 - 52 }
  let n : Array[Int32] = if e2 >= 0 {
    // x = m * 2^e2, an integer; then append prec zero digits
    let a = dec_from_u64(m)
    for _ in 0..<e2 {
      dec_mul_small(a, 2)
    }
    dec_shift10(a, prec)
  } else {
    let k = -e2
    // x = m / 2^k = (m * 5^k) / 10^k
    let a = dec_from_u64(m)
    for _ in 0..<k {
      dec_mul_small(a, 5)
    }
    if k <= prec {
      dec_shift10(a, prec - k)
    } else {
      let cut = k - prec
      if cut >= a.length() {
        round_quotient_zero(a, cut)
      } else {
        let kept : Array[Int32] = []
        for i in cut..<a.length() {
          kept.push(a[i])
        }
        let rd = if cut - 1 >= 0 && cut - 1 < a.length() {
          a[cut - 1]
        } else {
          0
        }
        let mut sticky = false
        let mut i = 0
        while i < cut - 1 {
          if i < a.length() && a[i] != 0 {
            sticky = true
          }
          i = i + 1
        }
        let lsb = if kept.length() > 0 { kept[0] } else { 0 }
        let up = rd > 5 || (rd == 5 && (sticky || lsb % 2 == 1))
        if up {
          dec_add_one(kept)
        }
        kept
      }
    }
  }
  // kept may be empty only when the value rounds to zero
  let digits = if n.length() == 0 {
    let z : Array[Int32] = [0]
    z
  } else {
    n
  }
  sign + dec_to_fixed(digits, prec)
}

///|
// Round A / 10^cut to 0 or 1 (round half to even) when A has at most cut
// digits. An exact tie keeps the even quotient 0.
fn round_quotient_zero(a : Array[Int32], cut : Int32) -> Array[Int32] {
  let r : Array[Int32] = [0]
  if cut == a.length() {
    let rd = a[cut - 1]
    let mut sticky = false
    for i in 0..<(cut - 1) {
      if a[i] != 0 {
        sticky = true
      }
    }
    if rd > 5 || (rd == 5 && sticky) {
      r[0] = 1
    }
  }
  r
}
