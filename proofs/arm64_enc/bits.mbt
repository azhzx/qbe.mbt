///|
// Trusted bit primitives: MoonBit cannot lower &, |, << in contracted
// bodies, so each is axiomatized with its Why3 bv.BV32 meaning.
fn band(
  a : Int,
  b : Int,
) -> Int where {
  proof_axiomatized: true,
  proof_ensure: result => word(result) == word(a).band(word(b)),
} {
  a & b
}

///|
fn bor(
  a : Int,
  b : Int,
) -> Int where {
  proof_axiomatized: true,
  proof_ensure: result => word(result) == word(a).bor(word(b)),
} {
  a | b
}

///|
fn shl(
  a : Int,
  s : Int,
) -> Int where {
  proof_axiomatized: true,
  proof_require: 0 <= s,
  proof_ensure: result => word(result) == word(a).shl(s),
} {
  a << s
}
