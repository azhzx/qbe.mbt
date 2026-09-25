///|
// C ABI for the programmatic QBE IL builder.
//
// Every function is exported with a stable `qbe_*` symbol (see
// `include/qbe_builder.h`). Handles are plain integers: a builder handle is a
// 1-based index into the process-wide registry; function/block ids and value
// handles are exactly the `ir_builder` handles. `-1` is the "none" value.

///|
// Process-wide builder registry. A slot is `None` after `qbe_builder_free`.
let builders : Array[@ir_builder.Builder?] = []

///|
// Last error message (UTF-8), set by the emit functions.
let last_error : Array[String] = [""]

///|
fn set_error(msg : String) -> Unit {
  last_error[0] = msg
}

///|
fn get_builder(h : Int64) -> @ir_builder.Builder {
  let i = h.to_int() - 1
  if i < 0 || i >= builders.length() {
    abort("qbe: invalid builder handle")
  }
  match builders[i] {
    Some(b) => b
    None => abort("qbe: released builder handle")
  }
}

///|
// Decode a UTF-8 byte string passed from C.
fn bytes_to_string(b : Bytes) -> String {
  @utf8.decode_lossy(b)
}

///|
// Read a little-endian int32 from a byte buffer.
fn read_i32(b : Bytes, off : Int) -> Int {
  b[off].to_int() |
  (b[off + 1].to_int() << 8) |
  (b[off + 2].to_int() << 16) |
  (b[off + 3].to_int() << 24)
}

///|
// Decode a little-endian int32 array from a byte buffer. Value handles are
// small non-negative indices, so no sign extension is needed.
fn read_i32_array(b : Bytes) -> Array[Int] {
  let n = b.length() / 4
  let a : Array[Int] = []
  for i in 0..<n {
    a.push(read_i32(b, i * 4))
  }
  a
}

///|
#export_name("qbe_builder_new")
pub fn qbe_builder_new() -> Int64 {
  builders.push(Some(@ir_builder.Builder::new()))
  builders.length().to_int64()
}

///|
#export_name("qbe_builder_free")
pub fn qbe_builder_free(h : Int64) -> Unit {
  let i = h.to_int() - 1
  if i >= 0 && i < builders.length() {
    builders[i] = None
  }
}

///|
#export_name("qbe_last_error")
pub fn qbe_last_error() -> Bytes {
  @utf8.encode(last_error[0])
}

///|
// Define a function. `params` is a little-endian array of int32 class codes
// (0=w, 1=l, 2=s, 3=d). `ret_cls` uses the same codes; anything else is void.
#export_name("qbe_add_func")
pub fn qbe_add_func(
  h : Int64,
  name : Bytes,
  ret_cls : Int,
  is_export : Int,
  params : Bytes,
) -> Int {
  let b = get_builder(h)
  let n = params.length() / 4
  let ps : Array[@types.Class] = []
  for i in 0..<n {
    ps.push(@types.Class::from_code(read_i32(params, i * 4)))
  }
  b.add_func(
    bytes_to_string(name),
    @ir_builder.Ret::from_code(ret_cls),
    ps,
    is_export != 0,
  )
}

///|
#export_name("qbe_func_param")
pub fn qbe_func_param(h : Int64, fid : Int, i : Int) -> Int {
  get_builder(h).param(fid, i)
}

///|
// The entry block id of a function.
#export_name("qbe_entry_block")
pub fn qbe_entry_block(h : Int64, fid : Int) -> Int {
  get_builder(h).entry_block(fid)
}

///|
#export_name("qbe_add_block")
pub fn qbe_add_block(h : Int64, fid : Int, label : Bytes) -> Int {
  get_builder(h).add_block(fid, bytes_to_string(label))
}

///|
#export_name("qbe_switch_to")
pub fn qbe_switch_to(h : Int64, fid : Int, bid : Int) -> Unit {
  get_builder(h).switch_to(fid, bid)
}

///|
#export_name("qbe_block_param")
pub fn qbe_block_param(h : Int64, fid : Int, bid : Int, cls : Int) -> Int {
  get_builder(h).block_param(fid, bid, @types.Class::from_code(cls))
}

///|
#export_name("qbe_const_int")
pub fn qbe_const_int(h : Int64, fid : Int, v : Int64) -> Int {
  get_builder(h).iconst(fid, v)
}

///|
#export_name("qbe_const_double")
pub fn qbe_const_double(h : Int64, fid : Int, v : Double) -> Int {
  get_builder(h).fconst(fid, v)
}

