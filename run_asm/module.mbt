///|
// Assembly text -> Mach-O object file / loadable module, by delegating to the
// system toolchain (clang). This is the "route A" backend: qbe.mbt still emits
// the assembly, and clang turns it into bytes.
//
// It only works on hosts whose clang can assemble the target's assembly; for
// macOS/aarch64 pass the Mach-O flavor (-G m) text.

///|
// Whether the in-process arm64 backend is usable on this host (macOS on
// aarch64). Other hosts skip the executable-memory tests.
pub fn host_supported() -> Bool {
  mbt_run_asm_host_supported() != 0
}

///|
fn cstr(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
fn run_clang(args : String) -> Unit raise {
  let rc = mbt_run_asm_run(cstr(args))
  if rc != 0 {
    abort("run-asm: command failed (\{rc}): \{args}")
  }
}

///|
fn tmp_path(suffix : String) -> String {
  @utf8.decode_lossy(mbt_run_asm_temp(cstr(suffix)))
}

///|
// Assemble qbe.mbt's emitted assembly text into a Mach-O object file and
// return its bytes.
pub fn assemble_object(asm : String) -> Bytes raise {
  let s_path = tmp_path(".s")
  let o_path = tmp_path(".o")
  if mbt_run_asm_write_file(cstr(s_path), cstr(asm)) != 0 {
    abort("run-asm: cannot write \{s_path}")
  }
  run_clang("clang -c \{s_path} -o \{o_path}")
  let obj = mbt_run_asm_read_file(cstr(o_path))
  ignore(mbt_run_asm_unlink(cstr(s_path)))
  ignore(mbt_run_asm_unlink(cstr(o_path)))
  if obj.length() == 0 {
    abort("run-asm: clang produced an empty object")
  }
  obj
}

///|
// A dynamically loaded module produced from assembly text.
pub struct RunAsmModule {
  handle : Int64
}

///|
// Assemble the text into a shared library and dlopen it.
pub fn RunAsmModule::load_shared(asm : String) -> RunAsmModule raise {
  let s_path = tmp_path(".s")
  let lib_path = tmp_path(".dylib")
  if mbt_run_asm_write_file(cstr(s_path), cstr(asm)) != 0 {
    abort("run-asm: cannot write \{s_path}")
  }
  run_clang("clang -dynamiclib -o \{lib_path} \{s_path}")
  let handle = mbt_run_asm_dlopen(cstr(lib_path))
  ignore(mbt_run_asm_unlink(cstr(s_path)))
  ignore(mbt_run_asm_unlink(cstr(lib_path)))
  if handle == 0L {
    abort("run-asm: dlopen failed")
  }
  { handle, }
}

///|
// A self-contained executable code block: machine code copied into
// mmap'd memory and made executable.
pub struct ExecBlock {
  addr : Int64
  size : Int
}

///|
// Copy a route-B module image into memory: the first code_bytes are made
// executable (RX) while any global data that follows stays writable (RW).
pub fn ExecBlock::load_module(
  image : Bytes,
  code_bytes : Int,
) -> ExecBlock raise {
  let n = image.length()
  if n == 0 {
    abort("run-asm: empty module image")
  }
  let addr = mbt_run_asm_alloc(n)
  if addr == 0L {
    abort("run-asm: mmap failed")
  }
  mbt_run_asm_write_bytes(addr, 0, image)
  if mbt_run_asm_protect(addr, code_bytes) != 0 {
    abort("run-asm: mprotect failed")
  }
  { addr, size: n, }
}

///|
// Copy arm64 code into executable memory.
pub fn ExecBlock::load_text(text : Bytes) -> ExecBlock raise {
  let n = text.length()
  if n == 0 {
    abort("run-asm: empty code")
  }
  let addr = mbt_run_asm_alloc(n)
  if addr == 0L {
    abort("run-asm: mmap failed")
  }
  mbt_run_asm_write_bytes(addr, 0, text)
  if mbt_run_asm_protect(addr, n) != 0 {
    abort("run-asm: mprotect failed")
  }
  { addr, size: n, }
}

///|
// Call a one-argument i64 function in this code block.
pub fn ExecBlock::call1(self : ExecBlock, a0 : Int64) -> Int64 raise {
  mbt_run_asm_call_i64_1(self.addr, a0)
}

///|
// Call a one-argument i64 function at a word offset into this code block (the
// offset used by Arm64BinModule::fns).
pub fn ExecBlock::call1_at(
  self : ExecBlock,
  off : Int,
  a0 : Int64,
) -> Int64 raise {
  mbt_run_asm_call_i64_1(self.addr + off.to_int64() * 4L, a0)
}

///|
// Run a shell command, returning its exit status.
pub fn run_command(cmd : String) -> Int {
  mbt_run_asm_run(cstr(cmd))
}

///|
// Compile WAT to wasm (moon-wasm-opt) and run `func` with `args` under node.
// Returns whatever the invocation printed (the result).
pub fn run_wasm(
  wat : String,
  func : String,
  args : Array[String],
) -> String raise {
  let wat_path = tmp_path(".wat")
  let wasm_path = tmp_path(".wasm")
  let js_path = tmp_path(".cjs")
  if mbt_run_asm_write_file(cstr(wat_path), cstr(wat)) != 0 {
    raise @util.QbeError::CompileError("run-wasm: cannot write " + wat_path)
  }
  let opt = "$HOME/.moon/bin/moon-wasm-opt"
  let rc = mbt_run_asm_run(cstr(opt + " " + wat_path + " -o " + wasm_path))
  if rc != 0 {
    raise @util.QbeError::CompileError(
      "run-wasm: wat2wasm failed (moon-wasm-opt missing, or the wasm is invalid)",
    )
  }
  if mbt_run_asm_write_file(cstr(js_path), cstr(driver)) != 0 {
    raise @util.QbeError::CompileError("run-wasm: cannot write the node driver")
  }
  let mut argstr = ""
  for a in args {
    argstr = argstr + " " + a
  }
  let out = mbt_run_asm_capture(
    cstr("node " + js_path + " " + wasm_path + " " + func + argstr),
  )
  ignore(mbt_run_asm_unlink(cstr(wat_path)))
  ignore(mbt_run_asm_unlink(cstr(wasm_path)))
  ignore(mbt_run_asm_unlink(cstr(js_path)))
  @utf8.decode_lossy(out)
}

///|
// Node driver used by run_wasm.
let driver : String =
  #|const fs = require('fs');
  #|const argv = process.argv;
  #|const wasmPath = argv[2];
  #|const func = argv[3];
  #|const rest = argv.slice(4);
  #|WebAssembly.instantiate(fs.readFileSync(wasmPath)).then(function(res) {
  #|  var f = res.instance.exports[func];
  #|  if (!f) { console.error('no export ' + func); process.exit(2); }
  #|  var r;
  #|  try { r = f.apply(null, rest.map(Number)); }
  #|  catch (e) { r = f.apply(null, rest.map(BigInt)); }
  #|  process.stdout.write(String(r));
  #|}).catch(function(e) { console.error(String(e.message || e)); process.exit(1); });
  #|

///|
// Write raw bytes to a file.
pub fn write_file(path : String, data : Bytes) -> Unit raise {
  if mbt_run_asm_write_file(cstr(path), data) != 0 {
    abort("run-asm: cannot write \{path}")
  }
}

///|
// Resolve an exported function. dlsym takes the C identifier (no leading
// underscore) even though Mach-O symbol tables store "_name".
pub fn RunAsmModule::lookup(self : RunAsmModule, name : String) -> Int64 raise {
  let addr = mbt_run_asm_dlsym(self.handle, cstr(name))
  if addr == 0L {
    abort("run-asm: symbol '\{name}' not found")
  }
  addr
}

///|
// Call a one-argument i64 function.
pub fn RunAsmModule::call1(
  self : RunAsmModule,
  name : String,
  a0 : Int64,
) -> Int64 raise {
  mbt_run_asm_call_i64_1(self.lookup(name), a0)
}

///|
// The base address of the mapped image.
pub fn ExecBlock::base(self : ExecBlock) -> Int64 {
  self.addr
}

///|
// Unmap the image. Call at most once.
pub fn ExecBlock::close(self : ExecBlock) -> Unit {
  if self.addr != 0L {
    mbt_run_asm_free(self.addr, self.size)
  }
}

///|
// A JIT-loaded module: the code image mapped executable, plus the symbol
// tables needed to resolve functions and globals.
pub struct JitModule {
  exec : ExecBlock
  fns : Array[(String, Int)] // function name -> word offset in the text
  datas : Array[(String, Int)] // global name -> byte offset in the data image
  code_bytes : Int // size of the (page-aligned) code region
}

///|
// Map a linked image into executable memory (Route B, no linker).
pub fn JitModule::from_bin_module(m : @qbe.Arm64BinModule) -> JitModule raise {
  let exec = ExecBlock::load_module(m.image(), m.code_bytes)
  { exec, fns: m.fns, datas: m.datas, code_bytes: m.code_bytes, }
}

///|
// Resolve a function to its entry address.
pub fn JitModule::symbol(self : JitModule, name : String) -> Int64 raise {
  for p in self.fns {
    if p.0 == name {
      return self.exec.base() + (p.1 * 4).to_int64()
    }
  }
  raise @util.QbeError::CompileError("jit: no such function: " + name)
}

///|
// Resolve a global to its address (the data image starts after the code).
pub fn JitModule::global(self : JitModule, name : String) -> Int64 raise {
  for p in self.datas {
    if p.0 == name {
      return self.exec.base() + self.code_bytes.to_int64() + p.1.to_int64()
    }
  }
  raise @util.QbeError::CompileError("jit: no such global: " + name)
}

///|
// Function names in the module.
pub fn JitModule::function_names(self : JitModule) -> Array[String] {
  let names : Array[String] = []
  for p in self.fns {
    names.push(p.0)
  }
  names
}

///|
// Call a one-argument i64 function by name.
pub fn JitModule::call_i64_1(
  self : JitModule,
  name : String,
  a0 : Int64,
) -> Int64 raise {
  mbt_run_asm_call_i64_1(self.symbol(name), a0)
}

///|
// Unmap the code image.
pub fn JitModule::close(self : JitModule) -> Unit {
  self.exec.close()
}
