///|
// Instruction - corresponds to struct Ins in QBE
// In C: struct Ins { uint op:30; Ref to; Ref arg[2]; uint cls:2; }
pub(all) struct Ins {
  mut op : Op
  mut cls : Class
  mut to : Ref // Destination, ref_none() if none
  mut arg1 : Ref
  mut arg2 : Ref
} derive(Debug, Eq)

///|
pub fn Ins::new(op : Op, cls : Class, to : Ref, arg1 : Ref, arg2 : Ref) -> Ins {
  Ins::{ op, cls, to, arg1, arg2 }
}

///|
// Create an instruction with no destination
pub fn Ins::new_void(op : Op, cls : Class, arg1 : Ref, arg2 : Ref) -> Ins {
  Ins::{ op, cls, to: Ref::none(), arg1, arg2 }
}

///|
// Phi node argument: value + source block id
pub(all) struct PhiArg {
  mut value : Ref
  mut blk_id : Int
} derive(Debug, Eq)

///|
// Phi instruction - corresponds to struct Phi in QBE
pub(all) struct Phi {
  mut cls : Class
  mut to : Ref
  args : Array[PhiArg]
} derive(Debug, Eq)

///|
pub fn Phi::new(to : Ref, cls : Class) -> Phi {
  Phi::{ to, cls, args: Array::new() }
}
