///|
// Constant folding of individual operations - corresponds to the "boring
// folding code" in fold.c (foldint/foldflt/opfold).

///|
fn is_word_cmp(op : @types.Op) -> Bool {
  let i = @types.op_index(op)
  i >= @types.op_index(@types.Ceqw) && i <= @types.op_index(@types.Cultw)
}

///|
fn is_long_cmp(op : @types.Op) -> Bool {
  let i = @types.op_index(op)
  i >= @types.op_index(@types.Ceql) && i <= @types.op_index(@types.Cultl)
}

///|
fn is_single_cmp(op : @types.Op) -> Bool {
  let i = @types.op_index(op)
  i >= @types.op_index(@types.Ceqs) && i <= @types.op_index(@types.Cuos)
}

///|
fn is_double_cmp(op : @types.Op) -> Bool {
  let i = @types.op_index(op)
  i >= @types.op_index(@types.Ceqd) && i <= @types.op_index(@types.Cuod)
}

///|
// Sign-extend the low 32 bits (C (int32_t) cast).
fn sext32(v : Int64) -> Int64 {
  v << 32 >> 32
}

///|
// The double value of a con (C union's .fd view of the raw bits).
fn con_double(c : @types.Con) -> Double {
  @types.con_raw_bits(c).reinterpret_as_double()
}

///|
// The single value of a con (C union's .fs view of the raw bits).
fn con_single(c : @types.Con) -> Float {
  let i = @types.con_raw_bits(c)
  let u : UInt = (i & 0xFFFFFFFF).reinterpret_as_uint64().to_uint()
  Float::reinterpret_from_uint(u)
}

///|
// Fold an integer operation. Returns (is_bot, con). w: true for long.
fn foldint(
  op : @types.Op,
  w : Bool,
  cl : @types.Con,
  cr : @types.Con,
) -> (Bool, @types.Con) {
  let l = cl.bits.i
  let r = cr.bits.i
  let mut typ = @types.CBits
  let mut lab = 0
  if op == @types.Add {
    if cl.kind == @types.CAddr {
      if cr.kind == @types.CAddr {
        abort("undefined addition (addr + addr)")
      }
      lab = cl.label
      typ = @types.CAddr
    } else if cr.kind == @types.CAddr {
      lab = cr.label
      typ = @types.CAddr
    }
  } else if op == @types.Sub {
    if cl.kind == @types.CAddr {
      if cr.kind != @types.CAddr {
        lab = cl.label
        typ = @types.CAddr
      } else if cl.label != cr.label {
        abort("undefined substraction (addr1 - addr2)")
      }
    } else if cr.kind == @types.CAddr {
      abort("undefined substraction (num - addr)")
    }
  } else if cl.kind == @types.CAddr || cr.kind == @types.CAddr {
    if is_long_cmp(op) {
      return (true, @types.Con::new())
    }
    abort("invalid address operand")
  }
  let x : Int64 = if is_word_cmp(op) || is_long_cmp(op) {
    let ci = if is_word_cmp(op) {
      @types.op_index(op) - @types.op_index(@types.Ceqw)
    } else {
      @types.op_index(op) - @types.op_index(@types.Ceql)
    }
    let l = if is_word_cmp(op) { sext32(l) } else { l }
    let r = if is_word_cmp(op) { sext32(r) } else { r }
    match ci {
      0 => if l == r { 1L } else { 0L } // Cieq
      1 => if l != r { 1L } else { 0L } // Cine
      2 => if l >= r { 1L } else { 0L } // Cisge
      3 => if l > r { 1L } else { 0L } // Cisgt
      4 => if l <= r { 1L } else { 0L } // Cisle
      5 => if l < r { 1L } else { 0L } // Cislt
      6 =>
        if l.reinterpret_as_uint64() >= r.reinterpret_as_uint64() {
          1L
        } else {
          0L
        } // Ciuge
      7 =>
        if l.reinterpret_as_uint64() > r.reinterpret_as_uint64() {
          1L
        } else {
          0L
        } // Ciugt
      8 =>
        if l.reinterpret_as_uint64() <= r.reinterpret_as_uint64() {
          1L
        } else {
          0L
        } // Ciule
      _ =>
        if l.reinterpret_as_uint64() < r.reinterpret_as_uint64() {
          1L
        } else {
          0L
        } // Ciult
    }
  } else if is_single_cmp(op) {
    let ci = @types.op_index(op) - @types.op_index(@types.Ceqs)
    let ls = con_single(cl)
    let rs = con_single(cr)
    match ci {
      0 => if ls == rs { 1L } else { 0L } // Cfeq
      1 => if ls >= rs { 1L } else { 0L } // Cfge
      2 => if ls > rs { 1L } else { 0L } // Cfgt
      3 => if ls <= rs { 1L } else { 0L } // Cfle
      4 => if ls < rs { 1L } else { 0L } // Cflt
      5 => if ls != rs { 1L } else { 0L } // Cfne
      6 => if ls < rs || ls >= rs { 1L } else { 0L } // Cfo
      _ => if !(ls < rs || ls >= rs) { 1L } else { 0L } // Cfuo
    }
  } else if is_double_cmp(op) {
    let ci = @types.op_index(op) - @types.op_index(@types.Ceqd)
    let ld = con_double(cl)
    let rd = con_double(cr)
    match ci {
      0 => if ld == rd { 1L } else { 0L } // Cfeq
      1 => if ld >= rd { 1L } else { 0L } // Cfge
      2 => if ld > rd { 1L } else { 0L } // Cfgt
      3 => if ld <= rd { 1L } else { 0L } // Cfle
      4 => if ld < rd { 1L } else { 0L } // Cflt
      5 => if ld != rd { 1L } else { 0L } // Cfne
      6 => if ld < rd || ld >= rd { 1L } else { 0L } // Cfo
      _ => if !(ld < rd || ld >= rd) { 1L } else { 0L } // Cfuo
    }
  } else {
    match op {
      @types.Add => l + r
      @types.Sub => l - r
      @types.Div => l / r
      @types.Rem => l % r
      @types.Udiv =>
        (l.reinterpret_as_uint64() / r.reinterpret_as_uint64()).reinterpret_as_int64()
      @types.Urem =>
        (l.reinterpret_as_uint64() % r.reinterpret_as_uint64()).reinterpret_as_int64()
      @types.Mul => l * r
      @types.And => l & r
      @types.Or => l | r
      @types.Xor => l ^ r
      @types.Sar => l >> (r & 63).to_int()
      @types.Shr =>
        (l.reinterpret_as_uint64() >> (r & 63).to_int()).reinterpret_as_int64()
      @types.Shl => l << (r & 63).to_int()
      @types.Extsb => l << 56 >> 56
      @types.Extub => l & 0xFF
      @types.Extsh => l << 48 >> 48
      @types.Extuh => l & 0xFFFF
      @types.Extsw => l << 32 >> 32
      @types.Extuw => l & 0xFFFFFFFF
      @types.Stosi =>
        if w {
          con_single(cl).to_double().to_int64()
        } else {
          sext32(con_single(cl).to_double().to_int().to_int64())
        }
      @types.Dtosi =>
        if w {
          con_double(cl).to_int64()
        } else {
          sext32(con_double(cl).to_int().to_int64())
        }
      @types.Cast => {
        if cl.kind == @types.CAddr {
          lab = cl.label
          typ = @types.CAddr
        }
        l
      }
      _ => abort("unreachable")
    }
  }
  (
    false,
    @types.Con::{
      kind: typ,
      label: lab,
      bits: @types.ConBits::{ i: x, d: 0.0, s: 0.0 },
      flt: 0,
      is_local: false,
    },
  )
}

