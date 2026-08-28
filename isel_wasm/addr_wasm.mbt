///|
// Wasm address mode decomposition.
// Wasm memory access only supports [base + offset], so complex
// addressing modes like [base + index*scale + offset] must be
// decomposed into explicit arithmetic + load/store.

///|
// Decompose a complex address into a simple base + offset form.
// Returns (base, index, scale, offset) where:
//   - base: the base register/ref
//   - index: the index register/ref (Ref::none() if not used)
//   - scale: the scale factor (1 if not used)
//   - offset: the constant offset
pub fn decompose_addr(
  base : @types.Ref,
  index : @types.Ref,
  scale : Int,
  offset : @types.Con,
) -> (@types.Ref, @types.Ref, Int, @types.Con) {
  // For wasm, we can only handle [base + offset] directly.
  // If there's an index/scale, we need to emit arithmetic.
  (base, index, scale, offset)
}

///|
// Check if a constant is a valid wasm memory offset.
// Wasm memory offsets must be non-negative integers.
pub fn is_wasm_mem_offset(c : @types.Con) -> Bool {
  if c.kind == @types.CBits && c.flt == 0 {
    c.bits.i >= 0L
  } else {
    false
  }
}

///|
// Get the numeric offset value from a constant.
pub fn wasm_mem_offset(c : @types.Con) -> Int64 {
  if c.kind == @types.CBits && c.flt == 0 {
    c.bits.i
  } else {
    0L
  }
}

///|
// Check if an address can be represented as a simple wasm [base + offset].
// Returns true if index is none and scale is 1.
pub fn is_simple_addr(
  base : @types.Ref,
  index : @types.Ref,
  scale : Int,
) -> Bool {
  index.is_none() && scale == 1
}
