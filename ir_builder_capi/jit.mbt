///|
// C ABI for the in-memory JIT: compile a built module to executable memory and
// resolve functions and globals. Native-only (see moon.pkg).

///|
// Process-wide JIT registry. A slot is None after qbe_jit_free.
let jits : Array[@run_asm.JitModule?] = []

///|
fn get_jit(h : Int64) -> @run_asm.JitModule {
  let i = h.to_int() - 1
  if i < 0 || i >= jits.length() {
    abort("qbe: invalid jit handle")
  }
  match jits[i] {
    Some(j) => j
    None => abort("qbe: released jit handle")
  }
}

///|
// Compile the module to a self-contained code image, map it executable and
// return a JIT handle (0 on failure; see qbe_last_error).
#export_name("qbe_jit_load")
pub fn qbe_jit_load(h : Int64) -> Int64 {
  let b = get_builder(h)
  try {
    let m = b.emit_bin_module()
    jits.push(Some(@run_asm.JitModule::from_bin_module(m)))
    jits.length().to_int64()
  } catch {
    e => {
      set_error("\{e}")
      0L
    }
  } noraise {
    v => v
  }
}

///|
// Resolve an exported function to its address (0 on failure).
#export_name("qbe_jit_symbol")
pub fn qbe_jit_symbol(h : Int64, name : Bytes) -> Int64 {
  let j = get_jit(h)
  try j.symbol(bytes_to_string(name)) catch {
    e => {
      set_error("\{e}")
      0L
    }
  } noraise {
    a => a
  }
}

///|
// Resolve a global to its address (0 on failure).
#export_name("qbe_jit_global")
pub fn qbe_jit_global(h : Int64, name : Bytes) -> Int64 {
  let j = get_jit(h)
  try j.global(bytes_to_string(name)) catch {
    e => {
      set_error("\{e}")
      0L
    }
  } noraise {
    a => a
  }
}

///|
// Unmap a JIT module and release its handle.
#export_name("qbe_jit_free")
pub fn qbe_jit_free(h : Int64) -> Unit {
  let i = h.to_int() - 1
  if i >= 0 && i < jits.length() {
    match jits[i] {
      Some(j) => j.close()
      None => ()
    }
    jits[i] = None
  }
}
