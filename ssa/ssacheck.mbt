///|
// SSA verification - corresponds to ssacheck in ssa.c

///|
// Check if b1 strictly dominates b2
fn sdom(fn_ : @types.Fn, b1 : Int32, b2 : Int32) -> Bool {
  if b1 == b2 {
    return false
  }
  let mut b2 = b2
  while b2 >= 0 && fn_.blks[b2].rpo_id > fn_.blks[b1].rpo_id {
    b2 = fn_.blks[b2].idom
  }
  b1 == b2
}

///|
// Check phi: whether phi p in block b uses temp t illegally
fn phicheck(fn_ : @types.Fn, p : @types.Phi, b : Int32, t : @types.Ref) -> Bool {
  for a in p.args {
    if a.value.eq(t) {
      let b1 = a.blk_id
      if b1 != b && !sdom(fn_, b, b1) {
        return true
      }
    }
  }
  false
}

///|
// Verify SSA form (C ssacheck)
// Requires: filluse and SSA construction done
pub fn ssacheck(fn_ : @types.Fn) -> Unit raise {
  for t in @types.Tmp0..<fn_.ntmp() {
    let tmp = fn_.tmps[t]
    if tmp.ndef > 1 {
      raise @util.QbeError::CompileError(
        "function $\{fn_.name}: \{tmp.name} is defined more than once (SSA)",
      )
    }
    if tmp.nuse > 0 && tmp.ndef == 0 {
      let bu = fn_.blks[tmp.uses[0].blk_id]
      raise @util.QbeError::CompileError(
        "function $\{fn_.name}: \{tmp.name} is used in @\{bu.name} but never defined there (SSA)",
      )
    }
  }
  for id in fn_.def_order {
    let b = fn_.blks[id]
    // Check phi nodes
    for p in b.phi {
      let r = p.to
      let tmp = fn_.tmps[r.tmp_val()]
      for u in tmp.uses {
        let bu = fn_.blks[u.blk_id]
        if u.kind == @types.UPhi {
          let phi = fn_.blks[u.blk_id].phi[u.ins_idx]
          if phicheck(fn_, phi, id, r) {
            raise @util.QbeError::CompileError(
              "function $\{fn_.name}: \{tmp.name} is used before its definition (SSA)",
            )
          }
        } else if bu.id != id && !sdom(fn_, id, bu.id) {
          raise @util.QbeError::CompileError(
            "function $\{fn_.name}: \{tmp.name} is defined at @\{b.name} " +
            "which does not dominate its use at @\{bu.name} (SSA)",
          )
        }
      }
    }
    // Check instructions
    for ii in 0..<b.ins.length() {
      let ins = b.ins[ii]
      if !ins.to.is_tmp() {
        continue
      }
      let r = ins.to
      let tmp = fn_.tmps[r.tmp_val()]
      for u in tmp.uses {
        let bu = fn_.blks[u.blk_id]
        if u.kind == @types.UPhi {
          let phi = fn_.blks[u.blk_id].phi[u.ins_idx]
          if phicheck(fn_, phi, id, r) {
            raise @util.QbeError::CompileError(
              "function $\{fn_.name}: \{tmp.name} is used before its definition (SSA)",
            )
          }
        } else if bu.id == id {
          if u.kind == @types.UIns && u.ins_idx <= ii {
            raise @util.QbeError::CompileError(
              "function $\{fn_.name}: \{tmp.name} is defined at @\{b.name}:\{ii} " +
              "but first used at @\{b.name}:\{u.ins_idx} (SSA: a value must be " +
              "defined before any use in the same block)",
            )
          }
        } else if !sdom(fn_, id, bu.id) {
          raise @util.QbeError::CompileError(
            "function $\{fn_.name}: \{tmp.name} is defined at @\{b.name} " +
            "which does not dominate its use at @\{bu.name} (SSA)",
          )
        }
      }
    }
  }
}
