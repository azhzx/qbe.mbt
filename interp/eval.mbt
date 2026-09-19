///|
// Instruction evaluation for the SSA interpreter. Integer semantics mirror
// the C QBE folder: word temporaries are kept sign-extended in 64 bits and
// word arithmetic truncates to 32 bits with sign extension.

///|
// Sign-extend the low 32 bits (C (int32_t) cast).
fn sext32(v : Int64) -> Int64 {
  v << 32 >> 32
}

///|
// Zero-extend the low 32 bits.
fn zx32(v : Int64) -> UInt64 {
  v.reinterpret_as_uint64() & 0xFFFFFFFFUL
}

///|
// Sign-extend the low 16 bits.
fn sext16(v : Int64) -> Int64 {
  v << 48 >> 48
}

///|
// Sign-extend the low 8 bits.
fn sext8(v : Int64) -> Int64 {
  v << 56 >> 56
}

///|
// The single-precision value stored in the low 32 bits.
fn bits_to_single(v : Int64) -> Float {
  let u : UInt = (v & 0xFFFFFFFFL).reinterpret_as_uint64().to_uint()
  Float::reinterpret_from_uint(u)
}

///|
fn bits_to_double(v : Int64) -> Double {
  v.reinterpret_as_double()
}

///|
// Evaluate a reference to a raw 64-bit word.
fn Interp::eval_ref(
  self : Interp,
  frame : Frame,
  r : @types.Ref,
) -> Int64 raise {
  match r {
    @types.RTmp(t) => frame.locals[t]
    @types.RCon(c) => {
      let con = frame.fn_.cons[c]
      match con.kind {
        @types.CBits => con.raw_bits()
        @types.CAddr => {
          let name = self.interner.get(con.label)
          match self.mem.symbols.get(name) {
            Some(addr) => addr.reinterpret_as_int64()
            None => self.code_of(name).reinterpret_as_int64()
          }
        }
        @types.CUndef => 0L
      }
    }
    _ =>
      raise @util.QbeError::CompileError(
        "interpreter: unsupported reference kind",
      )
  }
}

///|
// Evaluate an instruction to a raw 64-bit result word.
fn Interp::eval_ins(
  self : Interp,
  frame : Frame,
  ins : @types.Ins,
) -> Int64 raise {
  let k = ins.cls
  match ins.op {
    @types.Copy => self.eval_ref(frame, ins.arg1)
    // loads
    @types.Loadsb
    | @types.Loadub
    | @types.Loadsh
    | @types.Loaduh
    | @types.Loadsw
    | @types.Loaduw
    | @types.Load => {
      let addr = self.eval_ref(frame, ins.arg1).reinterpret_as_uint64()
      match ins.op {
        @types.Loadsb => sext8(self.mem.load_int(addr, 1))
        @types.Loadub => self.mem.load_int(addr, 1)
        @types.Loadsh => sext16(self.mem.load_int(addr, 2))
        @types.Loaduh => self.mem.load_int(addr, 2)
        @types.Loadsw => sext32(self.mem.load_int(addr, 4))
        @types.Loaduw => self.mem.load_int(addr, 4)
        // generic load: width from the class
        _ =>
          match k {
            @types.Kw => sext32(self.mem.load_int(addr, 4))
            @types.Ks => self.mem.load_int(addr, 4)
            @types.Kd => self.mem.load_int(addr, 8)
            _ => self.mem.load_int(addr, 8)
          }
      }
    }
    // stores
    @types.Storeb
    | @types.Storeh
    | @types.Storew
    | @types.Storel
    | @types.Stores
    | @types.Stored => {
      let addr = self.eval_ref(frame, ins.arg2).reinterpret_as_uint64()
      let v = self.eval_ref(frame, ins.arg1)
      let n = match ins.op {
        @types.Storeb => 1
        @types.Storeh => 2
        @types.Storew => 4
        @types.Stores => 4
        _ => 8
      }
      self.mem.store_int(addr, v, n)
      0L
    }
    // everything else is a pure operation on two operands (unary ops
    // leave arg2 as RNone)
    _ => {
      let a = self.eval_ref(frame, ins.arg1)
      let b = if ins.arg2.is_none() {
        0L
      } else {
        self.eval_ref(frame, ins.arg2)
      }
      self.eval_op(ins.op, k, a, b)
    }
  }
}

