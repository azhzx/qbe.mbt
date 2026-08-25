///|
// Parse a data definition
// export: whether the data is exported
fn Parser::parsedat(self : Self, is_export : Bool) -> Unit raise {
  // Emit DStart
  let d = @types.Dat::start()
  d.is_export = is_export
  self.datas.push(d)
  // Parse data name: $name =
  if self.next_nl() != TGlo {
    raise self.error("data name expected")
  }
  let name = self.tokens[self.pos - 1].raw
  if self.next_nl() != TEq {
    raise self.error("= expected after data name")
  }
  // Optional: align N
  let mut t = self.next_nl()
  if t == TId && self.tokens[self.pos - 1].raw == "align" {
    if self.next_nl() != TInt {
      raise self.error("alignment expected")
    }
    let align_val = parse_int64(self.tokens[self.pos - 1].raw)
    self.datas.push(@types.Dat::align(align_val))
    t = self.next_nl()
  }
  // Emit DName
  self.datas.push(@types.Dat::name(name, is_export))
  // Parse data body: { ... }
  if t != TLbr {
    raise self.error("expected data contents in { .. }")
  }
  while true {
    let t2 = self.next_nl()
    match t2 {
      TRbr =>
        // End of data
        break
      TId => {
        // Size specifier: b, h, w, l, s, d, z
        let spec = self.tokens[self.pos - 1].raw
        let dk : @types.DatKind = match spec {
          "l" => @types.DL
          "w" => @types.DW
          "h" => @types.DH
          "b" => @types.DB
          "s" => @types.DW // single float treated as word size
          "d" => @types.DL // double float treated as long size
          "z" => @types.DZ
          _ => raise self.error("invalid size specifier \{spec}")
        }
        // Parse values for this size
        let mut t3 = self.next_nl()
        let mut done = false
        while !done {
          let dat : @types.Dat = match t3 {
            TFlt => {
              let raw = self.tokens[self.pos - 1].raw
              let is_single = raw.length() > 0 && raw[0] == 's'
              let num_str = raw[2:].to_owned()
              let (fval, err_msg) = try @string.parse_double(num_str) catch {
                _ => (0.0, "Invalid floating-point literal")
              } noraise {
                n => (n, "")
              }
              if !err_msg.is_empty() {
                raise self.error(err_msg)
              }
              if is_single {
                @types.Dat::{
                  kind: dk,
                  num: 0,
                  fltd: 0.0,
                  flts: Float::from_double(fval),
                  str: "",
                  ref_name: "",
                  ref_offset: 0,
                  is_ref: false,
                  is_str: false,
                  is_export: false,
                }
              } else {
                @types.Dat::{
                  kind: dk,
                  num: 0,
                  fltd: fval,
                  flts: 0.0,
                  str: "",
                  ref_name: "",
                  ref_offset: 0,
                  is_ref: false,
                  is_str: false,
                  is_export: false,
                }
              }
            }
            TInt => {
              let val = parse_int64(self.tokens[self.pos - 1].raw)
              @types.Dat::{
                kind: dk,
                num: val,
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
            TGlo => {
              // Reference to a global symbol
              let ref_name = self.tokens[self.pos - 1].raw
              @types.Dat::ref_to(ref_name, 0L)
            }
            TStr => {
              // String literal
              let str_val = self.tokens[self.pos - 1].raw
              @types.Dat::string(str_val)
            }
            _ => raise self.error("constant literal expected")
          }
          // Set the correct data kind for this value
          if !dat.is_ref && !dat.is_str {
            dat.kind = dk
          }
          self.datas.push(dat)
          t3 = self.next_nl()
          match t3 {
            TInt | TFlt => continue
            _ => done = true
          }
        }
        // After value list
        match t3 {
          TRbr => break
          TCom =>
            // Continue to next size specifier
            continue
          _ => raise self.error(", or } expected")
        }
      }
      _ => raise self.error("invalid size specifier in data")
    }
  }
  // Emit DEnd
  self.datas.push(@types.Dat::end())
}

///|
// Parse a type definition: type :name = [align N] { fields }
fn Parser::parsetyp(self : Self) -> Unit raise {
  // Create the type
  let ty = @types.Typ::new("")
  ty.align = -1
  // Parse type name: :name =
  if self.next_nl() != TTyp {
    raise self.error("type name expected")
  }
  ty.name = self.tokens[self.pos - 1].raw
  if self.next_nl() != TEq {
    raise self.error("= expected after type name")
  }
  // Optional: align N
  let mut t = self.next_nl()
  if t == TId && self.tokens[self.pos - 1].raw == "align" {
    if self.next_nl() != TInt {
      raise self.error("alignment expected")
    }
    let align_val = parse_int64(self.tokens[self.pos - 1].raw)
    // Convert alignment value to log2
    let mut al = 0
    let mut v = align_val
    while v > 1L {
      v = v / 2L
      al = al + 1
    }
    ty.align = al
    t = self.next_nl()
  }
  // Parse type body: { ... }
  if t != TLbr {
    raise self.error("type body must start with {")
  }
  t = self.next_nl()
  // Check for dark type: { N }
  if t == TInt {
    ty.dark = 1
    ty.size = parse_int64(self.tokens[self.pos - 1].raw)
    if ty.align == -1 {
      raise self.error("dark types need alignment")
    }
    if self.next_nl() != TRbr {
      raise self.error("} expected")
    }
    self.typs.push(ty)
    return
  }
  // Parse fields
  let mut nunion = 0
  if t == TLbr {
    // Union type: { { fields } { fields } ... }
    while true {
      if t != TLbr {
        raise self.error("invalid union member")
      }
      self.parsefields(ty, self.next_nl())
      nunion = nunion + 1
      t = self.next_nl()
      if t == TRbr {
        break
      }
    }
  } else {
    // Single struct: { fields }
    self.parsefields(ty, t)
    nunion = 1
  }
  ty.nunion = nunion
  self.typs.push(ty)
}

///|
// Parse type fields
// ty: the type being built (for size/alignment calculation)
// t: the first token of the first field
fn Parser::parsefields(
  self : Self,
  ty : @types.Typ,
  t : @lexer.TokenKind,
) -> Unit raise {
  let mut t = t
  let mut sz : Int64 = 0L
  let mut al = ty.align
  while true {
    if t == TRbr {
      break
    }
    // Parse field type
    let (ftype, fs, fa, fty_idx) : (@types.FieldType, Int64, Int, Int) = match
      t {
      TId =>
        match self.tokens[self.pos - 1].raw {
          "b" => (@types.Fb, 1L, 0, -1)
          "h" => (@types.Fh, 2L, 1, -1)
          "w" => (@types.Fw, 4L, 2, -1)
          "l" => (@types.Fl, 8L, 3, -1)
          "s" => (@types.Fs, 4L, 2, -1)
          "d" => (@types.Fd, 8L, 3, -1)
          _ => raise self.error("invalid type member specifier")
        }
      TTyp => {
        // :type reference
        let ty_idx = self.findtyp(self.tokens[self.pos - 1].raw)
        let ref_ty = self.typs[ty_idx]
        (@types.FTyp, ref_ty.size, ref_ty.align, ty_idx)
      }
      _ => raise self.error("invalid type member specifier")
    }
    if fa > al {
      al = fa
    }
    // Handle alignment padding
    let a = sz & (fs - 1L)
    if a != 0L {
      let pad = fs - a
      ty.fields.push(@types.Field::new(@types.FPad, pad.to_int()))
      sz = sz + pad
    }
    // Parse count (default 1)
    t = self.next_nl()
    let c : Int = if t == TInt {
      let count = parse_int64(self.tokens[self.pos - 1].raw)
      t = self.next_nl()
      count.to_int()
    } else {
      1
    }
    sz = sz + fs * c.to_int64()
    // Add fields
    let field_len = if ftype == @types.FTyp {
      // For type references, len is the type index
      fty_idx
    } else {
      fs.to_int()
    }
    for _ in 0..<c {
      ty.fields.push(@types.Field::new(ftype, field_len))
    }
    if t != TCom {
      break
    }
    t = self.next_nl()
  }
  // Finalize type
  ty.fields.push(@types.Field::end())
  let a = 1 << al
  if sz < ty.size {
    sz = ty.size
  }
  ty.size = (sz + (a - 1).to_int64()) & (0 - a).to_int64()
  ty.align = al
}
