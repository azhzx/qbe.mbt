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
/// Return 1 if wide (l/d), 0 otherwise (corresponds to C KWIDE()).
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
/// Return the base class: 0 for int (w/l), 1 for float (s/d) (corresponds to C KBASE()).
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
/// Construct a class from its code: 0->Kw, 1->Kl, 2->Ks, 3->Kd, else Kx.
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
/// Return the class code: Kx->-1, Kw->0, Kl->1, Ks->2, Kd->3.
pub fn Class::code(self : Class) -> Int {
  match self {
    Kx => -1
    Kw => 0
    Kl => 1
    Ks => 2
    Kd => 3
  }
}
