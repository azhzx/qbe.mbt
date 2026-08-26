///|
// Liveness analysis - corresponds to live.c in QBE.
// Requires: fillrpo already computed.

///|
// Live-in contribution of a successor to a predecessor block (C liveon).
pub fn liveon(
  v : @types.BSet,
  b : Int,
  s : @types.Blk,
  fn_ : @types.Fn,
) -> Unit {
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
  b.gen_set.unwrap().set(rv)
  let in_ = b.in_set.unwrap()
  if !in_.has(rv) {
    nlv[tmp[rv].cls.base()] = nlv[tmp[rv].cls.base()] + 1
    in_.set(rv)
  }
}

///|
// Compute live sets for all blocks (C filllive).
// Returns the -dL debug text (empty when print_dbg is false).
pub fn filllive(fn_ : @types.Fn, print_dbg : Bool) -> String {
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
    for n in (fn_.rpo.length() - 1)>=..0 {
      let bid = fn_.rpo[n]
      let b = fn_.blks[bid]
      let out = b.out_set.unwrap()
      let old = @types.BSet::new(nt)
      old.copy_from(out)
      if b.jmp.s1 >= 0 {
        let v = @types.BSet::new(nt)
        liveon(v, bid, fn_.blks[b.jmp.s1], fn_)
        ignore(out.union(v))
      }
      if b.jmp.s2 >= 0 && b.jmp.s2 != b.jmp.s1 {
        let v = @types.BSet::new(nt)
        liveon(v, bid, fn_.blks[b.jmp.s2], fn_)
        ignore(out.union(v))
      }
      if !out.equal(old) {
        chg = true
      }
      // globally live registers (RBP | RSP)
      out.bits[0] = out.bits[0] | @types.rglob_mask()
      let in_ = b.in_set.unwrap()
      in_.copy_from(out)
      let nlv : Array[Int] = Array::make(2, 0)
      in_.each(t => {
        nlv[fn_.tmps[t].cls.base()] = nlv[fn_.tmps[t].cls.base()] + 1
      })
      if b.jmp.arg.call_val() >= 0 {
        let rr = b.jmp.arg.retregs()
        in_.bits[0] = in_.bits[0] | rr.0
        nlv[0] = rr.1
        nlv[1] = rr.2
      } else {
        bset(b.jmp.arg, b, nlv, fn_.tmps)
      }
      b.nlive_w = nlv[0]
      b.nlive_d = nlv[1]
      // instructions in reverse
      for ii in (b.ins.length() - 1)>=..0 {
        let ins = b.ins[ii]
        if ins.op == @types.Call && ins.arg2.call_val() >= 0 {
          let rr = ins.arg2.retregs()
          in_.bits[0] = in_.bits[0] & rr.0.lnot()
          nlv[0] = nlv[0] - rr.1 + 9
          nlv[1] = nlv[1] - rr.2 + 15
          if nlv[0] > b.nlive_w {
            b.nlive_w = nlv[0]
          }
          if nlv[1] > b.nlive_d {
            b.nlive_d = nlv[1]
          }
          let ar = ins.arg2.argregs()
          in_.bits[0] = in_.bits[0] | ar.0
          nlv[0] = nlv[0] - 9 + ar.1
          nlv[1] = nlv[1] - 15 + ar.2
        }
        if !ins.to.is_none() {
          let t = ins.to.tmp_val()
          if in_.has(t) {
            nlv[fn_.tmps[t].cls.base()] = nlv[fn_.tmps[t].cls.base()] - 1
          }
          b.gen_set.unwrap().set(t)
          in_.clr(t)
        }
        for k in 0..<2 {
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
        if nlv[0] > b.nlive_w {
          b.nlive_w = nlv[0]
        }
        if nlv[1] > b.nlive_d {
          b.nlive_d = nlv[1]
        }
      }
    }
  }
  if print_dbg {
    let sb = StringBuilder::new()
    sb.write_string("\n> Liveness analysis:\n")
    for id in fn_.def_order {
      let b = fn_.blks[id]
      sb.write_string("\t")
      sb.write_string(@util.lpad(b.name, 10))
      sb.write_string("in:   ")
      sb.write_string(@types.dumpts(b.in_set.unwrap(), fn_.tmps))
      sb.write_string("\t          out:  ")
      sb.write_string(@types.dumpts(b.out_set.unwrap(), fn_.tmps))
      sb.write_string("\t          gen:  ")
      sb.write_string(@types.dumpts(b.gen_set.unwrap(), fn_.tmps))
      sb.write_string("\t          live: ")
      sb.write_string("\{b.nlive_w} \{b.nlive_d}\n")
    }
    sb.to_string()
  } else {
    ""
  }
}
