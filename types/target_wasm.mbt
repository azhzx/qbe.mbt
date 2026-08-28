///|
// WebAssembly (wasm32) target constants.
// Mirrors target.mbt but for wasm: no physical registers, 32-bit pointers.

///|
// Wasm has no physical registers — all temporaries are locals.
// Tmp0 = 0 means every tmp id maps directly to a wasm local variable.
pub const WasmTmp0 : Int = 0

///|
// Wasm32 pointer size: Kw (32-bit), not Kl (64-bit).
// On amd64 Km=Kl; on wasm32 Km=Kw.
pub const WasmKmIsWide : Int = 0

///|
// Number of general purpose registers (wasm: 0)
pub const WasmNGPR : Int = 0

///|
// Number of float registers (wasm: 0)
pub const WasmNFPR : Int = 0

///|
// Number of caller-save GPRs (wasm: 0)
pub const WasmNGPS : Int = 0

///|
// Number of caller-save FPRs (wasm: 0)
pub const WasmNFPS : Int = 0

///|
// Number of callee-save registers (wasm: 0)
pub const WasmNCLR : Int = 0

///|
// Number of globally live registers (wasm: 0)
pub const WasmNRGLOB : Int = 0

///|
// Wasm caller-save register list (empty — no physical registers)
pub let wasm_rsave : Array[Int] = []

///|
// Wasm callee-save register list (empty)
pub let wasm_rclob : Array[Int] = []

///|
// Wasm globally live register mask (0 — no globally live registers)
pub fn wasm_rglob_mask() -> UInt64 {
  0UL
}

///|
// Wasm stack base address in linear memory (64KB)
pub const WASM_STACK_BASE : Int = 65536

///|
// Wasm stack alignment requirement (16 bytes)
pub const WASM_STACK_ALIGN : Int = 16

///|
// Wasm memory initial pages (64KB each)
pub const WASM_MEMORY_PAGES : Int = 1

///|
// Wasm local variable classes (maps QBE Class to wasm type)
pub enum WasmType {
  Wi32
  Wi64
  Wf32
  Wf64
  WVoid
} derive(Debug, Eq)

///|
// Map QBE Class to WasmType
pub fn class_to_wasm_type(cls : Class) -> WasmType {
  match cls {
    Kw => Wi32
    Kl => Wi64
    Ks => Wf32
    Kd => Wf64
    _ => Wi32
  }
}

///|
// Wasm type name string for WAT output
pub fn wasm_type_name(cls : Class) -> String {
  match cls {
    Kw => "i32"
    Kl => "i64"
    Ks => "f32"
    Kd => "f64"
    _ => "i32"
  }
}

///|
// Map QBE Class to wasm memory instruction width
pub fn wasm_load_op(cls : Class) -> String {
  match cls {
    Kw => "i32.load"
    Kl => "i64.load"
    Ks => "f32.load"
    Kd => "f64.load"
    _ => "i32.load"
  }
}

///|
pub fn wasm_store_op(cls : Class) -> String {
  match cls {
    Kw => "i32.store"
    Kl => "i64.store"
    Ks => "f32.store"
    Kd => "f64.store"
    _ => "i32.store"
  }
}

///|
// Initialize wasm function: no physical register temporaries.
// All tmps start at index 0 (WasmTmp0), directly mapping to wasm locals.
pub fn Fn::init_regs_wasm(self : Self) -> Unit {
  // Wasm has no physical registers — tmps[0..] are all user temporaries.
  // No register pre-population needed.
  ()
}
