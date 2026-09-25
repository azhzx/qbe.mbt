///|
// Assembly text -> Mach-O object file / loadable module, by delegating to the
// system toolchain (clang). This is the "route A" backend: qbe.mbt still emits
// the assembly, and clang turns it into bytes.
//
// It only works on hosts whose clang can assemble the target's assembly; for
// macOS/aarch64 pass the Mach-O flavor (-G m) text.

///|
fn run_clang(args : String) -> Unit raise {
  let rc = @native.mbt_native_run(@native.cstr(args))
  if rc != 0 {
    abort("run-asm: command failed (\{rc}): \{args}")
  }
}

///|
// Assemble qbe.mbt's emitted assembly text into a Mach-O object file and
// return its bytes.
pub fn assemble_object(asm : String) -> Bytes raise {
  let s_path = @native.tmp_path(".s")
  let o_path = @native.tmp_path(".o")
  if @native.mbt_native_write_file(@native.cstr(s_path), @native.cstr(asm)) != 0 {
    abort("run-asm: cannot write \{s_path}")
  }
  run_clang("clang -c \{s_path} -o \{o_path}")
  let obj = @native.mbt_native_read_file(@native.cstr(o_path))
  ignore(@native.mbt_native_unlink(@native.cstr(s_path)))
  ignore(@native.mbt_native_unlink(@native.cstr(o_path)))
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
  let s_path = @native.tmp_path(".s")
  let lib_path = @native.tmp_path(".dylib")
  if @native.mbt_native_write_file(@native.cstr(s_path), @native.cstr(asm)) != 0 {
    abort("run-asm: cannot write \{s_path}")
  }
  run_clang("clang -dynamiclib -o \{lib_path} \{s_path}")
  let handle = @native.mbt_native_dlopen(@native.cstr(lib_path))
  ignore(@native.mbt_native_unlink(@native.cstr(s_path)))
  ignore(@native.mbt_native_unlink(@native.cstr(lib_path)))
  if handle == 0L {
    abort("run-asm: dlopen failed")
  }
  { handle, }
}

///|
// Compile WAT to wasm (moon-wasm-opt) and run `func` with `args` under node.
// Returns whatever the invocation printed (the result).
pub fn run_wasm(
  wat : String,
  func : String,
  args : Array[String],
) -> String raise {
  let wat_path = @native.tmp_path(".wat")
  let wasm_path = @native.tmp_path(".wasm")
  let js_path = @native.tmp_path(".cjs")
  if @native.mbt_native_write_file(@native.cstr(wat_path), @native.cstr(wat)) !=
    0 {
    raise @util.QbeError::CompileError("run-wasm: cannot write " + wat_path)
  }
  let opt = "$HOME/.moon/bin/moon-wasm-opt"
  let rc = @native.mbt_native_run(
    @native.cstr(opt + " " + wat_path + " -o " + wasm_path),
  )
  if rc != 0 {
    raise @util.QbeError::CompileError(
      "run-wasm: wat2wasm failed (moon-wasm-opt missing, or the wasm is invalid)",
    )
  }
  if @native.mbt_native_write_file(@native.cstr(js_path), @native.cstr(driver)) !=
    0 {
    raise @util.QbeError::CompileError("run-wasm: cannot write the node driver")
  }
  let mut argstr = ""
  for a in args {
    argstr = argstr + " " + a
  }
  let out = @native.mbt_native_capture(
    @native.cstr("node " + js_path + " " + wasm_path + " " + func + argstr),
  )
  ignore(@native.mbt_native_unlink(@native.cstr(wat_path)))
  ignore(@native.mbt_native_unlink(@native.cstr(wasm_path)))
  ignore(@native.mbt_native_unlink(@native.cstr(js_path)))
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
// Resolve an exported function. dlsym takes the C identifier (no leading
// underscore) even though Mach-O symbol tables store "_name".
pub fn RunAsmModule::lookup(self : RunAsmModule, name : String) -> Int64 raise {
  let addr = @native.mbt_native_dlsym(self.handle, @native.cstr(name))
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
  @native.mbt_native_call_i64_1(self.lookup(name), a0)
}
