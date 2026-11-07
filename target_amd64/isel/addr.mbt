///|
// Address folding for amd64 isel: a transcription of the reference
// amd64/isel.c (refn/opn/match/matcher/unumber/adisp/amatch) and of
// runmatch() from util.c. The matcher bytecode tables are copied verbatim.

///|
// C struct Num: n is the pattern class, nl/nr the operand classes and l/r
// the operand refs.
priv struct ANum {
  mut n : Int32
  mut nl : Int32
  mut nr : Int32
  mut l : @types.Ref
  mut r : @types.Ref
}

///|
fn ANum::new() -> ANum {
  ANum::{ n: 0, nl: 0, nr: 0, l: @types.Ref::none(), r: @types.Ref::none(), }
}

///|
// Pattern ids (C enum in amd64/isel.c).
const POB : Int32 = 0

///|
const PBIS : Int32 = 1

///|
const POIS : Int32 = 2

///|
const POBIS : Int32 = 3

///|
const PBI1 : Int32 = 4

///|
const POBI1 : Int32 = 5

///|
// Generated Oaddtbl (C static uchar Oaddtbl[91]).
let oaddtbl : Array[Int32] = [
  2, 2, 2, 4, 4, 5, 6, 6, 8, 8, 4, 4, 9, 10, 9, 7, 7, 5, 8, 9, 5, 4, 4, 12, 10, 12,
  12, 12, 4, 4, 9, 10, 9, 9, 12, 9, 11, 11, 5, 8, 9, 5, 12, 9, 5, 7, 7, 5, 8, 9,
  5, 12, 9, 5, 5, 11, 11, 5, 8, 9, 5, 12, 9, 5, 5, 5, 4, 4, 9, 10, 9, 9, 12, 9, 9,
  9, 9, 9, 7, 7, 5, 8, 9, 5, 12, 9, 5, 5, 5, 9, 5,
]

///|
// C opn.
fn opn(op : @types.Op, l : Int32, r : Int32) -> Int32 {
  let mut l = l
  let mut r = r
  if l < r {
    let t = l
    l = r
    r = t
  }
  match op {
    @types.Mul => if 2 <= l && r == 0 { 3 } else { 2 }
    @types.Add => oaddtbl[(l + l * l) / 2 + r]
    _ => 2
  }
}

///|
// C refn.
fn refn(st : IselState, r : @types.Ref) -> Int32 {
  if r.is_tmp() {
    if st.an[r.tmp_val()].n == 0 {
      st.an[r.tmp_val()].n = 2
    }
    st.an[r.tmp_val()].n
  } else if r.is_con() {
    let con = st.fn_.cons[r.con_val()]
    if con.kind != @types.CBits {
      1
    } else {
      let n = con.bits.i
      if n == 8L || n == 4L || n == 2L || n == 1L {
        0
      } else {
        1
      }
    }
  } else {
    -2147483648
  }
}

///|
// C match[] bitset (indexed by Num.n).
fn match_mask(n : Int32) -> Int32 {
  match n {
    4 => 1
    5 => 16
    6 => 1 | 4
    7 => 1 | 32
    8 => 16 | 2
    9 => 16 | 32
    10 => 16 | 2 | 32 | 8
    11 => 1 | 32 | 8
    12 => 16 | 32 | 8
    _ => 0
  }
}

///|
// Generated matcher bytecode (C static uchar *matcher[]).
let matcher_pbi1 : Array[Int32] = [1, 3, 1, 3, 2, 0]

///|
let matcher_pbis : Array[Int32] = [
  5, 1, 8, 5, 27, 1, 5, 1, 2, 5, 13, 3, 1, 1, 3, 3, 3, 2, 0, 1, 3, 3, 3, 2, 3, 1,
  0, 1, 29,
]

///|
let matcher_pob : Array[Int32] = [1, 3, 0, 3, 1, 0]

///|
let matcher_pobI1 : Array[Int32] = [
  5, 3, 9, 9, 10, 33, 12, 35, 45, 1, 5, 3, 11, 9, 7, 9, 4, 9, 17, 1, 3, 0, 3, 1,
  3, 2, 0, 3, 1, 1, 3, 0, 34, 1, 37, 1, 5, 2, 5, 7, 2, 7, 8, 37, 29, 1, 3, 0, 1,
  32,
]

