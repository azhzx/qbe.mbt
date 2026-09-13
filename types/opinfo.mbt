///|
// Operation metadata - corresponds to struct Op and the optab in QBE
// (all.h + parse.c + ops.h)
// Class codes match QBE: Ke=-2 (erroneous), Kx=-1 (top), Kw=0, Kl=1, Ks=2, Kd=3
pub(all) struct OpInfo {
  name : String
  // arg class for each result class: [Kw, Kl, Ks, Kd]
  a0 : Array[Int]
  a1 : Array[Int]
  canfold : Bool
  nmem : Int // number of memory arguments
  zf : Int // sets zero flag
  lf : Int // leaves flags
} derive(Debug)

///|
fn mk(
  name : String,
  a0 : Array[Int],
  a1 : Array[Int],
  cf : Bool,
  x : (Int, Int, Int),
) -> OpInfo {
  OpInfo::{ name, a0, a1, canfold: cf, nmem: x.0, zf: x.1, lf: x.2, }
}

///|
fn cls(vals : Array[String]) -> Array[Int] {
  let r : Array[Int] = Array::new()
  for v in vals {
    let c = match v {
      "w" => 0
      "l" => 1
      "s" => 2
      "d" => 3
      "x" => -1
      "e" => -2
      "m" => 1
      _ => -1
    }
    r.push(c)
  }
  r
}

