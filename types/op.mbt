///|
// QBE operations - corresponds to enum O in QBE
// Public operations first, then internal operations
#derive(Eq, Debug)
pub(all) enum Op {
  Oxxx // Placeholder

  // === Arithmetic and Bits ===
  Add
  Sub
  Neg
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
  Stoui
  Dtosi
  Dtoui
  Swtof
  Uwtof
  Sltof
  Ultowf
  Cast

  // === Stack Allocation ===
  Alloc4
  Alloc8
  Alloc16

  // === Variadic Function Helpers ===
  Vaarg
  Vastart
  Copy

  // === Atomics (sequentially consistent) ===
  AtomicLoad
  AtomicStore
  Fence

  // === Debug info (C Odbgloc) ===
  Dbgloc

  // === INTERNAL OPERATIONS ===
  Nop
  Addr
  Blit0
  Blit1
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
  Reqz
  Rnez

  // === Arguments, Parameters, and Calls ===
  Par
  Parsb
  Parub
  Parsh
  Paruh
  Parc
  Pare
  Arg
  Argsb
  Argub
  Argsh
  Arguh
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

  // === Conditional select (if-conversion) ===
  Sel0
  Sel1
  Xselieq
  Xseline
  Xselisge
  Xselisgt
  Xselisle
  Xselislt
  Xseliuge
  Xseliugt
  Xseliule
  Xseliult
  Xselfeq
  Xselfge
  Xselfgt
  Xselfle
  Xselflt
  Xselfne
  Xselfo
  Xselfuo

  // === Variadic argument marker (C Oargv) ===
  Argv

  // === Inline assembly (a port extension: upstream QBE has no asm) ===
  // The instruction carries the raw text in Ins.asm_text and its input
  // temporaries in Ins.asm_ins; the target emitters substitute registers for
  // the %0..%9 placeholders. Kept last so every transcribed op index and the
  // generated pinned table stay valid.
  InlineAsm
}

///|
// Check if op is a store
pub fn Op::is_store(self : Op) -> Bool {
  match self {
    Storeb | Storeh | Storew | Storel | Stores | Stored => true
    _ => false
  }
}

///|
// Check if op is a load
pub fn Op::is_load(self : Op) -> Bool {
  match self {
    Loadsb | Loadub | Loadsh | Loaduh | Loadsw | Loaduw | Load => true
    _ => false
  }
}

///|
// Check if op is an extension
pub fn Op::is_ext(self : Op) -> Bool {
  match self {
    Extsb | Extub | Extsh | Extuh | Extsw | Extuw => true
    _ => false
  }
}

///|
// Width index for a load op: Loadsb=Wsb, Loadub=Wub, ... Loaduw=Wuw
pub fn Op::load_width_idx(self : Op) -> Int32 {
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
pub fn Op::ext_width_idx(self : Op) -> Int32 {
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
pub fn Op::is_par(self : Op) -> Bool {
  self == Par ||
  self == Parsb ||
  self == Parub ||
  self == Parsh ||
  self == Paruh ||
  self == Parc ||
  self == Pare
}

///|
// Check if op is an argument
pub fn Op::is_arg(self : Op) -> Bool {
  self == Arg ||
  self == Argsb ||
  self == Argub ||
  self == Argsh ||
  self == Arguh ||
  self == Argc ||
  self == Arge ||
  self == Argv
}

///|
// Parse op from string (the SSA opcode name)
pub fn Op::from_string(s : String) -> Op {
  match s {
    "add" => Add
    "sub" => Sub
    "neg" => Neg
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
    // C parse.c: loadw aliases loadsw; loadl/loads/loadd alias load.
    "loadw" => Loadsw
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
    "stoui" => Stoui
    "dtosi" => Dtosi
    "dtoui" => Dtoui
    "swtof" => Swtof
    "uwtof" => Uwtof
    "sltof" => Sltof
    "ultof" => Ultowf
    "cast" => Cast
    "alloc1" | "alloc2" | "alloc4" => Alloc4
    "alloc8" => Alloc8
    "alloc16" => Alloc16
    "atomicload" => AtomicLoad
    "atomicstore" => AtomicStore
    "fence" => Fence
    "vaarg" => Vaarg
    "vastart" => Vastart
    "copy" => Copy
    "dbgloc" => Dbgloc
    "call" => Call
    "argv" => Argv
    "asm" => InlineAsm
    _ => Oxxx
  }
}

///|
// C isparbh: sub-word parameter variants.
pub fn Op::is_par_bh(self : Op) -> Bool {
  let i = self.index()
  i >= Parsb.index() && i <= Paruh.index()
}

///|
// C isargbh: sub-word argument variants.
pub fn Op::is_arg_bh(self : Op) -> Bool {
  let i = self.index()
  i >= Argsb.index() && i <= Arguh.index()
}
