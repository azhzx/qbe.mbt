///|
// Floating-point constant stash shared by isel and emit (C gasstash in gas.c).
// Indexes become the "fp%d" labels emitted by gasemitfin.

///|
pub struct FpBits {
  b0 : Int64
  b1 : Int64
  size : Int
}

///|
// Compare the first n bytes of two 16-byte little-endian values.
fn fp_memcmp(a0 : Int64, a1 : Int64, b0 : Int64, b1 : Int64, n : Int) -> Bool {
  if n >= 8 {
    if a0 != b0 {
      return false
    }
    if n >= 16 {
      return a1 == b1
    }
    true
  } else if n == 4 {
    (a0 & 0xFFFFFFFF) == (b0 & 0xFFFFFFFF)
  } else {
    false
  }
}

///|
// Deduplicated stash of fp constants (C gasstash in gas.c). bits0/bits1 are
// the 16-byte value, size is 4, 8, or 16. A smaller size matches the prefix
// of a larger entry (size <= b->size).
let fp_stash : Array[FpBits] = Array::new()

///|
pub fn gasstash(bits0 : Int64, bits1 : Int64, size : Int) -> Int {
  for i in 0..<fp_stash.length() {
    let e = fp_stash[i]
    if size <= e.size {
      if fp_memcmp(bits0, bits1, e.b0, e.b1, size) {
        return i
      }
    }
  }
  fp_stash.push(FpBits::{ b0: bits0, b1: bits1, size })
  fp_stash.length() - 1
}

///|
pub fn fp_stash_len() -> Int {
  fp_stash.length()
}

///|
pub fn fp_stash_at(i : Int) -> FpBits {
  fp_stash[i]
}