///|
let optab : Array[OpInfo] = [
  // placeholder Oxxx
  mk(
    "xxx",
    cls(["x", "x", "x", "x"]),
    cls(["x", "x", "x", "x"]),
    false,
    (0, 0, 0),
  ),
  // Arithmetic and Bits
  mk(
    "add",
    cls(["w", "l", "s", "d"]),
    cls(["w", "l", "s", "d"]),
    true,
    (2, 1, 0),
  ),
  mk(
    "sub",
    cls(["w", "l", "s", "d"]),
    cls(["w", "l", "s", "d"]),
    true,
    (2, 1, 0),
  ),
  mk(
    "div",
    cls(["w", "l", "s", "d"]),
    cls(["w", "l", "s", "d"]),
    true,
    (0, 0, 0),
  ),
  mk(
    "rem",
    cls(["w", "l", "e", "e"]),
    cls(["w", "l", "e", "e"]),
    true,
    (0, 0, 0),
  ),
  mk(
    "udiv",
    cls(["w", "l", "e", "e"]),
    cls(["w", "l", "e", "e"]),
    true,
    (0, 0, 0),
  ),
  mk(
    "urem",
    cls(["w", "l", "e", "e"]),
    cls(["w", "l", "e", "e"]),
    true,
    (0, 0, 0),
  ),
  mk(
    "mul",
    cls(["w", "l", "s", "d"]),
    cls(["w", "l", "s", "d"]),
    true,
    (2, 0, 0),
  ),
  mk(
    "and",
    cls(["w", "l", "e", "e"]),
    cls(["w", "l", "e", "e"]),
    true,
    (2, 1, 0),
  ),
  mk(
    "or",
    cls(["w", "l", "e", "e"]),
    cls(["w", "l", "e", "e"]),
    true,
    (2, 1, 0),
  ),
  mk(
    "xor",
    cls(["w", "l", "e", "e"]),
    cls(["w", "l", "e", "e"]),
    true,
    (2, 1, 0),
  ),
  mk(
    "sar",
    cls(["w", "l", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (1, 1, 0),
  ),
  mk(
    "shr",
    cls(["w", "l", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (1, 1, 0),
  ),
  mk(
    "shl",
    cls(["w", "l", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (1, 1, 0),
  ),
  // Comparisons - word
  mk(
    "ceqw",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cnew",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "csgew",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "csgtw",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cslew",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "csltw",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cugew",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cugtw",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "culew",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cultw",
    cls(["w", "w", "e", "e"]),
    cls(["w", "w", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  // Comparisons - long
  mk(
    "ceql",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cnel",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "csgel",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "csgtl",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cslel",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "csltl",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cugel",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cugtl",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "culel",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cultl",
    cls(["l", "l", "e", "e"]),
    cls(["l", "l", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  // Comparisons - single
  mk(
    "ceqs",
    cls(["s", "s", "e", "e"]),
    cls(["s", "s", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cges",
    cls(["s", "s", "e", "e"]),
    cls(["s", "s", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cgts",
    cls(["s", "s", "e", "e"]),
    cls(["s", "s", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cles",
    cls(["s", "s", "e", "e"]),
    cls(["s", "s", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "clts",
    cls(["s", "s", "e", "e"]),
    cls(["s", "s", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cnes",
    cls(["s", "s", "e", "e"]),
    cls(["s", "s", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cos",
    cls(["s", "s", "e", "e"]),
    cls(["s", "s", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cuos",
    cls(["s", "s", "e", "e"]),
    cls(["s", "s", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  // Comparisons - double
  mk(
    "ceqd",
    cls(["d", "d", "e", "e"]),
    cls(["d", "d", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cged",
    cls(["d", "d", "e", "e"]),
    cls(["d", "d", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cgtd",
    cls(["d", "d", "e", "e"]),
    cls(["d", "d", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cled",
    cls(["d", "d", "e", "e"]),
    cls(["d", "d", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cltd",
    cls(["d", "d", "e", "e"]),
    cls(["d", "d", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cned",
    cls(["d", "d", "e", "e"]),
    cls(["d", "d", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cod",
    cls(["d", "d", "e", "e"]),
    cls(["d", "d", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  mk(
    "cuod",
    cls(["d", "d", "e", "e"]),
    cls(["d", "d", "e", "e"]),
    true,
    (0, 1, 0),
  ),
  // Memory - stores
  mk(
    "storeb",
    cls(["w", "e", "e", "e"]),
    cls(["m", "e", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "storeh",
    cls(["w", "e", "e", "e"]),
    cls(["m", "e", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "storew",
    cls(["w", "e", "e", "e"]),
    cls(["m", "e", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "storel",
    cls(["l", "e", "e", "e"]),
    cls(["m", "e", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "stores",
    cls(["s", "e", "e", "e"]),
    cls(["m", "e", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "stored",
    cls(["d", "e", "e", "e"]),
    cls(["m", "e", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  // Memory - loads
  mk(
    "loadsb",
    cls(["m", "m", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "loadub",
    cls(["m", "m", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "loadsh",
    cls(["m", "m", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "loaduh",
    cls(["m", "m", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "loadsw",
    cls(["m", "m", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "loaduw",
    cls(["m", "m", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "load",
    cls(["m", "m", "m", "m"]),
    cls(["x", "x", "x", "x"]),
    false,
    (0, 0, 1),
  ),
  // Extensions and truncations
  mk(
    "extsb",
    cls(["w", "w", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "extub",
    cls(["w", "w", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "extsh",
    cls(["w", "w", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "extuh",
    cls(["w", "w", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "extsw",
    cls(["e", "w", "e", "e"]),
    cls(["e", "x", "e", "e"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "extuw",
    cls(["e", "w", "e", "e"]),
    cls(["e", "x", "e", "e"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "exts",
    cls(["e", "e", "e", "s"]),
    cls(["e", "e", "e", "x"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "truncd",
    cls(["e", "e", "d", "e"]),
    cls(["e", "e", "x", "e"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "stosi",
    cls(["s", "s", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "dtosi",
    cls(["d", "d", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "swtof",
    cls(["e", "e", "w", "w"]),
    cls(["e", "e", "x", "x"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "sltof",
    cls(["e", "e", "l", "l"]),
    cls(["e", "e", "x", "x"]),
    true,
    (0, 0, 1),
  ),
  mk(
    "cast",
    cls(["s", "d", "w", "l"]),
    cls(["x", "x", "x", "x"]),
    true,
    (0, 0, 1),
  ),
  // Stack allocation
  mk(
    "alloc4",
    cls(["e", "l", "e", "e"]),
    cls(["e", "x", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "alloc8",
    cls(["e", "l", "e", "e"]),
    cls(["e", "x", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "alloc16",
    cls(["e", "l", "e", "e"]),
    cls(["e", "x", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  // Variadic function helpers
  mk(
    "vaarg",
    cls(["m", "m", "m", "m"]),
    cls(["x", "x", "x", "x"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "vastart",
    cls(["m", "e", "e", "e"]),
    cls(["x", "e", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "copy",
    cls(["w", "l", "s", "d"]),
    cls(["x", "x", "x", "x"]),
    false,
    (0, 0, 1),
  ),
  // Internal operations
  mk(
    "nop",
    cls(["x", "x", "x", "x"]),
    cls(["x", "x", "x", "x"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "addr",
    cls(["m", "m", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "swap",
    cls(["w", "l", "s", "d"]),
    cls(["w", "l", "s", "d"]),
    false,
    (1, 0, 0),
  ),
  mk(
    "sign",
    cls(["w", "l", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "salloc",
    cls(["e", "l", "e", "e"]),
    cls(["e", "x", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "xidiv",
    cls(["w", "l", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (1, 0, 0),
  ),
  mk(
    "xdiv",
    cls(["w", "l", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (1, 0, 0),
  ),
  mk(
    "xcmp",
    cls(["w", "l", "s", "d"]),
    cls(["w", "l", "s", "d"]),
    false,
    (1, 1, 0),
  ),
  mk(
    "xtest",
    cls(["w", "l", "e", "e"]),
    cls(["w", "l", "e", "e"]),
    false,
    (1, 1, 0),
  ),
  mk(
    "acmp",
    cls(["w", "l", "e", "e"]),
    cls(["w", "l", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "acmn",
    cls(["w", "l", "e", "e"]),
    cls(["w", "l", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "afcmp",
    cls(["e", "e", "s", "d"]),
    cls(["e", "e", "s", "d"]),
    false,
    (0, 0, 0),
  ),
  // Arguments, parameters, calls
  mk(
    "par",
    cls(["x", "x", "x", "x"]),
    cls(["x", "x", "x", "x"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "parc",
    cls(["e", "x", "e", "e"]),
    cls(["e", "x", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "pare",
    cls(["e", "x", "e", "e"]),
    cls(["e", "x", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "arg",
    cls(["w", "l", "s", "d"]),
    cls(["x", "x", "x", "x"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "argc",
    cls(["e", "x", "e", "e"]),
    cls(["e", "l", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "arge",
    cls(["e", "l", "e", "e"]),
    cls(["e", "x", "e", "e"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "call",
    cls(["m", "m", "m", "m"]),
    cls(["x", "x", "x", "x"]),
    false,
    (0, 0, 0),
  ),
  mk(
    "vacall",
    cls(["m", "m", "m", "m"]),
    cls(["x", "x", "x", "x"]),
    false,
    (0, 0, 0),
  ),
  // Flags setting - int
  mk(
    "flagieq",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagine",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagisge",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagisgt",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagisle",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagislt",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagiuge",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagiugt",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagiule",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagiult",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  // Flags setting - float
  mk(
    "flagfeq",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagfge",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagfgt",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagfle",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagflt",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagfne",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagfo",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
  mk(
    "flagfuo",
    cls(["x", "x", "e", "e"]),
    cls(["x", "x", "e", "e"]),
    false,
    (0, 0, 1),
  ),
]

///|
// Get OpInfo for an op
pub fn op_info(o : Op) -> OpInfo {
  let i = o.index()
  if i < 0 || i >= optab.length() {
    return optab[0]
  }
  optab[i]
}

///|
// Op name as string
pub fn Op::name(self : Op) -> String {
  op_info(self).name
}

///|
// Convert an optab index back to an Op
#as_free_fn(op_from_index, deprecated="use `Op::from_index` instead")
pub fn Op::from_index(i : Int) -> Op {
  match i {
    0 => Oxxx
    1 => Add
    2 => Sub
    3 => Div
    4 => Rem
    5 => Udiv
    6 => Urem
    7 => Mul
    8 => And
    9 => Or
    10 => Xor
    11 => Sar
    12 => Shr
    13 => Shl
    14 => Ceqw
    15 => Cnew
    16 => Csgew
    17 => Csgtw
    18 => Cslew
    19 => Csltw
    20 => Cugew
    21 => Cugtw
    22 => Culew
    23 => Cultw
    24 => Ceql
    25 => Cnel
    26 => Csgel
    27 => Csgtl
    28 => Cslel
    29 => Csltl
    30 => Cugel
    31 => Cugtl
    32 => Culel
    33 => Cultl
    34 => Ceqs
    35 => Cges
    36 => Cgts
    37 => Cles
    38 => Clts
    39 => Cnes
    40 => Cos
    41 => Cuos
    42 => Ceqd
    43 => Cged
    44 => Cgtd
    45 => Cled
    46 => Cltd
    47 => Cned
    48 => Cod
    49 => Cuod
    50 => Storeb
    51 => Storeh
    52 => Storew
    53 => Storel
    54 => Stores
    55 => Stored
    56 => Loadsb
    57 => Loadub
    58 => Loadsh
    59 => Loaduh
    60 => Loadsw
    61 => Loaduw
    62 => Load
    63 => Extsb
    64 => Extub
    65 => Extsh
    66 => Extuh
    67 => Extsw
    68 => Extuw
    69 => Exts
    70 => Truncd
    71 => Stosi
    72 => Dtosi
    73 => Swtof
    74 => Sltof
    75 => Cast
    76 => Alloc4
    77 => Alloc8
    78 => Alloc16
    79 => Vaarg
    80 => Vastart
    81 => Copy
    82 => Nop
    83 => Addr
    84 => Swap
    85 => Sign
    86 => Salloc
    87 => Xidiv
    88 => Xdiv
    89 => Xcmp
    90 => Xtest
    91 => Acmp
    92 => Acmn
    93 => Afcmp
    94 => Par
    95 => Parc
    96 => Pare
    97 => Arg
    98 => Argc
    99 => Arge
    100 => Call
    101 => Vacall
    102 => Flagieq
    103 => Flagine
    104 => Flagisge
    105 => Flagisgt
    106 => Flagisle
    107 => Flagislt
    108 => Flagiuge
    109 => Flagiugt
    110 => Flagiule
    111 => Flagiult
    112 => Flagfeq
    113 => Flagfge
    114 => Flagfgt
    115 => Flagfle
    116 => Flagflt
    117 => Flagfne
    118 => Flagfo
    119 => Flagfuo
    _ => Oxxx
  }
}

///|
// Get the zero-based index of an op in the optab
#as_free_fn(op_index, deprecated="use `Op::index` instead")
pub fn Op::index(self : Op) -> Int {
  match self {
    Oxxx => 0
    Add => 1
    Sub => 2
    Div => 3
    Rem => 4
    Udiv => 5
    Urem => 6
    Mul => 7
    And => 8
    Or => 9
    Xor => 10
    Sar => 11
    Shr => 12
    Shl => 13
    Ceqw => 14
    Cnew => 15
    Csgew => 16
    Csgtw => 17
    Cslew => 18
    Csltw => 19
    Cugew => 20
    Cugtw => 21
    Culew => 22
    Cultw => 23
    Ceql => 24
    Cnel => 25
    Csgel => 26
    Csgtl => 27
    Cslel => 28
    Csltl => 29
    Cugel => 30
    Cugtl => 31
    Culel => 32
    Cultl => 33
    Ceqs => 34
    Cges => 35
    Cgts => 36
    Cles => 37
    Clts => 38
    Cnes => 39
    Cos => 40
    Cuos => 41
    Ceqd => 42
    Cged => 43
    Cgtd => 44
    Cled => 45
    Cltd => 46
    Cned => 47
    Cod => 48
    Cuod => 49
    Storeb => 50
    Storeh => 51
    Storew => 52
    Storel => 53
    Stores => 54
    Stored => 55
    Loadsb => 56
    Loadub => 57
    Loadsh => 58
    Loaduh => 59
    Loadsw => 60
    Loaduw => 61
    Load => 62
    Extsb => 63
    Extub => 64
    Extsh => 65
    Extuh => 66
    Extsw => 67
    Extuw => 68
    Exts => 69
    Truncd => 70
    Stosi => 71
    Dtosi => 72
    Swtof => 73
    Sltof => 74
    Cast => 75
    Alloc4 => 76
    Alloc8 => 77
    Alloc16 => 78
    Vaarg => 79
    Vastart => 80
    Copy => 81
    Nop => 82
    Addr => 83
    Swap => 84
    Sign => 85
    Salloc => 86
    Xidiv => 87
    Xdiv => 88
    Xcmp => 89
    Xtest => 90
    Acmp => 91
    Acmn => 92
    Afcmp => 93
    Par => 94
    Parc => 95
    Pare => 96
    Arg => 97
    Argc => 98
    Arge => 99
    Call => 100
    Vacall => 101
    Flagieq => 102
    Flagine => 103
    Flagisge => 104
    Flagisgt => 105
    Flagisle => 106
    Flagislt => 107
    Flagiuge => 108
    Flagiugt => 109
    Flagiule => 110
    Flagiult => 111
    Flagfeq => 112
    Flagfge => 113
    Flagfgt => 114
    Flagfle => 115
    Flagflt => 116
    Flagfne => 117
    Flagfo => 118
    Flagfuo => 119
  }
}