///|
fn foldflt(
  op : @types.Op,
  w : Bool,
  cl : @types.Con,
  cr : @types.Con,
) -> @types.Con {
  if cl.kind != @types.CBits || cr.kind != @types.CBits {
    abort("invalid address operand")
  }
  if w {
    let ld = con_double(cl)
    let rd = con_double(cr)
    let xd : Double = match op {
      @types.Add => ld + rd
      @types.Sub => ld - rd
      @types.Div => ld / rd
      @types.Mul => ld * rd
      @types.Swtof => sext32(cl.bits.i).to_double()
      @types.Sltof => cl.bits.i.to_double()
      @types.Exts => con_single(cl).to_double()
      @types.Cast => ld
      _ => abort("unreachable")
    }
    @types.Con::{
      kind: @types.CBits,
      label: 0,
      bits: @types.ConBits::{ i: 0, d: xd, s: 0.0 },
      flt: 2,
      is_local: false,
    }
  } else {
    let ls = con_single(cl)
    let rs = con_single(cr)
    let xs : Float = match op {
      @types.Add => ls + rs
      @types.Sub => ls - rs
      @types.Div => ls / rs
      @types.Mul => ls * rs
      @types.Swtof => Float::from_double(sext32(cl.bits.i).to_double())
      @types.Sltof => Float::from_double(cl.bits.i.to_double())
      @types.Truncd => Float::from_double(con_double(cl))
      @types.Cast => ls
      _ => abort("unreachable")
    }
    @types.Con::{
      kind: @types.CBits,
      label: 0,
      bits: @types.ConBits::{ i: 0, d: 0.0, s: xs },
      flt: 1,
      is_local: false,
    }
  }
}

///|
// Fold an operation on two constants; returns a con index or BOT.
fn opfold(
  st : FoldState,
  op : @types.Op,
  cls : @types.Class,
  cl : @types.Con,
  cr : @types.Con,
) -> Int {
  if (
      op == @types.Div ||
      op == @types.Udiv ||
      op == @types.Rem ||
      op == @types.Urem
    ) &&
    czero(cr, @types.kwide(cls) == 1) {
    abort("null divisor")
  }
  let (is_bot, c) = if cls == @types.Kw || cls == @types.Kl {
    foldint(op, cls == @types.Kl, cl, cr)
  } else {
    (false, foldflt(op, cls == @types.Kd, cl, cr))
  }
  if is_bot {
    return BOT
  }
  if c.kind == @types.CBits {
    if c.flt == 0 {
      st.fn_.get_con(c.bits.i)
    } else {
      st.fn_.get_con_by(c)
    }
  } else {
    st.fn_.add_con(c)
  }
}
