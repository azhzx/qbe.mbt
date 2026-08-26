///|
// QBE operations - corresponds to enum O in QBE
// Public operations first, then internal operations
pub(all) enum Op {
  Oxxx // Placeholder

  // === Arithmetic and Bits ===
  Add
  Sub
  Div
  Rem
  Udiv
  Urem
  Mul
  And
  Or
  Xor
  Sar
  Shr
  Shl

  // === Comparisons - word ===
  Ceqw
  Cnew
  Csgew
  Csgtw
  Cslew
  Csltw
  Cugew
  Cugtw
  Culew
  Cultw

  // === Comparisons - long ===
  Ceql
  Cnel
  Csgel
  Csgtl
  Cslel
  Csltl
  Cugel
  Cugtl
  Culel
  Cultl

  // === Comparisons - single float ===
  Ceqs
  Cges
  Cgts
  Cles
  Clts
  Cnes
  Cos
  Cuos

  // === Comparisons - double float ===
  Ceqd
  Cged
  Cgtd
  Cled
  Cltd
  Cned
  Cod
  Cuod

  // === Memory - stores ===
  Storeb
  Storeh
  Storew
  Storel
  Stores
  Stored

  // === Memory - loads ===
  Loadsb
  Loadub
  Loadsh
  Loaduh
  Loadsw
  Loaduw
  Load

  // === Extensions and Truncations ===
  Extsb
  Extub
  Extsh
  Extuh
  Extsw
  Extuw
  Exts
  Truncd
  Stosi
  Dtosi
  Swtof
  Sltof
  Cast

  // === Stack Allocation ===
  Alloc4
  Alloc8
  Alloc16

  // === Variadic Function Helpers ===
  Vaarg
  Vastart
  Copy

  // === INTERNAL OPERATIONS ===
  Nop
  Addr
  Swap
  Sign
  Salloc
  Xidiv
  Xdiv
  Xcmp
  Xtest
  Acmp
  Acmn
  Afcmp

  // === Arguments, Parameters, and Calls ===
  Par
  Parc
  Pare
  Arg
  Argc
  Arge
  Call
  Vacall

  // === Flags Setting (int) ===
  Flagieq
  Flagine
  Flagisge
  Flagisgt
  Flagisle
  Flagislt
  Flagiuge
  Flagiugt
  Flagiule
  Flagiult

  // === Flags Setting (float) ===
  Flagfeq
  Flagfge
  Flagfgt
  Flagfle
  Flagflt
  Flagfne
  Flagfo
  Flagfuo
} derive(Eq, Debug)

///|
// Check if op is a store
#as_free_fn(is_store, deprecated="use `Op::is_store` instead")
pub fn Op::is_store(self : Op) -> Bool {
  match self {
    Storeb | Storeh | Storew | Storel | Stores | Stored => true
    _ => false
  }
}

///|
// Check if op is a load
#as_free_fn(is_load, deprecated="use `Op::is_load` instead")
pub fn Op::is_load(self : Op) -> Bool {
  match self {
    Loadsb | Loadub | Loadsh | Loaduh | Loadsw | Loaduw | Load => true
    _ => false
  }
}

///|
// Check if op is an extension
#as_free_fn(is_ext, deprecated="use `Op::is_ext` instead")
pub fn Op::is_ext(self : Op) -> Bool {
  match self {
    Extsb | Extub | Extsh | Extuh | Extsw | Extuw => true
    _ => false
  }
}

///|
// Width index for a load op: Loadsb=Wsb, Loadub=Wub, ... Loaduw=Wuw
#as_free_fn(load_width_idx, deprecated="use `Op::load_width_idx` instead")
pub fn Op::load_width_idx(self : Op) -> Int {
  match self {
    Loadsb => 1
    Loadub => 2
    Loadsh => 3
    Loaduh => 4
    Loadsw => 5
    Loaduw => 6
    _ => 0
  }
}

///|
// Width index for an extension op (C: Wsb + (op - Oextsb))
#as_free_fn(ext_width_idx, deprecated="use `Op::ext_width_idx` instead")
pub fn Op::ext_width_idx(self : Op) -> Int {
  match self {
    Extsb => 1
    Extub => 2
    Extsh => 3
    Extuh => 4
    Extsw => 5
    Extuw => 6
    _ => 0
  }
}

///|
// Check if op is a parameter
#as_free_fn(is_par, deprecated="use `Op::is_par` instead")
pub fn Op::is_par(self : Op) -> Bool {
  self == Par || self == Parc || self == Pare
}

///|
// Check if op is an argument
#as_free_fn(is_arg, deprecated="use `Op::is_arg` instead")
pub fn Op::is_arg(self : Op) -> Bool {
  self == Arg || self == Argc || self == Arge
}

///|
// Parse op from string (the SSA opcode name)
#as_free_fn(op_from_string, deprecated="use `Op::from_string` instead")
pub fn Op::from_string(s : String) -> Op {
  match s {
    "add" => Add
    "sub" => Sub
    "div" => Div
    "rem" => Rem
    "udiv" => Udiv
    "urem" => Urem
    "mul" => Mul
    "and" => And
    "or" => Or
    "xor" => Xor
    "sar" => Sar
    "shr" => Shr
    "shl" => Shl
    "ceqw" => Ceqw
    "cnew" => Cnew
    "csgew" => Csgew
    "csgtw" => Csgtw
    "cslew" => Cslew
    "csltw" => Csltw
    "cugew" => Cugew
    "cugtw" => Cugtw
    "culew" => Culew
    "cultw" => Cultw
    "ceql" => Ceql
    "cnel" => Cnel
    "csgel" => Csgel
    "csgtl" => Csgtl
    "cslel" => Cslel
    "csltl" => Csltl
    "cugel" => Cugel
    "cugtl" => Cugtl
    "culel" => Culel
    "cultl" => Cultl
    "ceqs" => Ceqs
    "cges" => Cges
    "cgts" => Cgts
    "cles" => Cles
    "clts" => Clts
    "cnes" => Cnes
    "cos" => Cos
    "cuos" => Cuos
    "ceqd" => Ceqd
    "cged" => Cged
    "cgtd" => Cgtd
    "cled" => Cled
    "cltd" => Cltd
    "cned" => Cned
    "cod" => Cod
    "cuod" => Cuod
    "storeb" => Storeb
    "storeh" => Storeh
    "storew" => Storew
    "storel" => Storel
    "stores" => Stores
    "stored" => Stored
    "loadsb" => Loadsb
    "loadub" => Loadub
    "loadsh" => Loadsh
    "loaduh" => Loaduh
    "loadsw" => Loadsw
    "loaduw" => Loaduw
    "load" => Load
    "loadw" => Load // alias
    "loadl" => Load // alias
    "loads" => Load // alias
    "loadd" => Load // alias
    "extsb" => Extsb
    "extub" => Extub
    "extsh" => Extsh
    "extuh" => Extuh
    "extsw" => Extsw
    "extuw" => Extuw
    "exts" => Exts
    "truncd" => Truncd
    "stosi" => Stosi
    "dtosi" => Dtosi
    "swtof" => Swtof
    "sltof" => Sltof
    "cast" => Cast
    "alloc4" => Alloc4
    "alloc8" => Alloc8
    "alloc16" => Alloc16
    "vaarg" => Vaarg
    "vastart" => Vastart
    "copy" => Copy
    "call" => Call
    _ => Oxxx
  }
}
