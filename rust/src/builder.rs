//! Cranelift-style function and instruction builders.

use crate::ffi;
use crate::module::{FunctionId, Module};
use crate::types::{fcmp_op, icmp_op, FloatCC, IntCC, Type};

/// A basic block handle.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct BlockId(pub(crate) i32);

/// An SSA value handle, carrying its QBE class.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Value {
    pub(crate) id: i32,
    pub(crate) ty: Type,
}

impl Value {
    pub(crate) fn new(id: i32, ty: Type) -> Value {
        Value { id, ty }
    }
    pub fn ty(self) -> Type {
        self.ty
    }
    pub fn id(self) -> i32 {
        self.id
    }
}

#[derive(Default)]
struct BlockMeta {
    params: Vec<Value>,
}

/// Builds the body of one function. Borrows the module mutably.
pub struct FunctionBuilder<'m> {
    pub(crate) module: &'m mut Module,
    f: FunctionId,
    cur: BlockId,
    blocks: Vec<BlockMeta>,
}

impl<'m> FunctionBuilder<'m> {
    pub(crate) fn new(module: &'m mut Module, f: FunctionId) -> FunctionBuilder<'m> {
        let fid = module.funcs[f.0].fid;
        let entry = unsafe { ffi::qbe_entry_block(module.handle, fid) };
        let mut blocks = Vec::new();
        for _ in 0..=entry {
            blocks.push(BlockMeta::default());
        }
        blocks[entry as usize].params = module.funcs[f.0].params.clone();
        FunctionBuilder {
            module,
            f,
            cur: BlockId(entry),
            blocks,
        }
    }

    pub(crate) fn funcid(&self) -> ffi::Func {
        self.module.funcs[self.f.0].fid
    }

    pub(crate) fn handle(&self) -> ffi::Builder {
        self.module.handle
    }

    /// Declare a local variable bound to `value` (Cranelift-style value label).
    /// Debug info must be enabled on the module before emitting.
    pub fn declare_var(&mut self, name: &str, ty: crate::debug::DebugType, value: Value) {
        let f = self.f;
        self.module.dbg_var(f, name, ty, value);
    }

    /// Attach a source location at the current point.
    pub fn set_source_loc(&mut self, line: u32, col: u32) {
        let fid = self.module.funcs[self.f.0].fid;
        unsafe { ffi::qbe_dbg_loc(self.module.handle, fid, line as i32, col as i32) };
    }

    /// The function parameters as SSA values.
    pub fn params(&self) -> &[Value] {
        &self.module.funcs[self.f.0].params
    }

    /// The entry block.
    pub fn entry_block(&self) -> BlockId {
        BlockId(unsafe { ffi::qbe_entry_block(self.module.handle, self.funcid()) })
    }

    /// Create a new block.
    pub fn create_block(&mut self, label: &str) -> BlockId {
        let fid = self.funcid();
        let b = ffi::with_bytes(label.as_bytes(), |nb| unsafe {
            ffi::qbe_add_block(self.module.handle, fid, nb)
        });
        while self.blocks.len() <= b as usize {
            self.blocks.push(BlockMeta::default());
        }
        BlockId(b)
    }

    /// Select the block that subsequent instructions are appended to.
    pub fn switch_to_block(&mut self, b: BlockId) {
        let fid = self.funcid();
        unsafe { ffi::qbe_switch_to(self.module.handle, fid, b.0) };
        self.cur = b;
    }

    pub fn current_block(&self) -> BlockId {
        self.cur
    }

    /// Append a block parameter (phi) to the given block.
    pub fn append_block_param(&mut self, b: BlockId, ty: Type) -> Value {
        let fid = self.funcid();
        let id = unsafe { ffi::qbe_block_param(self.module.handle, fid, b.0, ty.code()) };
        let v = Value::new(id, ty);
        self.blocks[b.0 as usize].params.push(v);
        v
    }

    /// The block parameters (function parameters for the entry block).
    pub fn block_params(&self, b: BlockId) -> &[Value] {
        &self.blocks[b.0 as usize].params
    }

    /// No-op: QBE binds branch arguments lazily.
    pub fn seal_block(&mut self, _b: BlockId) {}

    /// No-op, for API parity with Cranelift.
    pub fn seal_all_blocks(&mut self) {}

    /// Instruction inserter (builder.ins().iadd(a, b)).
    pub fn ins(&mut self) -> InstructionInserter<'_, 'm> {
        InstructionInserter { fb: self }
    }
}

/// Emits instructions into a FunctionBuilder.
pub struct InstructionInserter<'b, 'm> {
    fb: &'b mut FunctionBuilder<'m>,
}

fn pack_vals(args: &[Value]) -> Vec<u8> {
    let mut v = Vec::with_capacity(args.len() * 4);
    for a in args {
        v.extend_from_slice(&a.id.to_le_bytes());
    }
    v
}

impl<'b, 'm> InstructionInserter<'b, 'm> {
    fn emit(
        &mut self,
        op: &str,
        cls: Type,
        res: Option<Type>,
        a1: Option<Value>,
        a2: Option<Value>,
    ) -> Option<Value> {
        let fid = self.fb.funcid();
        let handle = self.fb.handle();
        let a1 = a1.map(|v| v.id).unwrap_or(-1);
        let a2 = a2.map(|v| v.id).unwrap_or(-1);
        let id = ffi::with_bytes(op.as_bytes(), |ob| unsafe {
            ffi::qbe_emit(
                handle,
                fid,
                ob,
                cls.code(),
                res.map(Type::code).unwrap_or(ffi::QBE_VOID),
                a1,
                a2,
            )
        });
        res.map(|ty| Value::new(id, ty))
    }

