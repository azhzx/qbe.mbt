///|
// Address folding for amd64 isel - corresponds to aref/ascale/anumber/amatch
// in amd64/isel.c. Recognizes complex addressing modes.

///|
// Address analysis info per temporary (C struct ANum).
priv struct ANum {
  mut n : Int
  mut l : Int
  mut r : Int
  // Index of the defining instruction in the current block, -1 if none.
  mut i : Int
}

///|
fn ANum::new() -> ANum {
  ANum::{ n: 0, l: 0, r: 0, i: -1 }
}

///|
// The add[] table of anumber (C static char add[10][10]).
let add_tab : Array[Array[Int]] = [
  [4, 0, 6, 4, 0, 7, 0, 0],
  [0, 0, 0, 0, 0, 0, 0, 0],
  [6, 0, 2, 5, 7, 5, 6, 7],
  [4, 0, 5, 0, 0, 0, 7, 0],
  [0, 0, 7, 0, 0, 0, 0, 0],
  [7, 0, 5, 0, 0, 0, 0, 0],
  [0, 0, 6, 7, 0, 0, 0, 0],
  [0, 0, 7, 0, 0, 0, 0, 0],
]

///|
fn aref(st : IselState, r : @types.Ref) -> Int {
  if r.is_con() {
    return 2
  }
  if r.is_tmp() {
    return st.an[r.tmp_val()].n
  }
  abort("constant or temporary expected")
}

///|
fn ascale(r : @types.Ref, cons : Array[@types.Con]) -> Bool {
  if !r.is_con() {
    return false
  }
  let con = cons[r.con_val()]
  if con.kind != @types.CBits {
    return false
  }
  let n = con.bits.i
  n == 1L || n == 2L || n == 4L || n == 8L
}

///|
// Number the addressable form of each add/mul in the block (C anumber).
fn anumber(st : IselState, b : @types.Blk) -> Unit {
  let ins = b.ins
  for idx = 0; idx < ins.length(); idx = idx + 1 {
    let i = ins[idx]
    if i.to.is_tmp() {
      st.an[i.to.tmp_val()].i = idx
    }
    if i.op != @types.Add && i.op != @types.Mul {
      continue
    }
    let a1 = aref(st, i.arg1)
    let a2 = aref(st, i.arg2)
    let t1 = a1 != 1 && a1 != 2
    let t2 = a2 != 1 && a2 != 2
    let mut n1 = 0
    let mut n2 = 0
    let mut a = 0
    if i.op == @types.Add {
      n1 = a1
      n2 = a2
      a = add_tab[a1][a2]
      if t1 && a < add_tab[0][a2] {
        n1 = 0
        n2 = a2
        a = add_tab[0][a2]
      }
      if t2 && a < add_tab[a1][0] {
        n1 = a1
        n2 = 0
        a = add_tab[a1][0]
      }
      if t1 && t2 && a < add_tab[0][0] {
        n1 = 0
        n2 = 0
        a = add_tab[0][0]
      }
    } else {
      n1 = 0
      n2 = 0
      a = 0
      if ascale(i.arg1, st.fn_.cons) && t2 {
        a = 3
        n1 = 2
        n2 = 0
      }
      if t1 && ascale(i.arg2, st.fn_.cons) {
        a = 3
        n1 = 0
        n2 = 2
      }
    }
    st.an[i.to.tmp_val()].n = a
    st.an[i.to.tmp_val()].l = n1
    st.an[i.to.tmp_val()].r = n2
  }
}

///|
// Match a temporary to an address (C amatch). The Addr is boxed and mutated
// in place.
fn amatch(st : IselState, a : @types.Addr, r : @types.Ref, top : Bool) -> Unit {
  if r.is_con() {
    a.offset = @types.addcon(a.offset, st.fn_.cons[r.con_val()])
    return
  }
  let idx = st.an[r.tmp_val()].i
  let mut nl = st.an[r.tmp_val()].l
  let mut nr = st.an[r.tmp_val()].r
  let mut al = @types.ref_none()
  let mut ar = @types.ref_none()
  if idx >= 0 {
    let ins = st.cur_ins[idx]
    if nl > nr {
      al = ins.arg2
      ar = ins.arg1
      let t = nl
      nl = nr
      nr = t
    } else {
      al = ins.arg1
      ar = ins.arg2
    }
  }
  match st.an[r.tmp_val()].n {
    3 =>
      if !top {
        a.index = al
        a.scale = st.fn_.cons[ar.con_val()].bits.i.to_int()
      } else {
        a.base = r
      }
    4 => {
      match nr {
        0 => {
          if st.fn_.tmps[ar.tmp_val()].slot != -1 {
            al = st.cur_ins[idx].arg2
            ar = st.cur_ins[idx].arg1
          }
          a.index = ar
          a.scale = 1
        }
        3 => amatch(st, a, ar, false)
        _ => ()
      }
      let s = st.fn_.tmps[al.tmp_val()].slot
      let r1 = if s != -1 { @types.Ref::slot(s) } else { al }
      a.base = r1
    }
    0 => {
      let s = st.fn_.tmps[r.tmp_val()].slot
      let r1 = if s != -1 { @types.Ref::slot(s) } else { r }
      a.base = r1
    }
    2 | 5 | 6 | 7 => {
      amatch(st, a, ar, false)
      amatch(st, a, al, false)
    }
    _ => abort("unreachable")
  }
}
