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
pub fn TmpWidth::code(self : TmpWidth) -> Int32 {
  match self {
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
pub fn TmpWidth::from_code(c : Int32) -> TmpWidth {
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
  blk_id : Int32
  // Mutable because narrowpars moves the start block's tail up by npar: C
  // keeps a pointer into the old array (alive in the function arena), this
  // port keeps an index and has to re-address it.
  mut ins_idx : Int32
  arg_num : Int32
} derive(Debug, Eq)

///|
// Register allocation hint
pub(all) struct RegHint {
  mut r : Int32 // Preferred register, -1 if unset
  mut w : Int32 // Weight
  mut m : UInt64 // Bitmask of registers to avoid
} derive(Debug)

///|
pub fn RegHint::default() -> RegHint {
  RegHint::{ r: -1, w: 0, m: 0, }
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
pub fn AliasType::astack(self : AliasType) -> Bool {
  match self {
    ALoc | AEsc => true
    _ => false
  }
}

///|
// Alias information
pub(all) struct AliasInfo {
  mut kind : AliasType
  mut base : Ref
  mut label : Int32
  mut offset : Int64
  // The underlying stack-slot temporary id (the alloc), or -1.
  // Mirrors C's Alias.slot pointer; for an alloc it points to itself.
  mut slot : Int32
  // C's Alias.u.loc: the slot size (-1 when unknown) and the mask of the
  // bytes something has stored through the slot. fillalias fills both.
  mut sz : Int32
  mut m : UInt64
} derive(Debug)

///|
pub fn AliasInfo::default() -> AliasInfo {
  AliasInfo::{
    kind: ABot,
    base: Ref::none(),
    label: 0,
    offset: 0,
    slot: -1,
    sz: -1,
    m: 0UL,
  }
}

///|
// Temporary variable - corresponds to struct Tmp in QBE
pub(all) struct Tmp {
  name : String
  uses : Array[Use]
  mut ndef : Int32
  mut nuse : Int32
  mut bid : Int32 // Block id of the definition (C Tmp.bid)
  mut cost : Int32
  mut slot : Int32 // Spill slot, -1 if unset
  mut reg : Int32 // Allocated register id, -1 if in a slot/untracked
  mut cls : Class
  mut hint : RegHint
  mut is_phi : Int32 // 0 = no, >0 = phi class id
  mut alias_info : AliasInfo
  mut width : TmpWidth
  mut visit : Int32
} derive(Debug)

///|
pub fn Tmp::new(name : String, cls : Class) -> Tmp {
  Tmp::{
    name,
    uses: [],
    ndef: 0,
    nuse: 0,
    bid: -1,
    cost: 0,
    slot: -1,
    reg: -1,
    cls,
    hint: RegHint::default(),
    is_phi: 0,
    alias_info: AliasInfo::default(),
    width: WFull,
    visit: 0,
  }
}
