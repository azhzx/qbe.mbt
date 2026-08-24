///|
// CFG analysis package - corresponds to cfg.c in QBE
// Provides: fillpreds, fillrpo, filldom, fillfron, fillloop, simpljmp

///|
// Fill predecessor information for all blocks in a function.
// Corresponds to fillpreds() in cfg.c
pub fn fillpreds(f : @types.Fn) -> Unit {
  // Reset predecessors for all blocks
  for i = 0; i < f.blks.length(); i = i + 1 {
    f.blks[i].pred.clear()
    f.blks[i].npred = 0
  }
  // Count predecessors for each successor
  for i = 0; i < f.blks.length(); i = i + 1 {
    let b = f.blks[i]
    let s1 = b.jmp.s1
    let s2 = b.jmp.s2
    if s1 >= 0 && s1 < f.blks.length() {
      f.blks[s1].npred = f.blks[s1].npred + 1
    }
    if s2 >= 0 && s2 < f.blks.length() && s2 != s1 {
      f.blks[s2].npred = f.blks[s2].npred + 1
    }
  }
  // Add predecessor entries
  for i = 0; i < f.blks.length(); i = i + 1 {
    let b = f.blks[i]
    let s1 = b.jmp.s1
    let s2 = b.jmp.s2
    if s1 >= 0 && s1 < f.blks.length() {
      f.blks[s1].pred.push(i)
    }
    if s2 >= 0 && s2 < f.blks.length() && s2 != s1 {
      f.blks[s2].pred.push(i)
    }
  }
}

///|
// DFS post-order traversal for RPO computation (C rporec: visits s1 before
// s2, swapping them when s1 is more deeply nested in loops).
fn rpo_dfs(f : @types.Fn, blk_id : Int, post_order : Array[Int]) -> Unit {
  if blk_id < 0 || blk_id >= f.blks.length() {
    return
  }
  let b = f.blks[blk_id]
  // -1 = unvisited, -2 = visiting, >=0 = visited
  if b.rpo_id != -1 {
    return
  }
  f.blks[blk_id].rpo_id = -2 // mark as visiting
  let mut s1 = b.jmp.s1
  let mut s2 = b.jmp.s2
  if s1 >= 0 && s2 >= 0 && s1 != s2 {
    if f.blks[s1].loop_depth > f.blks[s2].loop_depth {
      let t = s1
      s1 = s2
      s2 = t
    }
  }
  if s1 >= 0 {
    rpo_dfs(f, s1, post_order)
  }
  if s2 >= 0 && s2 != s1 {
    rpo_dfs(f, s2, post_order)
  }
  post_order.push(blk_id)
}

///|
// Remove one phi argument supplied by a deleted predecessor (C edgedel).
fn remove_phi_arg(f : @types.Fn, succ : Int, dead : Int) -> Unit {
  for pi = 0; pi < f.blks[succ].phi.length(); pi = pi + 1 {
    let p = f.blks[succ].phi[pi]
    let mut i = 0
    while i < p.args.length() {
      if p.args[i].blk_id == dead {
        let _ = p.args.remove(i)
      } else {
        i = i + 1
      }
    }
  }
}

///|
// Delete the edge from block bs to successor succ (C edgedel in cfg.c).
// Clears the successor pointer, then removes bs from succ's phi args and
// predecessor list (unless the edge is doubled: bs jumps to succ twice).
pub fn edgedel(f : @types.Fn, bs : Int, succ : Int) -> Unit {
  let b = f.blks[bs]
  let mult = 1 + (if b.jmp.s1 == b.jmp.s2 && b.jmp.s1 >= 0 { 1 } else { 0 })
  if b.jmp.s1 == succ {
    b.jmp.s1 = -1
  } else if b.jmp.s2 == succ {
    b.jmp.s2 = -1
  }
  if succ < 0 || mult > 1 {
    return
  }
  remove_phi_arg(f, succ, bs)
  let preds = f.blks[succ].pred
  let mut i = 0
  while i < preds.length() {
    if preds[i] == bs {
      let _ = preds.remove(i)
      f.blks[succ].npred = f.blks[succ].npred - 1
    } else {
      i = i + 1
    }
  }
}

