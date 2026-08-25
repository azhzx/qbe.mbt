///|
// Fixed-point float formatting matching C's %f / %lf output
// (round half to even, used by printfn for printing constants)

///|
pub fn fmt_fixed(v : Double, prec : Int) -> String {
  let neg = v < 0.0
  let x = if neg { -v } else { v }
  let mut scale : Int64 = 1
  for i in 0..<prec {
    ignore(i)
    scale = scale * 10
  }
  let scaled = x * scale.to_double()
  let f = scaled.floor()
  let frac = scaled - f
  let mut ival = f.to_int64()
  if frac > 0.5 || (frac == 0.5 && ival % 2L == 1L) {
    ival = ival + 1L
  }
  let int_part = ival / scale
  let frac_part = ival % scale
  let sb = StringBuilder::new()
  if neg {
    sb.write_char('-')
  }
  sb.write_string(int_part.to_string())
  sb.write_char('.')
  let frac_str = frac_part.to_string()
  for i = frac_str.length(); i < prec; i = i + 1 {
    ignore(i)
    sb.write_char('0')
  }
  sb.write_string(frac_str)
  sb.to_string()
}
