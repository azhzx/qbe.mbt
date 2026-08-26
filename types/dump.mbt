///|
// Debug/analysis helpers shared by the register allocator passes.
// phicls corresponds to util.c phicls, dumpts to util.c dumpts.

///|
// Find the representative of a phi class (C phicls in util.c), with path
// compression. is_phi is 0 for non-phi temporaries.
pub fn phicls(t : Int, tmps : Array[Tmp]) -> Int {
  let t1 = tmps[t].is_phi
  if t1 == 0 {
    return t
  }
  let r = phicls(t1, tmps)
  tmps[t].is_phi = r
  r
}

///|
// Dump the temporaries of a set, as C dumpts: "[ %a %b ]\n".
pub fn dumpts(bs : BSet, tmps : Array[Tmp]) -> String {
  let sb = StringBuilder::new()
  sb.write_char('[')
  bs.each_from(Tmp0, t => {
    sb.write_char(' ')
    sb.write_string(tmps[t].name)
  })
  sb.write_string(" ]\n")
  sb.to_string()
}