///|
#export_name("qbe_const_single")
pub fn qbe_const_single(h : Int64, fid : Int, v : Float) -> Int {
  get_builder(h).sconst(fid, v)
}

///|
#export_name("qbe_global")
pub fn qbe_global(h : Int64, fid : Int, name : Bytes) -> Int {
  get_builder(h).global(fid, bytes_to_string(name))
}

///|
// Generic instruction: `to =<cls> <op> a1, a2`. Pass `res_cls = -1` for a void
// instruction. `op` is the textual QBE opcode (e.g. "add", "loadw", "ceqw").
#export_name("qbe_emit")
pub fn qbe_emit(
  h : Int64,
  fid : Int,
  op : Bytes,
  cls : Int,
  res_cls : Int,
  a1 : Int,
  a2 : Int,
) -> Int {
  let b = get_builder(h)
  b.emit_ins(
    fid,
    @types.Op::from_string(bytes_to_string(op)),
    @types.Class::from_code(cls),
    @types.Class::from_code(res_cls),
    a1,
    a2,
  )
}

///|
#export_name("qbe_emit_void")
pub fn qbe_emit_void(
  h : Int64,
  fid : Int,
  op : Bytes,
  cls : Int,
  a1 : Int,
  a2 : Int,
) -> Unit {
  let b = get_builder(h)
  b.emit_void(
    fid,
    @types.Op::from_string(bytes_to_string(op)),
    @types.Class::from_code(cls),
    a1,
    a2,
  )
}

///|
// Emit one call argument (an `Arg` instruction). Call this for each argument
// in order, then `qbe_call`.
#export_name("qbe_arg")
pub fn qbe_arg(h : Int64, fid : Int, cls : Int, val : Int) -> Unit {
  get_builder(h).emit_void(
    fid,
    @types.Arg,
    @types.Class::from_code(cls),
    val,
    -1,
  )
}

///|
// Emit a direct call to `callee`. Returns the result handle, or -1 for void.
#export_name("qbe_call")
pub fn qbe_call(h : Int64, fid : Int, callee : Bytes, ret_cls : Int) -> Int {
  get_builder(h).call(
    fid,
    bytes_to_string(callee),
    [],
    @ir_builder.Ret::from_code(ret_cls),
  )
}

///|
#export_name("qbe_ret")
pub fn qbe_ret(h : Int64, fid : Int, val : Int) -> Unit {
  get_builder(h).ret(fid, val)
}

///|
#export_name("qbe_jmp")
pub fn qbe_jmp(h : Int64, fid : Int, dest : Int) -> Unit {
  get_builder(h).jmp(fid, dest, [])
}

///|
#export_name("qbe_jmp1")
pub fn qbe_jmp1(h : Int64, fid : Int, dest : Int, a0 : Int) -> Unit {
  get_builder(h).jmp(fid, dest, [a0])
}

///|
#export_name("qbe_jmp2")
pub fn qbe_jmp2(h : Int64, fid : Int, dest : Int, a0 : Int, a1 : Int) -> Unit {
  get_builder(h).jmp(fid, dest, [a0, a1])
}

///|
#export_name("qbe_jmp3")
pub fn qbe_jmp3(
  h : Int64,
  fid : Int,
  dest : Int,
  a0 : Int,
  a1 : Int,
  a2 : Int,
) -> Unit {
  get_builder(h).jmp(fid, dest, [a0, a1, a2])
}

///|
#export_name("qbe_jmp4")
pub fn qbe_jmp4(
  h : Int64,
  fid : Int,
  dest : Int,
  a0 : Int,
  a1 : Int,
  a2 : Int,
  a3 : Int,
) -> Unit {
  get_builder(h).jmp(fid, dest, [a0, a1, a2, a3])
}

///|
#export_name("qbe_jnz")
pub fn qbe_jnz(
  h : Int64,
  fid : Int,
  cond : Int,
  then_blk : Int,
  else_blk : Int,
) -> Unit {
  get_builder(h).jnz(fid, cond, then_blk, [], else_blk, [])
}

///|
#export_name("qbe_jnz1")
pub fn qbe_jnz1(
  h : Int64,
  fid : Int,
  cond : Int,
  then_blk : Int,
  then_arg : Int,
  else_blk : Int,
  else_arg : Int,
) -> Unit {
  get_builder(h).jnz(fid, cond, then_blk, [then_arg], else_blk, [else_arg])
}

