///|
// Text formatting helpers matching C's printf width flags.

///|
// Left-justify s in a field of width w (C "%-*s"), truncating if too long.
pub fn lpad(s : String, w : Int32) -> String {
  if s.length() >= w {
    s
  } else {
    s + " ".repeat(w - s.length())
  }
}

///|
// Right-justify an integer in a field of width w (C "%*d").
pub fn rpad(v : Int32, w : Int32) -> String {
  let s = v.to_string()
  if s.length() >= w {
    s
  } else {
    " ".repeat(w - s.length()) + s
  }
}
