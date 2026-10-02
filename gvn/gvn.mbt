// Package gvn ports QBE's gvn.c (global value numbering) and gcm.c (global
// code motion).  The two passes share a package: gcm.mbt defines pinned,
// which gvn.mbt uses.
//
// The port follows the C reference closely, adapted to this project's IR:
// instructions live in Blk.ins arrays (not linked lists) and uses are
// Use records holding (block id, instruction index, argument number).

///|
// Constant indices 0 and 1 for the current function (C gvn.c con01[]).
let con01 : Array[@types.Ref] = Array::make(2, @types.Ref::none())

// ---------------------------------------------------------------------------
// Ref helpers (mirror C rtype/rsval)
// ---------------------------------------------------------------------------

///|
fn rtype_of(r : @types.Ref) -> Int {
  match r {
    @types.RNone => -1
    @types.RTmp(_) => 0
    @types.RCon(_) => 1
    @types.RInt(_) => 2
    @types.RType(_) => 3
    @types.RSlot(_) => 4
    @types.RCall(_) => 5
    @types.RMem(_) => 6
  }
}

///|
fn rval_of(r : @types.Ref) -> Int {
  match r {
    @types.RNone => 0
    @types.RTmp(v) => v
    @types.RCon(v) => v
    @types.RInt(v) => v
    @types.RType(v) => v
    @types.RSlot(v) => v
    @types.RCall(v) => v
    @types.RMem(v) => v
  }
}

///|
// Instruction copy (C shallow struct copy).
fn ins_copy(i : @types.Ins) -> @types.Ins {
  @types.Ins::new(i.op, i.cls, i.to, i.arg1, i.arg2)
}

///|
fn nop_ins() -> @types.Ins {
  @types.Ins::new_void(
    @types.Nop,
    @types.Kw,
    @types.Ref::none(),
    @types.Ref::none(),
  )
}

// ---------------------------------------------------------------------------
// optab flag helpers (the port's OpInfo does not expose the gvn/gcm flags)
// ---------------------------------------------------------------------------

///|
fn op_commutes(op : @types.Op) -> Bool {
  match op {
    @types.Add
    | @types.Mul
    | @types.And
    | @types.Or
    | @types.Xor
    | @types.Ceqw
    | @types.Cnew
    | @types.Ceql
    | @types.Cnel
    | @types.Ceqs
    | @types.Cnes
    | @types.Cos
    | @types.Cuos
    | @types.Ceqd
    | @types.Cned
    | @types.Cod
    | @types.Cuod => true
    _ => false
  }
}

///|
fn op_assoc(op : @types.Op) -> Bool {
  match op {
    @types.Add | @types.And | @types.Or | @types.Xor => true
    _ => false
  }
}

///|
fn op_hasid(op : @types.Op) -> Bool {
  match op {
    @types.Add
    | @types.Sub
    | @types.Div
    | @types.Udiv
    | @types.Mul
    | @types.Or
    | @types.Xor
    | @types.Sar
    | @types.Shr
    | @types.Shl
    | @types.Ceqw
    | @types.Cnew => true
    _ => false
  }
}

///|
fn op_idval(op : @types.Op) -> Int {
  match op {
    @types.Div | @types.Udiv | @types.Mul | @types.Ceqw => 1
    _ => 0
  }
}

///|
fn op_idemp(op : @types.Op) -> Bool {
  match op {
    @types.And | @types.Or => true
    _ => false
  }
}

///|
fn op_cmpeqwl(op : @types.Op) -> Bool {
  match op {
    @types.Ceqw | @types.Cnew | @types.Ceql | @types.Cnel => true
    _ => false
  }
}

///|
fn op_cmplgtewl(op : @types.Op) -> Bool {
  match op {
    @types.Csgew
    | @types.Csgtw
    | @types.Cslew
    | @types.Csltw
    | @types.Cugew
    | @types.Cugtw
    | @types.Culew
    | @types.Cultw
    | @types.Csgel
    | @types.Csgtl
    | @types.Cslel
    | @types.Csltl
    | @types.Cugel
    | @types.Cugtl
    | @types.Culel
    | @types.Cultl => true
    _ => false
  }
}

///|
fn op_eqval(op : @types.Op) -> Int {
  match op {
    @types.Ceqw
    | @types.Ceql
    | @types.Csgew
    | @types.Cslew
    | @types.Cugew
    | @types.Culew
    | @types.Csgel
    | @types.Cslel
    | @types.Cugel
    | @types.Culel => 1
    _ => 0
  }
}

///|
fn is_word_cmp(op : @types.Op) -> Bool {
  let i = op.index()
  i >= @types.Ceqw.index() && i <= @types.Cultw.index()
}

///|
fn is_long_cmp(op : @types.Op) -> Bool {
  let i = op.index()
  i >= @types.Ceql.index() && i <= @types.Cultl.index()
}

///|
fn is_single_cmp(op : @types.Op) -> Bool {
  let i = op.index()
  i >= @types.Ceqs.index() && i <= @types.Cuos.index()
}

///|
fn is_double_cmp(op : @types.Op) -> Bool {
  let i = op.index()
  i >= @types.Ceqd.index() && i <= @types.Cuod.index()
}

///|
fn is_cmp_op(op : @types.Op) -> Bool {
  is_word_cmp(op) || is_long_cmp(op) || is_single_cmp(op) || is_double_cmp(op)
}

///|
// C argcls(i, n) == optab[i->op].argcls[n][i->cls].
fn argcls(i : @types.Ins, n : Int) -> Int {
  let info = @types.op_info(i.op)
  let c = i.cls.code()
  let idx = if c < 0 { 0 } else { c }
  let arr = if n == 0 { info.a0 } else { info.a1 }
  if idx < arr.length() {
    arr[idx]
  } else {
    -1
  }
}

