///|
// Floating-point constant stash shared by isel and emit (C gasstash in gas.c).
// Indexes become the "fp%d" labels emitted by gasemitfin.

///|
pub struct FpBits {
  b0 : Int64
  b1 : Int64
  size : Int32
}

///|
// Deduplicated stash of fp constants (C emit.c stashbits, declared in all.h
// as int stashbits(bits, int)). The C entry is {bits n; int size;}, so the
// identity of a constant is the FULL 64-bit word plus its size class: an entry
// is reused when size <= b->size && b->n == n. Comparing only the first
// size bytes is not equivalent: a 4-byte request whose word equals the low
// half of an 8-byte entry must NOT be folded into it, because C keeps the two
// labels (a 4-byte load of the 8-byte entry would happen to be the right
// value, but the reference's pool and label numbering differ).
//
// bits1 is the port's second halfword for size 16; C only stores one word and
// prints a literal zero for the second half, and every caller passes 0L here,
// so the comparison is on bits0 only, exactly like C.
let fp_stash : Array[FpBits] = []

///|
pub fn gasstash(bits0 : Int64, bits1 : Int64, size : Int32) -> Int32 {
  for i in 0..<fp_stash.length() {
    let e = fp_stash[i]
    if size <= e.size && e.b0 == bits0 {
      return i
    }
  }
  fp_stash.push(FpBits::{ b0: bits0, b1: bits1, size, })
  fp_stash.length() - 1
}

///|
pub fn fp_stash_len() -> Int32 {
  fp_stash.length()
}

///|
pub fn fp_stash_at(i : Int32) -> FpBits {
  fp_stash[i]
}

///|
// Reset the stash. The C reference processes one input file per process run;
// as a library, successive compile() calls in the same process must each start
// with an empty stash so fp label numbering (and the emitted rodata section)
// stays deterministic per module.
pub fn fp_stash_reset() -> Unit {
  fp_stash.clear()
}
