//! Raw bindings to the qbe.mbt C ABI (include/qbe_builder.h) plus the small
//! C shim in src/shim.c that bridges MoonBit Bytes values.
#![allow(dead_code)]

pub type Builder = i64;
pub type Func = i32;
pub type Block = i32;
pub type Val = i32;
pub type MbBytes = *mut u8;

pub const QBE_W: i32 = 0;
pub const QBE_L: i32 = 1;
pub const QBE_S: i32 = 2;
pub const QBE_D: i32 = 3;
pub const QBE_VOID: i32 = -1;

extern "C" {
    // shim.c
    pub fn qbe_glue_init();
    pub fn qbe_glue_bytes(ptr: *const u8, len: usize) -> MbBytes;
    pub fn qbe_glue_len(b: MbBytes) -> usize;
    pub fn qbe_glue_free(b: MbBytes);
    pub fn qbe_glue_error_copy(out: *mut u8, cap: usize) -> usize;

    // qbe_builder.h
    pub fn qbe_builder_new() -> Builder;
    pub fn qbe_builder_free(b: Builder);
    pub fn qbe_last_error() -> MbBytes;
    pub fn qbe_add_func(
        b: Builder,
        name: MbBytes,
        ret_cls: i32,
        is_export: i32,
        params: MbBytes,
    ) -> Func;
    pub fn qbe_func_param(b: Builder, f: Func, i: i32) -> Val;
    pub fn qbe_entry_block(b: Builder, f: Func) -> Block;
    pub fn qbe_add_block(b: Builder, f: Func, label: MbBytes) -> Block;
    pub fn qbe_switch_to(b: Builder, f: Func, blk: Block);
    pub fn qbe_block_param(b: Builder, f: Func, blk: Block, cls: i32) -> Val;
    pub fn qbe_const_int(b: Builder, f: Func, v: i64) -> Val;
    pub fn qbe_const_double(b: Builder, f: Func, v: f64) -> Val;
    pub fn qbe_const_single(b: Builder, f: Func, v: f32) -> Val;
    pub fn qbe_global(b: Builder, f: Func, name: MbBytes) -> Val;
    pub fn qbe_emit(
        b: Builder,
        f: Func,
        op: MbBytes,
        cls: i32,
        res_cls: i32,
        a1: Val,
        a2: Val,
    ) -> Val;
    pub fn qbe_emit_void(b: Builder, f: Func, op: MbBytes, cls: i32, a1: Val, a2: Val);
    pub fn qbe_arg(b: Builder, f: Func, cls: i32, val: Val);
    pub fn qbe_call(b: Builder, f: Func, callee: MbBytes, ret_cls: i32) -> Val;
    pub fn qbe_ret(b: Builder, f: Func, val: Val);
    pub fn qbe_jmp(b: Builder, f: Func, dest: Block);
    pub fn qbe_jmp_n(b: Builder, f: Func, dest: Block, args: MbBytes);
    pub fn qbe_jnz_n(
        b: Builder,
        f: Func,
        cond: Val,
        then_blk: Block,
        then_args: MbBytes,
        else_blk: Block,
        else_args: MbBytes,
    );
    pub fn qbe_data_string(b: Builder, name: MbBytes, is_export: i32, s: MbBytes);
    pub fn qbe_data_bytes(b: Builder, name: MbBytes, is_export: i32, data: MbBytes);
    pub fn qbe_emit_il(b: Builder) -> MbBytes;
    pub fn qbe_emit_asm(b: Builder) -> MbBytes;
    pub fn qbe_emit_object(b: Builder) -> MbBytes;

    // In-memory JIT (native).
    pub fn qbe_jit_load(b: Builder) -> i64;
    pub fn qbe_jit_symbol(jit: i64, name: MbBytes) -> i64;
    pub fn qbe_jit_global(jit: i64, name: MbBytes) -> i64;
    pub fn qbe_jit_free(jit: i64);
}

/// Create a MoonBit Bytes value, run `f` with it, then release it.
pub(crate) fn with_bytes<R>(data: &[u8], f: impl FnOnce(MbBytes) -> R) -> R {
    let b = unsafe { qbe_glue_bytes(data.as_ptr(), data.len()) };
    let r = f(b);
    unsafe { qbe_glue_free(b) };
    r
}

/// Copy a MoonBit Bytes value out and release it.
pub(crate) fn take_bytes(b: MbBytes) -> Vec<u8> {
    if b.is_null() {
        return Vec::new();
    }
    let n = unsafe { qbe_glue_len(b) };
    let v = unsafe { std::slice::from_raw_parts(b, n).to_vec() };
    unsafe { qbe_glue_free(b) };
    v
}
