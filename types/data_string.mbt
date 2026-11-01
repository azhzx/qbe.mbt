///|
// Decode the escape sequences of a data-string token into bytes.
//
// The IL keeps string escapes raw: the assembly emitters hand the text to the
// assembler, which decodes it, and the object writer and the interpreter have
// to reproduce the same bytes. That makes the assembler the definition of this
// function, so it matches GNU as on aarch64: \b \f \n \t \r \\ \" \' and
// \ooo octal (1-3 digits) are escapes; \x with up to two hex digits is accepted
// as well. Anything else yields the character itself.
//
// One copy lives here rather than in each consumer: the interpreter and the
// arm64 object writer used to disagree, and a string that reached the object
// image as `\a` came out as a BEL byte instead of a backslash and an 'a'.
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
      if ev == 98 {
        // \b is a backspace in the assembler, not the letter b
        out.push(8)
      } else if ev == 102 {
        // \f is a form feed
        out.push(12)
      } else if ev == 110 {
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
