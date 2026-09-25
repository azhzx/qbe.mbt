///|
// Programmatic QBE IL builder.
//
// A `Builder` accumulates functions, data and types and produces exactly the
// same in-memory IR that the textual parser produces (`@types.Fn`,
// `@types.Blk`, `@types.Ins`, ...). That IR is then handed to the compiler
// through `@qbe.compile_ir_object` / `@qbe.compile_ir_asm`, so callers never
// have to render or re-parse `.ssa` text.
//
// Handles are plain `Int`s: a function, block or value handle is an index into a
// table owned by the builder. `-1` is the "none" value.

///|
// Return classification of a function (matches QBE's `rcls`).
pub(all) enum Ret {
  Void
  Word
  Long
  Single
  Double
} derive(Eq, Debug)

///|
// The IR class corresponding to a return kind (`Kx` for void).
pub fn Ret::cls(self : Ret) -> @types.Class {
  match self {
    Void => @types.Kx
    Word => @types.Kw
    Long => @types.Kl
    Single => @types.Ks
    Double => @types.Kd
  }
}

///|
// The return jump kind (`jmp.kind`) corresponding to a return kind.
pub fn Ret::jump_kind(self : Ret) -> @types.JumpKind {
  match self {
    Void => @types.Jret0
    Word => @types.Jretw
    Long => @types.Jretl
    Single => @types.Jrets
    Double => @types.Jretd
  }
}

///|
// Map a class code (0=w, 1=l, 2=s, 3=d, anything else=void) to a return kind.
pub fn Ret::from_code(c : Int) -> Ret {
  match c {
    0 => Word
    1 => Long
    2 => Single
    3 => Double
    _ => Void
  }
}

///|
// A branch edge whose block-parameter arguments are bound lazily (so that a
// target block's params may be declared after the branch that feeds them,
// matching the textual parser's phi syntax).
priv struct PendingEdge {
  fid : Int
  pred : Int
  dest : Int
  args : Array[Int]
}

///|
// A programmatic module builder.
pub struct Builder {
  funcs : Array[@types.Fn]
  datas : Array[@types.Dat]
  typs : Array[@types.Typ]
  interner : @util.Interner
  // Value handle table (all functions): handle -> Ref.
  vals : Array[@types.Ref]
  // Function id -> currently selected block id.
  cur : Array[Int]
  // Function id -> return kind.
  rets : Array[Ret]
  // Function id -> parameter value handles.
  params : Array[Array[Int]]
  // Interleaved "f"/"d" definition order for the text emitter.
  order : Array[String]
  // Branch edges awaiting phi-argument binding (see `finalize`).
  priv pending : Array[PendingEdge]
}

///|
// Create an empty builder with the arm64 target selected.
pub fn Builder::new() -> Builder {
  @types.init_arm64_target()
  {
    funcs: [],
    datas: [],
    typs: [],
    interner: @util.Interner::new(),
    vals: [],
    cur: [],
    rets: [],
    params: [],
    order: [],
    pending: [],
  }
}

///|
// Append a value to the handle table and return its handle.
fn Builder::push_ref(self : Builder, r : @types.Ref) -> Int {
  self.vals.push(r)
  self.vals.length() - 1
}

///|
// Resolve a value handle to an IR reference (`-1` -> `Ref::none()`).
pub fn Builder::val_ref(self : Builder, v : Int) -> @types.Ref {
  if v < 0 {
    @types.Ref::none()
  } else {
    self.vals[v]
  }
}

///|
// Intern a global symbol name and return its id.
pub fn Builder::symbol(self : Builder, name : String) -> Int {
  self.interner.intern(name)
}

///|
// Define a function. The entry block is named `start` and receives one `Par`
// instruction per class in `params`. Returns the function id.
pub fn Builder::add_func(
  self : Builder,
  name : String,
  ret : Ret,
  params : Array[@types.Class],
  is_export : Bool,
) -> Int {
  let f = @types.Fn::new(name)
  f.is_export = is_export
  f.init_regs()
  let _ = f.get_con(0L)
  self.funcs.push(f)
  let fid = self.funcs.length() - 1
  self.cur.push(-1)
  self.rets.push(ret)
  self.params.push([])
  self.order.push("f")
  let start = f.add_blk("start")
  f.def_order.push(start)
  f.start_id = start
  self.cur[fid] = start
  for c in params {
    let _ = self.add_param(fid, c)
  }
  fid
}

