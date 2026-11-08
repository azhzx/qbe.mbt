///|
// Field type within aggregate type
#derive(Eq, Debug)
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
}

///|
#derive(Debug, Eq)
pub(all) struct Field {
  kind : FieldType
  len : Int32
}

///|
pub fn Field::new(kind : FieldType, len : Int32) -> Field {
  Field::{ kind, len, }
}

///|
pub fn Field::end() -> Field {
  Field::{ kind: FEnd, len: 0, }
}

///|
// Aggregate type definition - corresponds to struct Typ in QBE
#derive(Debug, Eq)
pub(all) struct Typ {
  mut name : String
  mut dark : Int32
  mut isunion : Bool // Independent of nunion: a union may have one alternative.
  mut align : Int32
  mut size : Int64
  mut nunion : Int32
  fields : Array[Field]
}

///|
pub fn Typ::new(name : String) -> Typ {
  Typ::{
    name,
    dark: 0,
    isunion: false,
    align: 0,
    size: 0,
    nunion: 1,
    fields: [],
  }
}

///|
// Size and alignment of one field, as bits: an FTyp names another type in
// typs[len], everything else is a scalar whose alignment follows its size.
fn field_size_align(f : Field, typs : Array[Typ]) -> (Int64, Int32) {
  match f.kind {
    FTyp => {
      let t = typs[f.len]
      (t.size, t.align)
    }
    Fb => (1L, 0)
    Fh => (2L, 1)
    Fw | Fs => (4L, 2)
    Fl | Fd => (8L, 3)
    FPad => (f.len.to_int64(), 0)
    FEnd => (0L, 0)
  }
}

///|
// Lay a type out from its fields and its stated alignment, the way parsefields
// does in C parse.c: pad up to each field's own alignment, accumulate, then
// round the total up to the type's alignment. Padding entries are inserted here
// so callers only list members. FTyp refers to typs[len].
//
// A union holds nunion member lists, each terminated by FEnd and each starting
// at offset 0 (C parsetyp). The member lists are laid out one after the other
// and the union's size is the largest member, aligned to the largest alignment
// seen so far; the alignment carries into later members, exactly as parsefields
// does when it is called again for the next member.
pub fn Typ::compute_layout(self : Typ, typs : Array[Typ]) -> Unit {
  let mut al = self.align
  let mut size = 0L
  let built : Array[Field] = []
  let mut fi = 0
  let mut members = 0
  while members < self.nunion {
    let mut sz = 0L
    let mut n = 0
    while fi < self.fields.length() && self.fields[fi].kind != FEnd {
      let f = self.fields[fi]
      fi = fi + 1
      let (fs, fa) = field_size_align(f, typs)
      if fa > al {
        al = fa
      }
      let mask = (1L << fa) - 1L
      let a = sz & mask
      if a != 0L {
        let pad = mask + 1L - a
        if n < 32 {
          built.push(Field::new(FPad, pad.to_int()))
          n = n + 1
        }
        sz = sz + pad
      }
      if n < 32 {
        built.push(f)
        n = n + 1
      }
      sz = sz + fs
    }
    if fi < self.fields.length() && self.fields[fi].kind == FEnd {
      fi = fi + 1
    }
    built.push(Field::end())
    if sz.reinterpret_as_uint64() < size.reinterpret_as_uint64() {
      sz = size
    }
    let a = 1L << al
    size = (sz + (a - 1L)) & (0L - a)
    members = members + 1
  }
  self.size = size
  self.align = al
  self.fields.clear()
  for f in built {
    self.fields.push(f)
  }
}
