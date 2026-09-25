//! End-to-end tests for the Rust glue layer.

use qbe_builder::{Context, IntCC, Signature, Type};

fn build_module() -> qbe_builder::Module {
    let ctx = Context::new();
    let mut module = ctx.create_module();

    // export function w $add(w %a, w %b)
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

    // export data $msg = { b "hi" }
    module.data_string("msg", true, "hi");

    // export function w $tri(w %n): 1 + 2 + ... + n
    let f = module.add_function("tri", Signature::new([Type::I32], Some(Type::I32)));
    {
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

    // export function w $fib(w %n)
    let f = module.add_function("fib", Signature::new([Type::I32], Some(Type::I32)));
    {
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

    module
}

#[test]
fn emit_il_has_signatures_phi_and_calls() {
    let module = build_module();
    let il = module.emit_il();
    assert!(il.contains("export function w $add(w %"), "{il}");
    assert!(il.contains("export function w $tri(w %"), "{il}");
    assert!(il.contains("phi @init"), "{il}");
    assert!(il.contains("call $fib(w %"), "{il}");
    assert!(il.contains("export data $msg = { b \"hi\" }"), "{il}");
}

#[test]
fn emit_asm_contains_all_functions() {
    let mut module = build_module();
    let asm = module.emit_asm().unwrap();
    for name in ["add:", "tri:", "fib:"] {
        assert!(asm.contains(name), "missing {name} in:\n{asm}");
    }
}

#[test]
fn emit_object_is_macho() {
    let mut module = build_module();
    let obj = module.emit_object().unwrap();
    assert!(obj.len() > 16);
    // Mach-O 64-bit magic, little-endian.
    assert_eq!(&obj[0..4], &[0xcf, 0xfa, 0xed, 0xfe]);
}

#[test]
fn object_links_and_runs() {
    if !cfg!(all(target_os = "macos", target_arch = "aarch64")) {
        return;
    }
    let mut module = build_module();
    let obj = module.emit_object().unwrap();
    drop(module);

    let dir = std::env::temp_dir().join(format!("qbe_builder_rust_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let obj_path = dir.join("module.o");
    std::fs::write(&obj_path, &obj).unwrap();
    let drv_path = dir.join("driver.c");
    std::fs::write(
        &drv_path,
        "extern int add(int, int);\nextern int tri(int);\nextern int fib(int);\n#include <stdio.h>\nint main(void) { int a = add(20, 22), t = tri(10), f = fib(10); printf(\"%d %d %d\\n\", a, t, f); return (a == 42 && t == 55 && f == 55) ? 0 : 1; }\n",
    )
    .unwrap();
    let exe = dir.join("run");
    let status = std::process::Command::new("cc")
        .arg("-o")
        .arg(&exe)
        .arg(&drv_path)
        .arg(&obj_path)
        .status()
        .unwrap();
    assert!(status.success(), "cc failed to link the generated object");
    let out = std::process::Command::new(&exe).output().unwrap();
    assert!(
        out.status.success(),
        "program failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    let text = String::from_utf8_lossy(&out.stdout);
    assert!(text.contains("42 55 55"), "unexpected output: {text}");
    let _ = std::fs::remove_dir_all(&dir);
}
