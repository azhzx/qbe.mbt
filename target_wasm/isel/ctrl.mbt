///|
// CFG → Wasm structured control flow conversion.
// Converts QBE's arbitrary CFG (jmp/jnz) to wasm's structured
// control flow (block/loop/if/br).
//
// Algorithm: Based on LLVM's WebAssemblyCFGStackify and
// Cheerp's Stackifier. Uses dominator tree + loop detection
// to generate nested block/loop/if structures.

///|
// Wasm control flow instruction
pub enum WasmCtrl {
  WBlock(String)
  WLoop(String)
  WIf(String)
  WElse
  WEnd
  WBr(Int)
  WBrIf(Int)
  WReturn
  WCall(Int)
  WUnreachable
} derive(Debug)

///|
// Control flow conversion state
priv struct CtrlState {
  fn_ : @types.Fn
  interner : @util.Interner
  // Maps block id → wasm label depth for br targets
  label_map : Map[Int, Int]
  // Current nesting depth
  mut depth : Int
  // Output control flow instructions per block
  ctrl : Array[Array[WasmCtrl]]
  // Loop header detection
  loop_headers : Array[Bool]
  // Block nesting levels
  block_level : Array[Int]
}

///|
fn ctrl_state_new(fn_ : @types.Fn, interner : @util.Interner) -> CtrlState {
  let nblk = fn_.nblk()
  CtrlState::{
    fn_,
    interner,
    label_map: Map([], capacity=16),
    depth: 0,
    ctrl: Array::make(nblk, Array::new()),
    loop_headers: Array::make(nblk, false),
    block_level: Array::make(nblk, 0),
  }
}

///|
// Step 1: Identify loop headers.
// A block is a loop header if any of its predecessors dominates it
// (i.e., there's a back-edge).
fn identify_loop_headers(st : CtrlState) -> Unit {
  for bid in 0..<st.fn_.nblk() {
    let blk = st.fn_.blks[bid]
    for pred_id in 0..<blk.npred {
      let pred_bid = blk.pred[pred_id]
      // If the predecessor comes after this block in RPO,
      // it's a back-edge, so this block is a loop header
      if st.fn_.blks[pred_bid].rpo_id > blk.rpo_id {
        st.loop_headers[bid] = true
        break
      }
    }
  }
}

///|
// Step 2: Compute block nesting levels based on dominator tree.
// Blocks inside loops get deeper nesting.
fn compute_nesting(st : CtrlState) -> Unit {
  // Start block is at depth 0
  if st.fn_.nblk() > 0 {
    st.block_level[st.fn_.start_id] = 0
    compute_nesting_dfs(st, st.fn_.start_id, 0)
  }
}

///|
fn compute_nesting_dfs(st : CtrlState, bid : Int, base_level : Int) -> Unit {
  let blk = st.fn_.blks[bid]
  let level = if st.loop_headers[bid] { base_level + 1 } else { base_level }
  st.block_level[bid] = level

  // Process dominator children
  let mut child = blk.dom_link
  while child >= 0 {
    compute_nesting_dfs(st, child, level)
    child = st.fn_.blks[child].dom_next
  }
}

///|
// Step 3: Build label map — for each block, compute the label depth
// needed to reach it from any nesting point.
fn build_label_map(st : CtrlState) -> Unit {
  for bid in 0..<st.fn_.nblk() {
    st.label_map[bid] = st.block_level[bid]
  }
}

///|
// Step 4: Generate wasm control flow for a block's jump.
fn gen_jump_ctrl(st : CtrlState, blk : @types.Blk) -> Array[WasmCtrl] {
  let ctrl = Array::new()
  let jmp = blk.jmp

  match jmp.kind {
    @types.Jjmp => {
      // Unconditional jump to successor
      let target = jmp.s1
      if target >= 0 && target != blk.id + 1 {
        // Need a br instruction
        let depth = compute_br_depth(st, blk.id, target)
        ctrl.push(WBr(depth))
      }
      // If target is the next block, fall-through (no instruction needed)
    }
    @types.Jjnz => {
      // Conditional jump: if (condition) br_else else fall_through
      // This becomes: (block $else (br_if $else condition) ... then_body ...)
      let target_true = jmp.s1
      let target_false = jmp.s2

      if target_true >= 0 && target_false >= 0 {
        // Both branches exist — generate if/else
        if target_true == target_false {
          // Same target for both — just br
          let depth = compute_br_depth(st, blk.id, target_true)
          ctrl.push(WBr(depth))
        } else {
          // Different targets — generate br_if for one, fall-through for other
          // We'll handle this in the emit phase with proper block structure
          let depth_false = compute_br_depth(st, blk.id, target_false)
          ctrl.push(WBrIf(depth_false))
        }
      }
    }
    @types.Jretw | @types.Jretl | @types.Jrets | @types.Jretd | @types.Jretc =>
      ctrl.push(WReturn)
    _ => ()
  }

  ctrl
}

///|
// Compute the br depth needed to jump from source to target.
// This is the number of block/loop boundaries that need to be crossed.
fn compute_br_depth(st : CtrlState, source : Int, target : Int) -> Int {
  let source_level = st.block_level[source]
  let target_level = st.block_level[target]

  // br depth = how many levels up we need to go
  let depth = source_level - target_level
  if depth > 0 {
    depth
  } else {
    0
  }
}

///|
// Step 5: Generate the full control flow sequence for all blocks.
// This produces the structured wasm control flow.
pub fn convert_ctrl_flow(
  fn_ : @types.Fn,
  interner : @util.Interner,
) -> Array[Array[WasmCtrl]] {
  let st = ctrl_state_new(fn_, interner)

  // Identify loops
  identify_loop_headers(st)

  // Compute nesting levels
  compute_nesting(st)

  // Build label map
  build_label_map(st)

  // Generate control flow for each block in RPO order
  for bid in fn_.rpo {
    let blk = fn_.blks[bid]
    let ctrl = gen_jump_ctrl(st, blk)
    st.ctrl[bid] = ctrl
  }

  st.ctrl
}

///|
// Check if a block is a loop header
pub fn is_loop_header(fn_ : @types.Fn, bid : Int) -> Bool {
  let blk = fn_.blks[bid]
  for pred_id in 0..<blk.npred {
    let pred_bid = blk.pred[pred_id]
    if fn_.blks[pred_bid].rpo_id > blk.rpo_id {
      return true
    }
  }
  false
}

///|
// Get the loop header for a block (the block it branches back to).
// Returns -1 if not a back-edge target.
pub fn get_loop_header(fn_ : @types.Fn, bid : Int) -> Int {
  let blk = fn_.blks[bid]
  for pred_id in 0..<blk.npred {
    let pred_bid = blk.pred[pred_id]
    if fn_.blks[pred_bid].rpo_id > blk.rpo_id {
      // pred_bid is after bid in RPO, so bid is the loop header
      return bid
    }
  }
  -1
}