///|
// Fill reverse post-order information.
// Computes f.rpo (array of block ids in RPO), sets b.rpo_id for each reachable
// block, and drops unreachable blocks (as fillrpo() in cfg.c does: it removes
// blocks that the DFS from start cannot reach).
pub fn fillrpo(f : @types.Fn) -> Unit {
  // Reset rpo_id for all blocks
  for i = 0; i < f.blks.length(); i = i + 1 {
    f.blks[i].rpo_id = -1
  }
  // DFS post-order from start block
  let post_order : Array[Int] = Array::new()
  rpo_dfs(f, f.start_id, post_order)
  // Build RPO array (reverse of post-order)
  f.rpo.clear()
  for i = post_order.length() - 1; i >= 0; i = i - 1 {
    let blk_id = post_order[i]
    f.blks[blk_id].rpo_id = f.rpo.length()
    f.rpo.push(blk_id)
  }
  // Drop unreachable blocks: they keep rpo_id == -1.  This mirrors cfg.c,
  // which deletes b->id == -1u blocks from the start link list.
  let new_def : Array[Int] = Array::new()
  for id in f.def_order {
    if f.blks[id].rpo_id >= 0 {
      new_def.push(id)
    } else {
      let b = f.blks[id]
      let s1 = b.jmp.s1
      let s2 = b.jmp.s2
      if s1 >= 0 {
        remove_phi_arg(f, s1, id)
      }
      if s2 >= 0 && s2 != s1 {
        remove_phi_arg(f, s2, id)
      }
    }
  }
  f.def_order.clear()
  for id in new_def {
    f.def_order.push(id)
  }
}

///|
// Intersect two blocks in the dominator tree (Cooper-Harvey-Kennedy)
fn dom_inter(f : @types.Fn, b1 : Int, b2 : Int) -> Int {
  if b1 < 0 {
    return b2
  }
  let mut b1 = b1
  let mut b2 = b2
  while b1 != b2 {
    while b1 > b2 {
      b1 = f.blks[b1].idom
      if b1 < 0 {
        break
      }
    }
    while b1 < b2 && b1 >= 0 {
      b2 = f.blks[b2].idom
      if b2 < 0 {
        break
      }
    }
  }
  b1
}

///|
// Fill dominator tree information.
// Requires: fillrpo and fillpreds already called.
// Corresponds to filldom() in cfg.c
pub fn filldom(f : @types.Fn) -> Unit {
  // Reset dominator info
  for i = 0; i < f.blks.length(); i = i + 1 {
    f.blks[i].idom = -1
    f.blks[i].dom_link = -1
    f.blks[i].dom_next = -1
  }
  // Iterative algorithm
  let mut changed = true
  while changed {
    changed = false
    // Skip start block (rpo index 0)
    for n = 1; n < f.rpo.length(); n = n + 1 {
      let b_id = f.rpo[n]
      let mut d = -1
      // Find first processed predecessor
      for p = 0; p < f.blks[b_id].npred; p = p + 1 {
        let pred_id = f.blks[b_id].pred[p]
        // Start block or block with idom already set
        if pred_id == f.start_id || f.blks[pred_id].idom >= 0 {
          if d < 0 {
            d = pred_id
          } else {
            d = dom_inter(f, d, pred_id)
          }
        }
      }
      if d != f.blks[b_id].idom {
        f.blks[b_id].idom = d
        changed = true
      }
    }
  }
  // Build dom tree children list using dom_link (first child) and dom_next
  // (next sibling).  Iterate in definition order (fn->start link order) like
  // cfg.c, prepending each block to its idom's child list so the sibling order
  // matches the reference.
  for id in f.def_order {
    let d = f.blks[id].idom
    if d >= 0 && d != id {
      // Add id as first child of d, link to previous first child
      f.blks[id].dom_next = f.blks[d].dom_link
      f.blks[d].dom_link = id
    }
  }
}

///|
// Check if b1 strictly dominates b2
pub fn sdom(f : @types.Fn, b1 : Int, b2 : Int) -> Bool {
  if b1 == b2 {
    return false
  }
  let mut b2 = b2
  while b2 >= 0 && f.blks[b2].rpo_id > f.blks[b1].rpo_id {
    b2 = f.blks[b2].idom
  }
  b1 == b2
}

///|
// Check if b1 dominates b2 (or b1 == b2)
pub fn dom(f : @types.Fn, b1 : Int, b2 : Int) -> Bool {
  b1 == b2 || sdom(f, b1, b2)
}

///|
// Add block b to dominance frontier of block a
fn add_frontier(a : Int, b : Int, f : @types.Fn) -> Unit {
  for i = 0; i < f.blks[a].fron.length(); i = i + 1 {
    if f.blks[a].fron[i] == b {
      return
    }
  }
  f.blks[a].fron.push(b)
}