    fn bin(&mut self, op: &str, a: Value, b: Value) -> Value {
        self.emit(op, a.ty, Some(a.ty), Some(a), Some(b)).unwrap()
    }

    /// Escape hatch: any QBE opcode with explicit classes.
    pub fn raw(
        &mut self,
        op: &str,
        cls: Type,
        res: Option<Type>,
        a1: Option<Value>,
        a2: Option<Value>,
    ) -> Option<Value> {
        self.emit(op, cls, res, a1, a2)
    }

    pub fn iconst(&mut self, ty: Type, v: i64) -> Value {
        let id = unsafe { ffi::qbe_const_int(self.fb.handle(), self.fb.funcid(), v) };
        Value::new(id, ty)
    }

    pub fn f32const(&mut self, v: f32) -> Value {
        let id = unsafe { ffi::qbe_const_single(self.fb.handle(), self.fb.funcid(), v) };
        Value::new(id, Type::F32)
    }

    pub fn f64const(&mut self, v: f64) -> Value {
        let id = unsafe { ffi::qbe_const_double(self.fb.handle(), self.fb.funcid(), v) };
        Value::new(id, Type::F64)
    }

    pub fn global(&mut self, name: &str) -> Value {
        let fid = self.fb.funcid();
        let handle = self.fb.handle();
        let id = ffi::with_bytes(name.as_bytes(), |nb| unsafe {
            ffi::qbe_global(handle, fid, nb)
        });
        Value::new(id, Type::I64)
    }

    // Integer ALU.
    pub fn iadd(&mut self, a: Value, b: Value) -> Value {
        self.bin("add", a, b)
    }
    pub fn isub(&mut self, a: Value, b: Value) -> Value {
        self.bin("sub", a, b)
    }
    pub fn imul(&mut self, a: Value, b: Value) -> Value {
        self.bin("mul", a, b)
    }
    pub fn sdiv(&mut self, a: Value, b: Value) -> Value {
        self.bin("div", a, b)
    }
    pub fn udiv(&mut self, a: Value, b: Value) -> Value {
        self.bin("udiv", a, b)
    }
    pub fn srem(&mut self, a: Value, b: Value) -> Value {
        self.bin("rem", a, b)
    }
    pub fn urem(&mut self, a: Value, b: Value) -> Value {
        self.bin("urem", a, b)
    }
    pub fn band(&mut self, a: Value, b: Value) -> Value {
        self.bin("and", a, b)
    }
    pub fn bor(&mut self, a: Value, b: Value) -> Value {
        self.bin("or", a, b)
    }
    pub fn bxor(&mut self, a: Value, b: Value) -> Value {
        self.bin("xor", a, b)
    }
    pub fn ishl(&mut self, a: Value, b: Value) -> Value {
        self.bin("shl", a, b)
    }
    pub fn ushr(&mut self, a: Value, b: Value) -> Value {
        self.bin("shr", a, b)
    }
    pub fn sshr(&mut self, a: Value, b: Value) -> Value {
        self.bin("sar", a, b)
    }