///|
// Add one parameter (a fresh temp plus a `Par` instruction) to a function's
// entry block. Returns the parameter's value handle.
pub fn Builder::add_param(self : Builder, fid : Int, cls : @types.Class) -> Int {
  let f = self.funcs[fid]
  let bid = self.cur[fid]
  let t = f.new_tmp("p", cls)
  let r = @types.Ref::tmp(t)
  f.blks[bid].ins.push(
    @types.Ins::new(@types.Par, cls, r, @types.Ref::none(), @types.Ref::none()),
  )
  let h = self.push_ref(r)
  self.params[fid].push(h)
  h
}

///|
// Value handle of parameter `i` of function `fid`.
pub fn Builder::param(self : Builder, fid : Int, i : Int) -> Int {
  self.params[fid][i]
}

///|
// Value handles of every parameter of function `fid`.
pub fn Builder::func_params(self : Builder, fid : Int) -> Array[Int] {
  self.params[fid]
}

///|
// Define a new basic block. Returns its block id.
pub fn Builder::add_block(self : Builder, fid : Int, label : String) -> Int {
  let f = self.funcs[fid]
  let b = f.add_blk(label)
  f.def_order.push(b)
  b
}

///|
// Make `bid` the block that subsequent instructions are appended to.
pub fn Builder::switch_to(self : Builder, fid : Int, bid : Int) -> Unit {
  self.cur[fid] = bid
}

///|
// The currently selected block of a function.
pub fn Builder::current_block(self : Builder, fid : Int) -> Int {
  self.cur[fid]
}

///|
// The entry block id of a function.
pub fn Builder::entry_block(self : Builder, fid : Int) -> Int {
  self.funcs[fid].start_id
}

///|
// Declare a block parameter (a phi node at the top of `bid`). Returns its
// value handle; predecessors pass an argument for it via the jump helpers.
pub fn Builder::block_param(
  self : Builder,
  fid : Int,
  bid : Int,
  cls : @types.Class,
) -> Int {
  let f = self.funcs[fid]
  let t = f.new_tmp("b", cls)
  let r = @types.Ref::tmp(t)
  f.blks[bid].phi.push(@types.Phi::new(r, cls))
  self.push_ref(r)
}

///|
// Integer constant.
pub fn Builder::iconst(self : Builder, fid : Int, v : Int64) -> Int {
  let f = self.funcs[fid]
  self.push_ref(@types.Ref::con(f.get_con(v)))
}

///|
// Double (`d`) constant.
pub fn Builder::fconst(self : Builder, fid : Int, v : Double) -> Int {
  let f = self.funcs[fid]
  self.push_ref(@types.Ref::con(f.get_con_by(@types.Con::double(v))))
}

///|
// Single (`s`) constant.
pub fn Builder::sconst(self : Builder, fid : Int, v : Float) -> Int {
  let f = self.funcs[fid]
  self.push_ref(@types.Ref::con(f.get_con_by(@types.Con::single(v))))
}

///|
// Address-of-global constant.
pub fn Builder::global(self : Builder, fid : Int, name : String) -> Int {
  let f = self.funcs[fid]
  let g = self.interner.intern(name)
  self.push_ref(@types.Ref::con(f.get_con_by(@types.Con::addr(g))))
}

///|
// Generic instruction emitter: `to =cls op arg1, arg2`. When `res` is
// `Kx` the instruction has no destination (use `emit_void` for that).
pub fn Builder::emit_ins(
  self : Builder,
  fid : Int,
  op : @types.Op,
  cls : @types.Class,
  res : @types.Class,
  a1 : Int,
  a2 : Int,
) -> Int {
  let f = self.funcs[fid]
  let bid = self.cur[fid]
  let to = if res == @types.Kx {
    @types.Ref::none()
  } else {
    @types.Ref::tmp(f.new_tmp("t", res))
  }
  f.blks[bid].ins.push(
    @types.Ins::new(op, cls, to, self.val_ref(a1), self.val_ref(a2)),
  )
  if res == @types.Kx {
    -1
  } else {
    self.push_ref(to)
  }
}

