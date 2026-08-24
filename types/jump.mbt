///|
// Jump kinds - corresponds to enum J in QBE
pub(all) enum JumpKind {
  Jxxx // Invalid/unset

  // Returns
  Jret0 // Return void
  Jretw // Return word
  Jretl // Return long
  Jrets // Return single
  Jretd // Return double
  Jretc // Return aggregate

  // Unconditional jump
  Jjmp

  // Conditional non-zero jump
  Jjnz

  // Int comparison jumps
  Jjfieq
  Jjfine
  Jjfisge
  Jjfisgt
  Jjfisle
  Jjfislt
  Jjfiuge
  Jjfiugt
  Jjfiule
  Jjfiult

  // Float comparison jumps
  Jjffeq
  Jjffge
  Jjffgt
  Jjffle
  Jjfflt
  Jjffne
  Jjffo
  Jjffuo
} derive(Eq, Debug)

///|
// Check if jump is a return
pub fn is_ret(j : JumpKind) -> Bool {
  match j {
    Jret0 | Jretw | Jretl | Jrets | Jretd | Jretc => true
    _ => false
  }
}
