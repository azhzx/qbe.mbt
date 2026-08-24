///| Ref - corresponds to struct Ref in all.h

///|
/// ADT replacing C bit-field (uint type:3; uint val:29)
pub(all) enum Ref {
  RNone
  RTmp(Int)
  RCon(Int)
  RType(Int)
  RSlot(Int)
  RCall(Int)
  RMem(Int)
} derive(Eq, Debug)

///|
/// R - empty reference (corresponds to C macro R)
pub fn ref_none() -> Ref {
  RNone
}

///|
/// TMP(x) - temporary reference
pub fn Ref::tmp(i : Int) -> Ref {
  RTmp(i)
}

///|
/// CON(x) - constant reference
pub fn Ref::con(i : Int) -> Ref {
  RCon(i)
}

///|
/// TYPE(x) - type reference
pub fn Ref::typ(i : Int) -> Ref {
  RType(i)
}

///|
/// SLOT(x) - stack slot reference
pub fn Ref::slot(i : Int) -> Ref {
  RSlot(i)
}

///|
/// CALL(x) - call result reference
pub fn Ref::call(i : Int) -> Ref {
  RCall(i)
}

///|
/// MEM(x) - memory address reference
pub fn Ref::mem(i : Int) -> Ref {
  RMem(i)
}

///|
/// req - reference equality (corresponds to C req())
pub fn req(a : Ref, b : Ref) -> Bool {
  a == b
}

///|
/// rtype - reference type, returns -1 for RNone (corresponds to C rtype())
pub fn rtype(r : Ref) -> Int {
  match r {
    RNone => -1
    RTmp(_) => 0
    RCon(_) => 1
    RType(_) => 2
    RSlot(_) => 3
    RCall(_) => 4
    RMem(_) => 5
  }
}

///|
/// is_none - check for empty reference
pub fn Ref::is_none(self : Ref) -> Bool {
  match self {
    RNone => true
    _ => false
  }
}

///|
/// is_tmp - check for temporary reference
pub fn Ref::is_tmp(self : Ref) -> Bool {
  match self {
    RTmp(_) => true
    _ => false
  }
}

///|
/// tmp_val - extract temporary index, -1 if not a temp
pub fn Ref::tmp_val(self : Ref) -> Int {
  match self {
    RTmp(v) => v
    _ => -1
  }
}

///|
/// is_con - check for constant reference
pub fn Ref::is_con(self : Ref) -> Bool {
  match self {
    RCon(_) => true
    _ => false
  }
}

///|
/// con_val - extract constant index, -1 if not a constant
pub fn Ref::con_val(self : Ref) -> Int {
  match self {
    RCon(v) => v
    _ => -1
  }
}
