///|
// Raw FFI to the native run-asm shim (run_asm_stub.c).
//
// Addresses cross the boundary as Int64 (pointer-sized) so relocation
// arithmetic can stay in MoonBit.

///|
// 1 on macOS/aarch64, the only host this backend targets.
pub extern "c" fn mbt_native_host_supported() -> Int = "mbt_native_host_supported"

///|
pub extern "c" fn mbt_native_alloc(size : Int) -> Int64 = "mbt_native_alloc"

///|
pub extern "c" fn mbt_native_protect(addr : Int64, size : Int) -> Int = "mbt_native_protect"

///|
pub extern "c" fn mbt_native_free(addr : Int64, size : Int) = "mbt_native_free"

///|
#borrow(data)
pub extern "c" fn mbt_native_write_bytes(addr : Int64, off : Int, data : Bytes) = "mbt_native_write_bytes"

///|
pub extern "c" fn mbt_native_write_u32(addr : Int64, off : Int, word : UInt) = "mbt_native_write_u32"

///|
#borrow(suffix)
pub extern "c" fn mbt_native_temp(suffix : Bytes) -> Bytes = "mbt_native_temp"

///|
#borrow(path, data)
pub extern "c" fn mbt_native_write_file(path : Bytes, data : Bytes) -> Int = "mbt_native_write_file"

///|
#borrow(path)
pub extern "c" fn mbt_native_read_file(path : Bytes) -> Bytes = "mbt_native_read_file"

///|
#borrow(path)
pub extern "c" fn mbt_native_unlink(path : Bytes) -> Int = "mbt_native_unlink"

///|
#borrow(cmd)
pub extern "c" fn mbt_native_run(cmd : Bytes) -> Int = "mbt_native_run"

///|
#borrow(cmd)
pub extern "c" fn mbt_native_capture(cmd : Bytes) -> Bytes = "mbt_native_capture"

///|
#borrow(path)
pub extern "c" fn mbt_native_dlopen(path : Bytes) -> Int64 = "mbt_native_dlopen"

///|
#borrow(name)
pub extern "c" fn mbt_native_dlsym(handle : Int64, name : Bytes) -> Int64 = "mbt_native_dlsym"

///|
#borrow(name)
pub extern "c" fn mbt_native_sym(name : Bytes) -> Int64 = "mbt_native_sym"

///|
pub extern "c" fn mbt_native_call_i64_1(addr : Int64, a0 : Int64) -> Int64 = "mbt_native_call_i64_1"

///|
pub extern "c" fn mbt_native_icache_flush(addr : Int64, size : Int) = "mbt_native_icache_flush"

///|
pub extern "c" fn mbt_native_call_i64_0(addr : Int64) -> Int64 = "mbt_native_call_i64_0"

///|
pub extern "c" fn mbt_native_call_i64_2(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
) -> Int64 = "mbt_native_call_i64_2"

///|
pub extern "c" fn mbt_native_call_i64_3(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
) -> Int64 = "mbt_native_call_i64_3"

///|
pub extern "c" fn mbt_native_call_i64_4(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
) -> Int64 = "mbt_native_call_i64_4"

///|
pub extern "c" fn mbt_native_call_i64_5(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
  a4 : Int64,
) -> Int64 = "mbt_native_call_i64_5"

///|
pub extern "c" fn mbt_native_call_i64_6(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
  a4 : Int64,
  a5 : Int64,
) -> Int64 = "mbt_native_call_i64_6"

///|
pub extern "c" fn mbt_native_call_i64_7(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
  a4 : Int64,
  a5 : Int64,
  a6 : Int64,
) -> Int64 = "mbt_native_call_i64_7"

///|
pub extern "c" fn mbt_native_call_i64_8(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
  a4 : Int64,
  a5 : Int64,
  a6 : Int64,
  a7 : Int64,
) -> Int64 = "mbt_native_call_i64_8"

///|
pub extern "c" fn mbt_native_call_f64_0(addr : Int64) -> Double = "mbt_native_call_f64_0"

///|
pub extern "c" fn mbt_native_call_f64_1(addr : Int64, d0 : Double) -> Double = "mbt_native_call_f64_1"

///|
pub extern "c" fn mbt_native_call_f64_2(
  addr : Int64,
  d0 : Double,
  d1 : Double,
) -> Double = "mbt_native_call_f64_2"

///|
pub extern "c" fn mbt_native_call_f64_3(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
) -> Double = "mbt_native_call_f64_3"

///|
pub extern "c" fn mbt_native_call_f64_4(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
) -> Double = "mbt_native_call_f64_4"

///|
pub extern "c" fn mbt_native_call_f64_5(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
  d4 : Double,
) -> Double = "mbt_native_call_f64_5"

///|
pub extern "c" fn mbt_native_call_f64_6(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
  d4 : Double,
  d5 : Double,
) -> Double = "mbt_native_call_f64_6"

///|
pub extern "c" fn mbt_native_call_f64_7(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
  d4 : Double,
  d5 : Double,
  d6 : Double,
) -> Double = "mbt_native_call_f64_7"

///|
pub extern "c" fn mbt_native_call_f64_8(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
  d4 : Double,
  d5 : Double,
  d6 : Double,
  d7 : Double,
) -> Double = "mbt_native_call_f64_8"