///|
// Evaluate a pure integer/float operation on raw words.
fn Interp::eval_op(
  self : Interp,
  op : @types.Op,
  k : @types.Class,
  a : Int64,
  b : Int64,
) -> Int64 raise {
  let is_word = k == @types.Kw
  // Conversions are dispatched by their result class, not the source
  // floating-point class.
  match op {
    @types.Stosi => {
      let v = bits_to_single(a).to_double().to_int64()
      return if is_word { sext32(v) } else { v }
    }
    @types.Dtosi => {
      let v = bits_to_double(a).to_int().to_int64()
      return if is_word { sext32(v) } else { v }
    }
    @types.Exts => return bits_to_single(a).to_double().reinterpret_as_int64()
    @types.Truncd =>
      return Float::from_double(bits_to_double(a))
        .reinterpret_as_uint()
        .to_int64()
    _ => ()
  }
  match op {
    @types.Ceqs
    | @types.Cnes
    | @types.Cles
    | @types.Clts
    | @types.Cges
    | @types.Cgts
    | @types.Cos
    | @types.Cuos => return self.eval_float_op(op, @types.Ks, a, b)
    @types.Ceqd
    | @types.Cned
    | @types.Cled
    | @types.Cltd
    | @types.Cged
    | @types.Cgtd
    | @types.Cod
    | @types.Cuod => return self.eval_float_op(op, @types.Kd, a, b)
    _ => ()
  }
  if k.base() == 1 {
    return self.eval_float_op(op, k, a, b)
  }
  let l = if is_word { sext32(a) } else { a }
  let r = if is_word { sext32(b) } else { b }
  match op {
    @types.Add => {
      let v = l + r
      if is_word {
        sext32(v)
      } else {
        v
      }
    }
    @types.Sub => {
      let v = l - r
      if is_word {
        sext32(v)
      } else {
        v
      }
    }
    @types.Mul => {
      let v = l * r
      if is_word {
        sext32(v)
      } else {
        v
      }
    }
    @types.Div => {
      if r == 0L {
        raise @util.QbeError::CompileError("interpreter: division by zero")
      }
      let v = if is_word { sext32(l / r) } else { l / r }
      v
    }
    @types.Rem => {
      if r == 0L {
        raise @util.QbeError::CompileError("interpreter: remainder by zero")
      }
      if is_word {
        sext32(l % r)
      } else {
        l % r
      }
    }
    @types.Udiv => {
      if (zx32(b) == 0UL && is_word) || b == 0L {
        raise @util.QbeError::CompileError("interpreter: division by zero")
      }
      if is_word {
        (zx32(a) / zx32(b)).reinterpret_as_int64()
      } else {
        (a.reinterpret_as_uint64() / b.reinterpret_as_uint64()).reinterpret_as_int64()
      }
    }
    @types.Urem => {
      if (zx32(b) == 0UL && is_word) || b == 0L {
        raise @util.QbeError::CompileError("interpreter: remainder by zero")
      }
      if is_word {
        (zx32(a) % zx32(b)).reinterpret_as_int64()
      } else {
        (a.reinterpret_as_uint64() % b.reinterpret_as_uint64()).reinterpret_as_int64()
      }
    }
    @types.And => l & r
    @types.Or => l | r
    @types.Xor => l ^ r
    @types.Sar => {
      let v = l >> ((r & 63L).to_int() & (if is_word { 31 } else { 63 }))
      v
    }
    @types.Shr => {
      let sh = (r & 63L).to_int() & (if is_word { 31 } else { 63 })
      let v = if is_word {
        (zx32(a) >> sh).reinterpret_as_int64()
      } else {
        (a.reinterpret_as_uint64() >> sh).reinterpret_as_int64()
      }
      if is_word {
        sext32(v)
      } else {
        v
      }
    }
    @types.Shl => {
      let sh = (r & 63L).to_int() & (if is_word { 31 } else { 63 })
      let v = a << sh
      if is_word {
        sext32(v)
      } else {
        v
      }
    }
    @types.Extsb => sext8(a)
    @types.Extub => a & 0xFF
    @types.Extsh => sext16(a)
    @types.Extuh => a & 0xFFFF
    @types.Extsw => sext32(a)
    @types.Extuw => a & 0xFFFFFFFF
    // comparisons: QBE compares produce words (0/1)
    @types.Ceqw | @types.Ceql => if l == r { 1L } else { 0L }
    @types.Cnew | @types.Cnel => if l != r { 1L } else { 0L }
    @types.Csgew | @types.Csgel => if l >= r { 1L } else { 0L }
    @types.Csgtw | @types.Csgtl => if l > r { 1L } else { 0L }
    @types.Cslew | @types.Cslel => if l <= r { 1L } else { 0L }
    @types.Csltw | @types.Csltl => if l < r { 1L } else { 0L }
    @types.Cugew | @types.Cugel =>
      if a.reinterpret_as_uint64() >= b.reinterpret_as_uint64() {
        1L
      } else {
        0L
      }
    @types.Cugtw | @types.Cugtl =>
      if a.reinterpret_as_uint64() > b.reinterpret_as_uint64() {
        1L
      } else {
        0L
      }
    @types.Culew | @types.Culel =>
      if a.reinterpret_as_uint64() <= b.reinterpret_as_uint64() {
        1L
      } else {
        0L
      }
    @types.Cultw | @types.Cultl =>
      if a.reinterpret_as_uint64() < b.reinterpret_as_uint64() {
        1L
      } else {
        0L
      }
    // float comparisons are dispatched on the class by eval_float_op;
    // reaching them here means an integer class mismatch
    @types.Ceqs
    | @types.Cnes
    | @types.Cles
    | @types.Clts
    | @types.Cges
    | @types.Cgts
    | @types.Cos
    | @types.Cuos
    | @types.Ceqd
    | @types.Cned
    | @types.Cled
    | @types.Cltd
    | @types.Cged
    | @types.Cgtd
    | @types.Cod
    | @types.Cuod => self.eval_float_op(op, k, a, b)
    // conversions
    @types.Cast => a
    _ =>
      raise @util.QbeError::CompileError(
        "interpreter: unsupported operation \{op.name()}",
      )
  }
}

