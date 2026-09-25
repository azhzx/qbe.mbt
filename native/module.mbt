///|
// Whether the in-process arm64 backend is usable on this host (macOS on
// aarch64). Other hosts skip the executable-memory tests.
pub fn host_supported() -> Bool {
  mbt_native_host_supported() != 0
}

///|
pub fn cstr(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
pub fn tmp_path(suffix : String) -> String {
  @utf8.decode_lossy(mbt_native_temp(cstr(suffix)))
}

///|
// Write raw bytes to a file.
pub fn write_file(path : String, data : Bytes) -> Unit raise {
  if mbt_native_write_file(cstr(path), data) != 0 {
    abort("run-asm: cannot write \{path}")
  }
}

///|
// Run a shell command, returning its exit status.
pub fn run_command(cmd : String) -> Int {
  mbt_native_run(cstr(cmd))
}
