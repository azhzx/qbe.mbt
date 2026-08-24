///|
// Register allocation - corresponds to rega.c in QBE.
// Depends on rpo, phi, cost, and (obviously) spill.

///|
// Block-local register mapping (C struct RMap).
priv struct RMap {
  t : Array[Int] // 64 entries
  r : Array[Int] // 64 entries
  w : Array[Int] // 64 entries, wait list for unmatched hints
  mut b : @types.BSet
  mut n : Int
}

///|
fn rmap_new(nt : Int) -> RMap {
  RMap::{
    t: Array::make(64, 0),
    r: Array::make(64, 0),
    w: Array::make(64, 0),
    b: @types.BSet::new(nt),
    n: 0,
  }
}

///|
// Copy of the mapping arrays (C rcopy). The BSet bits are never read from
// the copies, so sharing the reference is fine.
fn rcopy(ma : RMap, mb : RMap) -> Unit {
  for i = 0; i < 64; i = i + 1 {
    ma.t[i] = mb.t[i]
    ma.r[i] = mb.r[i]
    ma.w[i] = mb.w[i]
  }
  ma.n = mb.n
  ma.b = mb.b
}

///|
priv struct RState {
  fn_ : @types.Fn
  buf : Array[@types.Ins]
  mut regu : UInt64
  pm : Array[PmEntry]
  mut npm : Int
  mut cur_loop : Int
  mut stmov : Int
  mut stblk : Int
}

///|
priv struct PmEntry {
  src : @types.Ref
  dst : @types.Ref
  cls : @types.Class
}

///|
// The register hint of a temporary (C hint(), through phicls).
fn hint(st : RState, t : Int) -> Int {
  st.fn_.tmps[@types.phicls(t, st.fn_.tmps)].hint.r
}

///|
fn sethint(st : RState, t : Int, r : Int) -> Unit {
  let pc = @types.phicls(t, st.fn_.tmps)
  if st.fn_.tmps[pc].hint.r == -1 || st.fn_.tmps[pc].hint.w > st.cur_loop {
    st.fn_.tmps[pc].hint.r = r
    st.fn_.tmps[pc].hint.w = st.cur_loop
    st.fn_.tmps[t].visit = -1
  }
}

///|
fn r_emit(
  st : RState,
  op : @types.Op,
  k : @types.Class,
  to : @types.Ref,
  a0 : @types.Ref,
  a1 : @types.Ref,
) -> Unit {
  st.buf.push(@types.Ins::new(op, k, to, a0, a1))
}

