///|
// Width for partial-write temporaries
pub(all) enum TmpWidth {
  WFull
  Wsb
  Wub
  Wsh
  Wuh
  Wsw
  Wuw
} derive(Eq, Debug)

///|
// Width index as int (C: WFull=0, Wsb=1, ... Wuw=6)
pub fn width_code(w : TmpWidth) -> Int {
  match w {
    WFull => 0
    Wsb => 1
    Wub => 2
    Wsh => 3
    Wuh => 4
    Wsw => 5
    Wuw => 6
  }
}

///|
// Construct TmpWidth from an int code (1..6 => Wsb..Wuw)
pub fn width_from_code(c : Int) -> TmpWidth {
  match c {
    1 => Wsb
    2 => Wub
    3 => Wsh
    4 => Wuh
    5 => Wsw
    6 => Wuw
    _ => WFull
  }
}

///|
// Use type
pub(all) enum UseKind {
  UXXX
  UPhi
  UIns
  UJmp
} derive(Eq, Debug)

///|
// Use record
pub(all) struct Use {
  kind : UseKind
  blk_id : Int
  ins_idx : Int
  arg_num : Int
} derive(Debug)

///|
// Register allocation hint
pub(all) struct RegHint {
  r : Int // Preferred register, -1 if unset
  w : Int // Weight
  m : UInt64 // Bitmask of registers to avoid
} derive(Debug)

///|
pub fn RegHint::default() -> RegHint {
  RegHint::{ r: -1, w: 0, m: 0 }
}

///|
// Alias type
pub(all) enum AliasType {
  ABot
  ALoc
  ACon
  AEsc
  ASym
  AUnk
} derive(Eq, Debug)

///|
pub fn astack(t : AliasType) -> Bool {
  match t {
    ALoc | AEsc => true
    _ => false
  }
}

///|
// Alias information
pub(all) struct AliasInfo {
  mut kind : AliasType
  mut base : Ref
  mut label : Int
  mut offset : Int64
  // The underlying stack-slot temporary id (the alloc), or -1.
  // Mirrors C's Alias.slot pointer; for an alloc it points to itself.
  mut slot : Int
} derive(Debug)

///|
pub fn AliasInfo::default() -> AliasInfo {
  AliasInfo::{ kind: ABot, base: ref_none(), label: 0, offset: 0, slot: -1 }
}

///|
// Temporary variable - corresponds to struct Tmp in QBE
pub(all) struct Tmp {
  name : String
  uses : Array[Use]
  mut ndef : Int
  mut nuse : Int
  mut cost : Int
  mut slot : Int // Spill slot, -1 if unset
  mut cls : Class
  mut hint : RegHint
  mut is_phi : Int // 0 = no, >0 = phi class id
  mut alias_info : AliasInfo
  mut width : TmpWidth
  mut visit : Int
} derive(Debug)

///|
pub fn Tmp::new(name : String, cls : Class) -> Tmp {
  Tmp::{
    name,
    uses: Array::new(),
    ndef: 0,
    nuse: 0,
    cost: 0,
    slot: -1,
    cls,
    hint: RegHint::default(),
    is_phi: 0,
    alias_info: AliasInfo::default(),
    width: WFull,
    visit: 0,
  }
}
