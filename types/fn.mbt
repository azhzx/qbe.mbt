///|
// Memory address (amd64-style addressing)
pub(all) struct Addr {
  mut offset : Con
  mut base : Ref
  mut index : Ref
  mut scale : Int
} derive(Debug)

///|
pub fn Addr::new() -> Addr {
  Addr::{ offset: Con::new(), base: ref_none(), index: ref_none(), scale: 1 }
}

///|
// Function - corresponds to struct Fn in QBE
pub(all) struct Fn {
  name : String
  mut start_id : Int // Start block id
  blks : Array[Blk] // All basic blocks (index = block id)
  blk_names : Map[String, Int] // Name -> block id
  tmps : Array[Tmp] // Temporaries (index = tmp id)
  cons : Array[Con] // Constants (index = con id)
  mems : Array[Addr] // Memory addresses (index = mem id)
  rpo : Array[Int] // Reverse Post-Order block ids
  def_order : Array[Int] // Blocks in definition order
  mut ret_ty : Int // Return type index, -1 if no aggregate
  mut retr : Ref // Return reference
  mut reg : UInt64 // Used register mask
  mut slot : Int // Stack slot count
  mut is_export : Bool
  mut is_vararg : Bool
  mut has_dynalloc : Bool
} derive(Debug)

///|
pub fn Fn::new(name : String) -> Fn {
  Fn::{
    name,
    start_id: 0,
    blks: Array::new(),
    blk_names: Map([], capacity=16),
    tmps: Array::new(),
    cons: Array::new(),
    mems: Array::new(),
    rpo: Array::new(),
    def_order: Array::new(),
    ret_ty: -1,
    retr: ref_none(),
    reg: 0,
    slot: 0,
    is_export: false,
    is_vararg: false,
    has_dynalloc: false,
  }
}

///|
pub fn Fn::nblk(self : Fn) -> Int {
  self.blks.length()
}

///|
pub fn Fn::ntmp(self : Fn) -> Int {
  self.tmps.length()
}

///|
pub fn Fn::ncon(self : Fn) -> Int {
  self.cons.length()
}

///|
// Add a new block, returns its id
pub fn Fn::add_blk(self : Self, name : String) -> Int {
  let id = self.blks.length()
  let blk = Blk::new(id, name)
  self.blks.push(blk)
  self.blk_names[name] = id
  id
}

///|
// Find block id by name, returns -1 if not found
pub fn Fn::find_blk(self : Fn, name : String) -> Int {
  match self.blk_names.get(name) {
    Some(id) => id
    None => -1
  }
}

///|
// Add a new temporary, returns its id
pub fn Fn::add_tmp(self : Self, name : String, cls : Class) -> Int {
  let id = self.tmps.length()
  self.tmps.push(Tmp::new(name, cls))
  id
}

///|
// Pre-populate Tmp0 (64) register temporaries (matches C parse.c:779-783)
// Called at the start of function parsing so register temps occupy indices 0..Tmp0-1
pub fn Fn::init_regs(self : Self) -> Unit {
  for i = 0; i < Tmp0; i = i + 1 {
    let cls = if XMM0 <= i && i < XMM0 + NFPR { Kd } else { Kl }
    let tmp = Tmp::new("", cls)
    tmp.slot = -1
    tmp.nuse = 1
    tmp.ndef = 1
    self.tmps.push(tmp)
  }
}

///|
// Module-global counter for newtmp (matches C util.c static int n, which is
// shared across all functions compiled in one process).
let newtmp_counter : Array[Int] = Array::make(1, 0)

///|
pub fn Fn::new_tmp(self : Self, prfx : String, cls : Class) -> Int {
  let id = self.tmps.length()
  let name = if prfx == "" {
    ""
  } else {
    newtmp_counter[0] = newtmp_counter[0] + 1
    "\{prfx}.\{newtmp_counter[0]}"
  }
  let tmp = Tmp::new(name, cls)
  tmp.slot = -1
  tmp.nuse = 1
  tmp.ndef = 1
  self.tmps.push(tmp)
  id
}

///|
// Add a new constant, returns its id
pub fn Fn::add_con(self : Self, con : Con) -> Int {
  let id = self.cons.length()
  self.cons.push(con)
  id
}

///|
// Intern a constant: return existing id if a matching one exists,
// otherwise add it. Matching is by raw bits (like C's union compare).
pub fn Fn::get_con_by(self : Self, con : Con) -> Int {
  for i = 0; i < self.cons.length(); i = i + 1 {
    if con_eq(self.cons[i], con) {
      return i
    }
  }
  self.add_con(con)
}

///|
// Get a constant reference for an integer value
pub fn Fn::get_con(self : Self, val : Int64) -> Int {
  for i = 0; i < self.cons.length(); i = i + 1 {
    let c = self.cons[i]
    if c.kind == CBits && c.flt == 0 && c.bits.i == val {
      return i
    }
  }
  self.add_con(Con::int(val))
}

///|
// Get block by id
pub fn Fn::blk(self : Fn, id : Int) -> Blk {
  self.blks[id]
}

///|
// Get tmp by id
pub fn Fn::tmp(self : Fn, id : Int) -> Tmp {
  self.tmps[id]
}

///|
// Get con by id
pub fn Fn::con(self : Fn, id : Int) -> Con {
  self.cons[id]
}