    // Floating point ALU.
    pub fn fadd(&mut self, a: Value, b: Value) -> Value {
        self.bin("add", a, b)
    }
    pub fn fsub(&mut self, a: Value, b: Value) -> Value {
        self.bin("sub", a, b)
    }
    pub fn fmul(&mut self, a: Value, b: Value) -> Value {
        self.bin("mul", a, b)
    }
    pub fn fdiv(&mut self, a: Value, b: Value) -> Value {
        self.bin("div", a, b)
    }

    /// Integer comparison producing an I32 boolean.
    pub fn icmp(&mut self, cc: IntCC, a: Value, b: Value) -> Value {
        let op = icmp_op(a.ty, cc);
        self.emit(op, a.ty, Some(Type::I32), Some(a), Some(b))
            .unwrap()
    }

    /// Floating-point comparison producing an I32 boolean.
    pub fn fcmp(&mut self, cc: FloatCC, a: Value, b: Value) -> Value {
        let op = fcmp_op(a.ty, cc);
        self.emit(op, a.ty, Some(Type::I32), Some(a), Some(b))
            .unwrap()
    }

    /// Load a value of type `ty` from `addr`.
    pub fn load(&mut self, ty: Type, addr: Value) -> Value {
        let op = match ty {
            Type::I32 => "loaduw",
            Type::I64 => "load",
            Type::F32 => "loads",
            Type::F64 => "loadd",
        };
        self.emit(op, ty, Some(ty), Some(addr), None).unwrap()
    }

    pub fn loadsb(&mut self, addr: Value) -> Value {
        self.emit("loadsb", Type::I32, Some(Type::I32), Some(addr), None)
            .unwrap()
    }
    pub fn loadub(&mut self, addr: Value) -> Value {
        self.emit("loadub", Type::I32, Some(Type::I32), Some(addr), None)
            .unwrap()
    }
    pub fn loadsh(&mut self, addr: Value) -> Value {
        self.emit("loadsh", Type::I32, Some(Type::I32), Some(addr), None)
            .unwrap()
    }
    pub fn loaduh(&mut self, addr: Value) -> Value {
        self.emit("loaduh", Type::I32, Some(Type::I32), Some(addr), None)
            .unwrap()
    }
    pub fn loadsw(&mut self, addr: Value) -> Value {
        self.emit("loadsw", Type::I32, Some(Type::I32), Some(addr), None)
            .unwrap()
    }

    /// Store a value; the width follows the value class.
    pub fn store(&mut self, addr: Value, val: Value) {
        let op = match val.ty {
            Type::I32 => "storew",
            Type::I64 => "storel",
            Type::F32 => "stores",
            Type::F64 => "stored",
        };
        self.emit(op, val.ty, None, Some(val), Some(addr));
    }

    /// Direct call to a declared function.
    pub fn call(&mut self, f: FunctionId, args: &[Value]) -> Option<Value> {
        let (name, ret) = {
            let meta = &self.fb.module.funcs[f.0];
            (meta.name.clone(), meta.sig.ret)
        };
        self.call_by_name(&name, ret, args)
    }

