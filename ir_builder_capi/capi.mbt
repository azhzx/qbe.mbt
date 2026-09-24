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
