// GCM (global code motion) port of vendor/qbe/gcm.c.

///|
fn isdivwl(i : @types.Ins) -> Bool {
  match i.op {
    @types.Div | @types.Rem | @types.Udiv | @types.Urem => i.cls.base() == 0
    _ => false
  }
}

///|
// optab pinned column only (C optab[i->op].pinned).
fn op_pinned(i : @types.Ins) -> Bool {
  match i.op {
    @types.Storeb
    | @types.Storeh
    | @types.Storew
    | @types.Storel
    | @types.Stores
    | @types.Stored
    | @types.Loadsb
    | @types.Loadub
    | @types.Loadsh
    | @types.Loaduh
    | @types.Loadsw
    | @types.Loaduw
    | @types.Load
    | @types.Alloc4
    | @types.Alloc8
    | @types.Alloc16
    | @types.Vaarg
    | @types.Vastart
    | @types.Par
    | @types.Parc
    | @types.Pare
    | @types.Arg
    | @types.Argc
    | @types.Arge
    | @types.Call
    | @types.Vacall => true
    _ => false
  }
}

///|
fn pinned(i : @types.Ins) -> Bool {
  op_pinned(i) || isdivwl(i)
}

///|
// Pinned instructions that can be eliminated if unused.
fn canelim(i : @types.Ins) -> Bool {
  i.op.is_load() || isalloc_op(i.op) || isdivwl(i)
}

///|
fn isalloc_op(op : @types.Op) -> Bool {
  match op {
    @types.Alloc4 | @types.Alloc8 | @types.Alloc16 => true
    _ => false
  }
}

///|
fn cheap(i : @types.Ins) -> Bool {
  if i.cls.base() != 0 {
    return false
  }
  match i.op {
    @types.Add
    | @types.Sub
    | @types.Mul
    | @types.And
    | @types.Or
    | @types.Xor
    | @types.Sar
    | @types.Shr
    | @types.Shl => true
    _ => is_cmp_op(i.op)
  }
}

// ---------------------------------------------------------------------------
// GCM state
// ---------------------------------------------------------------------------

///|
struct GcmState {
  fn_ : @types.Fn
  mut depth : Array[Int]
  gcmbid : Array[Int]
  mut def_idx : Array[Int]
  sinkbuf : Array[@types.Ins]
}

///|
fn GcmState::new(fn_ : @types.Fn) -> GcmState {
  GcmState::{
    fn_,
    depth: [],
    gcmbid: Array::make(fn_.ntmp(), -1),
    def_idx: [],
    sinkbuf: [],
  }
}

///|
fn gcmbid_get(st : GcmState, t : Int) -> Int {
  if t >= 0 && t < st.gcmbid.length() {
    st.gcmbid[t]
  } else {
    -1
  }
}

///|
fn gcmbid_set(st : GcmState, t : Int, v : Int) -> Unit {
  while st.gcmbid.length() <= t {
    st.gcmbid.push(-1)
  }
  st.gcmbid[t] = v
}

