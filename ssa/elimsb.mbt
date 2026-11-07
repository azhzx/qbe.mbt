///|
// C abi.c elimsb: eliminate the sub-word ABI op variants for targets that
// treat char/short as words with arbitrary high bits (all upstream targets
// use this as their abi0).

///|
pub fn elimsb(fn_ : @types.Fn) -> Unit {
  for bi in 0..<fn_.blks.length() {
    let b = fn_.blks[bi]
    for ii in 0..<b.ins.length() {
      let op = b.ins[ii].op
      if op.is_arg_bh() {
        b.ins[ii].op = @types.Arg
      } else if op.is_par_bh() {
        b.ins[ii].op = @types.Par
      }
    }
    if b.jmp.kind.is_ret_bh() {
      b.jmp.kind = @types.Jretw
    }
  }
}