///|
// Generic void instruction emitter (stores, calls to void, vastart, ...).
pub fn Builder::emit_void(
  self : Builder,
  fid : Int,
  op : @types.Op,
  cls : @types.Class,
  a1 : Int,
  a2 : Int,
) -> Unit {
  let f = self.funcs[fid]
  let bid = self.cur[fid]
  f.blks[bid].ins.push(
    @types.Ins::new_void(op, cls, self.val_ref(a1), self.val_ref(a2)),
  )
}

///|
// Binary arithmetic / bitwise operation with the same operand and result class.
pub fn Builder::arith(
  self : Builder,
  fid : Int,
  op : @types.Op,
  cls : @types.Class,
  a : Int,
  b : Int,
) -> Int {
  self.emit_ins(fid, op, cls, cls, a, b)
}

///|
// Comparison producing a word (`w`) result.
pub fn Builder::cmp(
  self : Builder,
  fid : Int,
  op : @types.Op,
  cls : @types.Class,
  a : Int,
  b : Int,
) -> Int {
  self.emit_ins(fid, op, cls, @types.Kw, a, b)
}

///|
// Unary operation (extensions, truncations, casts) whose result class differs.
pub fn Builder::unop(
  self : Builder,
  fid : Int,
  op : @types.Op,
  cls : @types.Class,
  res : @types.Class,
  a : Int,
) -> Int {
  self.emit_ins(fid, op, cls, res, a, -1)
}

///|
// Load: `%t =res op addr`.
pub fn Builder::load(
  self : Builder,
  fid : Int,
  op : @types.Op,
  res : @types.Class,
  addr : Int,
) -> Int {
  self.emit_ins(fid, op, res, res, addr, -1)
}

///|
// Store: `op val, addr` with the store class `cls`.
pub fn Builder::store(
  self : Builder,
  fid : Int,
  op : @types.Op,
  cls : @types.Class,
  val : Int,
  addr : Int,
) -> Unit {
  self.emit_void(fid, op, cls, val, addr)
}

///|
// Direct call. Emits one `Arg` instruction per argument followed by the
// `call`. Returns the result handle, or `-1` for a void call.
pub fn Builder::call(
  self : Builder,
  fid : Int,
  callee : String,
  args : Array[(@types.Class, Int)],
  ret : Ret,
) -> Int {
  let f = self.funcs[fid]
  let bid = self.cur[fid]
  f.leaf = false
  let g = self.interner.intern(callee)
  let callee_ref = @types.Ref::con(f.get_con_by(@types.Con::addr(g)))
  for a in args {
    f.blks[bid].ins.push(
      @types.Ins::new(
        @types.Arg,
        a.0,
        @types.Ref::none(),
        self.val_ref(a.1),
        @types.Ref::none(),
      ),
    )
  }
  let ret_cls = ret.cls()
  let to = if ret_cls == @types.Kx {
    @types.Ref::none()
  } else {
    @types.Ref::tmp(f.new_tmp("t", ret_cls))
  }
  let call_cls = if ret_cls == @types.Kx { @types.Kw } else { ret_cls }
  f.blks[bid].ins.push(
    @types.Ins::new(@types.Call, call_cls, to, callee_ref, @types.Ref::none()),
  )
  if ret_cls == @types.Kx {
    -1
  } else {
    self.push_ref(to)
  }
}

///|
// Record a branch edge. Block-parameter arguments are bound in `finalize`
// so a block's params may be declared before or after the branches into it.
fn Builder::add_edge(
  self : Builder,
  fid : Int,
  pred : Int,
  dest : Int,
  args : Array[Int],
) -> Unit {
  self.pending.push(PendingEdge::{ fid, pred, dest, args, })
}

///|
// Bind every pending branch edge to its target block's phi nodes. Called once
// before emitting, so repeated emit calls are not supported on the same IR.
fn Builder::finalize(self : Builder) -> Unit {
  for e in self.pending {
    let phis = self.funcs[e.fid].blks[e.dest].phi
    for i in 0..<phis.length() {
      let v = if i < e.args.length() {
        self.val_ref(e.args[i])
      } else {
        @types.Ref::none()
      }
      phis[i].args.push(@types.PhiArg::{ value: v, blk_id: e.pred, })
    }
  }
  self.pending.clear()
}

