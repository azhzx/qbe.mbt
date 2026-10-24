///|
// Decode the escape sequences of a data-string token into bytes.
//
// The lexer keeps string escapes raw (see lexer/lexer.mbt), so every consumer
// that needs the actual bytes has to decode them. The assembly emitters get
// this for free by passing the raw text to gas, but the interpreter stores
// bytes directly and used to copy the raw characters:
//   data $x = { b "0x42" }   (spelled with a backslash escape in real input)
// produced the characters backslash, 'x', '4', '2' instead of 0x42.
pub fn decode_data_string(raw : String) -> Array[Int32] {
  let a = raw.to_array()
  let n = a.length()
  let out : Array[Int32] = []
  let mut i = 0
  while i < n {
    let ch = a[i]
    if ch.to_int() == 92 && i + 1 < n {
      i = i + 1
      let e = a[i]
      let ev = e.to_int()
      if ev == 110 {
        out.push(10)
      } else if ev == 116 {
        out.push(9)
      } else if ev == 114 {
        out.push(13)
      } else if ev == 92 {
        out.push(92)
      } else if ev == 34 {
        out.push(34)
      } else if ev == 39 {
        out.push(39)
      } else if ev == 120 {
        // hex escape, one or two digits
        let mut v = 0
        let mut k = 0
        while i + 1 < n && k < 2 {
          let d = hex_val(a[i + 1])
          if d < 0 {
            break
          }
          v = v * 16 + d
          i = i + 1
          k = k + 1
        }
        out.push(v & 0xFF)
      } else if ev >= 48 && ev <= 55 {
        // octal escape, up to three digits
        let mut v = 0
        let mut k = 0
        while i < n && k < 3 && a[i].to_int() >= 48 && a[i].to_int() <= 55 {
          v = v * 8 + (a[i].to_int() - 48)
          i = i + 1
          k = k + 1
        }
        i = i - 1
        out.push(v & 0xFF)
      } else {
        out.push(ev)
      }
    } else {
      out.push(ch.to_int())
    }
    i = i + 1
  }
  out
}

///|
fn hex_val(c : Char) -> Int32 {
  let v = c.to_int()
  if v >= 48 && v <= 57 {
    v - 48
  } else if v >= 97 && v <= 102 {
    v - 87
  } else if v >= 65 && v <= 70 {
    v - 55
  } else {
    -1
  }
}