///|
let matcher_pobIS : Array[Int32] = [
  5, 2, 10, 7, 11, 19, 49, 1, 1, 3, 3, 3, 2, 1, 3, 0, 3, 1, 0, 1, 3, 0, 5, 1, 8,
  5, 25, 1, 5, 1, 2, 5, 13, 3, 1, 1, 3, 3, 3, 2, 0, 1, 3, 3, 3, 2, 26, 1, 51, 1,
  5, 1, 6, 5, 9, 1, 3, 0, 51, 3, 1, 1, 3, 0, 45,
]

///|
let matcher_pois : Array[Int32] = [1, 3, 0, 1, 3, 3, 3, 2, 0]

///|
fn matcher_for(p : Int32) -> Array[Int32] {
  match p {
    PBI1 => matcher_pbi1
    PBIS => matcher_pbis
    POB => matcher_pob
    POBI1 => matcher_pobI1
    POBIS => matcher_pobIS
    _ => matcher_pois
  }
}

///|
// C runmatch: interpret the matcher bytecode, writing the matched operands
// into vars.
fn runmatch(
  st : IselState,
  code : Array[Int32],
  ref : @types.Ref,
  vars : Array[@types.Ref],
) -> Unit raise {
  let stk : Array[@types.Ref] = Array::make(20, @types.Ref::none())
  let mut sp = 0
  let mut pc = 0
  let mut r = ref
  while pc < code.length() && code[pc] != 0 {
    let bc = code[pc]
    if bc == 1 || bc == 2 {
      let nl = st.an[r.tmp_val()].nl
      let nr = st.an[r.tmp_val()].nr
      if bc == 1 && nl > nr {
        stk[sp] = st.an[r.tmp_val()].l
        sp = sp + 1
        r = st.an[r.tmp_val()].r
      } else {
        stk[sp] = st.an[r.tmp_val()].r
        sp = sp + 1
        r = st.an[r.tmp_val()].l
      }
      pc = pc + 1
    } else if bc == 3 {
      pc = pc + 1
      let vi = code[pc]
      vars[vi] = r
      if pc + 1 < code.length() && code[pc + 1] == 0 {
        return
      }
      sp = sp - 1
      r = stk[sp]
      pc = pc + 1
    } else if bc == 4 {
      sp = sp - 1
      r = stk[sp]
      pc = pc + 1
    } else if bc == 5 {
      let n = st.an[r.tmp_val()].n
      let mut s = pc + 1
      let cnt = code[s]
      s = s + 1
      let mut i = 0
      while i < cnt {
        let cand = code[s]
        s = s + 1
        if n == cand {
          break
        }
        s = s + 1
        i = i + 1
      }
      if s < code.length() {
        pc = pc + code[s]
      } else {
        return
      }
    } else if bc >= 10 {
      pc = bc - 10
    } else {
      raise @util.QbeError::Ice("invalid matcher bytecode")
    }
  }
}

///|
// C addcon: add c1*m to c0; None when the reference would fail.
fn addcon(c0 : @types.Con, c1 : @types.Con, m : Int32) -> @types.Con? {
  if m != 1 && c1.kind == @types.CAddr {
    return None
  }
  if c0.kind == @types.CUndef {
    Some(@types.Con::{
      kind: c1.kind,
      label: c1.label,
      bits: @types.ConBits::{
        i: c1.bits.i * m.to_int64(),
        d: c1.bits.d,
        s: c1.bits.s,
      },
      flt: c1.flt,
      is_local: c1.is_local,
      sym_type: c1.sym_type,
    })
  } else if c1.kind == @types.CAddr {
    if c0.kind == @types.CAddr {
      return None
    }
    Some(@types.Con::{
      kind: @types.CAddr,
      label: c1.label,
      bits: @types.ConBits::{
        i: c0.bits.i + c1.bits.i * m.to_int64(),
        d: c0.bits.d,
        s: c0.bits.s,
      },
      flt: c0.flt,
      is_local: c0.is_local,
      sym_type: c1.sym_type,
    })
  } else {
    Some(@types.Con::{
      kind: c0.kind,
      label: c0.label,
      bits: @types.ConBits::{
        i: c0.bits.i + c1.bits.i * m.to_int64(),
        d: c0.bits.d,
        s: c0.bits.s,
      },
      flt: c0.flt,
      is_local: c0.is_local,
      sym_type: c0.sym_type,
    })
  }
}

