///|
// Spill cost computation - corresponds to fillcost in spill.c.
// Requires: rpo, preds, liveness (in/out/gen sets, nlive).

///|
// Aggregate looping information at loop headers (C aggreg).
fn aggreg(fn_ : @types.Fn, hd : Int, b : Int) -> Unit {
  ignore(fn_.blks[hd].gen_set.unwrap().union(fn_.blks[b].gen_set.unwrap()))
  if fn_.blks[b].nlive_w > fn_.blks[hd].nlive_w {
    fn_.blks[hd].nlive_w = fn_.blks[b].nlive_w
  }
  if fn_.blks[b].nlive_d > fn_.blks[hd].nlive_d {
    fn_.blks[hd].nlive_d = fn_.blks[b].nlive_d
  }
}

///|
fn tmpuse(fn_ : @types.Fn, r : @types.Ref, use_ : Int, loopv : Int) -> Unit {
  if r.is_mem() {
    let m = fn_.mems[r.mem_val()]
    tmpuse(fn_, m.base, 1, loopv)
    tmpuse(fn_, m.index, 1, loopv)
  } else if r.is_tmp() && r.tmp_val() >= @types.Tmp0 {
    let t = r.tmp_val()
    fn_.tmps[t].nuse = fn_.tmps[t].nuse + use_
    fn_.tmps[t].ndef = fn_.tmps[t].ndef + (if use_ == 0 { 1 } else { 0 })
    fn_.tmps[t].cost = fn_.tmps[t].cost + loopv
  }
}

///|
// Evaluate spill costs of temporaries (C fillcost).
// Returns the -dS debug text (empty when print_dbg is false).
pub fn fillcost(fn_ : @types.Fn, print_dbg : Bool) -> String {
  @cfg.loopiter(fn_, fn(hd, b) { aggreg(fn_, hd, b) })
  let sb = StringBuilder::new()
  if print_dbg {
    sb.write_string("\n> Loop information:\n")
    for id in fn_.def_order {
      let b = fn_.blks[id]
      let mut a = 0
      while a < b.npred {
        if b.rpo_id <= fn_.blks[b.pred[a]].rpo_id {
          break
        }
        a = a + 1
      }
      if a != b.npred {
        sb.write_string("\t")
        sb.write_string(@util.lpad(b.name, 10))
        sb.write_string(" (")
        sb.write_string(@util.rpad(b.nlive_w, 3))
        sb.write_string(" ")
        sb.write_string(@util.rpad(b.nlive_d, 3))
        sb.write_string(") ")
        sb.write_string(@types.dumpts(b.gen_set.unwrap(), fn_.tmps))
      }
    }
  }
  for t = 0; t < fn_.tmps.length(); t = t + 1 {
    let mx = if t < @types.Tmp0 { ((1L << 32) - 1L).to_int() } else { 0 }
    fn_.tmps[t].cost = mx
    fn_.tmps[t].nuse = 0
    fn_.tmps[t].ndef = 0
  }
  for id in fn_.def_order {
    let b = fn_.blks[id]
    for p in b.phi {
      let t = p.to.tmp_val()
      tmpuse(fn_, p.to, 0, 0)
      for a in p.args {
        let n = fn_.blks[a.blk_id].loop_depth
        fn_.tmps[t].cost = fn_.tmps[t].cost + n
        tmpuse(fn_, a.value, 1, n)
      }
    }
    let n = b.loop_depth
    for ins in b.ins {
      tmpuse(fn_, ins.to, 0, n)
      tmpuse(fn_, ins.arg1, 1, n)
      tmpuse(fn_, ins.arg2, 1, n)
    }
    tmpuse(fn_, b.jmp.arg, 1, n)
  }
  if print_dbg {
    sb.write_string("\n> Spill costs:\n")
    for n = @types.Tmp0; n < fn_.tmps.length(); n = n + 1 {
      sb.write_string("\t")
      sb.write_string(@util.lpad(fn_.tmps[n].name, 10))
      sb.write_string(" ")
      sb.write_string(fn_.tmps[n].cost.to_string())
      sb.write_string("\n")
    }
    sb.write_string("\n")
  }
  sb.to_string()
}
