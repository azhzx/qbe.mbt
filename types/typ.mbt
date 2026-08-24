///|
// Field type within aggregate type
pub(all) enum FieldType {
  FEnd
  Fb
  Fh
  Fw
  Fl
  Fs
  Fd
  FPad
  FTyp
} derive(Eq, Debug)

///|
pub(all) struct Field {
  kind : FieldType
  len : Int
} derive(Debug)

///|
pub fn Field::new(kind : FieldType, len : Int) -> Field {
  Field::{ kind, len }
}

///|
pub fn Field::end() -> Field {
  Field::{ kind: FEnd, len: 0 }
}

///|
// Aggregate type definition - corresponds to struct Typ in QBE
pub(all) struct Typ {
  mut name : String
  mut dark : Int
  mut align : Int
  mut size : Int64
  mut nunion : Int
  fields : Array[Field]
} derive(Debug)

///|
pub fn Typ::new(name : String) -> Typ {
  Typ::{ name, dark: 0, align: 0, size: 0, nunion: 1, fields: Array::new() }
}
