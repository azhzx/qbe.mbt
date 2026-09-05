///|
// Basic block id
pub type BlkId = Int

///|
// Jump at end of basic block
pub(all) struct Jump {
  mut kind : JumpKind
  mut arg : Ref // Argument for jnz/comparison (Ref::none() if none)
  mut s1 : Int // First successor block id (-1 if none)
  mut s2 : Int // Second successor block id (-1 if none)
} derive(Debug)

///|
pub fn Jump::new(kind : JumpKind) -> Jump {
  Jump::{ kind, arg: Ref::none(), s1: -1, s2: -1, }
}

///|
pub fn Jump::full(kind : JumpKind, arg : Ref, s1 : Int, s2 : Int) -> Jump {
  Jump::{ kind, arg, s1, s2, }
}

///|
// Basic block - corresponds to struct Blk in QBE
pub(all) struct Blk {
  id : Int // Block id
  name : String // Block label name
  phi : Array[Phi] // Phi nodes
  ins : Array[Ins] // Instructions
  mut jmp : Jump // Terminal jump
  // CFG info
  pred : Array[Int] // Predecessor block ids
  mut npred : Int // Number of predecessors
  mut idom : Int // Immediate dominator (-1 if none)
  mut dom_link : Int // First child in dom tree (-1 if none)
  mut dom_next : Int // Next sibling in dom tree (-1 if none)
  fron : Array[Int] // Dominance frontier
  mut rpo_id : Int // RPO order (-1 if unvisited)
  mut loop_depth : Int // Loop nesting depth
  // Liveness info
  mut nlive_w : Int // Live word temps count
  mut nlive_d : Int // Live double temps count
  // Liveness bit sets
  mut in_set : BSet?
  mut out_set : BSet?
  mut gen_set : BSet?
  // Link list for block ordering
  mut link : Int // Next block in link list (-1 if none)
  // Visit flag
  mut visit : Int
} derive(Debug)

///|
pub fn Blk::new(id : Int, name : String) -> Blk {
  Blk::{
    id,
    name,
    phi: Array::new(),
    ins: Array::new(),
    jmp: Jump::new(Jxxx),
    pred: Array::new(),
    npred: 0,
    idom: -1,
    dom_link: -1,
    dom_next: -1,
    fron: Array::new(),
    rpo_id: -1,
    loop_depth: 0,
    nlive_w: 0,
    nlive_d: 0,
    in_set: None,
    out_set: None,
    gen_set: None,
    link: -1,
    visit: 0,
  }
}
