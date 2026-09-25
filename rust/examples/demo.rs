//! Cranelift-style demo: build add, a phi loop (tri) and recursive fib, then
//! print the IL, the arm64 assembly, and emit Mach-O objects.
use qbe_builder::{Context, IntCC, Signature, Type};

fn build_tri(module: &mut qbe_builder::Module) {
    let f = module.add_function("tri", Signature::new([Type::I32], Some(Type::I32)));
    let mut b = module.builder(f);
    let n = b.params()[0];
    let init = b.create_block("init");
    let zero = b.create_block("zero");
    let loop_blk = b.create_block("loop");
    let body = b.create_block("body");
    let end = b.create_block("end");
    let one = b.ins().iconst(Type::I32, 1);
    let z = b.ins().iconst(Type::I32, 0);
    let c0 = b.ins().icmp(IntCC::SignedGreaterThan, n, z);
    b.ins().brif(c0, init, &[], zero, &[]);
    b.switch_to_block(init);
    b.ins().jump(loop_blk, &[one, z]);
    b.switch_to_block(zero);
    b.ins().return_(&[z]);
    b.switch_to_block(loop_blk);
    let i = b.append_block_param(loop_blk, Type::I32);
    let s = b.append_block_param(loop_blk, Type::I32);
    let s2 = b.ins().iadd(s, i);
    let i2 = b.ins().iadd(i, one);
    let c = b.ins().icmp(IntCC::SignedLessThanOrEqual, i2, n);
    b.ins().brif(c, body, &[], end, &[]);
    b.switch_to_block(body);
    b.ins().jump(loop_blk, &[i2, s2]);
    b.switch_to_block(end);
    b.ins().return_(&[s2]);
}

fn build_fib(module: &mut qbe_builder::Module) {
    let f = module.add_function("fib", Signature::new([Type::I32], Some(Type::I32)));
    let mut b = module.builder(f);
    let n = b.params()[0];
    let base = b.create_block("base");
    let rec = b.create_block("rec");
    let one = b.ins().iconst(Type::I32, 1);
    let c = b.ins().icmp(IntCC::SignedLessThanOrEqual, n, one);
    b.ins().brif(c, base, &[], rec, &[]);
    b.switch_to_block(base);
    b.ins().return_(&[n]);
    b.switch_to_block(rec);
    let n1 = b.ins().isub(n, one);
    let f1 = b.ins().call(f, &[n1]).unwrap();
    let two = b.ins().iconst(Type::I32, 2);
    let n2 = b.ins().isub(n, two);
    let f2 = b.ins().call(f, &[n2]).unwrap();
    let r = b.ins().iadd(f1, f2);
    b.ins().return_(&[r]);
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let ctx = Context::new();
    let mut module = ctx.create_module();

    let f = module.add_function(
        "add",
        Signature::new([Type::I32, Type::I32], Some(Type::I32)),
    );
    {
        let mut b = module.builder(f);
        let a = b.params()[0];
        let c = b.params()[1];
        let r = b.ins().iadd(a, c);
        b.ins().return_(&[r]);
    }
    build_tri(&mut module);
    build_fib(&mut module);

    // Print the constructed IR.
    print!("{}", module.emit_il());

    // Compile to executable memory and call the functions directly
    // (Cranelift-style get_finalized_function).
    let jit = module.jit()?;
    let add: extern "C" fn(i32, i32) -> i32 = jit.get_fn("add")?;
    let tri: extern "C" fn(i32) -> i32 = jit.get_fn("tri")?;
    let fib: extern "C" fn(i32) -> i32 = jit.get_fn("fib")?;
    println!(
        "add(20,22)={} tri(10)={} fib(10)={}",
        add(20, 22),
        tri(10),
        fib(10)
    );
    Ok(())
}
