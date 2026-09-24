///|
// Assembly text -> Mach-O object file / loadable module, by delegating to the
// system toolchain (clang). This is the "route A" backend: qbe.mbt still emits
// the assembly, and clang turns it into bytes.
//
// It only works on hosts whose clang can assemble the target's assembly; for
// macOS/aarch64 pass the Mach-O flavor (-G m) text.

///|
fn cstr(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
fn run_clang(args : String) -> Unit raise {
  let rc = mbt_jit_run(cstr(args))
  if rc != 0 {
    abort("jit: command failed (\{rc}): \{args}")
  }
}

///|
fn tmp_path(suffix : String) -> String {
  @utf8.decode_lossy(mbt_jit_temp(cstr(suffix)))
}

///|
// Assemble qbe.mbt's emitted assembly text into a Mach-O object file and
// return its bytes.
pub fn assemble_object(asm : String) -> Bytes raise {
  let s_path = tmp_path(".s")
  let o_path = tmp_path(".o")
  if mbt_jit_write_file(cstr(s_path), cstr(asm)) != 0 {
    abort("jit: cannot write \{s_path}")
  }
  run_clang("clang -c \{s_path} -o \{o_path}")
  let obj = mbt_jit_read_file(cstr(o_path))
  ignore(mbt_jit_unlink(cstr(s_path)))
  ignore(mbt_jit_unlink(cstr(o_path)))
  if obj.length() == 0 {
    abort("jit: clang produced an empty object")
  }
  obj
}

///|
// A dynamically loaded module produced from assembly text.
pub struct JitModule {
  handle : Int64
}

///|
// Assemble the text into a shared library and dlopen it.
pub fn JitModule::load_shared(asm : String) -> JitModule raise {
  let s_path = tmp_path(".s")
  let lib_path = tmp_path(".dylib")
  if mbt_jit_write_file(cstr(s_path), cstr(asm)) != 0 {
    abort("jit: cannot write \{s_path}")
  }
  run_clang("clang -dynamiclib -o \{lib_path} \{s_path}")
  let handle = mbt_jit_dlopen(cstr(lib_path))
  ignore(mbt_jit_unlink(cstr(s_path)))
  ignore(mbt_jit_unlink(cstr(lib_path)))
  if handle == 0L {
    abort("jit: dlopen failed")
  }
  { handle, }
}

///|
// A self-contained executable code block: machine code copied into
// mmap'd memory and made executable.
pub struct JitExec {
  addr : Int64
  size : Int
}

///|
// Copy arm64 code into executable memory.
pub fn JitExec::load_text(text : Bytes) -> JitExec raise {
  let n = text.length()
  if n == 0 {
    abort("jit: empty code")
  }
  let addr = mbt_jit_alloc(n)
  if addr == 0L {
    abort("jit: mmap failed")
  }
  mbt_jit_write_bytes(addr, 0, text)
  if mbt_jit_protect(addr, n) != 0 {
    abort("jit: mprotect failed")
  }
  { addr, size: n, }
}

///|
// Call a one-argument i64 function in this code block.
pub fn JitExec::call1(self : JitExec, a0 : Int64) -> Int64 raise {
  mbt_jit_call_i64_1(self.addr, a0)
}

///|
// Run a shell command, returning its exit status.
pub fn run_command(cmd : String) -> Int {
  mbt_jit_run(cstr(cmd))
}

///|
// Write raw bytes to a file.
pub fn write_file(path : String, data : Bytes) -> Unit raise {
  if mbt_jit_write_file(cstr(path), data) != 0 {
    abort("jit: cannot write \{path}")
  }
}

///|
// Resolve an exported function. dlsym takes the C identifier (no leading
// underscore) even though Mach-O symbol tables store "_name".
pub fn JitModule::lookup(self : JitModule, name : String) -> Int64 raise {
  let addr = mbt_jit_dlsym(self.handle, cstr(name))
  if addr == 0L {
    abort("jit: symbol '\{name}' not found")
  }
  addr
}

///|
// Call a one-argument i64 function.
pub fn JitModule::call1(
  self : JitModule,
  name : String,
  a0 : Int64,
) -> Int64 raise {
  mbt_jit_call_i64_1(self.lookup(name), a0)
}