///|
fn gcm_def_idx(st : GcmState) -> Unit {
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
// Dominator tree depth (C cfg.c filldepth).
fn depth_rec(d : Array[Int], fn_ : @types.Fn, id : Int) -> Int {
  if id < 0 || id >= d.length() {
    return 0
  }
  if d[id] >= 0 {
    return d[id]
  }
  let p = fn_.blks[id].idom
  let v = if p < 0 { 0 } else { depth_rec(d, fn_, p) + 1 }
  d[id] = v
  v
}

///|
fn gcm_filldepth(st : GcmState) -> Unit {
  let d : Array[Int] = Array::make(st.fn_.nblk(), -1)
  d[st.fn_.start_id] = 0
  for id in 0..<st.fn_.nblk() {
    ignore(depth_rec(d, st.fn_, id))
  }
  st.depth = d
}

// ---------------------------------------------------------------------------
// Early scheduling
// ---------------------------------------------------------------------------

///|
fn earlyins(st : GcmState, b_id : Int, i_idx : Int) -> Int {
  let i = st.fn_.blks[b_id].ins[i_idx]
  let b0 = schedearly(st, i.arg1)
  let b1 = schedearly(st, i.arg2)
  let mut b0 = b0
  if st.depth[b0] < st.depth[b1] {
    b0 = b1
  }
  if pinned(i) {
    b_id
  } else {
    b0
  }
}

///|
fn schedearly(st : GcmState, r : @types.Ref) -> Int {
  if !r.is_tmp() {
    return st.fn_.start_id
  }
  let t = r.tmp_val()
  let g = gcmbid_get(st, t)
  if g != -1 {
    return g
  }
  let tb = st.fn_.tmps[t].bid
  let di = st.def_idx[t]
  let mut gb = -1
  if di >= 0 {
    gcmbid_set(st, t, 0)
    gb = earlyins(st, tb, di)
    gcmbid_set(st, t, gb)
  } else {
    gb = tb
    gcmbid_set(st, t, gb)
  }
  gb
}

///|
fn earlyblk(st : GcmState, b_id : Int) -> Unit {
  let b = st.fn_.blks[b_id]
  for p in b.phi {
    for a in p.args {
      ignore(schedearly(st, a.value))
    }
  }
  for i in b.ins {
    if pinned(i) {
      ignore(schedearly(st, i.arg1))
      ignore(schedearly(st, i.arg2))
    }
  }
  ignore(schedearly(st, b.jmp.arg))
}

// ---------------------------------------------------------------------------
// Late scheduling
// ---------------------------------------------------------------------------

///|
// Least common ancestor in the dominator tree.
fn lca_bid(st : GcmState, b1 : Int, b2 : Int) -> Int {
  if b1 == -1 {
    return b2
  }
  if b2 == -1 {
    return b1
  }
  let mut x = b1
  let mut y = b2
  while st.depth[x] > st.depth[y] {
    x = st.fn_.blks[x].idom
  }
  while st.depth[y] > st.depth[x] {
    y = st.fn_.blks[y].idom
  }
  while x != y {
    x = st.fn_.blks[x].idom
    y = st.fn_.blks[y].idom
  }
  x
}

///|
fn bestbid(st : GcmState, earlybid : Int, latebid : Int) -> Int {
  if latebid == -1 {
    return -1
  }
  let mut curb = latebid
  let mut bestb = latebid
  while curb != earlybid {
    let nxt = st.fn_.blks[curb].idom
    if nxt < 0 {
      break
    }
    curb = nxt
    if st.fn_.blks[curb].loop_depth < st.fn_.blks[bestb].loop_depth {
      bestb = curb
    }
  }
  bestb
}

///|
fn lateins(st : GcmState, b_id : Int, i_idx : Int, r : @types.Ref) -> Int {
  ignore(r)
  let i = st.fn_.blks[b_id].ins[i_idx]
  let latebid = schedlate(st, i.to)
  if pinned(i) {
    if latebid == -1 && canelim(i) {
      return -1
    }
    return b_id
  }
  latebid
}

///|
fn latephi(st : GcmState, p : @types.Phi, r : @types.Ref) -> Int {
  if p.args.length() == 0 {
    return -1
  }
  let mut latebid = -1
  for a in p.args {
    if a.value.eq(r) {
      latebid = lca_bid(st, latebid, a.blk_id)
    }
  }
  latebid
}

///|
fn latejmp(b : @types.Blk, r : @types.Ref) -> Int {
  ignore(r)
  if b.jmp.arg.is_none() {
    -1
  } else {
    b.id
  }
}

///|
fn schedlate(st : GcmState, r : @types.Ref) -> Int {
  if !r.is_tmp() {
    return -1
  }
  let t = r.tmp_val()
  if st.fn_.tmps[t].visit != 0 {
    return gcmbid_get(st, t)
  }
  st.fn_.tmps[t].visit = 1
  let earlybid = gcmbid_get(st, t)
  if earlybid == -1 {
    return -1
  }
  gcmbid_set(st, t, st.fn_.tmps[t].bid)
  let mut latebid = -1
  let n = st.fn_.tmps[t].nuse
  for k in 0..<n {
    let u = st.fn_.tmps[t].uses[k]
    let b = st.fn_.blks[u.blk_id]
    let ulb = match u.kind {
      @types.UXXX => -1
      @types.UPhi => latephi(st, b.phi[u.ins_idx], r)
      @types.UIns => lateins(st, u.blk_id, u.ins_idx, r)
      @types.UJmp => latejmp(b, r)
    }
    latebid = lca_bid(st, latebid, ulb)
  }
  let di = st.def_idx[t]
  if di >= 0 && !pinned(st.fn_.blks[st.fn_.tmps[t].bid].ins[di]) {
    gcmbid_set(st, t, bestbid(st, earlybid, latebid))
  }
  gcmbid_get(st, t)
}

///|
fn lateblk(st : GcmState, b_id : Int) -> Unit {
  let b = st.fn_.blks[b_id]
  for pi in 0..<b.phi.length() {
    let p = b.phi[pi]
    if schedlate(st, p.to) == -1 {
      p.args.clear()
    }
  }
  for i in b.ins {
    if pinned(i) {
      ignore(schedlate(st, i.to))
    }
  }
}

// ---------------------------------------------------------------------------
// Moving instructions
// ---------------------------------------------------------------------------

///|
fn add_one(st : GcmState, i : @types.Ins) -> Unit {
  if i.op == @types.Nop {
    return
  }
  if !i.to.is_tmp() {
    return
  }
  let gb = gcmbid_get(st, i.to.tmp_val())
  if gb < 0 || gb >= st.fn_.nblk() {
    return
  }
  st.fn_.blks[gb].ins.push(i)
}

///|
fn addgcmins(st : GcmState, vins : Array[@types.Ins], reverse : Bool) -> Unit {
  if reverse {
    let mut k = vins.length()
    while k > 0 {
      k = k - 1
      add_one(st, vins[k])
    }
  } else {
    for x in vins {
      add_one(st, x)
    }
  }
}

///|
fn gcmmove(st : GcmState) -> Unit {
  let vins : Array[@types.Ins] = []
  for t in 0..<st.fn_.ntmp() {
    let di = st.def_idx[t]
    if di < 0 {
      continue
    }
    let tb = st.fn_.tmps[t].bid
    let gb = gcmbid_get(st, t)
    if tb == gb {
      continue
    }
    let i = st.fn_.blks[tb].ins[di]
    if pinned(i) && !canelim(i) {
      continue
    }
    if gb != -1 {
      vins.push(ins_copy(i))
    }
    st.fn_.blks[tb].ins[di] = nop_ins()
  }
  addgcmins(st, vins, false)
}

// ---------------------------------------------------------------------------
// Sinking cheap ops to uses (C sink/sinkref)
// ---------------------------------------------------------------------------

///|
fn sinkref(st : GcmState, b_id : Int, pr : @types.Ref) -> @types.Ref {
  if !pr.is_tmp() {
    return pr
  }
  let tid = pr.tmp_val()
  let di = st.def_idx[tid]
  if di < 0 {
    return pr
  }
  let tb = st.fn_.tmps[tid].bid
  if tb == b_id {
    return pr
  }
  let defi = st.fn_.blks[tb].ins[di]
  if pinned(defi) || !cheap(defi) {
    return pr
  }
  let i = ins_copy(defi)
  let cls = st.fn_.tmps[tid].cls
  let r = @types.Ref::tmp(st.fn_.new_tmp("snk", cls))
  i.to = r
  gcmbid_set(st, r.tmp_val(), b_id)
  st.sinkbuf.push(ins_copy(i))
  i.arg1 = sinkref(st, b_id, i.arg1)
  i.arg2 = sinkref(st, b_id, i.arg2)
  r
}

///|
fn sink(st : GcmState) -> Unit {
  for b_id in st.fn_.def_order {
    let b = st.fn_.blks[b_id]
    for idx in 0..<b.ins.length() {
      let op = b.ins[idx].op
      if op.is_load() {
        b.ins[idx].arg1 = sinkref(st, b_id, b.ins[idx].arg1)
      } else if op.is_store() {
        b.ins[idx].arg2 = sinkref(st, b_id, b.ins[idx].arg2)
      }
    }
    b.jmp.arg = sinkref(st, b_id, b.jmp.arg)
  }
  addgcmins(st, st.sinkbuf, true)
  st.sinkbuf.clear()
}

// ---------------------------------------------------------------------------
// Instruction scheduling within a block (C schedblk/schedins/igroup)
// ---------------------------------------------------------------------------

///|
fn igroup(fn_ : @types.Fn, b : @types.Blk, i_idx : Int) -> (Int, Int) {
  ignore(fn_)
  let ie = b.ins.length()
  let op = b.ins[i_idx].op
  if op.is_par() {
    let mut i0 = i_idx
    while i0 > 0 && b.ins[i0 - 1].op.is_par() {
      i0 = i0 - 1
    }
    let mut i1 = i_idx
    while i1 < ie && b.ins[i1].op.is_par() {
      i1 = i1 + 1
    }
    (i0, i1)
  } else if op.is_arg() || op == @types.Call || op == @types.Vacall {
    let mut i0 = i_idx
    while i0 > 0 && b.ins[i0 - 1].op.is_arg() {
      i0 = i0 - 1
    }
    let mut i1 = i_idx
    while i1 < ie &&
          b.ins[i1].op != @types.Call &&
          b.ins[i1].op != @types.Vacall {
      i1 = i1 + 1
    }
    if i1 < ie {
      i1 = i1 + 1
    }
    (i0, i1)
  } else {
    (i_idx, i_idx + 1)
  }
}

///|
fn schedins(
  st : GcmState,
  b : @types.Blk,
  i_idx : Int,
  vins : Array[@types.Ins],
) -> Int {
  let (i0, i1) = igroup(st.fn_, b, i_idx)
  for k in i0..<i1 {
    let i = b.ins[k]
    for n in 0..<2 {
      let arg = if n == 0 { i.arg1 } else { i.arg2 }
      if !arg.is_tmp() {
        continue
      }
      let t = arg.tmp_val()
      if st.fn_.tmps[t].bid != b.id {
        continue
      }
      let di = st.def_idx[t]
      if di < 0 {
        continue
      }
      ignore(schedins(st, b, di, vins))
    }
  }
  for k in i0..<i1 {
    let i = b.ins[k]
    if i.op != @types.Nop {
      vins.push(ins_copy(i))
    }
    b.ins[k] = nop_ins()
  }
  i1
}

///|
fn schedblk(st : GcmState) -> Unit {
  for b_id in st.fn_.def_order {
    let b = st.fn_.blks[b_id]
    let vins : Array[@types.Ins] = []
    let mut i = 0
    while i < b.ins.length() {
      i = schedins(st, b, i, vins)
    }
    b.ins.clear()
    for x in vins {
      b.ins.push(x)
    }
  }
}

// ---------------------------------------------------------------------------
// Pass entry point
// ---------------------------------------------------------------------------

///|
// Global code motion (C gcm.c).  Requires use/dom; this port refreshes them
// defensively.  Returns the -dG debug text (empty when print_dbg is false).
pub fn gcm(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let st = GcmState::new(fn_)
  @cfg.fillrpo(fn_)
  @cfg.fillpreds(fn_)
  @cfg.filldom(fn_)
  g_filluse(fn_)
  @cfg.fillloop(fn_)
  gcm_filldepth(st)
  gcm_def_idx(st)
  for t in 0..<fn_.ntmp() {
    fn_.tmps[t].visit = 0
    gcmbid_set(st, t, -1)
  }
  for b_id in fn_.rpo {
    earlyblk(st, b_id)
  }
  for b_id in fn_.rpo {
    lateblk(st, b_id)
  }
  // Remove phis that lateblk marked unused so later passes/dumps skip them.
  for id in fn_.def_order {
    let b = fn_.blks[id]
    let kept : Array[@types.Phi] = []
    for p in b.phi {
      if p.args.length() > 0 {
        kept.push(p)
      }
    }
    b.phi.clear()
    for p in kept {
      b.phi.push(p)
    }
  }
  gcmmove(st)
  g_filluse(fn_)
  gcm_def_idx(st)
  sink(st)
  g_filluse(fn_)
  gcm_def_idx(st)
  schedblk(st)
  if print_dbg {
    "\n> After GCM:\n" + @parser.printfn(fn_, interner, all_typs) + "\n"
  } else {
    ""
  }
}