    /// Call an external or not-yet-declared symbol by name.
    pub fn call_by_name(
        &mut self,
        callee: &str,
        ret: Option<Type>,
        args: &[Value],
    ) -> Option<Value> {
        let fid = self.fb.funcid();
        let handle = self.fb.handle();
        for a in args {
            unsafe { ffi::qbe_arg(handle, fid, a.ty.code(), a.id) };
        }
        let id = ffi::with_bytes(callee.as_bytes(), |cb| unsafe {
            ffi::qbe_call(
                handle,
                fid,
                cb,
                ret.map(Type::code).unwrap_or(ffi::QBE_VOID),
            )
        });
        ret.map(|ty| Value::new(id, ty))
    }

    /// Return the first value (QBE has a single return value).
    pub fn return_(&mut self, vals: &[Value]) {
        let fid = self.fb.funcid();
        let handle = self.fb.handle();
        let v = vals.first().map(|v| v.id).unwrap_or(-1);
        unsafe { ffi::qbe_ret(handle, fid, v) };
    }

    pub fn return_void(&mut self) {
        self.return_(&[]);
    }

    /// Unconditional jump, passing block-parameter arguments.
    pub fn jump(&mut self, dest: BlockId, args: &[Value]) {
        let fid = self.fb.funcid();
        let handle = self.fb.handle();
        let packed = pack_vals(args);
        ffi::with_bytes(&packed, |ab| unsafe {
            ffi::qbe_jmp_n(handle, fid, dest.0, ab)
        });
    }

    /// Conditional branch.
    pub fn brif(
        &mut self,
        cond: Value,
        then_blk: BlockId,
        then_args: &[Value],
        else_blk: BlockId,
        else_args: &[Value],
    ) {
        let fid = self.fb.funcid();
        let handle = self.fb.handle();
        let ta = pack_vals(then_args);
        let ea = pack_vals(else_args);
        ffi::with_bytes(&ta, |tb| {
            ffi::with_bytes(&ea, |eb| unsafe {
                ffi::qbe_jnz_n(handle, fid, cond.id, then_blk.0, tb, else_blk.0, eb)
            })
        });
    }

    // Extensions and conversions.
    pub fn extend_u8(&mut self, a: Value, to: Type) -> Value {
        self.emit("extub", to, Some(to), Some(a), None).unwrap()
    }
    pub fn extend_s8(&mut self, a: Value, to: Type) -> Value {
        self.emit("extsb", to, Some(to), Some(a), None).unwrap()
    }
    pub fn extend_u16(&mut self, a: Value, to: Type) -> Value {
        self.emit("extuh", to, Some(to), Some(a), None).unwrap()
    }
    pub fn extend_s16(&mut self, a: Value, to: Type) -> Value {
        self.emit("extsh", to, Some(to), Some(a), None).unwrap()
    }
    pub fn extend_u32(&mut self, a: Value) -> Value {
        self.emit("extuw", Type::I64, Some(Type::I64), Some(a), None)
            .unwrap()
    }
    pub fn extend_s32(&mut self, a: Value) -> Value {
        self.emit("extsw", Type::I64, Some(Type::I64), Some(a), None)
            .unwrap()
    }
    pub fn promote_f32(&mut self, a: Value) -> Value {
        self.emit("exts", Type::F64, Some(Type::F64), Some(a), None)
            .unwrap()
    }
    pub fn demote_f64(&mut self, a: Value) -> Value {
        self.emit("truncd", Type::F32, Some(Type::F32), Some(a), None)
            .unwrap()
    }
    pub fn bitcast(&mut self, a: Value, to: Type) -> Value {
        self.emit("cast", to, Some(to), Some(a), None).unwrap()
    }

    // Stack allocation (address result).
    pub fn alloc4(&mut self, count: Value) -> Value {
        self.emit("alloc4", Type::I64, Some(Type::I64), Some(count), None)
            .unwrap()
    }
    pub fn alloc8(&mut self, count: Value) -> Value {
        self.emit("alloc8", Type::I64, Some(Type::I64), Some(count), None)
            .unwrap()
    }
    pub fn alloc16(&mut self, count: Value) -> Value {
        self.emit("alloc16", Type::I64, Some(Type::I64), Some(count), None)
            .unwrap()
    }
}
