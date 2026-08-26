///|
// Data item type
pub(all) enum DatKind {
  DStart
  DEnd
  DName
  DAlign
  DB // Byte data
  DH // Half data
  DW // Word data
  DL // Long data
  DZ // Zero fill
} derive(Eq, Debug)

///|
// Data section item - corresponds to struct Dat in QBE
pub(all) struct Dat {
  mut kind : DatKind
  num : Int64
  fltd : Double
  flts : Float
  str : String
  ref_name : String
  ref_offset : Int64
  is_ref : Bool
  is_str : Bool
  mut is_export : Bool
} derive(Debug)

///|
pub fn Dat::start() -> Dat {
  Dat::{
    kind: DStart,
    num: 0,
    fltd: 0.0,
    flts: 0.0,
    str: "",
    ref_name: "",
    ref_offset: 0,
    is_ref: false,
    is_str: false,
    is_export: false,
  }
}

///|
pub fn Dat::end() -> Dat {
  Dat::{
    kind: DEnd,
    num: 0,
    fltd: 0.0,
    flts: 0.0,
    str: "",
    ref_name: "",
    ref_offset: 0,
    is_ref: false,
    is_str: false,
    is_export: false,
  }
}

///|
pub fn Dat::name(name : String, is_export : Bool) -> Dat {
  Dat::{
    kind: DName,
    num: 0,
    fltd: 0.0,
    flts: 0.0,
    str: name,
    ref_name: "",
    ref_offset: 0,
    is_ref: false,
    is_str: false,
    is_export,
  }
}

///|
pub fn Dat::align(a : Int64) -> Dat {
  Dat::{
    kind: DAlign,
    num: a,
    fltd: 0.0,
    flts: 0.0,
    str: "",
    ref_name: "",
    ref_offset: 0,
    is_ref: false,
    is_str: false,
    is_export: false,
  }
}

///|
pub fn Dat::byte(b : Int64) -> Dat {
  Dat::{
    kind: DB,
    num: b,
    fltd: 0.0,
    flts: 0.0,
    str: "",
    ref_name: "",
    ref_offset: 0,
    is_ref: false,
    is_str: false,
    is_export: false,
  }
}

///|
pub fn Dat::zero(n : Int64) -> Dat {
  Dat::{
    kind: DZ,
    num: n,
    fltd: 0.0,
    flts: 0.0,
    str: "",
    ref_name: "",
    ref_offset: 0,
    is_ref: false,
    is_str: false,
    is_export: false,
  }
}

///|
pub fn Dat::string(s : String) -> Dat {
  Dat::{
    kind: DB,
    num: 0,
    fltd: 0.0,
    flts: 0.0,
    str: s,
    ref_name: "",
    ref_offset: 0,
    is_ref: false,
    is_str: true,
    is_export: false,
  }
}

///|
pub fn Dat::ref_to(name : String, offset : Int64) -> Dat {
  Dat::{
    kind: DL,
    num: 0,
    fltd: 0.0,
    flts: 0.0,
    str: "",
    ref_name: name,
    ref_offset: offset,
    is_ref: true,
    is_str: false,
    is_export: false,
  }
}
