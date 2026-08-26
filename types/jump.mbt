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
#as_free_fn(is_ret, deprecated="use `JumpKind::is_ret` instead")
pub fn JumpKind::is_ret(self : JumpKind) -> Bool {
  match self {
    Jret0 | Jretw | Jretl | Jrets | Jretd | Jretc => true
    _ => false
  }
}

///|
// Index of a jump kind in the J enum.
#as_free_fn(jump_index, deprecated="use `JumpKind::index` instead")
pub fn JumpKind::index(self : JumpKind) -> Int {
  match self {
    Jxxx => 0
    Jret0 => 1
    Jretw => 2
    Jretl => 3
    Jrets => 4
    Jretd => 5
    Jretc => 6
    Jjmp => 7
    Jjnz => 8
    Jjfieq => 9
    Jjfine => 10
    Jjfisge => 11
    Jjfisgt => 12
    Jjfisle => 13
    Jjfislt => 14
    Jjfiuge => 15
    Jjfiugt => 16
    Jjfiule => 17
    Jjfiult => 18
    Jjffeq => 19
    Jjffge => 20
    Jjffgt => 21
    Jjffle => 22
    Jjfflt => 23
    Jjffne => 24
    Jjffo => 25
    Jjffuo => 26
  }
}

///|
// Jump kind from its index in the J enum.
#as_free_fn(jump_from_index, deprecated="use `JumpKind::from_index` instead")
pub fn JumpKind::from_index(i : Int) -> JumpKind {
  match i {
    0 => Jxxx
    1 => Jret0
    2 => Jretw
    3 => Jretl
    4 => Jrets
    5 => Jretd
    6 => Jretc
    7 => Jjmp
    8 => Jjnz
    9 => Jjfieq
    10 => Jjfine
    11 => Jjfisge
    12 => Jjfisgt
    13 => Jjfisle
    14 => Jjfislt
    15 => Jjfiuge
    16 => Jjfiugt
    17 => Jjfiule
    18 => Jjfiult
    19 => Jjffeq
    20 => Jjffge
    21 => Jjffgt
    22 => Jjffle
    23 => Jjfflt
    24 => Jjffne
    25 => Jjffo
    26 => Jjffuo
    _ => abort("invalid jump index")
  }
}
