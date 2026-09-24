///|
// Raw FFI to the native JIT shim (jit_stub.c).
//
// Addresses cross the boundary as Int64 (pointer-sized) so relocation
// arithmetic can stay in MoonBit.

///|
extern "c" fn mbt_jit_alloc(size : Int) -> Int64 = "mbt_jit_alloc"

///|
extern "c" fn mbt_jit_protect(addr : Int64, size : Int) -> Int = "mbt_jit_protect"

///|
extern "c" fn mbt_jit_free(addr : Int64, size : Int) = "mbt_jit_free"

///|
#borrow(data)
extern "c" fn mbt_jit_write_bytes(addr : Int64, off : Int, data : Bytes) = "mbt_jit_write_bytes"

///|
extern "c" fn mbt_jit_write_u32(addr : Int64, off : Int, word : UInt) = "mbt_jit_write_u32"

///|
#borrow(suffix)
extern "c" fn mbt_jit_temp(suffix : Bytes) -> Bytes = "mbt_jit_temp"

///|
#borrow(path, data)
extern "c" fn mbt_jit_write_file(path : Bytes, data : Bytes) -> Int = "mbt_jit_write_file"

///|
#borrow(path)
extern "c" fn mbt_jit_read_file(path : Bytes) -> Bytes = "mbt_jit_read_file"

///|
#borrow(path)
extern "c" fn mbt_jit_unlink(path : Bytes) -> Int = "mbt_jit_unlink"

///|
#borrow(cmd)
extern "c" fn mbt_jit_run(cmd : Bytes) -> Int = "mbt_jit_run"

///|
#borrow(path)
extern "c" fn mbt_jit_dlopen(path : Bytes) -> Int64 = "mbt_jit_dlopen"

///|
#borrow(name)
extern "c" fn mbt_jit_dlsym(handle : Int64, name : Bytes) -> Int64 = "mbt_jit_dlsym"

///|
#borrow(name)
extern "c" fn mbt_jit_sym(name : Bytes) -> Int64 = "mbt_jit_sym"

///|
extern "c" fn mbt_jit_call_i64_1(addr : Int64, a0 : Int64) -> Int64 = "mbt_jit_call_i64_1"
