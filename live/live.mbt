///|
// Liveness analysis - corresponds to live.c in QBE.
// Requires: fillrpo already computed.

///|
// Live-in contribution of a successor to a predecessor block (C liveon).
fn liveon(v : @types.BSet, b : Int, s : @types.Blk, fn_ : @types.Fn) -> Unit {
  v.copy_from(s.in_set.unwrap())
  for p in s.phi {
    if p.to.is_tmp() {
      v.clr(p.to.tmp_val())
    }
  }
  for p in s.phi {
    for a in p.args {
      if a.blk_id == b && a.value.is_tmp() {
        v.set(a.value.tmp_val())
        fn_.blks[b].gen_set.unwrap().set(a.value.tmp_val())
      }
    }
  }
}

///|
fn bset(
  r : @types.Ref,
  b : @types.Blk,
  nlv : Array[Int],
  tmp : Array[@types.Tmp],
) -> Unit {
  if !r.is_tmp() {
    return
  }
  let rv = r.tmp_val()
  let g = b.gen_set.unwrap()
  g.set(rv)
  let in_ = b.in_set.unwrap()
  if !in_.has(rv) {
    nlv[kbase(tmp[rv].cls)] = nlv[kbase(tmp[rv].cls)] + 1
    in_.set(rv)
  }
}

///|
fn kbase(k : @types.Class) -> Int {
  match k {
    @types.Kx => 0
    @types.Kw | @types.Ks => 0
    @types.Kl | @types.Kd => 1
  }
}

///|
// Compute live sets for all blocks (C filllive)
pub fn filllive(fn_ : @types.Fn) -> Unit {
  let nt = fn_.ntmp()
  for id in fn_.def_order {
    let b = fn_.blks[id]
    b.in_set = Some(@types.BSet::new(nt))
    b.out_set = Some(@types.BSet::new(nt))
    b.gen_set = Some(@types.BSet::new(nt))
  }
  let mut chg = true
  while chg {
    chg = false
    // Iterate RPO in reverse
    for n = fn_.rpo.length() - 1; n >= 0; n = n - 1 {
      let bid = fn_.rpo[n]
      let b = fn_.blks[bid]
      let u = b.out_set.unwrap()
      let old = @types.BSet::new(nt)
      old.copy_from(u)
      if b.jmp.s1 >= 0 {
        let v = @types.BSet::new(nt)
        liveon(v, bid, fn_.blks[b.jmp.s1], fn_)
        if u.union(v) {
          chg = true
        }
      }
      if b.jmp.s2 >= 0 && b.jmp.s2 != b.jmp.s1 {
        let v = @types.BSet::new(nt)
        liveon(v, bid, fn_.blks[b.jmp.s2], fn_)
        if u.union(v) {
          chg = true
        }
      }
      if !u.equal(old) {
        chg = true
      }
      // Globally live registers (RBP | RSP) are always live (C T.rglob).
      u.set(@types.RBP)
      u.set(@types.RSP)
      let in_ = b.in_set.unwrap()
      in_.copy_from(u)
      let nlv : Array[Int] = Array::make(2, 0)
      let mut t = in_.iter(-1)
      while t >= 0 {
        nlv[kbase(fn_.tmps[t].cls)] = nlv[kbase(fn_.tmps[t].cls)] + 1
        t = in_.iter(t)
      }
      // Jump argument
      bset(b.jmp.arg, b, nlv, fn_.tmps)
      for k = 0; k < 2; k = k + 1 {
        b.nlive_w = nlv[0]
        b.nlive_d = nlv[1]
      }
      // Instructions in reverse
      for ii = b.ins.length() - 1; ii >= 0; ii = ii - 1 {
        let ins = b.ins[ii]
        if !ins.to.is_none() {
          let t = ins.to.tmp_val()
          if in_.has(t) {
            nlv[kbase(fn_.tmps[t].cls)] = nlv[kbase(fn_.tmps[t].cls)] - 1
          }
          b.gen_set.unwrap().set(t)
          in_.clr(t)
        }
        for k = 0; k < 2; k = k + 1 {
          let arg = if k == 0 { ins.arg1 } else { ins.arg2 }
          match arg {
            @types.RMem(m) => {
              let ma = fn_.mems[m]
              bset(ma.base, b, nlv, fn_.tmps)
              bset(ma.index, b, nlv, fn_.tmps)
            }
            _ => bset(arg, b, nlv, fn_.tmps)
          }
        }
      }
      for k = 0; k < 2; k = k + 1 {
        if nlv[0] > b.nlive_w {
          b.nlive_w = nlv[0]
        }
        if nlv[1] > b.nlive_d {
          b.nlive_d = nlv[1]
        }
      }
    }
  }
}