///|
fn isconbits(fn_ : @types.Fn, r : @types.Ref) -> Int64? {
  match r {
    @types.RCon(v) => {
      let c = fn_.cons[v]
      if c.kind == @types.CBits {
        Some(c.bits.i)
      } else {
        None
      }
    }
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Extension descriptors (C ext() table)
// ---------------------------------------------------------------------------

///|
struct ExtInfo {
  zext : Bool
  nopw : Int
  usew : Int
}

///|
fn ext_of(i : @types.Ins) -> ExtInfo? {
  match i.op {
    @types.Extsb => Some(ExtInfo::{ zext: false, nopw: 7, usew: 8, })
    @types.Extub => Some(ExtInfo::{ zext: true, nopw: 8, usew: 8, })
    @types.Extsh => Some(ExtInfo::{ zext: false, nopw: 15, usew: 16, })
    @types.Extuh => Some(ExtInfo::{ zext: true, nopw: 16, usew: 16, })
    @types.Extsw => Some(ExtInfo::{ zext: false, nopw: 31, usew: 32, })
    @types.Extuw => Some(ExtInfo::{ zext: true, nopw: 32, usew: 32, })
    _ => None
  }
}

///|
fn bitwidth(v : UInt64) -> Int {
  let mut n = 0
  let mut v = v
  if v >> 32 != 0UL {
    n = n + 32
    v = v >> 32
  }
  if v >> 16 != 0UL {
    n = n + 16
    v = v >> 16
  }
  if v >> 8 != 0UL {
    n = n + 8
    v = v >> 8
  }
  if v >> 4 != 0UL {
    n = n + 4
    v = v >> 4
  }
  if v >> 2 != 0UL {
    n = n + 2
    v = v >> 2
  }
  if v >> 1 != 0UL {
    n = n + 1
    v = v >> 1
  }
  n + v.to_int()
}

///|
fn extcpy_width(w : Int) -> Int {
  match w {
    0 => 0
    1 => (1 << 1) | (1 << 3) | (1 << 5)
    2 => (1 << 2) | (1 << 4) | (1 << 6)
    3 => (1 << 3) | (1 << 5)
    4 => (1 << 4) | (1 << 6)
    5 => 1 << 5
    6 => 1 << 6
    _ => 0
  }
}

// ---------------------------------------------------------------------------
// Constant folding (C fold.c foldint/foldflt/opfold/foldref)
// ---------------------------------------------------------------------------

///|
fn sext32(v : Int64) -> Int64 {
  v << 32 >> 32
}

///|
fn low32u(v : Int64) -> UInt64 {
  v.reinterpret_as_uint64() & 0xFFFFFFFFUL
}

///|
fn con_single(c : @types.Con) -> Float {
  let i = c.raw_bits()
  let u : UInt = (i & 0xFFFFFFFF).reinterpret_as_uint64().to_uint()
  Float::reinterpret_from_uint(u)
}

///|
fn con_double(c : @types.Con) -> Double {
  c.raw_bits().reinterpret_as_double()
}

///|
fn c_iscon(c : @types.Con, w : Bool, k : Int64) -> Bool {
  if c.kind != @types.CBits {
    return false
  }
  if w {
    c.bits.i == k
  } else {
    (c.bits.i & 0xFFFFFFFF) == (k & 0xFFFFFFFF)
  }
}

///|
// C foldint: returns None when the reference would return nonzero (failure).
fn c_foldint(
  op : @types.Op,
  w : Bool,
  cl : @types.Con,
  cr : @types.Con,
) -> @types.Con? {
  let l = cl.bits.i
  let r = cr.bits.i
  let mut typ = @types.CBits
  let mut lab = 0
  if op == @types.Add {
    if cl.kind == @types.CAddr {
      if cr.kind == @types.CAddr {
        return None
      }
      typ = @types.CAddr
      lab = cl.label
    } else if cr.kind == @types.CAddr {
      typ = @types.CAddr
      lab = cr.label
    }
  } else if op == @types.Sub {
    if cl.kind == @types.CAddr {
      if cr.kind != @types.CAddr {
        typ = @types.CAddr
        lab = cl.label
      } else if cl.label != cr.label {
        return None
      }
    } else if cr.kind == @types.CAddr {
      return None
    }
  } else if cl.kind == @types.CAddr || cr.kind == @types.CAddr {
    return None
  }
  if op == @types.Div ||
    op == @types.Rem ||
    op == @types.Udiv ||
    op == @types.Urem {
    if c_iscon(cr, w, 0L) {
      return None
    }
    if op == @types.Div || op == @types.Rem {
      let x = if w { -9223372036854775808L } else { -2147483648L }
      if c_iscon(cr, w, -1L) && c_iscon(cl, w, x) {
        return None
      }
    }
  }
  let x : Int64 = if is_word_cmp(op) || is_long_cmp(op) {
    let l2 = if is_word_cmp(op) { sext32(l) } else { l }
    let r2 = if is_word_cmp(op) { sext32(r) } else { r }
    let ci = if is_word_cmp(op) {
      op.index() - @types.Ceqw.index()
    } else {
      op.index() - @types.Ceql.index()
    }
    match ci {
      0 => if l2 == r2 { 1L } else { 0L }
      1 => if l2 != r2 { 1L } else { 0L }
      2 => if l2 >= r2 { 1L } else { 0L }
      3 => if l2 > r2 { 1L } else { 0L }
      4 => if l2 <= r2 { 1L } else { 0L }
      5 => if l2 < r2 { 1L } else { 0L }
      6 =>
        if l2.reinterpret_as_uint64() >= r2.reinterpret_as_uint64() {
          1L
        } else {
          0L
        }
      7 =>
        if l2.reinterpret_as_uint64() > r2.reinterpret_as_uint64() {
          1L
        } else {
          0L
        }
      8 =>
        if l2.reinterpret_as_uint64() <= r2.reinterpret_as_uint64() {
          1L
        } else {
          0L
        }
      _ =>
        if l2.reinterpret_as_uint64() < r2.reinterpret_as_uint64() {
          1L
        } else {
          0L
        }
    }
  } else if is_single_cmp(op) {
    let ci = op.index() - @types.Ceqs.index()
    let ls = con_single(cl)
    let rs = con_single(cr)
    match ci {
      0 => if ls == rs { 1L } else { 0L }
      1 => if ls >= rs { 1L } else { 0L }
      2 => if ls > rs { 1L } else { 0L }
      3 => if ls <= rs { 1L } else { 0L }
      4 => if ls < rs { 1L } else { 0L }
      5 => if ls != rs { 1L } else { 0L }
      6 => if ls < rs || ls >= rs { 1L } else { 0L }
      _ => if !(ls < rs || ls >= rs) { 1L } else { 0L }
    }
  } else if is_double_cmp(op) {
    let ci = op.index() - @types.Ceqd.index()
    let ld = con_double(cl)
    let rd = con_double(cr)
    match ci {
      0 => if ld == rd { 1L } else { 0L }
      1 => if ld >= rd { 1L } else { 0L }
      2 => if ld > rd { 1L } else { 0L }
      3 => if ld <= rd { 1L } else { 0L }
      4 => if ld < rd { 1L } else { 0L }
      5 => if ld != rd { 1L } else { 0L }
      6 => if ld < rd || ld >= rd { 1L } else { 0L }
      _ => if !(ld < rd || ld >= rd) { 1L } else { 0L }
    }
  } else {
    let mask : UInt64 = if w { 63UL } else { 31UL }
    let sh = (r.reinterpret_as_uint64() & mask).to_int()
    match op {
      @types.Add => l + r
      @types.Sub => l - r
      @types.Div => if w { l / r } else { sext32(l) / sext32(r) }
      @types.Rem => if w { l % r } else { sext32(l) % sext32(r) }
      @types.Udiv =>
        if w {
          (l.reinterpret_as_uint64() / r.reinterpret_as_uint64()).reinterpret_as_int64()
        } else {
          (low32u(l) / low32u(r)).reinterpret_as_int64()
        }
      @types.Urem =>
        if w {
          (l.reinterpret_as_uint64() % r.reinterpret_as_uint64()).reinterpret_as_int64()
        } else {
          (low32u(l) % low32u(r)).reinterpret_as_int64()
        }
      @types.Mul => l * r
      @types.And => l & r
      @types.Or => l | r
      @types.Xor => l ^ r
      @types.Sar => if w { l >> sh } else { sext32(l) >> sh }
      @types.Shr =>
        if w {
          (l.reinterpret_as_uint64() >> sh).reinterpret_as_int64()
        } else {
          (low32u(l) >> sh).reinterpret_as_int64()
        }
      @types.Shl => (l.reinterpret_as_uint64() << sh).reinterpret_as_int64()
      @types.Extsb => l << 56 >> 56
      @types.Extub => l & 0xFF
      @types.Extsh => l << 48 >> 48
      @types.Extuh => l & 0xFFFF
      @types.Extsw => l << 32 >> 32
      @types.Extuw => l & 0xFFFFFFFF
      @types.Stosi =>
        if w {
          sext32(con_single(cl).to_double().to_int().to_int64())
        } else {
          con_single(cl).to_double().to_int64()
        }
      @types.Dtosi =>
        if w {
          sext32(con_double(cl).to_int().to_int64())
        } else {
          con_double(cl).to_int64()
        }
      @types.Cast => {
        if cl.kind == @types.CAddr {
          typ = @types.CAddr
          lab = cl.label
        }
        l
      }
      _ => return None
    }
  }
  Some(@types.Con::{
    kind: typ,
    label: lab,
    bits: @types.ConBits::{ i: x, d: 0.0, s: 0.0, },
    flt: 0,
    is_local: false,
  })
}

///|
fn c_foldflt(
  op : @types.Op,
  w : Bool,
  cl : @types.Con,
  cr : @types.Con,
) -> @types.Con? {
  if cl.kind != @types.CBits || cr.kind != @types.CBits {
    return None
  }
  if w {
    let ld = con_double(cl)
    let rd = con_double(cr)
    let xd = match op {
      @types.Add => ld + rd
      @types.Sub => ld - rd
      @types.Div => ld / rd
      @types.Mul => ld * rd
      @types.Swtof => sext32(cl.bits.i).to_double()
      @types.Sltof => cl.bits.i.to_double()
      @types.Exts => con_single(cl).to_double()
      @types.Cast => ld
      _ => return None
    }
    Some(@types.Con::{
      kind: @types.CBits,
      label: 0,
      bits: @types.ConBits::{ i: 0L, d: xd, s: 0.0, },
      flt: 2,
      is_local: false,
    })
  } else {
    let ls = con_single(cl)
    let rs = con_single(cr)
    let xs = match op {
      @types.Add => ls + rs
      @types.Sub => ls - rs
      @types.Div => ls / rs
      @types.Mul => ls * rs
      @types.Swtof => Float::from_double(sext32(cl.bits.i).to_double())
      @types.Sltof => Float::from_double(cl.bits.i.to_double())
      @types.Truncd => Float::from_double(con_double(cl))
      @types.Cast => ls
      _ => return None
    }
    Some(@types.Con::{
      kind: @types.CBits,
      label: 0,
      bits: @types.ConBits::{ i: 0L, d: 0.0, s: xs, },
      flt: 1,
      is_local: false,
    })
  }
}

///|
// C opfold: intern a folded constant.
fn c_opfold(
  fn_ : @types.Fn,
  op : @types.Op,
  cls : @types.Class,
  cl : @types.Con,
  cr : @types.Con,
) -> @types.Ref {
  let res = if cls == @types.Kw || cls == @types.Kl {
    c_foldint(op, cls == @types.Kl, cl, cr)
  } else {
    c_foldflt(op, cls == @types.Kd, cl, cr)
  }
  match res {
    None => @types.Ref::none()
    Some(c) => {
      let c2 = if cls.wide() == 0 {
        @types.Con::{
          kind: c.kind,
          label: c.label,
          bits: @types.ConBits::{
            i: c.bits.i & 0xFFFFFFFF,
            d: c.bits.d,
            s: c.bits.s,
          },
          flt: c.flt,
          is_local: c.is_local,
        }
      } else {
        c
      }
      @types.Ref::con(fn_.get_con_by(c2))
    }
  }
}

///|
// C foldref.
fn foldref(fn_ : @types.Fn, i : @types.Ins) -> @types.Ref {
  if !i.to.is_tmp() {
    return @types.Ref::none()
  }
  if @types.op_info(i.op).canfold {
    if !i.arg1.is_con() {
      return @types.Ref::none()
    }
    let cl = fn_.cons[i.arg1.con_val()]
    let rr = if i.arg2.is_none() { con01[0] } else { i.arg2 }
    if !rr.is_con() {
      return @types.Ref::none()
    }
    let cr = fn_.cons[rr.con_val()]
    return c_opfold(fn_, i.op, i.cls, cl, cr)
  }
  @types.Ref::none()
}

// ---------------------------------------------------------------------------
// GVN state
// ---------------------------------------------------------------------------

///|
struct GState {
  fn_ : @types.Fn
  mut tbl : Array[@types.Ins?]
  mut def_idx : Array[Int]
  mut phi_visit : Array[Int]
}

///|
fn GState::new(fn_ : @types.Fn) -> GState {
  GState::{ fn_, tbl: [], def_idx: [], phi_visit: Array::make(fn_.ntmp(), 0), }
}

///|
// Build tmp -> defining instruction index (within the defining block) map.
fn build_def_idx(st : GState) -> Unit {
  let fn_ = st.fn_
  let a : Array[Int] = Array::make(fn_.ntmp(), -1)
  for b_id in fn_.def_order {
    let b = fn_.blks[b_id]
    for idx in 0..<b.ins.length() {
      let to = b.ins[idx].to
      if to.is_tmp() {
        a[to.tmp_val()] = idx
      }
    }
  }
  st.def_idx = a
}

///|
fn clear_phi_visit(st : GState) -> Unit {
  for i in 0..<st.phi_visit.length() {
    st.phi_visit[i] = 0
  }
}

///|
fn find_phi(fn_ : @types.Fn, bid : Int, r : @types.Ref) -> Int {
  let phis = fn_.blks[bid].phi
  for pi in 0..<phis.length() {
    if phis[pi].to.eq(r) {
      return pi
    }
  }
  -1
}

///|
fn phiarg(p : @types.Phi, blk_id : Int) -> @types.Ref? {
  for a in p.args {
    if a.blk_id == blk_id {
      return Some(a.value)
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Width analysis (C copy.c dwl/uwl/usewidthle/defwidthle/isw1)
// ---------------------------------------------------------------------------

///|
fn dwl(st : GState, r : @types.Ref, w0 : Int) -> Bool {
  let fn_ = st.fn_
  match isconbits(fn_, r) {
    Some(v) => if bitwidth(v.reinterpret_as_uint64()) <= w0 { return true }
    None => ()
  }
  let mut w = w0
  if w <= 0 {
    return false
  }
  if !r.is_tmp() {
    return false
  }
  let tid = r.tmp_val()
  if fn_.tmps[tid].cls != @types.Kw {
    return false
  }
  let di = st.def_idx[tid]
  if di < 0 {
    let bid = fn_.tmps[tid].bid
    let pi = find_phi(fn_, bid, r)
    if pi < 0 {
      return false
    }
    let pv = st.phi_visit[r.tmp_val()]
    if pv != 0 && pv <= w {
      return true
    }
    st.phi_visit[r.tmp_val()] = w
    for a in fn_.blks[bid].phi[pi].args {
      if !dwl(st, a.value, w) {
        return false
      }
    }
    return true
  }
  let i = fn_.blks[fn_.tmps[tid].bid].ins[di]
  if i.op == @types.Copy {
    return dwl(st, i.arg1, w)
  }
  if i.op == @types.Shr || i.op == @types.Sar {
    match isconbits(fn_, i.arg2) {
      Some(v) =>
        if v > 0L && v <= 32L {
          if i.op == @types.Shr && w + v.to_int() >= 32 {
            return true
          }
          if w < 32 {
            if i.op == @types.Sar {
              w = if 31 < w + v.to_int() { 31 } else { w + v.to_int() }
            } else {
              w = if 32 < w + v.to_int() { 32 } else { w + v.to_int() }
            }
          }
        }
      None => ()
    }
    return dwl(st, i.arg1, w)
  }
  if is_cmp_op(i.op) {
    return w >= 1
  }
  if i.op == @types.And {
    if dwl(st, i.arg1, w) || dwl(st, i.arg2, w) {
      return true
    }
    return false
  }
  if i.op == @types.Or || i.op == @types.Xor {
    if dwl(st, i.arg1, w) && dwl(st, i.arg2, w) {
      return true
    }
    return false
  }
  match ext_of(i) {
    Some(e) => {
      if e.zext && e.usew <= w {
        return true
      }
      return dwl(st, i.arg1, if w < e.nopw { w } else { e.nopw })
    }
    None => ()
  }
  false
}

///|
fn defwidthle(st : GState, r : @types.Ref, w : Int) -> Bool {
  clear_phi_visit(st)
  dwl(st, r, w)
}

///|
fn uwl(st : GState, r : @types.Ref, w : Int) -> Bool {
  let fn_ = st.fn_
  if !r.is_tmp() {
    return false
  }
  let tid = r.tmp_val()
  let n = fn_.tmps[tid].nuse
  for k in 0..<n {
    let u = fn_.tmps[tid].uses[k]
    match u.kind {
      @types.UPhi => {
        let p = fn_.blks[u.blk_id].phi[u.ins_idx]
        if st.phi_visit[p.to.tmp_val()] != 0 || p.to.is_none() {
          continue
        }
        st.phi_visit[p.to.tmp_val()] = 1
        if uwl(st, p.to, w) {
          continue
        }
        return false
      }
      @types.UIns => {
        let i = fn_.blks[u.blk_id].ins[u.ins_idx]
        if i.op == @types.Copy {
          if uwl(st, i.to, w) {
            continue
          }
        }
        match ext_of(i) {
          Some(e) => {
            if e.usew <= w {
              continue
            }
            if uwl(st, i.to, w) {
              continue
            }
          }
          None => ()
        }
        if i.op == @types.And {
          let rc = if r.eq(i.arg1) { i.arg2 } else { i.arg1 }
          match isconbits(fn_, rc) {
            Some(v) => if bitwidth(v.reinterpret_as_uint64()) <= w { continue }
            None => ()
          }
        }
        return false
      }
      _ => return false
    }
  }
  true
}

///|
fn usewidthle(st : GState, r : @types.Ref, w : Int) -> Bool {
  clear_phi_visit(st)
  uwl(st, r, w)
}

///|
fn isw1(st : GState, r : @types.Ref) -> Bool {
  defwidthle(st, r, 1)
}

// ---------------------------------------------------------------------------
// Use maintenance (C adduse/replaceuse/replaceuses)
// ---------------------------------------------------------------------------

///|
fn gvn_adduse(
  fn_ : @types.Fn,
  t : Int,
  kind : @types.UseKind,
  blk_id : Int,
  ins_idx : Int,
  arg_num : Int,
) -> Unit {
  let tmp = fn_.tmps[t]
  tmp.nuse = tmp.nuse + 1
  tmp.uses.push(@types.Use::{ kind, blk_id, ins_idx, arg_num, })
}

///|
fn replaceuse(
  st : GState,
  u : @types.Use,
  r1 : @types.Ref,
  r2 : @types.Ref,
) -> Unit {
  let fn_ = st.fn_
  let b = fn_.blks[u.blk_id]
  let is_t2 = r2.is_tmp()
  match u.kind {
    @types.UPhi => {
      let p = b.phi[u.ins_idx]
      for n in 0..<p.args.length() {
        if p.args[n].value.eq(r1) {
          p.args[n].value = r2
        }
      }
      if is_t2 {
        gvn_adduse(fn_, r2.tmp_val(), @types.UPhi, b.id, u.ins_idx, 0)
      }
    }
    @types.UIns => {
      let i = b.ins[u.ins_idx]
      if i.arg1.eq(r1) {
        i.arg1 = r2
      }
      if i.arg2.eq(r1) {
        i.arg2 = r2
      }
      if is_t2 {
        gvn_adduse(fn_, r2.tmp_val(), @types.UIns, b.id, u.ins_idx, 0)
      }
    }
    @types.UJmp => {
      if b.jmp.arg.eq(r1) {
        b.jmp.arg = r2
      }
      if is_t2 {
        gvn_adduse(fn_, r2.tmp_val(), @types.UJmp, b.id, 0, 0)
      }
    }
    @types.UXXX => ()
  }
}

///|
fn replaceuses(st : GState, r1 : @types.Ref, r2 : @types.Ref) -> Unit {
  let fn_ = st.fn_
  let t1 = fn_.tmps[r1.tmp_val()]
  let n = t1.nuse
  for k in 0..<n {
    replaceuse(st, t1.uses[k], r1, r2)
  }
  t1.nuse = 0
}

///|
fn killins(st : GState, i : @types.Ins, r : @types.Ref) -> Unit {
  replaceuses(st, i.to, r)
  i.op = @types.Nop
  i.cls = @types.Kw
  i.to = @types.Ref::none()
  i.arg1 = @types.Ref::none()
  i.arg2 = @types.Ref::none()
}

// ---------------------------------------------------------------------------
// Controls: rcmp, cmpeqz, dom/zeroval, reaches
// ---------------------------------------------------------------------------

///|
fn rcmp(a : @types.Ref, b : @types.Ref) -> Int {
  let ta = rtype_of(a)
  let tb = rtype_of(b)
  if ta != tb {
    return ta - tb
  }
  rval_of(a) - rval_of(b)
}

///|
fn sdom_b(st : GState, b1 : Int, b2 : Int) -> Bool {
  if b1 == b2 {
    return false
  }
  let fn_ = st.fn_
  let mut b2 = b2
  while b2 >= 0 && fn_.blks[b2].rpo_id > fn_.blks[b1].rpo_id {
    b2 = fn_.blks[b2].idom
  }
  b2 == b1
}

///|
fn dom_b(st : GState, b1 : Int, b2 : Int) -> Bool {
  b1 == b2 || sdom_b(st, b1, b2)
}

///|
fn reachrec(st : GState, b : Int, to : Int) -> Bool {
  if b == to {
    return true
  }
  if b < 0 || b >= st.fn_.nblk() {
    return false
  }
  if st.fn_.blks[b].visit != 0 {
    return false
  }
  st.fn_.blks[b].visit = 1
  if reachrec(st, st.fn_.blks[b].jmp.s1, to) {
    return true
  }
  if reachrec(st, st.fn_.blks[b].jmp.s2, to) {
    return true
  }
  false
}

///|
fn reaches(st : GState, b : Int, to : Int) -> Bool {
  let r = reachrec(st, b, to)
  for id in 0..<st.fn_.nblk() {
    st.fn_.blks[id].visit = 0
  }
  r
}

///|
fn reachesnotvia(st : GState, b : Int, to : Int, excl : Int) -> Bool {
  st.fn_.blks[excl].visit = 1
  reaches(st, b, to)
}

///|
fn branchdom(st : GState, bif : Int, bbr1 : Int, bbr2 : Int, b : Int) -> Bool {
  if b != bif && dom_b(st, bbr1, b) && !reachesnotvia(st, bbr2, b, bif) {
    return true
  }
  false
}

///|
fn domzero(st : GState, d : Int, b : Int) -> Int? {
  let db = st.fn_.blks[d]
  if branchdom(st, d, db.jmp.s1, db.jmp.s2, b) {
    return Some(0)
  }
  if branchdom(st, d, db.jmp.s2, db.jmp.s1, b) {
    return Some(1)
  }
  None
}

///|
fn cmpeqz(st : GState, r : @types.Ref) -> (@types.Ref, Int, Int)? {
  let fn_ = st.fn_
  if !r.is_tmp() {
    return None
  }
  let tid = r.tmp_val()
  let di = st.def_idx[tid]
  if di < 0 {
    return None
  }
  let i = fn_.blks[fn_.tmps[tid].bid].ins[di]
  if op_cmpeqwl(i.op) {
    if i.arg2.eq(con01[0]) {
      return Some((i.arg1, argcls(i, 0), op_eqval(i.op)))
    }
  }
  None
}

///|
fn zeroval(st : GState, b : Int, r : @types.Ref, cls : Int) -> Int? {
  let fn_ = st.fn_
  let mut d = fn_.blks[b].idom
  while d >= 0 {
    let db = fn_.blks[d]
    if db.jmp.kind == @types.Jjnz {
      if r.eq(db.jmp.arg) && cls == 0 {
        match domzero(st, d, b) {
          Some(z) => return Some(z)
          None => ()
        }
      }
      match cmpeqz(st, db.jmp.arg) {
        Some((arg, cls1, eqval)) =>
          if r.eq(arg) && cls == cls1 {
            match domzero(st, d, b) {
              Some(z) => return Some(eqval ^ z)
              None => ()
            }
          }
        None => ()
      }
    }
    d = db.idom
  }
  None
}

///|
fn usecls(st : GState, u : @types.Use, r : @types.Ref, cls : Int) -> Int {
  match u.kind {
    @types.UIns => {
      let i = st.fn_.blks[u.blk_id].ins[u.ins_idx]
      let mut k = -1
      if i.arg1.eq(r) {
        k = argcls(i, 0)
      }
      if i.arg2.eq(r) {
        if k == -1 || (k & 1) == 0 {
          k = argcls(i, 1)
        }
      }
      if k == -1 {
        cls
      } else {
        k
      }
    }
    @types.UPhi => {
      let p = st.fn_.blks[u.blk_id].phi[u.ins_idx]
      if p.to.is_none() {
        cls
      } else {
        p.cls.code()
      }
    }
    @types.UJmp => 0
    @types.UXXX => cls
  }
}

///|
fn propjnz0(
  st : GState,
  bif : Int,
  s0 : Int,
  snon0 : Int,
  r : @types.Ref,
  cls : Int,
) -> Unit {
  if st.fn_.blks[s0].npred != 1 || !r.is_tmp() {
    return
  }
  let t = st.fn_.tmps[r.tmp_val()]
  let n = t.nuse
  for k in 0..<n {
    let u = t.uses[k]
    if usecls(st, u, r, cls) == cls {
      if branchdom(st, bif, s0, snon0, u.blk_id) {
        replaceuse(st, u, r, con01[0])
      }
    }
  }
}

// ---------------------------------------------------------------------------
// GVN dedup
// ---------------------------------------------------------------------------

///|
fn mix(x0 : Int, x1 : Int) -> Int {
  x0 + 17 * x1
}

///|
fn ref_hash(r : @types.Ref) -> Int {
  mix(rtype_of(r), rval_of(r))
}

///|
fn ins_hash(i : @types.Ins) -> Int {
  let mut h = mix(i.op.index(), i.cls.code())
  h = mix(h, ref_hash(i.arg1))
  h = mix(h, ref_hash(i.arg2))
  h
}

///|
fn ins_eq(a : @types.Ins, b : @types.Ins) -> Bool {
  a.op == b.op && a.cls == b.cls && a.arg1.eq(b.arg1) && a.arg2.eq(b.arg2)
}

///|
// C gvndup: open-addressing hash table storing instruction copies.
fn gvndup(st : GState, i : @types.Ins, insert : Bool) -> @types.Ins? {
  let n = st.tbl.length()
  if n == 0 {
    return None
  }
  let h = ins_hash(i)
  let mut idx = (h % n + n) % n
  let mut result : @types.Ins? = None
  let mut searching = true
  while searching {
    match st.tbl[idx] {
      None => {
        if insert {
          st.tbl[idx] = Some(ins_copy(i))
        }
        searching = false
      }
      Some(ii) =>
        if ins_eq(i, ii) {
          result = Some(ii)
          searching = false
        } else {
          idx = (idx + 1) % n
        }
    }
  }
  result
}

///|
fn negcon(cls : @types.Class, c : @types.Con) -> @types.Con? {
  c_foldint(@types.Sub, cls.code() != 0, @types.Con::int(0L), c)
}

///|
fn normins(st : GState, i : @types.Ins) -> Unit {
  let fn_ = st.fn_
  for n in 0..<2 {
    let k = argcls(i, n)
    if (k & 1) == 0 {
      let a = if n == 0 { i.arg1 } else { i.arg2 }
      match isconbits(fn_, a) {
        Some(v) =>
          if (v & 0xFFFFFFFF) != v {
            let nv = v & 0xFFFFFFFF
            let c = @types.Ref::con(fn_.get_con(nv))
            if n == 0 {
              i.arg1 = c
            } else {
              i.arg2 = c
            }
          }
        None => ()
      }
    }
  }
  if op_commutes(i.op) {
    if rcmp(i.arg1, i.arg2) > 0 {
      let t = i.arg1
      i.arg1 = i.arg2
      i.arg2 = t
    }
  }
}

///|
fn assoccon(st : GState, b : @types.Blk, i : @types.Ins, idx : Int) -> Unit {
  let fn_ = st.fn_
  let mut op = i.op
  if op == @types.Sub {
    op = @types.Add
  }
  if !op_assoc(op) {
    return
  }
  if i.cls.base() != 0 {
    return
  }
  if !i.arg1.is_tmp() || !i.arg2.is_con() {
    return
  }
  let c1 = fn_.cons[i.arg2.con_val()]
  let t2 = i.arg1.tmp_val()
  let di = st.def_idx[t2]
  if di < 0 {
    return
  }
  let i2 = fn_.blks[fn_.tmps[t2].bid].ins[di]
  let op2 = if i2.op == @types.Sub { @types.Add } else { i2.op }
  if op != op2 {
    return
  }
  if !i2.arg2.is_con() {
    return
  }
  let c2 = fn_.cons[i2.arg2.con_val()]
  let c1n = if i.op == @types.Sub {
    match negcon(i.cls, c1) {
      Some(x) => x
      None => return
    }
  } else {
    c1
  }
  let c2n = if i2.op == @types.Sub {
    match negcon(i2.cls, c2) {
      Some(x) => x
      None => return
    }
  } else {
    c2
  }
  let c = match c_foldint(op, i.cls.code() != 0, c1n, c2n) {
    Some(x) => x
    None => return
  }
  let mut op = op
  let mut c = c
  if op == @types.Add && c.kind == @types.CBits {
    let neg = if i.cls == @types.Kl {
      c.bits.i < 0
    } else {
      sext32(c.bits.i) < 0
    }
    if neg {
      match negcon(i.cls, c) {
        Some(x) => {
          c = x
          op = @types.Sub
        }
        None => return
      }
    }
  }
  i.op = op
  i.arg1 = i2.arg1
  i.arg2 = @types.Ref::con(fn_.get_con_by(c))
  gvn_adduse(fn_, i.arg1.tmp_val(), @types.UIns, b.id, idx, 0)
}

///|
fn phieq(fn_ : @types.Fn, pa : @types.Phi, pb : @types.Phi) -> Bool {
  ignore(fn_)
  if pa.args.length() != pb.args.length() {
    return false
  }
  for a in pa.args {
    match phiarg(pb, a.blk_id) {
      Some(r) => if !a.value.eq(r) { return false }
      None => return false
    }
  }
  true
}

///|
fn phicopyref(st : GState, b : @types.Blk, pi : Int) -> @types.Ref {
  let fn_ = st.fn_
  let p = b.phi[pi]
  let narg = p.args.length()
  let mut r = @types.Ref::none()
  let mut n = 0
  while n < narg {
    let a = p.args[n].value
    if !a.eq(p.to) {
      if r.is_none() {
        r = a
      } else if !a.eq(r) {
        break
      }
    }
    n = n + 1
  }
  if n == narg {
    return r
  }
  for pj in 0..<pi {
    let p1 = b.phi[pj]
    if !p1.to.is_none() {
      if phieq(fn_, p1, p) {
        return p1.to
      }
    }
  }
  let d = b.idom
  if d < 0 {
    return @types.Ref::none()
  }
  let dj = fn_.blks[d].jmp
  if narg != 2 || dj.kind != @types.Jjnz || !isw1(st, dj.arg) {
    return @types.Ref::none()
  }
  let mut sb0 = -1
  let mut sb1 = -1
  for n2 in 0..<2 {
    for c in 0..<2 {
      if p.args[n2].value.eq(con01[c]) {
        if c == 0 {
          sb0 = p.args[n2].blk_id
        } else {
          sb1 = p.args[n2].blk_id
        }
      }
    }
  }
  if dj.s1 == sb1 && dj.s2 == sb0 && dj.s1 >= 0 && dj.s2 >= 0 {
    if fn_.blks[dj.s1].jmp.kind == @types.Jjmp &&
      fn_.blks[dj.s2].jmp.kind == @types.Jjmp {
      return dj.arg
    }
  }
  @types.Ref::none()
}

///|
fn copyref(st : GState, b : @types.Blk, i : @types.Ins) -> @types.Ref {
  let fn_ = st.fn_
  if i.op == @types.Copy {
    return i.arg1
  }
  if op_hasid(i.op) && i.cls.base() == 0 && i.arg2.eq(con01[op_idval(i.op)]) {
    if !op_cmpeqwl(i.op) || isw1(st, i.arg1) {
      return i.arg1
    }
  }
  if op_idemp(i.op) && i.arg1.eq(i.arg2) {
    return i.arg1
  }
  if (op_cmpeqwl(i.op) || op_cmplgtewl(i.op)) && i.arg1.eq(i.arg2) {
    return con01[op_eqval(i.op)]
  }
  if op_cmpeqwl(i.op) && i.arg2.eq(con01[0]) {
    match zeroval(st, b.id, i.arg1, argcls(i, 0)) {
      Some(z) => return con01[op_eqval(i.op) ^ z ^ 1]
      None => ()
    }
  }
  if i.op == @types.And {
    match isconbits(fn_, i.arg2) {
      Some(v) =>
        if v > 0L && ((v + 1L) & v) == 0L {
          if defwidthle(st, i.arg1, bitwidth(v.reinterpret_as_uint64())) {
            return i.arg1
          }
        }
      None => ()
    }
  }
  if i.cls == @types.Kw && (i.op == @types.Extsw || i.op == @types.Extuw) {
    return i.arg1
  }
  match ext_of(i) {
    Some(e) =>
      if i.arg1.is_tmp() {
        let tid = i.arg1.tmp_val()
        if i.cls.wide() > fn_.tmps[tid].cls.wide() {
          return @types.Ref::none()
        }
        let w = i.op.ext_width_idx()
        if ((1 << w) & extcpy_width(fn_.tmps[tid].width.code())) != 0 {
          return i.arg1
        }
        let di = st.def_idx[tid]
        let def_is_par = if di < 0 {
          false
        } else {
          fn_.blks[fn_.tmps[tid].bid].ins[di].op.is_par()
        }
        if !def_is_par && usewidthle(st, i.to, e.usew) {
          return i.arg1
        }
        if defwidthle(st, i.arg1, e.nopw) {
          return i.arg1
        }
      }
    None => ()
  }
  @types.Ref::none()
}

///|
fn dedupphi(st : GState, b : @types.Blk) -> Unit {
  for pi in 0..<b.phi.length() {
    let p = b.phi[pi]
    let r = phicopyref(st, b, pi)
    if !r.is_none() {
      replaceuses(st, p.to, r)
      p.to = @types.Ref::none()
    }
  }
}

///|
fn dedupins(st : GState, b : @types.Blk, idx : Int) -> Unit {
  let i = b.ins[idx]
  normins(st, i)
  if i.op == @types.Nop || pinned(i) || i.to.is_none() {
    return
  }
  assoccon(st, b, i, idx)
  let r = copyref(st, b, i)
  if !r.is_none() {
    killins(st, i, r)
    return
  }
  let r2 = foldref(st.fn_, i)
  if !r2.is_none() {
    killins(st, i, r2)
    return
  }
  match gvndup(st, i, true) {
    Some(i1) => killins(st, i, i1.to)
    None => ()
  }
}

///|
fn dedupjmp(st : GState, b : @types.Blk) -> Unit {
  if b.jmp.kind != @types.Jjnz {
    return
  }
  propjnz0(st, b.id, b.jmp.s2, b.jmp.s1, b.jmp.arg, 0)
  match cmpeqz(st, b.jmp.arg) {
    Some((arg, cls, eqval)) => {
      let ps = [b.jmp.s1, b.jmp.s2]
      propjnz0(st, b.id, ps[eqval ^ 1], ps[eqval], arg, cls)
    }
    None => ()
  }
  let mut v : Int64 = 1L
  let mut z = 0
  let mut trigger = false
  if b.jmp.s1 == b.jmp.s2 {
    trigger = true
  } else {
    match isconbits(st.fn_, b.jmp.arg) {
      Some(x) => {
        v = x
        trigger = true
      }
      None =>
        match zeroval(st, b.id, b.jmp.arg, 0) {
          Some(zz) => {
            z = zz
            trigger = true
          }
          None => ()
        }
    }
  }
  if trigger {
    if v == 0L || z != 0 {
      b.jmp.s1 = b.jmp.s2
    }
    b.jmp.s2 = -1
    b.jmp.kind = @types.Jjmp
    b.jmp.arg = @types.Ref::none()
  }
}

// ---------------------------------------------------------------------------
// narrowpars (C copy.c)
// ---------------------------------------------------------------------------

///|
fn narrowpars(st : GState) -> Unit {
  let fn_ = st.fn_
  let mut has_loop = false
  for id in fn_.def_order {
    if fn_.blks[id].loop_depth > 1 {
      has_loop = true
    }
  }
  if !has_loop {
    return
  }
  let b = fn_.blks[fn_.start_id]
  let mut npar = 0
  while npar < b.ins.length() && b.ins[npar].op.is_par() {
    npar = npar + 1
  }
  if npar == 0 {
    return
  }
  let old : Array[@types.Ins] = []
  for x in b.ins {
    old.push(x)
  }
  b.ins.clear()
  for k in 0..<npar {
    b.ins.push(old[k])
  }
  for _ in 0..<npar {
    b.ins.push(nop_ins())
  }
  for k in npar..<old.length() {
    b.ins.push(old[k])
  }
  for k in 0..<npar {
    let par = b.ins[k]
    let ext = nop_ins()
    if par.cls == @types.Kw && usewidthle(st, par.to, 16) {
      ext.op = @types.Extuh
      if usewidthle(st, par.to, 8) {
        ext.op = @types.Extub
      }
      let r = @types.Ref::tmp(fn_.new_tmp("vw", par.cls))
      ext.cls = par.cls
      ext.to = par.to
      ext.arg1 = r
      par.to = r
    }
    b.ins[k + npar] = ext
  }
}

// ---------------------------------------------------------------------------
// rebuildcfg
// ---------------------------------------------------------------------------

///|
fn rebuildcfg(st : GState) -> Unit {
  let fn_ = st.fn_
  let old_rpo : Array[Int] = []
  for x in fn_.rpo {
    old_rpo.push(x)
  }
  @cfg.fillrpo(fn_)
  @cfg.fillpreds(fn_)
  let s_id = fn_.start_id
  for b_id in old_rpo {
    let b = fn_.blks[b_id]
    if b.rpo_id >= 0 {
      continue
    }
    for idx in 0..<b.ins.length() {
      let i = b.ins[idx]
      if !op_pinned(i) {
        match gvndup(st, i, false) {
          Some(ii) => if ins_eq(ii, i) { fn_.blks[s_id].ins.push(ins_copy(i)) }
          None => ()
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Pass entry point
// ---------------------------------------------------------------------------

///|
fn g_filluse(fn_ : @types.Fn) -> Unit {
  try @ssa.filluse(fn_) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
fn g_ssacheck(fn_ : @types.Fn) -> Unit {
  try @ssa.ssacheck(fn_) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
// Global value numbering (C gvn.c).  Requires rpo/pred/ssa/use/dom; this port
// refreshes them defensively.  Returns the -dG debug text (empty when
// print_dbg is false).
pub fn gvn(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let st = GState::new(fn_)
  con01[0] = @types.Ref::con(fn_.get_con(0))
  con01[1] = @types.Ref::con(fn_.get_con(1))
  @cfg.fillrpo(fn_)
  @cfg.fillpreds(fn_)
  @cfg.filldom(fn_)
  g_filluse(fn_)
  @cfg.fillloop(fn_)
  narrowpars(st)
  g_filluse(fn_)
  // narrowpars may have created temporaries; keep the phi visit table sized.
  st.phi_visit = Array::make(fn_.ntmp(), 0)
  g_ssacheck(fn_)
  let mut nins = 0
  for id in fn_.def_order {
    fn_.blks[id].visit = 0
    nins = nins + fn_.blks[id].ins.length()
  }
  let tlen = if nins + nins / 2 < 1 { 1 } else { nins + nins / 2 }
  let tbl : Array[@types.Ins?] = Array::make(tlen, None)
  st.tbl = tbl
  build_def_idx(st)
  for b_id in fn_.rpo {
    let b = fn_.blks[b_id]
    dedupphi(st, b)
    for idx in 0..<b.ins.length() {
      dedupins(st, b, idx)
    }
    dedupjmp(st, b)
  }
  rebuildcfg(st)
  // Drop phis eliminated by dedupphi so the dump matches the reference.
  for id in fn_.def_order {
    let b = fn_.blks[id]
    let kept : Array[@types.Phi] = []
    for p in b.phi {
      if !p.to.is_none() {
        kept.push(p)
      }
    }
    b.phi.clear()
    for p in kept {
      b.phi.push(p)
    }
  }
  if print_dbg {
    "\n> After GVN:\n" + @parser.printfn(fn_, interner, all_typs) + "\n"
  } else {
    ""
  }
}
