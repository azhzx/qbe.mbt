///|
// C ABI for the in-memory JIT: compile a built module to executable memory and
// resolve functions and globals. Native-only (see moon.pkg).

///|
// Process-wide JIT registry. A slot is None after qbe_jit_free.
let jits : Array[@jit.JitModule?] = []

///|
// Host-callback symbols consulted before dlsym when qbe_jit_load resolves
// external symbols. Populate with qbe_jit_symbol_define, then load.
let jit_symbols : Array[(String, Int64)] = []

///|
fn get_jit(h : Int64) -> @jit.JitModule {
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
    let (m, fx) = b.emit_bin_module_ex()
    jits.push(
      Some(@jit.JitModule::from_bin_module_ex(m, fx, symbols=jit_symbols)),
    )
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
// Register a host callback symbol for subsequent qbe_jit_load calls.
#export_name("qbe_jit_symbol_define")
pub fn qbe_jit_symbol_define(name : Bytes, addr : Int64) -> Unit {
  jit_symbols.push((bytes_to_string(name), addr))
}

///|
// Clear the host callback symbol table.
#export_name("qbe_jit_symbol_clear")
pub fn qbe_jit_symbol_clear() -> Unit {
  jit_symbols.clear()
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
