///|
/// Class - corresponds to enum Class in all.h
pub(all) enum Class {
  Kx // -1, "top" class
  Kw
  Kl
  Ks
  Kd
} derive(Eq, Debug)

///|
/// kwide - 1 if wide (l/d), 0 otherwise (corresponds to C KWIDE())
pub fn kwide(k : Class) -> Int {
  match k {
    Kx => 0
    Kw => 0
    Kl => 1
    Ks => 0
    Kd => 1
  }
}

///|
/// kbase - base class: 0 for int (w/l), 1 for float (s/d) (corresponds to C KBASE())
pub fn kbase(k : Class) -> Int {
  match k {
    Kx => 0
    Kw => 0
    Kl => 0
    Ks => 1
    Kd => 1
  }
}

///|
/// class_from_code - inverse of kcode: 0->Kw, 1->Kl, 2->Ks, 3->Kd, else Kx.
pub fn class_from_code(c : Int) -> Class {
  match c {
    0 => Kw
    1 => Kl
    2 => Ks
    3 => Kd
    _ => Kx
  }
}
