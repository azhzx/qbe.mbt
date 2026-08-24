///|
// Constant folding via sparse conditional constant propagation (SCCP).
// Corresponds to fold.c in QBE.
// Requires: rpo, use, pred already computed (filluse, fillpreds, fillrpo).

///|
// Lattice values: a tmp's value is Top, Bot, or a constant index.
const BOT = -2

///|
const TOP = -1

///|
priv struct Edge {
  dest : Int // RPO index of the successor, -1 if none
  mut dead : Bool
}

///|
priv struct FoldState {
  fn_ : @types.Fn
  val : Array[Int] // per-tmp lattice value
  edges : Array[Array[Edge]] // edges[n] = [s1, s2] for block at RPO n
  usewrk : Array[@types.Use]
  mut nuse : Int
  work : Array[Int] // stack of edge ids: 2*n+slot, or -1 for the start edge
}

///|
fn czero(c : @types.Con, w : Bool) -> Bool {
  if c.kind != @types.CBits {
    return false
  }
  if w {
    c.bits.i == 0
  } else {
    (c.bits.i & 0xFFFFFFFF) == 0
  }
}

///|
fn latval(st : FoldState, r : @types.Ref) -> Int {
  match r {
    @types.RTmp(v) => st.val[v]
    @types.RCon(v) => v
    _ => abort("unreachable")
  }
}

///|
fn latmerge(v : Int, m : Int) -> Int {
  if m == TOP {
    v
  } else if v == TOP || v == m {
    m
  } else {
    BOT
  }
}

///|
fn update(st : FoldState, t : Int, m : Int) -> Unit {
  let m = latmerge(st.val[t], m)
  if m != st.val[t] {
    for u in st.fn_.tmps[t].uses {
      st.usewrk.push(u)
      st.nuse = st.nuse + 1
    }
    st.val[t] = m
  }
}

///|
// Whether edge from RPO-indexed block s to block d is currently alive.
fn deadedge(st : FoldState, s : Int, d : Int) -> Bool {
  let e = st.edges[s]
  if e[0].dest == d && !e[0].dead {
    return false
  }
  if e[1].dest == d && !e[1].dead {
    return false
  }
  true
}

///|
fn visitphi(st : FoldState, p : @types.Phi, n : Int) -> Unit {
  let mut v = TOP
  for a in p.args {
    if !deadedge(st, st.fn_.blks[a.blk_id].rpo_id, n) {
      v = latmerge(v, latval(st, a.value))
    }
  }
  update(st, p.to.tmp_val(), v)
}

///|
fn visitins(st : FoldState, i : @types.Ins) -> Unit {
  if !i.to.is_tmp() {
    return
  }
  let mut v = BOT
  if @types.op_info(i.op).canfold {
    let l = latval(st, i.arg1)
    let r = if i.arg2.is_none() {
      0 // CON_Z.val: the zero constant is always con index 0
    } else {
      latval(st, i.arg2)
    }
    if l == BOT || r == BOT {
      v = BOT
    } else if l == TOP || r == TOP {
      v = TOP
    } else {
      v = opfold(st, i.op, i.cls, st.fn_.cons[l], st.fn_.cons[r])
    }
  }
  update(st, i.to.tmp_val(), v)
}

///|
fn visitjmp(st : FoldState, b : @types.Blk, n : Int) -> Unit {
  match b.jmp.kind {
    @types.Jjnz => {
      let l = latval(st, b.jmp.arg)
      if l == BOT {
        st.work.push(2 * n + 1)
        st.work.push(2 * n)
      } else if czero(st.fn_.cons[l], false) {
        st.work.push(2 * n + 1)
      } else {
        st.work.push(2 * n)
      }
    }
    @types.Jjmp => st.work.push(2 * n)
    _ => ()
  }
}

///|
// Visit the block at RPO index d (shared by the start edge and block edges).
fn visit_blk(st : FoldState, d : Int) -> Unit {
  let b = st.fn_.blks[st.fn_.rpo[d]]
  for p in b.phi {
    visitphi(st, p, d)
  }
  if b.visit == 0 {
    for i in b.ins {
      visitins(st, i)
    }
    visitjmp(st, b, d)
  }
  b.visit = b.visit + 1
}

///|
// Replace a ref with its constant value if known; returns the new ref.
fn renref(st : FoldState, r : @types.Ref) -> @types.Ref {
  if r.is_tmp() {
    let l = st.val[r.tmp_val()]
    if l != BOT {
      @types.Ref::con(l)
    } else {
      r
    }
  } else {
    r
  }
}