///|
// Unconditional branch, optionally passing block-parameter arguments.
pub fn Builder::jmp(
  self : Builder,
  fid : Int,
  dest : Int,
  args : Array[Int],
) -> Unit {
  let bid = self.cur[fid]
  self.funcs[fid].blks[bid].jmp = @types.Jump::full(
    @types.Jjmp,
    @types.Ref::none(),
    dest,
    -1,
  )
  self.add_edge(fid, bid, dest, args)
}

///|
// Conditional branch on a non-zero word, with per-edge block-parameter args.
pub fn Builder::jnz(
  self : Builder,
  fid : Int,
  cond : Int,
  then_blk : Int,
  then_args : Array[Int],
  else_blk : Int,
  else_args : Array[Int],
) -> Unit {
  let bid = self.cur[fid]
  self.funcs[fid].blks[bid].jmp = @types.Jump::full(
    @types.Jjnz,
    self.val_ref(cond),
    then_blk,
    else_blk,
  )
  self.add_edge(fid, bid, then_blk, then_args)
  self.add_edge(fid, bid, else_blk, else_args)
}

///|
// Return (value handle `-1` for void).
pub fn Builder::ret(self : Builder, fid : Int, v : Int) -> Unit {
  let bid = self.cur[fid]
  let jk = self.rets[fid].jump_kind()
  self.funcs[fid].blks[bid].jmp = @types.Jump::full(jk, self.val_ref(v), -1, -1)
}

///|
// Append a data section holding the given bytes as `b` items.
pub fn Builder::data_bytes(
  self : Builder,
  name : String,
  is_export : Bool,
  bytes : Bytes,
) -> Unit {
  let start = @types.Dat::start()
  start.is_export = is_export
  self.datas.push(start)
  self.datas.push(@types.Dat::name(name, is_export))
  for i in 0..<bytes.length() {
    self.datas.push(@types.Dat::byte(bytes[i].to_int().to_int64()))
  }
  self.datas.push(@types.Dat::end())
  self.order.push("d")
}

///|
// Append a data section holding a string as a single `b "<str>"` item.
pub fn Builder::data_string(
  self : Builder,
  name : String,
  is_export : Bool,
  s : String,
) -> Unit {
  let start = @types.Dat::start()
  start.is_export = is_export
  self.datas.push(start)
  self.datas.push(@types.Dat::name(name, is_export))
  self.datas.push(@types.Dat::string(s))
  self.datas.push(@types.Dat::end())
  self.order.push("d")
}

///|
// Append a data section holding a pointer to another global.
pub fn Builder::data_ref(
  self : Builder,
  name : String,
  is_export : Bool,
  target : String,
  offset : Int64,
) -> Unit {
  let start = @types.Dat::start()
  start.is_export = is_export
  self.datas.push(start)
  self.datas.push(@types.Dat::name(name, is_export))
  self.datas.push(@types.Dat::ref_to(target, offset))
  self.datas.push(@types.Dat::end())
  self.order.push("d")
}

///|
// The raw IR functions (for advanced use and tests).
pub fn Builder::functions(self : Builder) -> Array[@types.Fn] {
  self.funcs
}

///|
// The raw data items.
pub fn Builder::data_items(self : Builder) -> Array[@types.Dat] {
  self.datas
}

///|
// The interner that owns every symbol referenced by the module.
pub fn Builder::interner_ref(self : Builder) -> @util.Interner {
  self.interner
}

///|
// Emit arm64 assembly text (self-contained, no assembler needed).
pub fn Builder::emit_asm(self : Builder, gas? : String = "e") -> String raise {
  self.finalize()
  @qbe.compile_ir_asm(
    self.funcs,
    self.datas,
    self.order,
    self.typs,
    self.interner,
    gas~,
  )
}

///|
// Emit a self-contained Mach-O arm64 object.
pub fn Builder::emit_object(self : Builder) -> Bytes raise {
  self.finalize()
  @qbe.compile_ir_object(self.funcs, self.datas, self.typs, self.interner)
}

///|
// Compile to a linked, self-contained arm64 image (Route B) for in-memory
// execution via `azhzx/qbe/run_asm`.
pub fn Builder::emit_bin_module(self : Builder) -> @qbe.Arm64BinModule raise {
  self.finalize()
  @qbe.compile_ir_bin_module(self.funcs, self.datas, self.typs, self.interner)
}
