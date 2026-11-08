///|
// Instruction - corresponds to struct Ins in QBE
// In C: struct Ins { uint op:30; Ref to; Ref arg[2]; uint cls:2; }
#derive(Debug, Eq)
pub(all) struct Ins {
  mut op : Op
  mut cls : Class
  mut to : Ref // Destination, Ref::none() if none
  mut arg1 : Ref
  mut arg2 : Ref
  // Inline assembly payload (port extension, op == InlineAsm). The text keeps its
  // %0..%2 placeholders: %0 is the output (`to`), %1 and %2 are the inputs in
  // `arg1` and `arg2`. Keeping the inputs in the regular argument slots means
  // liveness, spilling and register allocation already see them as uses.
  mut asm_text : String
}

///|
pub fn Ins::new(op : Op, cls : Class, to : Ref, arg1 : Ref, arg2 : Ref) -> Ins {
  Ins::{ op, cls, to, arg1, arg2, asm_text: "", }
}

///|
// Load size in bytes (C loadsz).
pub fn Ins::load_size(self : Ins) -> Int32 {
  match self.op {
    Loadsb | Loadub => 1
    Loadsh | Loaduh => 2
    Loadsw | Loaduw => 4
    Load => if self.cls.wide() == 1 { 8 } else { 4 }
    _ => 0
  }
}

///|
// Store size in bytes (C storesz).
pub fn Ins::store_size(self : Ins) -> Int32 {
  match self.op {
    Storeb => 1
    Storeh => 2
    Storew | Stores => 4
    _ => 8
  }
}

///|
// Create an instruction with no destination
pub fn Ins::new_void(op : Op, cls : Class, arg1 : Ref, arg2 : Ref) -> Ins {
  Ins::{ op, cls, to: Ref::none(), arg1, arg2, asm_text: "", }
}

///|
// Create an inline-assembly instruction. `to` is the output operand (or
// Ref::none()), `ins` are the input temporaries, `text` is the raw assembly
// with %0..%9 placeholders numbered outputs first, then inputs.
pub fn Ins::new_asm(
  cls : Class,
  to : Ref,
  arg1 : Ref,
  arg2 : Ref,
  text : String,
) -> Ins {
  Ins::{ op: InlineAsm, cls, to, arg1, arg2, asm_text: text, }
}

///|
// Phi node argument: value + source block id
#derive(Debug, Eq)
pub(all) struct PhiArg {
  mut value : Ref
  mut blk_id : Int32
}

///|
// Phi instruction - corresponds to struct Phi in QBE
#derive(Debug, Eq)
pub(all) struct Phi {
  mut cls : Class
  mut to : Ref
  args : Array[PhiArg]
}

///|
pub fn Phi::new(to : Ref, cls : Class) -> Phi {
  Phi::{ to, cls, args: [], }
}