///|
fn r_emiti(st : RState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
fn emit_block(st : RState) -> Array[@types.Ins] {
  let r : Array[@types.Ins] = Array::new()
  for k = st.buf.length() - 1; k >= 0; k = k - 1 {
    r.push(st.buf[k])
  }
  r
}

///|
fn rfind(m : RMap, t : Int) -> Int {
  for i = 0; i < m.n; i = i + 1 {
    if m.t[i] == t {
      return m.r[i]
    }
  }
  -1
}

///|
fn rref(st : RState, m : RMap, t : Int) -> @types.Ref {
  let r = rfind(m, t)
  if r == -1 {
    let s = st.fn_.tmps[t].slot
    @types.Ref::slot(s)
  } else {
    @types.Ref::tmp(r)
  }
}

///|
fn radd(st : RState, m : RMap, t : Int, r : Int) -> Unit {
  m.b.set(t)
  m.b.set(r)
  m.t[m.n] = t
  m.r[m.n] = r
  m.n = m.n + 1
  st.regu = st.regu | (1UL << r)
}

///|
fn ralloctry(st : RState, m : RMap, t : Int, try_ : Bool) -> @types.Ref {
  if t < @types.Tmp0 {
    return @types.Ref::tmp(t)
  }
  if m.b.has(t) {
    let r = rfind(m, t)
    return @types.Ref::tmp(r)
  }
  let mut r = st.fn_.tmps[t].visit
  if r == -1 || m.b.has(r) {
    r = hint(st, t)
  }
  if r == -1 || m.b.has(r) {
    if try_ {
      return @types.ref_none()
    }
    let mut regs = st.fn_.tmps[@types.phicls(t, st.fn_.tmps)].hint.m
    regs = regs | m.b.bits[0]
    let r0 = if @types.kbase(st.fn_.tmps[t].cls) == 0 {
      @types.RAX
    } else {
      @types.XMM0
    }
    let r1 = r0 + (if @types.kbase(st.fn_.tmps[t].cls) == 0 { 16 } else { 15 })
    let mut found = -1
    for rr = r0; rr < r1; rr = rr + 1 {
      if (regs & (1UL << rr)) == 0 {
        found = rr
        break
      }
    }
    if found < 0 {
      for rr = r0; rr < r1; rr = rr + 1 {
        if !m.b.has(rr) {
          found = rr
          break
        }
      }
    }
    if found < 0 {
      abort("no more regs")
    }
    r = found
  }
  radd(st, m, t, r)
  sethint(st, t, r)
  st.fn_.tmps[t].visit = r
  let h = hint(st, t)
  if h != -1 && h != r {
    m.w[h] = t
  }
  @types.Ref::tmp(r)
}

///|
fn ralloc(st : RState, m : RMap, t : Int) -> @types.Ref {
  ralloctry(st, m, t, false)
}

///|
fn rfree(_st : RState, m : RMap, t : Int) -> Int {
  if !m.b.has(t) {
    return -1
  }
  let mut i = 0
  while m.t[i] != t {
    i = i + 1
  }
  let r = m.r[i]
  m.b.clr(t)
  m.b.clr(r)
  m.n = m.n - 1
  while i < m.n {
    m.t[i] = m.t[i + 1]
    m.r[i] = m.r[i + 1]
    i = i + 1
  }
  r
}

///|
fn isreg(r : @types.Ref) -> Bool {
  r.is_tmp() && r.tmp_val() < @types.Tmp0
}

///|
fn is_regcpy(i : @types.Ins) -> Bool {
  i.op == @types.Copy && isreg(i.arg1)
}

///|
fn pmadd(
  st : RState,
  src : @types.Ref,
  dst : @types.Ref,
  k : @types.Class,
) -> Unit {
  st.pm[st.npm] = PmEntry::{ src, dst, cls: k }
  st.npm = st.npm + 1
}

///|
// Parallel move states (C enum PMStat).
const TOMOVE = 0

///|
const MOVING = 1

///|
const MOVED = 2

///|
fn pmrec(st : RState, status : Array[Int], i : Int, k : @ref.Ref[Int]) -> Int {
  if @types.req(st.pm[i].src, st.pm[i].dst) {
    status[i] = MOVED
    return -1
  }
  k.val = k.val | @types.kcode(st.pm[i].cls)
  let mut j = 0
  while j < st.npm {
    if @types.req(st.pm[j].dst, st.pm[i].src) {
      break
    }
    j = j + 1
  }
  let mut c = 0
  if j == st.npm {
    status[i] = MOVED
    r_emit(
      st,
      @types.Copy,
      st.pm[i].cls,
      st.pm[i].dst,
      st.pm[i].src,
      @types.ref_none(),
    )
    return -1
  } else {
    match status[j] {
      MOVING => {
        c = j
        r_emit(
          st,
          @types.Swap,
          @types.class_from_code(k.val),
          @types.ref_none(),
          st.pm[i].src,
          st.pm[i].dst,
        )
      }
      TOMOVE => {
        status[i] = MOVING
        c = pmrec(st, status, j, k)
        if c == i {
          c = -1
        } else if c != -1 {
          r_emit(
            st,
            @types.Swap,
            @types.class_from_code(k.val),
            @types.ref_none(),
            st.pm[i].src,
            st.pm[i].dst,
          )
        } else {
          r_emit(
            st,
            @types.Copy,
            st.pm[i].cls,
            st.pm[i].dst,
            st.pm[i].src,
            @types.ref_none(),
          )
        }
      }
      MOVED => {
        r_emit(
          st,
          @types.Copy,
          st.pm[i].cls,
          st.pm[i].dst,
          st.pm[i].src,
          @types.ref_none(),
        )
        c = -1
      }
      _ => abort("invalid pm status")
    }
  }
  status[i] = MOVED
  c
}

///|
fn pmgen(st : RState) -> Unit {
  let status : Array[Int] = Array::make(st.npm, TOMOVE)
  for i = 0; i < st.npm; i = i + 1 {
    if status[i] == TOMOVE {
      ignore(pmrec(st, status, i, @ref.new(@types.kcode(st.pm[i].cls))))
    }
  }
}

///|
fn r_move(st : RState, r : Int, to : @types.Ref, m : RMap) -> Unit {
  if to.is_tmp() {
    ignore(rfree(st, m, to.tmp_val()))
  }
  if m.b.has(r) {
    let mut n = 0
    while m.r[n] != r {
      n = n + 1
    }
    let t = m.t[n]
    ignore(rfree(st, m, t))
    m.b.set(r)
    ignore(ralloc(st, m, t))
    m.b.clr(r)
  }
  let t = if to.is_none() { r } else { to.tmp_val() }
  radd(st, m, t, r)
}

///|
// Process a run of consecutive copy-from-register instructions in rega
// (C dopm in rega.c). Returns the index of the first copy in the run.
fn rega_dopm(st : RState, b : @types.Blk, i : Int, m : RMap) -> Int {
  let m0 = rmap_new(st.fn_.ntmp())
  for z = 0; z < 64; z = z + 1 {
    m0.t[z] = m.t[z]
    m0.r[z] = m.r[z]
  }
  m0.n = m.n
  let i1 = i + 1
  let mut idx = i + 1
  while true {
    idx = idx - 1
    r_move(st, b.ins[idx].arg1.tmp_val(), b.ins[idx].to, m)
    if idx != 0 && is_regcpy(b.ins[idx - 1]) {
      continue
    } else {
      break
    }
  }
  if idx != 0 && b.ins[idx - 1].op == @types.Call {
    let rr = @types.retregs(b.ins[idx - 1].arg2)
    let def = rr.0 | @types.rglob_mask()
    for z = 0; z < @types.rsave.length(); z = z + 1 {
      if (def & (1UL << @types.rsave[z])) == 0 {
        r_move(st, @types.rsave[z], @types.ref_none(), m)
      }
    }
  }
  st.npm = 0
  for n = 0; n < m.n; n = n + 1 {
    let t = m.t[n]
    let s = st.fn_.tmps[t].slot
    let r1 = m.r[n]
    let r = rfind(m0, t)
    if r != -1 {
      pmadd(st, @types.Ref::tmp(r1), @types.Ref::tmp(r), st.fn_.tmps[t].cls)
    } else if s != -1 {
      pmadd(st, @types.Ref::tmp(r1), @types.Ref::slot(s), st.fn_.tmps[t].cls)
    }
  }
  for ip = idx; ip < i1; ip = ip + 1 {
    if !b.ins[ip].to.is_none() {
      ignore(rfree(st, m, b.ins[ip].to.tmp_val()))
    }
    let r = b.ins[ip].arg1.tmp_val()
    if rfind(m, r) == -1 {
      radd(st, m, r, r)
    }
  }
  pmgen(st)
  idx
}

///|
// Priority of a ref for the argument allocation list (C prio1).
fn prio1(st : RState, r1 : @types.Ref, r2 : @types.Ref) -> Bool {
  ignore(r2)
  hint(st, r1.tmp_val()) != -1
}

///|
// Insert a ref-slot into the priority list (C insert).
fn insert(
  st : RState,
  slot : (Int, Int, Int),
  rs : Array[(Int, Int, Int)],
  p : Int,
) -> Unit {
  rs[p] = slot
  let mut i = p
  while i > 0 {
    i = i - 1
    let rr = read_slot(st, rs[i])
    if prio1(st, read_slot(st, slot), rr) {
      rs[i + 1] = rs[i]
      rs[i] = slot
    } else {
      break
    }
  }
}

///|
// Read the current Ref at a ref-slot: (kind, idx1, idx2) where kind 0 is a
// buffer ins argument (idx1=buf index, idx2=0/1 for arg1/arg2), kind 1 is a
// mem base, kind 2 is a mem index.
fn read_slot(st : RState, s : (Int, Int, Int)) -> @types.Ref {
  if s.0 == 0 {
    if s.2 == 0 {
      st.buf[s.1].arg1
    } else {
      st.buf[s.1].arg2
    }
  } else if s.0 == 1 {
    st.fn_.mems[s.1].base
  } else {
    st.fn_.mems[s.1].index
  }
}

///|
fn write_slot(st : RState, s : (Int, Int, Int), r : @types.Ref) -> Unit {
  if s.0 == 0 {
    if s.2 == 0 {
      st.buf[s.1].arg1 = r
    } else {
      st.buf[s.1].arg2 = r
    }
  } else if s.0 == 1 {
    st.fn_.mems[s.1].base = r
  } else {
    st.fn_.mems[s.1].index = r
  }
}

///|
// The default case of the doblk switch (C default in doblk): free the
// destination's register and rewrite the buffer ins. Returns the freed
// register, or -1 if the ins has no live-out effect, or -2 if the ins is dead.
fn doblk_def(st : RState, cur : RMap, last : Int) -> Int {
  let ins = st.buf[last]
  if !ins.to.is_none() {
    let r = ins.to.tmp_val()
    if r < @types.Tmp0 && (@types.rglob_mask() & (1UL << r)) != 0 {
      return -1
    }
    let rf = rfree(st, cur, r)
    if rf == -1 {
      return -2
    }
    ins.to = @types.Ref::tmp(rf)
    rf
  } else {
    -1
  }
}

///|
// Allocate registers for one block (C doblk).
fn doblk(st : RState, b : @types.Blk, cur : RMap) -> Unit {
  // registers live-in are mapped to themselves
  let mut r = b.out_set.unwrap().iter(0)
  while r >= 0 && r < @types.Tmp0 {
    radd(st, cur, r, r)
    r = b.out_set.unwrap().iter(r + 1)
  }
  if b.jmp.arg.is_tmp() {
    b.jmp.arg = ralloc(st, cur, b.jmp.arg.tmp_val())
  }
  st.buf.clear()
  let mut i1 = b.ins.length()
  while i1 > 0 {
    i1 = i1 - 1
    r_emiti(st, b.ins[i1])
    let last = st.buf.length() - 1
    let ins = st.buf[last]
    let mut rf = -1
    if ins.op == @types.Call {
      let ar = @types.argregs(ins.arg2)
      let rs = ar.0 | @types.rglob_mask()
      for z = 0; z < @types.rsave.length(); z = z + 1 {
        if (rs & (1UL << @types.rsave[z])) == 0 {
          ignore(rfree(st, cur, @types.rsave[z]))
        }
      }
    } else {
      if ins.op == @types.Copy {
        if is_regcpy(ins) {
          ignore(st.buf.pop())
          i1 = rega_dopm(st, b, i1, cur)
          st.stmov = st.stmov + (st.buf.length() - last)
          continue
        }
        if isreg(ins.to) && ins.arg1.is_tmp() {
          sethint(st, ins.arg1.tmp_val(), ins.to.tmp_val())
        }
      }
      let rr = doblk_def(st, cur, last)
      if rr == -2 {
        ignore(st.buf.pop())
        continue
      }
      rf = rr
    }
    // collect and prioritize arguments
    let ra : Array[(Int, Int, Int)] = Array::make(4, (0, 0, 0))
    let mut nr = 0
    for x = 0; x < 2; x = x + 1 {
      let arg = if x == 0 { st.buf[last].arg1 } else { st.buf[last].arg2 }
      match arg {
        @types.RMem(mi) => {
          let m = st.fn_.mems[mi]
          if m.base.is_tmp() {
            insert(st, (1, mi, 0), ra, nr)
            nr = nr + 1
          }
          if m.index.is_tmp() {
            insert(st, (2, mi, 0), ra, nr)
            nr = nr + 1
          }
        }
        @types.RTmp(_) => {
          insert(st, (0, last, x), ra, nr)
          nr = nr + 1
        }
        _ => ()
      }
    }
    for z = 0; z < nr; z = z + 1 {
      let slot = ra[z]
      let v = read_slot(st, slot)
      write_slot(st, slot, ralloc(st, cur, v.tmp_val()))
    }
    // try to change the register of a hinted temporary if rf is available
    if rf != -1 {
      let t = cur.w[rf]
      if t != 0 {
        if !cur.b.has(rf) && hint(st, t) == rf {
          let rt = rfree(st, cur, t)
          if rt != -1 {
            st.fn_.tmps[t].visit = -1
            ignore(ralloc(st, cur, t))
            r_emit(
              st,
              @types.Copy,
              st.fn_.tmps[t].cls,
              @types.Ref::tmp(rt),
              @types.Ref::tmp(rf),
              @types.ref_none(),
            )
            st.stmov = st.stmov + 1
            cur.w[rf] = 0
            for z = 0; z < nr; z = z + 1 {
              let slot = ra[z]
              if @types.req(read_slot(st, slot), @types.Ref::tmp(rt)) {
                write_slot(st, slot, @types.Ref::tmp(rf))
              }
            }
          }
        }
      }
    }
  }
  let nb = emit_block(st)
  b.ins.clear()
  for x in nb {
    b.ins.push(x)
  }
}

///|
// qsort comparison for carve: peel loop nests from inside out.
fn carve_cmp(st : RState, a : Int, b : Int) -> Int {
  let ba = st.fn_.blks[a]
  let bb = st.fn_.blks[b]
  if ba.loop_depth == bb.loop_depth {
    if ba.rpo_id > bb.rpo_id {
      -1
    } else if ba.rpo_id < bb.rpo_id {
      1
    } else {
      0
    }
  } else if ba.loop_depth > bb.loop_depth {
    -1
  } else {
    1
  }
}

///|
// Comparison to order temporaries for allocation at the end of blocks.
fn prio2(st : RState, t1 : Int, t2 : Int) -> Int {
  if (st.fn_.tmps[t1].visit ^ st.fn_.tmps[t2].visit) < 0 {
    return if st.fn_.tmps[t1].visit != -1 { 1 } else { -1 }
  }
  if (hint(st, t1) ^ hint(st, t2)) < 0 {
    return if hint(st, t1) != -1 { 1 } else { -1 }
  }
  st.fn_.tmps[t1].cost - st.fn_.tmps[t2].cost
}

///|
// Register allocation (C rega). Returns the -dR debug text (empty when
// print_dbg is false).
pub fn rega(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let st = RState::{
    fn_,
    buf: Array::new(),
    regu: 0,
    pm: Array::make(64, PmEntry::{
      src: @types.ref_none(),
      dst: @types.ref_none(),
      cls: @types.Kx,
    }),
    npm: 0,
    cur_loop: 0,
    stmov: 0,
    stblk: 0,
  }
  let nblk = fn_.rpo.length()
  let end : Array[RMap] = Array::new()
  let beg : Array[RMap] = Array::new()
  for n = 0; n < nblk; n = n + 1 {
    end.push(rmap_new(fn_.ntmp()))
    beg.push(rmap_new(fn_.ntmp()))
  }

  // 1. setup
  st.cur_loop = 2147483647
  for t = 0; t < fn_.tmps.length(); t = t + 1 {
    fn_.tmps[t].hint.r = if t < @types.Tmp0 { t } else { -1 }
    fn_.tmps[t].hint.w = st.cur_loop
    fn_.tmps[t].visit = -1
  }
  // sort blocks by loop nesting (C carve)
  let blk : Array[Int] = Array::new()
  for id in fn_.def_order {
    blk.push(id)
  }
  @util.qsort_int(blk, 0, nblk - 1, fn(a, b) { carve_cmp(st, a, b) })
  // hint the leading copy chain of the start block
  for idx = 0; idx < fn_.blks[fn_.start_id].ins.length(); idx = idx + 1 {
    let i = fn_.blks[fn_.start_id].ins[idx]
    if i.op != @types.Copy || !isreg(i.arg1) {
      break
    } else {
      sethint(st, i.to.tmp_val(), i.arg1.tmp_val())
    }
  }

  // 2. assign registers
  for z = 0; z < nblk; z = z + 1 {
    let b = fn_.blks[blk[z]]
    let n = b.rpo_id
    st.cur_loop = b.loop_depth
    let cur = rmap_new(fn_.ntmp())
    // sort out-set temps by priority (C prio2 insertion sort)
    let rl : Array[Int] = Array::make(64, 0)
    let mut x = 0
    let mut t = b.out_set.unwrap().iter(@types.Tmp0)
    while t >= 0 {
      rl[x] = t
      let mut j = x
      x = x + 1
      while j > 0 {
        j = j - 1
        if prio2(st, t, rl[j]) > 0 {
          rl[j + 1] = rl[j]
          rl[j] = t
        } else {
          break
        }
      }
      t = b.out_set.unwrap().iter(t + 1)
    }
    for j = 0; j < x; j = j + 1 {
      ignore(ralloctry(st, cur, rl[j], true))
    }
    for j = 0; j < x; j = j + 1 {
      ignore(ralloc(st, cur, rl[j]))
    }
    rcopy(end[n], cur)
    doblk(st, b, cur)
    b.in_set.unwrap().copy_from(cur.b)
    for p in b.phi {
      if p.to.is_tmp() {
        b.in_set.unwrap().clr(p.to.tmp_val())
      }
    }
    rcopy(beg[n], cur)
  }

  // 3. emit copies shared by multiple edges to the same block
  for id in fn_.def_order {
    let s = fn_.blks[id]
    if s.npred <= 1 {
      continue
    }
    let m = beg[s.rpo_id]
    // rl maps a register live at the beginning of s to the one used in all
    // predecessors (if any, -1 otherwise)
    let rl : Array[Int] = Array::make(64, 0)
    for p in s.phi {
      let r = rfind(m, p.to.tmp_val())
      if r == -1 {
        continue
      }
      for a in p.args {
        let b = a.blk_id
        let src = a.value
        if !src.is_tmp() {
          continue
        }
        let xx = rfind(end[fn_.blks[b].rpo_id], src.tmp_val())
        if xx != -1 {
          if rl[r] == 0 || rl[r] == xx {
            rl[r] = xx
          } else {
            rl[r] = -1
          }
        }
      }
      if rl[r] == 0 {
        rl[r] = -1
      }
    }
    for j = 0; j < m.n; j = j + 1 {
      let t = m.t[j]
      let r = m.r[j]
      if rl[r] != 0 || t < @types.Tmp0 {
        continue
      }
      for bp = 0; bp < s.npred; bp = bp + 1 {
        let xx = rfind(end[fn_.blks[s.pred[bp]].rpo_id], t)
        if xx != -1 {
          if rl[r] == 0 || rl[r] == xx {
            rl[r] = xx
          } else {
            rl[r] = -1
          }
        }
      }
    }
    st.npm = 0
    for j = 0; j < m.n; j = j + 1 {
      let t = m.t[j]
      let r = m.r[j]
      let xx = rl[r]
      if xx > 0 {
        pmadd(st, @types.Ref::tmp(xx), @types.Ref::tmp(r), fn_.tmps[t].cls)
        m.r[j] = xx
      }
    }
    st.buf.clear()
    pmgen(st)
    let nb = emit_block(st)
    if nb.length() == 0 {
      continue
    }
    st.stmov = st.stmov + nb.length()
    let new_ins : Array[@types.Ins] = Array::new()
    for xi in nb {
      new_ins.push(xi)
    }
    for xi in s.ins {
      new_ins.push(xi)
    }
    s.ins.clear()
    for xi in new_ins {
      s.ins.push(xi)
    }
  }

  // 4. emit remaining copies in new blocks
  let blist : Array[Int] = Array::new()
  let nblocks0 = fn_.def_order.length()
  for bi = 0; bi < nblocks0; bi = bi + 1 {
    let b_id = fn_.def_order[bi]
    let b = fn_.blks[b_id]
    for succ_idx = 0; succ_idx < 2; succ_idx = succ_idx + 1 {
      let sp = if succ_idx == 0 { b.jmp.s1 } else { b.jmp.s2 }
      if sp < 0 {
        continue
      }
      let s = fn_.blks[sp]
      st.npm = 0
      for p in s.phi {
        let mut dst = p.to
        if dst.is_tmp() {
          let r = rfind(beg[s.rpo_id], dst.tmp_val())
          if r == -1 {
            continue
          }
          dst = @types.Ref::tmp(r)
        }
        let mut u = 0
        while p.args[u].blk_id != b_id {
          u = u + 1
        }
        let mut src = p.args[u].value
        if src.is_tmp() {
          src = rref(st, end[fn_.blks[b_id].rpo_id], src.tmp_val())
        }
        pmadd(st, src, dst, p.cls)
      }
      let mut t = s.in_set.unwrap().iter(@types.Tmp0)
      while t >= 0 {
        let src = rref(st, end[fn_.blks[b_id].rpo_id], t)
        let dst = rref(st, beg[s.rpo_id], t)
        pmadd(st, src, dst, fn_.tmps[t].cls)
        t = s.in_set.unwrap().iter(t + 1)
      }
      st.buf.clear()
      pmgen(st)
      let nb = emit_block(st)
      if nb.length() == 0 {
        continue
      }
      let bn_id = fn_.add_blk(b.name + "_" + s.name)
      let bn = fn_.blks[bn_id]
      bn.loop_depth = (b.loop_depth + s.loop_depth) / 2
      bn.ins.clear()
      for xi in nb {
        bn.ins.push(xi)
      }
      bn.jmp.kind = @types.Jjmp
      bn.jmp.s1 = sp
      blist.push(bn_id)
      st.stmov = st.stmov + nb.length()
      st.stblk = st.stblk + 1
      if succ_idx == 0 {
        b.jmp.s1 = bn_id
      } else {
        b.jmp.s2 = bn_id
      }
    }
  }
  // append the new blocks at the end of the link chain (in reverse
  // creation order, as the C prepends to blist)
  for k = blist.length() - 1; k >= 0; k = k - 1 {
    fn_.def_order.push(blist[k])
  }
  for id in fn_.def_order {
    fn_.blks[id].phi.clear()
  }
  fn_.reg = st.regu

  if print_dbg {
    let sb = StringBuilder::new()
    sb.write_string("\n> Register mappings:\n")
    for n = 0; n < nblk; n = n + 1 {
      let b = fn_.rpo[n]
      sb.write_string("\t")
      sb.write_string(@util.lpad(fn_.blks[b].name, 10))
      sb.write_string(" beg")
      sb.write_string(mdump(st, beg[n]))
      sb.write_string("\t           end")
      sb.write_string(mdump(st, end[n]))
    }
    sb.write_string("\n")
    sb.write_string("\n> Register allocation statistics:\n")
    sb.write_string("\tnew moves:  ")
    sb.write_string(st.stmov.to_string())
    sb.write_string("\n")
    sb.write_string("\tnew blocks: ")
    sb.write_string(st.stblk.to_string())
    sb.write_string("\n")
    sb.write_string("\n> After register allocation:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}

///|
// Dump the register mapping of a block (C mdump).
fn mdump(st : RState, m : RMap) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < m.n; i = i + 1 {
    if m.t[i] >= @types.Tmp0 {
      sb.write_string(" (")
      sb.write_string(st.fn_.tmps[m.t[i]].name)
      sb.write_string(", R")
      sb.write_string(m.r[i].to_string())
      sb.write_string(")")
    }
  }
  sb.write_string("\n")
  sb.to_string()
}