///|
// C adisp: fold all $const(%tmp) chains into c.
fn adisp(
  st : IselState,
  c : @types.Con,
  r : @types.Ref,
  s : Int32,
) -> (@types.Con, @types.Ref) raise {
  let mut c = c
  let mut r = r
  while !r.is_none() {
    let n = refn(st, r)
    let pobbit = 1 << POB
    let has = match_mask(n) & pobbit
    if has == 0 {
      break
    }
    let v : Array[@types.Ref] = Array::make(4, @types.Ref::none())
    runmatch(st, matcher_pob, r, v)
    let con = st.fn_.cons[v[0].con_val()]
    match addcon(c, con, s) {
      Some(x) => c = x
      None => ()
    }
    r = v[1]
  }
  (c, r)
}

///|
// C amatch: match r to an x86 addressing mode.
fn amatch(st : IselState, a : @types.Addr, r : @types.Ref) -> Bool raise {
  if !r.is_tmp() {
    return false
  }
  let n = refn(st, r)
  let v : Array[@types.Ref] = Array::make(4, @types.Ref::none())
  let pats : Array[Int32] = [POBIS, POBI1, PBIS, POIS, PBI1]
  let mut found = -1
  for p in pats {
    let pbit = 1 << p
    let has = match_mask(n) & pbit
    if has != 0 {
      runmatch(st, matcher_for(p), r, v)
      found = p
      break
    }
  }
  if found < 0 {
    v[1] = r
  }
  let mut co = @types.Con::new()
  let ro = v[0]
  let (co1, rb) = adisp(st, co, v[1], 1)
  co = co1
  let mut ri = v[2]
  let rs = v[3]
  let mut s = 1
  if found < 0 && co.kind != @types.CUndef {
    if amatch(st, a, rb) {
      match addcon(a.offset, co, 1) {
        Some(x) => {
          a.offset = x
          return true
        }
        None => return false
      }
    }
  }
  if !ro.is_none() {
    let c1 = st.fn_.cons[ro.con_val()]
    match addcon(co, c1, 1) {
      Some(x) => co = x
      None => return false
    }
  }
  if !rs.is_none() {
    let c2 = st.fn_.cons[rs.con_val()]
    s = c2.bits.i.to_int()
  }
  let (co2, ri2) = adisp(st, co, ri, s)
  co = co2
  ri = ri2
  a.offset = co
  a.base = rb
  a.index = ri
  a.scale = s
  if ri.is_tmp() && st.fn_.tmps[ri.tmp_val()].slot != -1 {
    if a.scale != 1 || (rb.is_tmp() && st.fn_.tmps[rb.tmp_val()].slot != -1) {
      return false
    }
    a.base = ri
    a.index = rb
  }
  if !a.base.is_none() {
    if a.base.is_tmp() {
      let sl = st.fn_.tmps[a.base.tmp_val()].slot
      if sl != -1 {
        a.base = @types.Ref::slot(sl)
      }
    }
  }
  true
}

///|
// C anumber: number the addressable form of each instruction in the block.
fn anumber(st : IselState, b : @types.Blk) -> Unit raise {
  for idx in 0..<b.ins.length() {
    let i = b.ins[idx]
    if !i.to.is_tmp() {
      continue
    }
    let t = i.to.tmp_val()
    st.an[t].l = i.arg1
    st.an[t].r = i.arg2
    let nl = refn(st, i.arg1)
    let nr = refn(st, i.arg2)
    st.an[t].nl = nl
    st.an[t].nr = nr
    st.an[t].n = opn(i.op, nl, nr)
  }
}
