///|
// SSA construction - corresponds to phiins/renblk/ssa in ssa.c

///|
// Create a new temporary (like C newtmp with name prefix)
fn refindex(t : Int, fn_ : @types.Fn) -> @types.Ref {
  let id = fn_.new_tmp(fn_.tmps[t].name, fn_.tmps[t].cls)
  @types.Ref::tmp(id)
}

///|
// Rename stack entries
priv struct Name {
  r : @types.Ref
  blk_id : Int
  up : Int
}

///|
// A pool of Name entries
priv struct NamePool {
  entries : Array[Name]
  free : Array[Int]
}

///|
fn NamePool::new() -> NamePool {
  NamePool::{ entries: Array::new(), free: Array::new() }
}

///|
fn np_alloc(pool : NamePool, r : @types.Ref, blk_id : Int, up : Int) -> Int {
  let idx = if pool.free.length() > 0 {
    let f = pool.free.pop().unwrap()
    pool.entries[f] = Name::{ r, blk_id, up }
    f
  } else {
    pool.entries.push(Name::{ r, blk_id, up })
    pool.entries.length() - 1
  }
  idx
}

///|
fn np_free(pool : NamePool, idx : Int) -> Unit {
  pool.free.push(idx)
}

///|
// Insert phi nodes (C phiins) - requires filllive (b.in), filldom, fillfron
pub fn phiins(fn_ : @types.Fn) -> Unit raise {
  let nb = fn_.nblk()
  let nt = fn_.ntmp()
  let u = @types.BSet::new(nb)
  let defs = @types.BSet::new(nb)
  // LIFO worklist, mirroring cfg.c's `*--bp` / `*bp++` stack.
  let work : Array[Int] = Array::new()
  for t in @types.Tmp0..<nt {
    fn_.tmps[t].visit = 0
    if fn_.tmps[t].is_phi != 0 {
      continue
    }
    u.zero()
    let mut k = -1
    // First pass: rename intra-block defs and find blocks that define t
    for id in fn_.def_order {
      let b = fn_.blks[id]
      b.visit = 0
      let mut r = @types.Ref::none()
      for ii in 0..<b.ins.length() {
        let i = b.ins[ii]
        if !r.is_none() {
          if i.arg1.eq(@types.Ref::tmp(t)) {
            b.ins[ii].arg1 = r
          }
          if i.arg2.eq(@types.Ref::tmp(t)) {
            b.ins[ii].arg2 = r
          }
        }
        if !i.to.is_none() && i.to.eq(@types.Ref::tmp(t)) {
          if !b.out_set.unwrap().has(t) {
            if fn_.tmps[t].ndef == 1 {
              r = @types.Ref::tmp(t)
            } else {
              r = refindex(t, fn_)
            }
            b.ins[ii].to = r
          } else {
            if !u.has(id) {
              u.set(id)
              work.push(id)
            }
            // C: if (clsmerge(&k, i->cls)) die("invalid input");
            let k_ref : Ref[Int] = Ref::{ val: k }
            if clsmerge(k_ref, kcode(i.cls)) {
              raise @util.QbeError::Ice("invalid input class")
            }
            k = k_ref.val
          }
        }
      }
      if !r.is_none() && b.jmp.arg.eq(@types.Ref::tmp(t)) {
        fn_.blks[id].jmp.arg = r
      }
    }
    // defs = copy of u
    defs.copy_from(u)
    // Worklist processing
    while work.length() > 0 {
      fn_.tmps[t].visit = t
      let b_id = work.pop().unwrap()
      u.clr(b_id)
      for f in fn_.blks[b_id].fron {
        if fn_.blks[f].visit == 0 {
          fn_.blks[f].visit = 1
          if fn_.blks[f].in_set.unwrap().has(t) {
            let p = @types.Phi::new(@types.Ref::tmp(t), @types.Kw)
            p.cls = @types.Class::from_code(k)
            // C phiins prepends: p->link = a->phi; a->phi = p;
            fn_.blks[f].phi.insert(0, p)
            if !defs.has(f) && !u.has(f) {
              u.set(f)
              work.push(f)
            }
          }
        }
      }
    }
  }
}

///|
// Rename temporaries (C renblk) - requires filldom (dom tree) and ssa phis
pub fn renblk(fn_ : @types.Fn) -> Unit {
  let pool = NamePool::new()
  let stk : Array[Int] = Array::make(fn_.ntmp(), -1)
  ren_dfs(fn_, fn_.start_id, stk, pool)
}

