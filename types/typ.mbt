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
  len : Int32
} derive(Debug, Eq)

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
pub(all) struct Typ {
  mut name : String
  mut dark : Int32
  mut align : Int32
  mut size : Int64
  mut nunion : Int32
  fields : Array[Field]
} derive(Debug, Eq)

///|
pub fn Typ::new(name : String) -> Typ {
  Typ::{ name, dark: 0, align: 0, size: 0, nunion: 1, fields: [], }
}

///|
// Lay a type out from its fields and its stated alignment, the way parsefields
// does in C parse.c: pad up to each field's own alignment, accumulate, then
// round the total up to the type's alignment. Padding entries are inserted here
// so callers only list members. FTyp refers to typs[len].
pub fn Typ::compute_layout(self : Typ, typs : Array[Typ]) -> Unit {
  let mut sz = 0L
  let mut al = self.align
  let built : Array[Field] = []
  for f in self.fields {
    if f.kind == FEnd {
      continue
    }
    let (fs, fa) = match f.kind {
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
    if fa > al {
      al = fa
    }
    let mask = (1L << fa) - 1L
    let a = sz & mask
    if a != 0L {
      let pad = mask + 1L - a
      built.push(Field::new(FPad, pad.to_int()))
      sz = sz + pad
    }
    built.push(f)
    sz = sz + fs
  }
  built.push(Field::end())
  let a = 1L << al
  self.size = (sz + (a - 1L)) & (0L - a)
  self.align = al
  self.fields.clear()
  for f in built {
    self.fields.push(f)
  }
}