///|
// Unconditional branch with an arbitrary number of block-parameter arguments,
// passed as a little-endian int32 array.
#export_name("qbe_jmp_n")
pub fn qbe_jmp_n(h : Int64, fid : Int, dest : Int, args : Bytes) -> Unit {
  get_builder(h).jmp(fid, dest, read_i32_array(args))
}

///|
// Conditional branch with arbitrary per-edge block-parameter arguments.
#export_name("qbe_jnz_n")
pub fn qbe_jnz_n(
  h : Int64,
  fid : Int,
  cond : Int,
  then_blk : Int,
  then_args : Bytes,
  else_blk : Int,
  else_args : Bytes,
) -> Unit {
  get_builder(h).jnz(
    fid,
    cond,
    then_blk,
    read_i32_array(then_args),
    else_blk,
    read_i32_array(else_args),
  )
}

///|
#export_name("qbe_data_string")
pub fn qbe_data_string(
  h : Int64,
  name : Bytes,
  is_export : Int,
  s : Bytes,
) -> Unit {
  get_builder(h).data_string(
    bytes_to_string(name),
    is_export != 0,
    bytes_to_string(s),
  )
}

///|
#export_name("qbe_data_bytes")
pub fn qbe_data_bytes(
  h : Int64,
  name : Bytes,
  is_export : Int,
  data : Bytes,
) -> Unit {
  get_builder(h).data_bytes(bytes_to_string(name), is_export != 0, data)
}

///|
// Serialize the constructed module to QBE IL text (UTF-8). The output is
// accepted by the textual parser.
#export_name("qbe_emit_il")
pub fn qbe_emit_il(h : Int64) -> Bytes {
  @utf8.encode(get_builder(h).emit_il())
}

///|
// Emit arm64 assembly text (UTF-8). Empty on failure; see `qbe_last_error`.
#export_name("qbe_emit_asm")
pub fn qbe_emit_asm(h : Int64) -> Bytes {
  let b = get_builder(h)
  let s = try b.emit_asm() catch {
    e => {
      set_error("\{e}")
      ""
    }
  } noraise {
    s => s
  }
  @utf8.encode(s)
}

///|
// Emit a self-contained Mach-O arm64 object. Empty on failure.
#export_name("qbe_emit_object")
pub fn qbe_emit_object(h : Int64) -> Bytes {
  let b = get_builder(h)
  try b.emit_object() catch {
    e => {
      set_error("\{e}")
      @utf8.encode("")
    }
  } noraise {
    bytes => bytes
  }
}

///|
// Enable (1) or disable (0) DWARF debug info for this builder's assembly.
#export_name("qbe_dbg_enable")
pub fn qbe_dbg_enable(on : Int) -> Unit {
  @util.set_debug_info(on != 0)
}

///|
// Set the compilation-unit name and directory used by debug info.
#export_name("qbe_dbg_compile_unit")
pub fn qbe_dbg_compile_unit(h : Int64, name : Bytes, dir : Bytes) -> Unit {
  get_builder(h).set_dbg_compile_unit(
    bytes_to_string(name),
    bytes_to_string(dir),
  )
}

///|
// Declare a debug variable bound to a value handle.
//
// `ty` is 0=w, 1=l, 2=s, 3=d, 4=pointer, 5=aggregate (named by `type_name`,
// sized by `size`).
#export_name("qbe_dbg_var")
pub fn qbe_dbg_var(
  h : Int64,
  fid : Int,
  name : Bytes,
  ty : Int,
  type_name : Bytes,
  size : Int,
  val : Int,
) -> Unit {
  let t = match ty {
    0 => @types.DbgW
    1 => @types.DbgL
    2 => @types.DbgS
    3 => @types.DbgD
    4 => @types.DbgPtr
    _ => @types.DbgAgg(bytes_to_string(type_name), size)
  }
  get_builder(h).dbg_var(fid, bytes_to_string(name), t, val)
}

///|
// Attach a source location (a `dbgloc` instruction) at the current point.
#export_name("qbe_dbg_loc")
pub fn qbe_dbg_loc(h : Int64, fid : Int, line : Int, col : Int) -> Unit {
  get_builder(h).dbg_loc(fid, line, col)
}

///|
// Emit arm64 assembly text for a gas flavor ("e" ELF, "m" Mach-O).
#export_name("qbe_emit_asm_gas")
pub fn qbe_emit_asm_gas(h : Int64, gas : Bytes) -> Bytes {
  let b = get_builder(h)
  let s = try b.emit_asm(gas=bytes_to_string(gas)) catch {
    e => {
      set_error("\{e}")
      ""
    }
  } noraise {
    s => s
  }
  @utf8.encode(s)
}
