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
#as_free_fn(kwide, deprecated="use `Class::wide` instead")
pub fn Class::wide(self : Class) -> Int {
  match self {
    Kx => 0
    Kw => 0
    Kl => 1
    Ks => 0
    Kd => 1
  }
}

///|
/// kbase - base class: 0 for int (w/l), 1 for float (s/d) (corresponds to C KBASE())
#as_free_fn(kbase, deprecated="use `Class::base` instead")
pub fn Class::base(self : Class) -> Int {
  match self {
    Kx => 0
    Kw => 0
    Kl => 0
    Ks => 1
    Kd => 1
  }
}

///|
/// class_from_code - inverse of kcode: 0->Kw, 1->Kl, 2->Ks, 3->Kd, else Kx.
#as_free_fn(class_from_code, deprecated="use `Class::from_code` instead")
pub fn Class::from_code(c : Int) -> Class {
  match c {
    0 => Kw
    1 => Kl
    2 => Ks
    3 => Kd
    _ => Kx
  }
}

///|
/// kcode - class to code: Kx->-1, Kw->0, Kl->1, Ks->2, Kd->3.
#as_free_fn(kcode, deprecated="use `Class::code` instead")
pub fn Class::code(self : Class) -> Int {
  match self {
    Kx => -1
    Kw => 0
    Kl => 1
    Ks => 2
    Kd => 3
  }
}
