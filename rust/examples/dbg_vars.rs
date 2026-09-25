//! Emit arm64 assembly with DWARF debug info for a declared variable.
//!
//! Used by `scripts/run_dbg_vars_demo.sh`: the front end names a variable and
//! its type, and the emitted `.debug_info`/`.debug_loc` let lldb show it.

use qbe_builder::{Context, DebugType, Signature, Type};

fn main() {
    let ctx = Context::new();
    let mut module = ctx.create_module();
    module.enable_debug_info(true);
    module.dbg_compile_unit("demo.c", ".");

    // int f(int x) { int sum = x + 1; return sum; }
    let f = module.add_function("f", Signature::new([Type::I32], Some(Type::I32)));
    {
        let mut b = module.builder(f);
        let x = b.params()[0];
        let one = b.ins().iconst(Type::I32, 1);
        let sum = b.ins().iadd(x, one);
        b.declare_var("sum", DebugType::W, sum);
        b.ins().return_(&[sum]);
    }

    // int main(void) { return f(41); }
    let m = module.add_function("main", Signature::new([], Some(Type::I32)));
    {
        let mut b = module.builder(m);
        let a = b.ins().iconst(Type::I32, 41);
        let r = b.ins().call_by_name("f", Some(Type::I32), &[a]).unwrap();
        b.ins().return_(&[r]);
    }

    print!("{}", module.emit_asm_with_gas("m").unwrap());
}
