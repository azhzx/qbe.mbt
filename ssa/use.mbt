///|
// SSA analysis and construction - corresponds to ssa.c in QBE

///|
// Class enumeration values (match C: Kx=-1, Kw=0, Kl=1, Ks=2, Kd=3)
fn kx() -> Int {
  -1
}

///|
// Convert Class to int code (C: Kx=-1, Kw=0, Kl=1, Ks=2, Kd=3)
fn kcode(k : @types.Class) -> Int {
  match k {
    @types.Kx => -1
    @types.Kw => 0
    @types.Kl => 1
    @types.Ks => 2
    @types.Kd => 3
  }
}

///|
// Merge a class into a running class. Returns true if incompatible.
fn clsmerge(pk : Ref[Int], k : Int) -> Bool {
  let k1 = pk.val
  if k1 == kx() {
    pk.val = k
    return false
  }
  if (k1 == 0 && k == 1) || (k1 == 1 && k == 0) {
    pk.val = 0
    return false
  }
  k1 != k
}

///|
// Phi class resolution with path compression (C phicls)
fn phicls(t : Int, tmps : Array[@types.Tmp]) -> Int {
  let mut t1 = tmps[t].is_phi
  if t1 == 0 {
    return t
  }
  t1 = phicls(t1, tmps)
  tmps[t].is_phi = t1
  t1
}

///|
// Load size in bytes (C load.c loadsz: Oload size depends on the class width)
fn loadsz(i : @types.Ins) -> Int {
  match i.op {
    @types.Loadsb | @types.Loadub => 1
    @types.Loadsh | @types.Loaduh => 2
    @types.Loadsw | @types.Loaduw => 4
    @types.Load => if i.cls.wide() == 1 { 8 } else { 4 }
    _ => 0
  }
}

///|
// Store size in bytes
fn storesz(i : @types.Ins) -> Int {
  match i.op {
    @types.Storeb => 1
    @types.Storeh => 2
    @types.Storew | @types.Stores => 4
    _ => 8
  }
}

///|
// Fill usage, width, phi, and class information (C filluse)
pub fn filluse(fn_ : @types.Fn) -> Unit raise {
  for t in @types.Tmp0..<fn_.ntmp() {
    let tmp = fn_.tmps[t]
    tmp.ndef = 0
    tmp.nuse = 0
    tmp.cls = @types.Kx
    tmp.is_phi = 0
    tmp.width = @types.WFull
    tmp.uses.clear()
  }
  for id in fn_.def_order {
    let b = fn_.blks[id]
    // Phis
    for pi in 0..<b.phi.length() {
      let p = b.phi[pi]
      if !p.to.is_tmp() {
        raise @util.QbeError::Ice("phi to not a tmp")
      }
      let tp = p.to.tmp_val()
      fn_.tmps[tp].ndef = fn_.tmps[tp].ndef + 1
      fn_.tmps[tp].cls = p.cls
      let tp1 = phicls(tp, fn_.tmps)
      for a in p.args {
        if a.value.is_tmp() {
          let t = a.value.tmp_val()
          adduse(fn_, t, @types.UPhi, id, pi, 0)
          let t1 = phicls(t, fn_.tmps)
          if t1 != tp1 {
            fn_.tmps[t1].is_phi = tp1
          }
        }
      }
    }
    // Instructions
    for ii in 0..<b.ins.length() {
      let ins = b.ins[ii]
      if !ins.to.is_none() {
        if !ins.to.is_tmp() {
          raise @util.QbeError::Ice("ins to not a tmp")
        }
        let mut w = @types.WFull
        if is_load(ins.op) && ins.op != @types.Load {
          w = @types.TmpWidth::from_code(ins.op.load_width_idx())
        }
        if is_ext(ins.op) {
          w = @types.TmpWidth::from_code(ins.op.ext_width_idx())
        }
        if (w == @types.Wsw || w == @types.Wuw) && ins.cls == @types.Kw {
          w = @types.WFull
        }
        let t = ins.to.tmp_val()
        fn_.tmps[t].width = w
        fn_.tmps[t].ndef = fn_.tmps[t].ndef + 1
        fn_.tmps[t].cls = ins.cls
      }
      for m in 0..<2 {
        let arg = if m == 0 { ins.arg1 } else { ins.arg2 }
        if arg.is_tmp() {
          adduse(fn_, arg.tmp_val(), @types.UIns, id, ii, m)
        }
      }
    }
    // Jump argument
    if b.jmp.arg.is_tmp() {
      adduse(fn_, b.jmp.arg.tmp_val(), @types.UJmp, id, 0, 0)
    }
  }
}

///|
// Add a use to a temporary's use list
fn adduse(
  fn_ : @types.Fn,
  t : Int,
  kind : @types.UseKind,
  blk_id : Int,
  ins_idx : Int,
  arg_num : Int,
) -> Unit {
  let tmp = fn_.tmps[t]
  tmp.nuse = tmp.nuse + 1
  tmp.uses.push(@types.Use::{ kind, blk_id, ins_idx, arg_num })
}

///|
fn is_load(o : @types.Op) -> Bool {
  o.is_load()
}

///|
fn is_ext(o : @types.Op) -> Bool {
  o.is_ext()
}