///|
// Sparse conditional constant propagation (C fold).
// Returns the -dF debug text (empty when print_dbg is false).
pub fn fold(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let nb = fn_.rpo.length()
  let nt = fn_.ntmp()
  let st = FoldState::{
    fn_,
    val: Array::make(nt, TOP),
    edges: Array::new(),
    usewrk: Array::new(),
    nuse: 0,
    work: Array::new(),
  }
  for n = 0; n < nb; n = n + 1 {
    let b = fn_.blks[fn_.rpo[n]]
    b.visit = 0
    let s1 = if b.jmp.s1 >= 0 { fn_.blks[b.jmp.s1].rpo_id } else { -1 }
    let s2 = if b.jmp.s2 >= 0 { fn_.blks[b.jmp.s2].rpo_id } else { -1 }
    st.edges.push([
      Edge::{ dest: s1, dead: true },
      Edge::{ dest: s2, dead: true },
    ])
  }
  // The start edge into rpo[0] (the start block).
  st.work.push(-1)

  let sb = StringBuilder::new()

  // 1. find out constants and dead cfg edges
  while true {
    if st.work.length() > 0 {
      let e = st.work.pop().unwrap()
      if e == -1 {
        // start edge
        visit_blk(st, 0)
      } else {
        let n = e / 2
        let slot = e % 2
        let edge = st.edges[n][slot]
        if edge.dest == -1 || !edge.dead {
          continue
        }
        st.edges[n][slot].dead = false
        visit_blk(st, edge.dest)
      }
    } else if st.nuse > 0 {
      let u = st.usewrk.pop().unwrap()
      st.nuse = st.nuse - 1
      let n = fn_.blks[u.blk_id].rpo_id
      let b = fn_.blks[fn_.rpo[n]]
      if b.visit == 0 {
        continue
      }
      match u.kind {
        @types.UPhi => {
          let p = b.phi[u.ins_idx]
          visitphi(st, p, n)
        }
        @types.UIns => {
          let i = b.ins[u.ins_idx]
          visitins(st, i)
        }
        @types.UJmp => visitjmp(st, b, n)
        _ => abort("unreachable")
      }
    } else {
      break
    }
  }

  if print_dbg {
    sb.write_string("\n> SCCP findings:")
    for t = @types.Tmp0; t < nt; t = t + 1 {
      if st.val[t] == BOT {
        continue
      }
      sb.write_char('\n')
      let name = fn_.tmps[t].name
      let pad = " ".repeat(
        if 10 > name.length() {
          10 - name.length()
        } else {
          0
        },
      )
      sb.write_string(pad)
      sb.write_string(name)
      sb.write_string(": ")
      if st.val[t] == TOP {
        sb.write_string("Top")
      } else {
        @parser.printref(
          @types.Ref::con(st.val[t]),
          fn_,
          interner,
          sb,
          all_typs,
        )
      }
    }
    sb.write_string("\n dead code: ")
  }

  // 2. trim dead code, replace constants
  let mut d = 0
  let new_def : Array[Int] = Array::new()
  for id in fn_.def_order {
    let b = fn_.blks[id]
    if b.visit == 0 {
      d = 1
      if print_dbg {
        sb.write_string(b.name)
        sb.write_string(" ")
      }
      @cfg.edgedel(fn_, id, b.jmp.s1)
      @cfg.edgedel(fn_, id, b.jmp.s2)
      continue
    }
    new_def.push(id)
    // trim phis
    let mut pi = 0
    while pi < b.phi.length() {
      let p = b.phi[pi]
      if st.val[p.to.tmp_val()] != BOT {
        let _ = b.phi.remove(pi)
      } else {
        for a in p.args {
          if !deadedge(st, fn_.blks[a.blk_id].rpo_id, b.rpo_id) {
            a.value = renref(st, a.value)
          }
        }
        pi = pi + 1
      }
    }
    // trim instructions
    for ii = 0; ii < b.ins.length(); ii = ii + 1 {
      let i = b.ins[ii]
      if !i.to.is_none() {
        let new_to = renref(st, i.to)
        if !@types.req(new_to, i.to) {
          b.ins[ii] = @types.Ins::new_void(
            @types.Nop,
            @types.Kw,
            @types.ref_none(),
            @types.ref_none(),
          )
          continue
        }
      }
      let a1 = renref(st, i.arg1)
      let a2 = renref(st, i.arg2)
      if !@types.req(a1, i.arg1) || !@types.req(a2, i.arg2) {
        b.ins[ii] = @types.Ins::new(i.op, i.cls, i.to, a1, a2)
      }
    }
    // trim jump argument
    b.jmp.arg = renref(st, b.jmp.arg)
    if b.jmp.kind == @types.Jjnz && b.jmp.arg.is_con() {
      if czero(fn_.cons[b.jmp.arg.con_val()], false) {
        @cfg.edgedel(fn_, id, b.jmp.s1)
        b.jmp.s1 = b.jmp.s2
        b.jmp.s2 = -1
      } else {
        @cfg.edgedel(fn_, id, b.jmp.s2)
      }
      b.jmp.kind = @types.Jjmp
      b.jmp.arg = @types.ref_none()
    }
  }
  fn_.def_order.clear()
  for id in new_def {
    fn_.def_order.push(id)
  }

  if print_dbg {
    if d == 0 {
      sb.write_string("(none)")
    }
    sb.write_string("\n\n> After constant folding:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}
