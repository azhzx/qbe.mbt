///|
// SSA verification - corresponds to ssacheck in ssa.c

///|
// Check if b1 strictly dominates b2
fn sdom(fn_ : @types.Fn, b1 : Int, b2 : Int) -> Bool {
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
fn phicheck(fn_ : @types.Fn, p : @types.Phi, b : Int, t : @types.Ref) -> Bool {
  for a in p.args {
    if @types.req(a.value, t) {
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
  for t = @types.Tmp0; t < fn_.ntmp(); t = t + 1 {
    let tmp = fn_.tmps[t]
    if tmp.ndef > 1 {
      raise @util.QbeError::CompileError(
        "\{tmp.name} violates ssa invariant (defined more than once)",
      )
    }
    if tmp.nuse > 0 && tmp.ndef == 0 {
      let bu = fn_.blks[tmp.uses[0].blk_id]
      raise @util.QbeError::CompileError(
        "\{tmp.name} is used undefined in @\{bu.name}",
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
              "\{tmp.name} violates ssa invariant",
            )
          }
        } else if bu.id != id && !sdom(fn_, id, bu.id) {
          raise @util.QbeError::CompileError(
            "\{tmp.name} violates ssa invariant",
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
              "\{tmp.name} violates ssa invariant",
            )
          }
        } else if bu.id == id {
          if u.kind == @types.UIns && u.ins_idx <= ii {
            raise @util.QbeError::CompileError(
              "\{tmp.name} violates ssa invariant",
            )
          }
        } else if !sdom(fn_, id, bu.id) {
          raise @util.QbeError::CompileError(
            "\{tmp.name} violates ssa invariant",
          )
        }
      }
    }
  }
}