///|
// Recursive rename over dominator tree
fn ren_dfs(
  fn_ : @types.Fn,
  bid : Int,
  stk : Array[Int],
  pool : NamePool,
) -> Unit {
  let b = fn_.blks[bid]
  // Rename phi destinations
  for pi in 0..<b.phi.length() {
    let p = b.phi[pi]
    if p.to.is_tmp() {
      let t = p.to.tmp_val()
      if fn_.tmps[t].visit != 0 {
        let r = refindex(t, fn_)
        fn_.tmps[r.tmp_val()].visit = t
        stk[t] = np_alloc(pool, r, bid, stk[t])
        b.phi[pi].to = r
      }
    }
  }
  // Rename instruction args and destinations
  for ii in 0..<b.ins.length() {
    let ins = b.ins[ii]
    // Rename args
    if ins.arg1.is_tmp() {
      let t = ins.arg1.tmp_val()
      if fn_.tmps[t].visit != 0 {
        b.ins[ii].arg1 = getstk(t, bid, stk, fn_, pool)
      }
    }
    if ins.arg2.is_tmp() {
      let t = ins.arg2.tmp_val()
      if fn_.tmps[t].visit != 0 {
        b.ins[ii].arg2 = getstk(t, bid, stk, fn_, pool)
      }
    }
    // Rename destination
    if !ins.to.is_none() && ins.to.is_tmp() {
      let t = ins.to.tmp_val()
      if fn_.tmps[t].visit != 0 {
        let r = refindex(t, fn_)
        fn_.tmps[r.tmp_val()].visit = t
        stk[t] = np_alloc(pool, r, bid, stk[t])
        b.ins[ii].to = r
      }
    }
  }
  // Rename jump argument
  if b.jmp.arg.is_tmp() {
    let t = b.jmp.arg.tmp_val()
    if fn_.tmps[t].visit != 0 {
      fn_.blks[bid].jmp.arg = getstk(t, bid, stk, fn_, pool)
    }
  }
  // Fill phi arguments in successors
  let succs : Array[Int] = Array::new()
  if b.jmp.s1 >= 0 {
    succs.push(b.jmp.s1)
  }
  if b.jmp.s2 >= 0 && b.jmp.s2 != b.jmp.s1 {
    succs.push(b.jmp.s2)
  }
  for s_id in succs {
    let s = fn_.blks[s_id]
    for pi in 0..<s.phi.length() {
      let p = s.phi[pi]
      if p.to.is_tmp() {
        // C ssa.c: t = p->to.val; if ((t = fn->tmp[t].visit)) ...
        // The visit field of a phi destination points back to the original
        // temporary id that indexes the rename stack, even after the phi
        // destination itself has been renamed.
        let t = fn_.tmps[p.to.tmp_val()].visit
        if t != 0 {
          let v = getstk(t, bid, stk, fn_, pool)
          fn_.blks[s_id].phi[pi].args.push(@types.PhiArg::{
            value: v,
            blk_id: bid,
          })
        }
      }
    }
  }
  // Recurse into dominator children
  let mut c = b.dom_link
  while c >= 0 {
    ren_dfs(fn_, c, stk, pool)
    c = fn_.blks[c].dom_next
  }
  // Note: C renblk does NOT pop the stack here.
  // Stack entries are freed by getstk() when they don't dominate the current block.
}

///|
// Get the current renamed version of temp t at block b
fn getstk(
  t : Int,
  b : Int,
  stk : Array[Int],
  fn_ : @types.Fn,
  pool : NamePool,
) -> @types.Ref {
  let mut n = stk[t]
  while n >= 0 && !dom(fn_, pool.entries[n].blk_id, b) {
    let n1 = n
    n = pool.entries[n].up
    np_free(pool, n1)
  }
  stk[t] = n
  if n < 0 {
    // Should not happen in valid SSA; return a constant zero
    @types.Ref::con(fn_.get_con(0))
  } else {
    pool.entries[n].r
  }
}

///|
// Check if b1 dominates b2 (b1 == b2 or strict)
fn dom(fn_ : @types.Fn, b1 : Int, b2 : Int) -> Bool {
  b1 == b2 || sdom(fn_, b1, b2)
}
