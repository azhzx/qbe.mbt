///|
// Spill code insertion - corresponds to spill.c in QBE (after fillcost).
// Requires: spill costs, rpo, liveness. Replaces the in/out liveness info
// with the temporaries that must be in registers at block borders.

///|
priv struct SpillState {
  fn_ : @types.Fn
  buf : Array[@types.Ins]
  mut fst : @types.BSet?
  ntmp : Int
  locs : Int
  mut slot4 : Int
  mut slot8 : Int
  mask : Array[@types.BSet]
}

///|
fn s_emit(
  st : SpillState,
  op : @types.Op,
  k : @types.Class,
  to : @types.Ref,
  a0 : @types.Ref,
  a1 : @types.Ref,
) -> Unit {
  st.buf.push(@types.Ins::new(op, k, to, a0, a1))
}

///|
fn s_emiti(st : SpillState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
// The emitted instructions in block order (reverse of push order).
fn emit_block(st : SpillState) -> Array[@types.Ins] {
  let r : Array[@types.Ins] = Array::new()
  for k = st.buf.length() - 1; k >= 0; k = k - 1 {
    r.push(st.buf[k])
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
// Assign/return the stack slot of a temporary (C slot in spill.c).
fn sp_slot(st : SpillState, t : Int) -> @types.Ref {
  let mut s = st.fn_.tmps[t].slot
  if s == -1 {
    if @types.kwide(st.fn_.tmps[t].cls) == 1 {
      s = st.slot8
      if st.slot4 == st.slot8 {
        st.slot4 = st.slot4 + 2
      }
      st.slot8 = st.slot8 + 2
    } else {
      s = st.slot4
      if st.slot4 == st.slot8 {
        st.slot8 = st.slot8 + 2
        st.slot4 = st.slot4 + 1
      } else {
        st.slot4 = st.slot8
      }
    }
    s = s + st.locs
    st.fn_.tmps[t].slot = s
  }
  @types.Ref::slot(s)
}

///|
fn tcmp0(st : SpillState, pa : Int, pb : Int) -> Int {
  let ca = st.fn_.tmps[pa].cost
  let cb = st.fn_.tmps[pb].cost
  if cb < ca {
    -1
  } else if cb > ca {
    1
  } else {
    0
  }
}

///|
fn tcmp1(st : SpillState, pa : Int, pb : Int) -> Int {
  let fst = st.fst.unwrap()
  let c = (if fst.has(pb) { 1 } else { 0 }) - (if fst.has(pa) { 1 } else { 0 })
  if c != 0 {
    c
  } else {
    tcmp0(st, pa, pb)
  }
}

///|
// Keep only the k highest-priority temps in b, spilling the rest (C limit).
fn limit(st : SpillState, b : @types.BSet, k : Int, f : @types.BSet?) -> Unit {
  let nt = b.count()
  if nt <= k {
    return
  }
  let tarr : Array[Int] = Array::new()
  let mut t = b.iter(0)
  while t >= 0 {
    b.clr(t)
    tarr.push(t)
    t = b.iter(t + 1)
  }
  if f is None {
    @util.qsort_int(tarr, 0, nt - 1, fn(pa, pb) { tcmp0(st, pa, pb) })
  } else {
    st.fst = f
    @util.qsort_int(tarr, 0, nt - 1, fn(pa, pb) { tcmp1(st, pa, pb) })
  }
  let mut i = 0
  while i < k && i < nt {
    b.set(tarr[i])
    i = i + 1
  }
  while i < nt {
    ignore(sp_slot(st, tarr[i]))
    i = i + 1
  }
}

///|
// Limit by register class (C limit2).
fn limit2(
  st : SpillState,
  b1 : @types.BSet,
  k1 : Int,
  k2 : Int,
  fst : @types.BSet?,
) -> Unit {
  let b2 = @types.BSet::new(st.ntmp)
  b2.copy_from(b1)
  b1.inter(st.mask[0])
  b2.inter(st.mask[1])
  limit(st, b1, 16 - k1, fst)
  limit(st, b2, 15 - k2, fst)
  ignore(b1.union(b2))
}

///|
fn sethint(st : SpillState, u : @types.BSet, r : UInt64) -> Unit {
  let mut t = u.iter(@types.Tmp0)
  while t >= 0 {
    let pc = @types.phicls(t, st.fn_.tmps)
    st.fn_.tmps[pc].hint.m = st.fn_.tmps[pc].hint.m | r
    t = u.iter(t + 1)
  }
}

///|
fn reloads(st : SpillState, u : @types.BSet, v : @types.BSet) -> Unit {
  let mut t = u.iter(@types.Tmp0)
  while t >= 0 {
    if !v.has(t) {
      s_emit(
        st,
        @types.Load,
        st.fn_.tmps[t].cls,
        @types.Ref::tmp(t),
        sp_slot(st, t),
        @types.ref_none(),
      )
    }
    t = u.iter(t + 1)
  }
}

///|
fn store(st : SpillState, r : @types.Ref, s : Int) -> Unit {
  if s != -1 {
    let op = @types.op_from_index(
      @types.op_index(@types.Storew) +
      @types.kcode(st.fn_.tmps[r.tmp_val()].cls),
    )
    s_emit(st, op, @types.Kw, @types.ref_none(), r, @types.Ref::slot(s))
  }
}

///|
// Process a run of consecutive copy-from-register instructions (C dopm in
// spill.c). Returns the index of the first copy in the run.
fn dopm(st : SpillState, b : @types.Blk, i : Int, v : @types.BSet) -> Int {
  let u = @types.BSet::new(st.ntmp)
  let mut i1 = i + 1
  let mut idx = i + 1
  while true {
    idx = idx - 1
    let t = b.ins[idx].to.tmp_val()
    if !b.ins[idx].to.is_none() {
      if v.has(t) {
        v.clr(t)
        store(st, b.ins[idx].to, st.fn_.tmps[t].slot)
      }
    }
    v.set(b.ins[idx].arg1.tmp_val())
    if idx != 0 && is_regcpy(b.ins[idx - 1]) {
      continue
    } else {
      break
    }
  }
  u.copy_from(v)
  let mut r : UInt64 = 0
  if idx != 0 && b.ins[idx - 1].op == @types.Call {
    let rr = @types.retregs(b.ins[idx - 1].arg2)
    v.bits[0] = v.bits[0] & rr.0.lnot()
    limit2(st, v, 9, 15, None)
    for n = 0; n < @types.rsave.length(); n = n + 1 {
      r = r | (1UL << @types.rsave[n])
    }
    let ar = @types.argregs(b.ins[idx - 1].arg2)
    v.bits[0] = v.bits[0] | ar.0
  } else {
    limit2(st, v, 0, 0, None)
    r = v.bits[0]
  }
  sethint(st, v, r)
  reloads(st, u, v)
  while i1 > idx {
    i1 = i1 - 1
    s_emiti(st, b.ins[i1])
  }
  idx
}

///|
// Spill code insertion (C spill).
// Returns the -dS debug text (empty when print_dbg is false).
pub fn spill(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let st = SpillState::{
    fn_,
    buf: Array::new(),
    fst: None,
    ntmp: fn_.ntmp(),
    locs: fn_.slot,
    slot4: 0,
    slot8: 0,
    mask: Array::new(),
  }
  st.mask.push(@types.BSet::new(st.ntmp))
  st.mask.push(@types.BSet::new(st.ntmp))
  for t = 0; t < st.ntmp; t = t + 1 {
    let mut k = 0
    if t >= @types.XMM0 && t < @types.XMM0 + @types.NFPR {
      k = 1
    }
    if t >= @types.Tmp0 {
      k = @types.kbase(fn_.tmps[t].cls)
    }
    st.mask[k].set(t)
  }

  for n = fn_.rpo.length() - 1; n >= 0; n = n - 1 {
    let bid = fn_.rpo[n]
    let b = fn_.blks[bid]
    // 1. find temporaries in registers at the end of the block (v)
    let s1 = b.jmp.s1
    let s2 = b.jmp.s2
    let mut hd = -1
    if s1 >= 0 && fn_.blks[s1].rpo_id <= b.rpo_id {
      hd = s1
    }
    if s2 >= 0 && fn_.blks[s2].rpo_id <= b.rpo_id {
      if hd < 0 || fn_.blks[s2].rpo_id >= fn_.blks[hd].rpo_id {
        hd = s2
      }
    }
    let v = @types.BSet::new(st.ntmp)
    if hd >= 0 {
      // back-edge
      let hgen = fn_.blks[hd].gen_set.unwrap()
      hgen.bits[0] = hgen.bits[0] | @types.rglob_mask()
      for k = 0; k < 2; k = k + 1 {
        let nreg = if k == 0 { 16 } else { 15 }
        let u = @types.BSet::new(st.ntmp)
        u.copy_from(b.out_set.unwrap())
        u.inter(st.mask[k])
        let w = @types.BSet::new(st.ntmp)
        w.copy_from(u)
        u.inter(hgen)
        w.diff(hgen)
        if u.count() < nreg {
          let j = w.count()
          let l = if k == 0 {
            fn_.blks[hd].nlive_w
          } else {
            fn_.blks[hd].nlive_d
          }
          limit(st, w, nreg - (l - j), None)
          ignore(u.union(w))
        } else {
          limit(st, u, nreg, None)
        }
        ignore(v.union(u))
      }
    } else if s1 >= 0 {
      @live.liveon(v, bid, fn_.blks[s1], fn_)
      let w = @types.BSet::new(st.ntmp)
      if s2 >= 0 {
        let u = @types.BSet::new(st.ntmp)
        @live.liveon(u, bid, fn_.blks[s2], fn_)
        w.copy_from(u)
        w.inter(v)
        ignore(v.union(u))
      }
      limit2(st, v, 0, 0, Some(w))
    } else {
      v.copy_from(b.out_set.unwrap())
      if b.jmp.arg.call_val() >= 0 {
        v.bits[0] = v.bits[0] | @types.retregs(b.jmp.arg).0
      }
    }
    // spill temps live-out but not in registers at the border
    let mut t = b.out_set.unwrap().iter(@types.Tmp0)
    while t >= 0 {
      if !v.has(t) {
        ignore(sp_slot(st, t))
      }
      t = b.out_set.unwrap().iter(t + 1)
    }
    b.out_set.unwrap().copy_from(v)

    // 2. process the block instructions
    st.buf.clear()
    let lvarg : Array[Int] = Array::make(2, 0)
    let mut idx = b.ins.length()
    while idx > 0 {
      idx = idx - 1
      let ins = b.ins[idx]
      if is_regcpy(ins) {
        idx = dopm(st, b, idx, v)
        continue
      }
      let w = @types.BSet::new(st.ntmp)
      if !ins.to.is_none() {
        let tt = ins.to.tmp_val()
        if v.has(tt) {
          v.clr(tt)
        } else {
          v.set(tt)
          w.set(tt)
        }
      }
      let mut j = @types.op_info(ins.op).nmem
      for n2 = 0; n2 < 2; n2 = n2 + 1 {
        let arg = if n2 == 0 { ins.arg1 } else { ins.arg2 }
        if arg.is_mem() {
          j = j - 1
        }
      }
      for n2 = 0; n2 < 2; n2 = n2 + 1 {
        let arg = if n2 == 0 { ins.arg1 } else { ins.arg2 }
        match arg {
          @types.RMem(mi) => {
            let m = fn_.mems[mi]
            if m.base.is_tmp() {
              v.set(m.base.tmp_val())
              w.set(m.base.tmp_val())
            }
            if m.index.is_tmp() {
              v.set(m.index.tmp_val())
              w.set(m.index.tmp_val())
            }
          }
          @types.RTmp(_) => {
            let tt = arg.tmp_val()
            lvarg[n2] = if v.has(tt) { 1 } else { 0 }
            v.set(tt)
            if j <= 0 {
              w.set(tt)
            }
            j = j - 1
          }
          _ => ()
        }
      }
      let u = @types.BSet::new(st.ntmp)
      u.copy_from(v)
      limit2(st, v, 0, 0, Some(w))
      for n2 = 0; n2 < 2; n2 = n2 + 1 {
        let arg = if n2 == 0 { ins.arg1 } else { ins.arg2 }
        if arg.is_tmp() {
          let tt = arg.tmp_val()
          if !v.has(tt) {
            if lvarg[n2] == 0 {
              u.clr(tt)
            }
            if n2 == 0 {
              b.ins[idx].arg1 = sp_slot(st, tt)
            } else {
              b.ins[idx].arg2 = sp_slot(st, tt)
            }
          }
        }
      }
      reloads(st, u, v)
      if !ins.to.is_none() {
        let tt = ins.to.tmp_val()
        store(st, ins.to, fn_.tmps[tt].slot)
        v.clr(tt)
      }
      s_emiti(st, b.ins[idx])
      let r = v.bits[0]
      if r != 0 {
        sethint(st, v, r)
      }
    }

    for p in b.phi {
      let tt = p.to.tmp_val()
      if v.has(tt) {
        v.clr(tt)
        store(st, p.to, fn_.tmps[tt].slot)
      } else if b.in_set.unwrap().has(tt) {
        p.to = sp_slot(st, tt)
      }
    }
    b.in_set.unwrap().copy_from(v)
    let nb = emit_block(st)
    b.ins.clear()
    for x in nb {
      b.ins.push(x)
    }
  }

  // align the locals to a 16 byte boundary
  st.slot8 = st.slot8 + (st.slot8 & 3)
  fn_.slot = fn_.slot + st.slot8

  if print_dbg {
    let sb = StringBuilder::new()
    sb.write_string("\n> Block information:\n")
    for id in fn_.def_order {
      let b = fn_.blks[id]
      sb.write_string("\t")
      sb.write_string(@util.lpad(b.name, 10))
      sb.write_string(" (")
      sb.write_string(@util.rpad(b.loop_depth, 5))
      sb.write_string(") ")
      sb.write_string(@types.dumpts(b.out_set.unwrap(), fn_.tmps))
    }
    sb.write_string("\n> After spilling:\n")
    sb.write_string(@parser.printfn(fn_, interner, all_typs))
    sb.write_string("\n")
    sb.to_string()
  } else {
    ""
  }
}
