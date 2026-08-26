///|
// Parse a class specifier: w, l, s, d, or :type
// Returns (Class, type_index) where type_index is -1 if not a type class
// and Class::Kx with type_index set if it's a :type reference
fn Parser::parsecls(self : Self) -> (@types.Class, Int) raise {
  let t = self.next()
  match t.kind {
    TTyp => {
      // :type reference - find the type
      let ty = self.findtyp(t.raw)
      (@types.Kx, ty)
    }
    TId =>
      match t.raw {
        "w" => (@types.Kw, -1)
        "l" => (@types.Kl, -1)
        "s" => (@types.Ks, -1)
        "d" => (@types.Kd, -1)
        _ => raise self.error("invalid class specifier \{t.raw}")
      }
    _ => raise self.error("invalid class specifier")
  }
}

///|
// Find a type by name, returns its index or raises error
fn Parser::findtyp(self : Self, name : String) -> Int raise {
  let mut i = self.typs.length() - 1
  while i >= 0 {
    if self.typs[i].name == name {
      return i
    }
    i = i - 1
  }
  raise self.error("undefined type :\{name}")
}

///|
// Get or create a temporary reference by name
fn Parser::tmpref(self : Self, name : String) -> @types.Ref raise {
  let fn_ = self.curfn()
  // Look up existing user temporary by name (skip register temps 0..Tmp0-1)
  for i in @types.Tmp0..<fn_.ntmp() {
    if fn_.tmps[i].name == name {
      return @types.Ref::tmp(i)
    }
  }
  // Create new temporary with Kx class
  let id = fn_.add_tmp(name, @types.Kx)
  @types.Ref::tmp(id)
}

///|
// Parse a reference (temp, constant, global, int, float)
// Returns ref_none() if the token is not a valid reference
fn Parser::parseref(self : Self) -> @types.Ref raise {
  let t = self.next()
  match t.kind {
    TTemp =>
      // Temporary variable - look up or create
      self.tmpref(t.raw)
    TInt => {
      // Integer constant
      let val = parse_int64(t.raw)
      @types.Ref::con(self.curfn().get_con(val))
    }
    TFlt => {
      // Float literal (s_ or d_ prefix)
      let raw = t.raw
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
        let con = @types.Con::single(Float::from_double(fval))
        @types.Ref::con(self.curfn().get_con_by(con))
      } else {
        let con = @types.Con::double(fval)
        @types.Ref::con(self.curfn().get_con_by(con))
      }
    }
    TGlo => {
      // Global symbol address
      let label = self.interner.intern(t.raw)
      let con = @types.Con::addr(label)
      @types.Ref::con(self.curfn().get_con_by(con))
    }
    _ => @types.Ref::none()
  }
}

///|
// Parse an integer from string to Int64
fn parse_int64(s : String) -> Int64 {
  let mut result : Int64 = 0L
  let mut neg = false
  let mut i = 0
  let chars = s.to_array()
  if chars.length() > 0 && chars[0] == '-' {
    neg = true
    i = 1
  } else if chars.length() > 0 && chars[0] == '+' {
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      result = result * 10L + (c.to_int() - '0'.to_int()).to_int64()
      i = i + 1
    } else {
      break
    }
  }
  if neg {
    -result
  } else {
    result
  }
}
