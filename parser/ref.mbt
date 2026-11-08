///|
// Parse a class specifier: w, l, s, d, or :type
// Returns (Class, type_index) where type_index is -1 if not a type class
// and Class::Kx with type_index set if it's a :type reference
// Returns (Class, type_index, subword_index): subword_index is -1 for the
// ordinary classes and 0..3 for sb/ub/sh/uh (C parsecls returns Ksb..Kuh).
fn Parser::parsecls(self : Self) -> (@types.Class, Int32, Int32) raise {
  let t = self.next()
  match t.kind {
    TTyp => {
      // :type reference - find the type
      let ty = self.findtyp(t.raw)
      (@types.Kx, ty, -1)
    }
    TId =>
      match t.raw {
        "w" => (@types.Kw, -1, -1)
        "l" => (@types.Kl, -1, -1)
        "s" => (@types.Ks, -1, -1)
        "d" => (@types.Kd, -1, -1)
        "sb" => (@types.Kw, -1, 0)
        "ub" => (@types.Kw, -1, 1)
        "sh" => (@types.Kw, -1, 2)
        "uh" => (@types.Kw, -1, 3)
        _ => raise self.error("invalid class specifier \{t.raw}")
      }
    _ => raise self.error("invalid class specifier")
  }
}

///|
// Find a type by name, returns its index or raises error
fn Parser::findtyp(self : Self, name : String) -> Int32 raise {
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
  // C parseref: extern/thread prefixes may precede a global (and may repeat).
  let mut sym_type = 0
  let mut t = self.next()
  let mut prefixes = true
  while prefixes {
    match t.kind {
      TExtern => {
        sym_type = sym_type | @types.SYM_EXT
        t = self.next()
      }
      TThread => {
        sym_type = sym_type | @types.SYM_THR
        t = self.next()
      }
      _ => prefixes = false
    }
  }
  if sym_type != 0 && t.kind != TGlo {
    return @types.Ref::none()
  }
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
      // Float literal (s_ or d_ prefix), including C99 hexadecimal floats.
      let raw = t.raw
      let is_single = raw.length() > 0 && raw[0] == 's'
      let (fval, fval_s, err_msg) = parse_float_literal(raw)
      if !err_msg.is_empty() {
        raise self.error(err_msg)
      }
      if is_single {
        let con = @types.Con::single(fval_s)
        @types.Ref::con(self.curfn().get_con_by(con))
      } else {
        let con = @types.Con::double(fval)
        @types.Ref::con(self.curfn().get_con_by(con))
      }
    }
    TGlo => {
      // Global symbol address
      let label = self.interner.intern(t.raw)
      let con = @types.Con::addr_sym(label, sym_type)
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