///|
// Evaluate a floating point operation (single or double).
fn Interp::eval_float_op(
  self : Interp,
  op : @types.Op,
  k : @types.Class,
  a : Int64,
  b : Int64,
) -> Int64 raise {
  let single = k == @types.Ks
  // int -> float conversions
  match op {
    @types.Swtof => {
      let i = sext32(a)
      let v = if single {
        Float::from_int(i.to_int()).reinterpret_as_uint().to_int64()
      } else {
        i.to_int().to_double().reinterpret_as_int64()
      }
      return v
    }
    @types.Sltof => {
      let v = if single {
        Float::from_int(a.to_int()).reinterpret_as_uint().to_int64()
      } else {
        a.to_int().to_double().reinterpret_as_int64()
      }
      return v
    }
    _ => ()
  }
  if single {
    let x = bits_to_single(a)
    let y = bits_to_single(b)
    match op {
      @types.Add => (x + y).reinterpret_as_uint().to_int64()
      @types.Sub => (x - y).reinterpret_as_uint().to_int64()
      @types.Mul => (x * y).reinterpret_as_uint().to_int64()
      @types.Div => (x / y).reinterpret_as_uint().to_int64()
      @types.Ceqs => if x == y { 1L } else { 0L }
      @types.Cnes => if x != y { 1L } else { 0L }
      @types.Cles => if x <= y { 1L } else { 0L }
      @types.Clts => if x < y { 1L } else { 0L }
      @types.Cges => if x >= y { 1L } else { 0L }
      @types.Cgts => if x > y { 1L } else { 0L }
      @types.Cos => if x < y || x >= y { 1L } else { 0L }
      @types.Cuos => if !(x < y || x >= y) { 1L } else { 0L }
      _ =>
        raise @util.QbeError::CompileError(
          "interpreter: unsupported single operation \{op.name()}",
        )
    }
  } else {
    let x = bits_to_double(a)
    let y = bits_to_double(b)
    match op {
      @types.Add => (x + y).reinterpret_as_int64()
      @types.Sub => (x - y).reinterpret_as_int64()
      @types.Mul => (x * y).reinterpret_as_int64()
      @types.Div => (x / y).reinterpret_as_int64()
      @types.Ceqd => if x == y { 1L } else { 0L }
      @types.Cned => if x != y { 1L } else { 0L }
      @types.Cled => if x <= y { 1L } else { 0L }
      @types.Cltd => if x < y { 1L } else { 0L }
      @types.Cged => if x >= y { 1L } else { 0L }
      @types.Cgtd => if x > y { 1L } else { 0L }
      @types.Cod => if x < y || x >= y { 1L } else { 0L }
      @types.Cuod => if !(x < y || x >= y) { 1L } else { 0L }
      _ =>
        raise @util.QbeError::CompileError(
          "interpreter: unsupported double operation \{op.name()}",
        )
    }
  }
}
