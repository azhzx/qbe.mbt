///|
// Bit set - corresponds to struct BSet in QBE
pub(all) struct BSet {
  nt : Int // Number of elements (total bits)
  bits : Array[UInt64] // Bit storage (mutable array)
} derive(Debug)

///|
// Bits per UInt64 word
let nbit = 64

///|
// Create a new BSet for nt elements
pub fn BSet::new(nt : Int) -> BSet {
  let nwords = (nt + nbit - 1) / nbit
  let zero : UInt64 = 0
  BSet::{ nt, bits: Array::make(nwords, zero) }
}

///|
// Zero out all bits
pub fn BSet::zero(self : Self) -> Unit {
  let zero : UInt64 = 0
  for i in 0..<self.bits.length() {
    self.bits[i] = zero
  }
}

///|
// Set a bit
pub fn BSet::set(self : Self, elt : Int) -> Unit {
  let word = elt / nbit
  let bit = elt % nbit
  let one : UInt64 = 1
  self.bits[word] = self.bits[word] | (one << bit)
}

///|
// Clear a bit
pub fn BSet::clr(self : Self, elt : Int) -> Unit {
  let word = elt / nbit
  let bit = elt % nbit
  let one : UInt64 = 1
  self.bits[word] = self.bits[word] & (one << bit).lnot()
}

///|
// Test if a bit is set
pub fn BSet::has(self : Self, elt : Int) -> Bool {
  let word = elt / nbit
  let bit = elt % nbit
  if word < 0 || word >= self.bits.length() {
    return false
  }
  let one : UInt64 = 1
  (self.bits[word] & (one << bit)) != 0
}

///|
// Count set bits
pub fn BSet::count(self : Self) -> Int {
  let mut cnt = 0
  for w in self.bits {
    cnt = cnt + w.popcnt()
  }
  cnt
}

///|
// Copy from another BSet
pub fn BSet::copy_from(self : Self, other : BSet) -> Unit {
  let len = self.bits.length().min(other.bits.length())
  for i in 0..<len {
    self.bits[i] = other.bits[i]
  }
}

///|
// Union: self |= other. Returns true if self changed
pub fn BSet::union(self : Self, other : BSet) -> Bool {
  let len = self.bits.length().min(other.bits.length())
  let mut changed = false
  for i in 0..<len {
    let old = self.bits[i]
    self.bits[i] = self.bits[i] | other.bits[i]
    if old != self.bits[i] {
      changed = true
    }
  }
  changed
}

///|
// Intersect: self &= other
pub fn BSet::inter(self : Self, other : BSet) -> Unit {
  let len = self.bits.length().min(other.bits.length())
  for i in 0..<len {
    self.bits[i] = self.bits[i] & other.bits[i]
  }
}

///|
// Difference: self &= ~other
pub fn BSet::diff(self : Self, other : BSet) -> Unit {
  let len = self.bits.length().min(other.bits.length())
  for i in 0..<len {
    self.bits[i] = self.bits[i] & other.bits[i].lnot()
  }
}

///|
// Equality check
pub fn BSet::equal(self : Self, other : BSet) -> Bool {
  let len = self.bits.length().min(other.bits.length())
  for i in 0..<len {
    if self.bits[i] != other.bits[i] {
      return false
    }
  }
  true
}

///|
// Iterate over set bits. Returns the next element index >= start, or -1 if
// done. Matches C bsiter (inclusive of start).
pub fn BSet::iter(self : Self, start : Int) -> Int {
  let mut i = if start < 0 { 0 } else { start }
  let nbits_total = self.bits.length() * nbit
  while i < nbits_total {
    if self.has(i) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
// Call f for every set bit, in increasing order.
pub fn BSet::each(self : Self, f : (Int) -> Unit) -> Unit {
  for i in 0..<(self.bits.length() * nbit) {
    if self.has(i) {
      f(i)
    }
  }
}

///|
// Call f for every set bit with index >= start, in increasing order.
pub fn BSet::each_from(self : Self, start : Int, f : (Int) -> Unit) -> Unit {
  for i in start.max(0)..<(self.bits.length() * nbit) {
    if self.has(i) {
      f(i)
    }
  }
}