///|
// Fill dominance frontier information.
// Requires: fillrpo, fillpreds, filldom already called.
// Corresponds to fillfron() in cfg.c
pub fn fillfron(f : @types.Fn) -> Unit {
  // Reset frontiers
  for i = 0; i < f.blks.length(); i = i + 1 {
    f.blks[i].fron.clear()
  }
  // For each block, walk up the dom tree from block to its idom,
  // adding the successor to the frontier of each block that doesn't dominate it
  for i = 0; i < f.blks.length(); i = i + 1 {
    let b = f.blks[i]
    let s1 = b.jmp.s1
    let s2 = b.jmp.s2
    if s1 >= 0 {
      let mut a = i
      while a >= 0 && !sdom(f, a, s1) {
        add_frontier(a, s1, f)
        a = f.blks[a].idom
      }
    }
    if s2 >= 0 {
      let mut a = i
      while a >= 0 && !sdom(f, a, s2) {
        add_frontier(a, s2, f)
        a = f.blks[a].idom
      }
    }
  }
}

///|
// Recursive loop marking (C loopmark in cfg.c).
fn loop_mark(f : @types.Fn, hd : Int, b : Int, fv : (Int, Int) -> Unit) -> Unit {
  if b < 0 || b >= f.blks.length() {
    return
  }
  let hd_id = f.blks[hd].rpo_id
  if f.blks[b].rpo_id < hd_id || f.blks[b].visit == hd_id {
    return
  }
  f.blks[b].visit = hd_id
  fv(hd, b)
  for p = 0; p < f.blks[b].npred; p = p + 1 {
    loop_mark(f, hd, f.blks[b].pred[p], fv)
  }
}

///|
// Iterate over loops, calling f(hd, b) for every block b in a loop headed by
// hd (C loopiter in cfg.c). Requires: fillrpo and fillpreds.
pub fn loopiter(f : @types.Fn, fv : (Int, Int) -> Unit) -> Unit {
  for i = 0; i < f.blks.length(); i = i + 1 {
    f.blks[i].visit = -1
  }
  for n = 0; n < f.rpo.length(); n = n + 1 {
    let b = f.rpo[n]
    for p = 0; p < f.blks[b].npred; p = p + 1 {
      if f.blks[f.blks[b].pred[p]].rpo_id >= n {
        loop_mark(f, b, f.blks[b].pred[p], fv)
      }
    }
  }
}

///|
// Fill loop depth information (C fillloop in cfg.c): loop is a multiplicative
// nesting factor (1, 10, 100, ...). Requires: fillrpo, fillpreds.
pub fn fillloop(f : @types.Fn) -> Unit {
  for i = 0; i < f.blks.length(); i = i + 1 {
    f.blks[i].loop_depth = 1
  }
  loopiter(f, fn(hd, b) {
    ignore(hd)
    f.blks[b].loop_depth = f.blks[b].loop_depth * 10
  })
}

///|
// Union-find find with path compression (C uffind in cfg.c).
fn uf_find(f : @types.Fn, pb : Int, uf : Array[Int]) -> Int {
  let pb1 = uf[f.blks[pb].rpo_id]
  if pb1 >= 0 {
    let root = uf_find(f, pb1, uf)
    uf[f.blks[pb].rpo_id] = root
    root
  } else {
    pb
  }
}

///|
// Simplify jumps by merging empty blocks that just jump (C simpljmp in cfg.c).
// Requires: rpo and no phis (rega clears them). Breaks the CFG.
pub fn simpljmp(f : @types.Fn) -> Unit {
  // union-find indexed by block rpo id
  let uf : Array[Int] = Array::make(f.blks.length(), -1)
  for id in f.def_order {
    let b = f.blks[id]
    if b.ins.length() == 0 {
      if b.jmp.kind == @types.Jjmp {
        let s1 = uf_find(f, b.jmp.s1, uf)
        if s1 != id {
          uf[b.rpo_id] = s1
        }
      }
    }
  }
  for id in f.def_order {
    let b = f.blks[id]
    if b.jmp.s1 >= 0 {
      b.jmp.s1 = uf_find(f, b.jmp.s1, uf)
    }
    if b.jmp.s2 >= 0 {
      b.jmp.s2 = uf_find(f, b.jmp.s2, uf)
    }
    let c = @types.jump_index(b.jmp.kind) - @types.jump_index(@types.Jjfieq)
    if c >= 0 && c <= 18 {
      if b.jmp.s1 == b.jmp.s2 {
        b.jmp.kind = @types.Jjmp
        b.jmp.s2 = -1
      }
    }
  }
}
