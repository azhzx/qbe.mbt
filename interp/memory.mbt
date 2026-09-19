///|
// Flat little-endian byte memory for the SSA interpreter. Sparse: backed by
// a Map from address to byte, so the data segment, heap and stack can live
// in fixed conceptual regions without preallocating anything.

///|
priv struct Memory {
  bytes : Map[UInt64, Byte]
  // resolved symbol addresses (data labels)
  symbols : Map[String, UInt64]
}

///|
fn Memory::new() -> Memory {
  Memory::{ bytes: Map([], capacity=0), symbols: Map([], capacity=0), }
}

///|
fn Memory::store8(self : Memory, addr : UInt64, v : Int) -> Unit {
  self.bytes[addr] = (v & 0xFF).to_byte()
}

///|
fn Memory::store_int(self : Memory, addr : UInt64, v : Int64, n : Int) -> Unit {
  let u = v.reinterpret_as_uint64()
  for i in 0..<n {
    let b = ((u >> (i * 8)) & 0xFFUL).to_int()
    self.store8(addr + i.to_uint64(), b)
  }
}

///|
fn Memory::zero(self : Memory, addr : UInt64, n : Int64) -> Unit {
  // sparse memory is zero by default; nothing to do but the call documents
  // intent at the call sites
  ignore(addr)
  ignore(n)
}

///|
fn Memory::load8(self : Memory, addr : UInt64) -> Int {
  match self.bytes.get(addr) {
    Some(b) => b.to_int()
    None => 0
  }
}

///|
// Load an n-byte little-endian integer.
fn Memory::load_int(self : Memory, addr : UInt64, n : Int) -> Int64 {
  let mut v : UInt64 = 0UL
  for i in 0..<n {
    let b = self.load8(addr + i.to_uint64())
    v = v | ((b & 0xFF).to_uint64() << (i * 8))
  }
  v.reinterpret_as_int64()
}

///|
// Zero-extended n-byte load as unsigned (for unsigned word compares).
fn Memory::load_uint(self : Memory, addr : UInt64, n : Int) -> UInt64 {
  let mut v : UInt64 = 0UL
  for i in 0..<n {
    let b = self.load8(addr + i.to_uint64())
    v = v | ((b & 0xFF).to_uint64() << (i * 8))
  }
  v
}

///|
// Read a NUL-terminated string (for printf %s and puts).
fn Memory::load_cstr(self : Memory, addr : UInt64) -> String {
  let sb = StringBuilder::StringBuilder()
  let mut p = addr
  for ;; {
    let c = self.load8(p)
    if c == 0 {
      break
    }
    sb.write_char(c.unsafe_to_char())
    p = p + 1UL
  }
  sb.to_string()
}

///|
// Store a string with NUL terminator, returning the end address.
fn Memory::store_cstr(self : Memory, addr : UInt64, s : String) -> UInt64 {
  let mut p = addr
  for c in s {
    let _ = self.bytes.set(p, c.to_int().to_byte())
    p = p + 1UL
  }
  let _ = self.bytes.set(p, b'\x00')
  p + 1UL
}
