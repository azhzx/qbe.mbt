//! demo/13_builder_rust - build QBE IL from Rust.
//!
//! The Rust counterpart of demo/12_builder_capi.c. Through the qbe-builder
//! crate it builds $add, a phi loop $tri and a recursive $fib, prints the QBE
//! IL, emits arm64 assembly, and (on macOS/aarch64) JITs the functions and
//! calls them directly.
//!
//! Run:
//!   cargo run --manifest-path demo/13_builder_rust/Cargo.toml
//!   ./scripts/run_builder_rust_demo.sh

use qbe_builder::{Context, IntCC, Module, Signature, Type};

// export function w $add(w %a, w %b) { @start  %r =w add %a, %b  ret %r }
fn build_add(module: &mut Module) {
    let f = module.add_function(
        "add",
        Signature::new([Type::I32, Type::I32], Some(Type::I32)),
    );
    let mut b = module.builder(f);
    let a = b.params()[0];
    let c = b.params()[1];
    let r = b.ins().iadd(a, c);
    b.ins().return_(&[r]);
}

// export function w $tri(w %n): 1 + 2 + ... + n, with a phi loop.
fn build_tri(module: &mut Module) {
    let f = module.add_function("tri", Signature::new([Type::I32], Some(Type::I32)));
    let mut b = module.builder(f);
    let n = b.params()[0];
    let init = b.create_block("init");
    let zero = b.create_block("zero");
    let lp = b.create_block("loop");
    let body = b.create_block("body");
    let end = b.create_block("end");
    let one = b.ins().iconst(Type::I32, 1);
    let z = b.ins().iconst(Type::I32, 0);

    let c0 = b.ins().icmp(IntCC::SignedGreaterThan, n, z);
    b.ins().brif(c0, init, &[], zero, &[]);

    b.switch_to_block(init);
    b.ins().jump(lp, &[one, z]);

    b.switch_to_block(zero);
    b.ins().return_(&[z]);

    b.switch_to_block(lp);
    let i = b.append_block_param(lp, Type::I32);
    let s = b.append_block_param(lp, Type::I32);
    let s2 = b.ins().iadd(s, i);
    let i2 = b.ins().iadd(i, one);
    let c = b.ins().icmp(IntCC::SignedLessThanOrEqual, i2, n);
    b.ins().brif(c, body, &[], end, &[]);

    b.switch_to_block(body);
    b.ins().jump(lp, &[i2, s2]);

    b.switch_to_block(end);
    b.ins().return_(&[s2]);
}

// export function w $fib(w %n): recursive, exercises calls.
fn build_fib(module: &mut Module) {
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
    build_add(&mut module);
    build_tri(&mut module);
    build_fib(&mut module);

    // Print the constructed IR as QBE IL.
    print!("{}", module.emit_il());

    // Compile to executable memory and call the functions directly.
    #[cfg(all(target_os = "macos", target_arch = "aarch64"))]
    {
        let jit = module.jit()?;
        let add: extern "C" fn(i32, i32) -> i32 = jit.get_fn("add")?;
        let tri: extern "C" fn(i32) -> i32 = jit.get_fn("tri")?;
        let fib: extern "C" fn(i32) -> i32 = jit.get_fn("fib")?;
        println!("JIT: add(20,22)={}", add(20, 22));
        println!("JIT: tri(10)={}", tri(10));
        println!("JIT: fib(10)={}", fib(10));
    }

    // Elsewhere, emit arm64 assembly text instead (the JIT runs arm64 code).
    #[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
    {
        let asm = module.emit_asm()?;
        println!(
            "(JIT needs macOS/aarch64; emitted {} bytes of arm64 assembly)",
            asm.len()
        );
    }

    Ok(())
}
