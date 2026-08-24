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
/// SLOT(x) - stack slot reference (value masked to 29 bits, as C SLOT())
pub fn Ref::slot(i : Int) -> Ref {
  RSlot(i & 0x1fffffff)
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
/// is_mem - check for memory reference
pub fn Ref::is_mem(self : Ref) -> Bool {
  match self {
    RMem(_) => true
    _ => false
  }
}

///|
/// mem_val - extract memory index, -1 if not a memory ref
pub fn Ref::mem_val(self : Ref) -> Int {
  match self {
    RMem(v) => v
    _ => -1
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

///|
/// call_val - extract call info index, -1 if not a call ref
pub fn Ref::call_val(self : Ref) -> Int {
  match self {
    RCall(v) => v
    _ => -1
  }
}

///|
/// slot_val - extract slot index, -1 if not a slot ref
pub fn Ref::slot_val(self : Ref) -> Int {
  match self {
    RSlot(v) => v
    _ => -1
  }
}

///|
/// typ_val - extract type index, -1 if not a type ref
pub fn Ref::typ_val(self : Ref) -> Int {
  match self {
    RType(v) => v
    _ => -1
  }
}
