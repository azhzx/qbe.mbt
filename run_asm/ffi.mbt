///|
// Raw FFI to the native run-asm shim (run_asm_stub.c).
//
// Addresses cross the boundary as Int64 (pointer-sized) so relocation
// arithmetic can stay in MoonBit.

///|
// 1 on macOS/aarch64, the only host this backend targets.
extern "c" fn mbt_run_asm_host_supported() -> Int = "mbt_run_asm_host_supported"

///|
extern "c" fn mbt_run_asm_alloc(size : Int) -> Int64 = "mbt_run_asm_alloc"

///|
extern "c" fn mbt_run_asm_protect(addr : Int64, size : Int) -> Int = "mbt_run_asm_protect"

///|
extern "c" fn mbt_run_asm_free(addr : Int64, size : Int) = "mbt_run_asm_free"

///|
#borrow(data)
extern "c" fn mbt_run_asm_write_bytes(addr : Int64, off : Int, data : Bytes) = "mbt_run_asm_write_bytes"

///|
extern "c" fn mbt_run_asm_write_u32(addr : Int64, off : Int, word : UInt) = "mbt_run_asm_write_u32"

///|
#borrow(suffix)
extern "c" fn mbt_run_asm_temp(suffix : Bytes) -> Bytes = "mbt_run_asm_temp"

///|
#borrow(path, data)
extern "c" fn mbt_run_asm_write_file(path : Bytes, data : Bytes) -> Int = "mbt_run_asm_write_file"

///|
#borrow(path)
extern "c" fn mbt_run_asm_read_file(path : Bytes) -> Bytes = "mbt_run_asm_read_file"

///|
#borrow(path)
extern "c" fn mbt_run_asm_unlink(path : Bytes) -> Int = "mbt_run_asm_unlink"

///|
#borrow(cmd)
extern "c" fn mbt_run_asm_run(cmd : Bytes) -> Int = "mbt_run_asm_run"

///|
#borrow(cmd)
extern "c" fn mbt_run_asm_capture(cmd : Bytes) -> Bytes = "mbt_run_asm_capture"

///|
#borrow(path)
extern "c" fn mbt_run_asm_dlopen(path : Bytes) -> Int64 = "mbt_run_asm_dlopen"

///|
#borrow(name)
extern "c" fn mbt_run_asm_dlsym(handle : Int64, name : Bytes) -> Int64 = "mbt_run_asm_dlsym"

///|
#borrow(name)
extern "c" fn mbt_run_asm_sym(name : Bytes) -> Int64 = "mbt_run_asm_sym"

///|
extern "c" fn mbt_run_asm_call_i64_1(addr : Int64, a0 : Int64) -> Int64 = "mbt_run_asm_call_i64_1"

///|
extern "c" fn mbt_run_asm_icache_flush(addr : Int64, size : Int) = "mbt_run_asm_icache_flush"

///|
extern "c" fn mbt_run_asm_call_i64_0(addr : Int64) -> Int64 = "mbt_run_asm_call_i64_0"

///|
extern "c" fn mbt_run_asm_call_i64_2(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
) -> Int64 = "mbt_run_asm_call_i64_2"

///|
extern "c" fn mbt_run_asm_call_i64_3(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
) -> Int64 = "mbt_run_asm_call_i64_3"

///|
extern "c" fn mbt_run_asm_call_i64_4(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
) -> Int64 = "mbt_run_asm_call_i64_4"

///|
extern "c" fn mbt_run_asm_call_i64_5(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
  a4 : Int64,
) -> Int64 = "mbt_run_asm_call_i64_5"

///|
extern "c" fn mbt_run_asm_call_i64_6(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
  a4 : Int64,
  a5 : Int64,
) -> Int64 = "mbt_run_asm_call_i64_6"

///|
extern "c" fn mbt_run_asm_call_i64_7(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
  a4 : Int64,
  a5 : Int64,
  a6 : Int64,
) -> Int64 = "mbt_run_asm_call_i64_7"

///|
extern "c" fn mbt_run_asm_call_i64_8(
  addr : Int64,
  a0 : Int64,
  a1 : Int64,
  a2 : Int64,
  a3 : Int64,
  a4 : Int64,
  a5 : Int64,
  a6 : Int64,
  a7 : Int64,
) -> Int64 = "mbt_run_asm_call_i64_8"

///|
extern "c" fn mbt_run_asm_call_f64_0(addr : Int64) -> Double = "mbt_run_asm_call_f64_0"

///|
extern "c" fn mbt_run_asm_call_f64_1(addr : Int64, d0 : Double) -> Double = "mbt_run_asm_call_f64_1"

///|
extern "c" fn mbt_run_asm_call_f64_2(
  addr : Int64,
  d0 : Double,
  d1 : Double,
) -> Double = "mbt_run_asm_call_f64_2"

///|
extern "c" fn mbt_run_asm_call_f64_3(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
) -> Double = "mbt_run_asm_call_f64_3"

///|
extern "c" fn mbt_run_asm_call_f64_4(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
) -> Double = "mbt_run_asm_call_f64_4"

///|
extern "c" fn mbt_run_asm_call_f64_5(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
  d4 : Double,
) -> Double = "mbt_run_asm_call_f64_5"

///|
extern "c" fn mbt_run_asm_call_f64_6(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
  d4 : Double,
  d5 : Double,
) -> Double = "mbt_run_asm_call_f64_6"

///|
extern "c" fn mbt_run_asm_call_f64_7(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
  d4 : Double,
  d5 : Double,
  d6 : Double,
) -> Double = "mbt_run_asm_call_f64_7"

///|
extern "c" fn mbt_run_asm_call_f64_8(
  addr : Int64,
  d0 : Double,
  d1 : Double,
  d2 : Double,
  d3 : Double,
  d4 : Double,
  d5 : Double,
  d6 : Double,
  d7 : Double,
) -> Double = "mbt_run_asm_call_f64_8"
