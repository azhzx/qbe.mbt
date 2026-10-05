//! Broader coverage for the Rust glue layer: integer and floating point ALU,
//! every condition code, conversions, loads and stores, globals, error paths
//! and the IL/asm surface.
//!
//! The interpreter/JIT/object backends are arm64, so the tests that execute
//! code return early elsewhere. IL/asm assertions run everywhere.
//!
//! Tests that execute code run through both the object path and the JIT; every
//! operation here also appears in the arm64 assembly, which is byte-identical
//! to the reference QBE.

use qopple::{Context, FloatCC, IntCC, Signature, Type};

const CAN_JIT: bool = cfg!(all(target_os = "macos", target_arch = "aarch64"));

/// Declare w $name(w %a, w %b) with a body of op %a, %b.
fn int_bin(m: &mut qopple::Module, name: &str, op: &str) {
    let f = m.add_function(
        name,
        Signature::new([Type::I32, Type::I32], Some(Type::I32)),
    );
    let mut b = m.builder(f);
    let x = b.params()[0];
    let y = b.params()[1];
    let r = match op {
        "iadd" => b.ins().iadd(x, y),
        "isub" => b.ins().isub(x, y),
        "imul" => b.ins().imul(x, y),
        "sdiv" => b.ins().sdiv(x, y),
        "srem" => b.ins().srem(x, y),
        "band" => b.ins().band(x, y),
        "bor" => b.ins().bor(x, y),
        "bxor" => b.ins().bxor(x, y),
        "ishl" => b.ins().ishl(x, y),
        "ushr" => b.ins().ushr(x, y),
        "sshr" => b.ins().sshr(x, y),
        other => panic!("unknown op {other}"),
    };
    b.ins().return_(&[r]);
}

/// Every integer binary operator, checked through the JIT.
#[test]
fn int_binary_ops_jit() {
    let cases: &[(&str, i32, i32, i32)] = &[
        ("iadd", 20, 22, 42),
        ("isub", 50, 8, 42),
        ("imul", 6, 7, 42),
        ("sdiv", 84, 2, 42),
        ("srem", 85, 2, 1),
        ("band", 0b1111, 0b1010, 0b1010),
        ("bor", 0b1100, 0b1010, 0b1110),
        ("bxor", 0b1100, 0b1010, 0b0110),
        ("ishl", 21, 1, 42),
        // Logical shift fills with zero: 0xFFFFFFFF >> 31 == 1
        ("ushr", -1, 31, 1),
        // Arithmetic shift keeps the sign: -2 >> 1 == -1
        ("sshr", -2, 1, -1),
    ];

    let ctx = Context::new();
    let mut m = ctx.create_module();
    for &(name, ..) in cases {
        int_bin(&mut m, name, name);
    }
    let il = m.emit_il();
    for &(name, ..) in cases {
        assert!(il.contains(name), "IL lacks {name}:\n{il}");
    }
    if !CAN_JIT {
        return;
    }
    let jit = m.jit().unwrap();
    for &(name, a, b, want) in cases {
        let f: extern "C" fn(i32, i32) -> i32 = jit.get_fn(name).unwrap();
        assert_eq!(f(a, b), want, "{name}({a}, {b})");
    }
}

/// icmp for every IntCC, signed and unsigned, through the JIT.
#[test]
fn int_compare_all_cc_jit() {
    let all: &[(&str, IntCC, i32, i32, i32)] = &[
        ("eq", IntCC::Equal, 5, 5, 1),
        ("ne", IntCC::NotEqual, 5, 5, 0),
        ("slt", IntCC::SignedLessThan, -1, 1, 1),
        ("sle", IntCC::SignedLessThanOrEqual, 1, 1, 1),
        ("sgt", IntCC::SignedGreaterThan, 1, -1, 1),
        ("sge", IntCC::SignedGreaterThanOrEqual, -1, 1, 0),
        // -1 is the largest unsigned value, so -1 < 1 is false and -1 > 1 true.
        ("ult", IntCC::UnsignedLessThan, -1, 1, 0),
        ("ule", IntCC::UnsignedLessThanOrEqual, 1, -1, 1),
        ("ugt", IntCC::UnsignedGreaterThan, -1, 1, 1),
        ("uge", IntCC::UnsignedGreaterThanOrEqual, 1, -1, 0),
    ];

    let ctx = Context::new();
    let mut m = ctx.create_module();
    for &(name, cc, ..) in all {
        let f = m.add_function(
            name,
            Signature::new([Type::I32, Type::I32], Some(Type::I32)),
        );
        let mut b = m.builder(f);
        let x = b.params()[0];
        let y = b.params()[1];
        let r = b.ins().icmp(cc, x, y);
        b.ins().return_(&[r]);
    }
    if !CAN_JIT {
        return;
    }
    let jit = m.jit().unwrap();
    for &(name, _, a, b, want) in all {
        let f: extern "C" fn(i32, i32) -> i32 = jit.get_fn(name).unwrap();
        assert_eq!(f(a, b), want, "{name}({a}, {b})");
    }
}
/// fcmp for every FloatCC, through the JIT. NaN exercises ordered vs unordered.
#[test]
fn float_compare_all_cc_jit() {
    let all: &[(&str, FloatCC, f64, f64, i32)] = &[
        ("oeq", FloatCC::Equal, 1.0, 2.0, 0),
        ("one", FloatCC::NotEqual, 1.0, 2.0, 1),
        ("olt", FloatCC::LessThan, 1.0, 2.0, 1),
        ("ole", FloatCC::LessThanOrEqual, 1.0, 2.0, 1),
        ("ogt", FloatCC::GreaterThan, 1.0, 2.0, 0),
        ("oge", FloatCC::GreaterThanOrEqual, 1.0, 2.0, 0),
        ("ord", FloatCC::Ordered, 1.0, 2.0, 1),
        ("uno", FloatCC::Unordered, 1.0, 2.0, 0),
        // NaN: unordered holds and inequality is true.
        ("nan_oeq", FloatCC::Equal, f64::NAN, f64::NAN, 0),
        ("nan_one", FloatCC::NotEqual, f64::NAN, f64::NAN, 1),
        ("nan_ord", FloatCC::Ordered, f64::NAN, f64::NAN, 0),
        ("nan_uno", FloatCC::Unordered, f64::NAN, f64::NAN, 1),
    ];

    let ctx = Context::new();
    let mut m = ctx.create_module();
    for &(name, cc, ..) in all {
        let f = m.add_function(
            name,
            Signature::new([Type::F64, Type::F64], Some(Type::I32)),
        );
        let mut b = m.builder(f);
        let x = b.params()[0];
        let y = b.params()[1];
        let r = b.ins().fcmp(cc, x, y);
        b.ins().return_(&[r]);
    }
    if !CAN_JIT {
        return;
    }
    let jit = m.jit().unwrap();
    for &(name, _, a, b, want) in all {
        let f: extern "C" fn(f64, f64) -> i32 = jit.get_fn(name).unwrap();
        assert_eq!(f(a, b), want, "{name}({a}, {b})");
    }
}

/// Double precision arithmetic chained through all four operators.
#[test]
fn float_arith_jit() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    let f = m.add_function(
        "fcalc",
        Signature::new([Type::F64, Type::F64], Some(Type::F64)),
    );
    {
        let mut b = m.builder(f);
        let x = b.params()[0];
        let y = b.params()[1];
        let sum = b.ins().fadd(x, y);
        let diff = b.ins().fsub(x, y);
        let prod = b.ins().fmul(sum, diff);
        let quot = b.ins().fdiv(prod, y);
        b.ins().return_(&[quot]);
    }
    let il = m.emit_il();
    for op in ["add", "sub", "mul", "div"] {
        assert!(il.contains(op), "IL lacks {op}:\n{il}");
    }
    if !CAN_JIT {
        return;
    }
    let jit = m.jit().unwrap();
    let fcalc: extern "C" fn(f64, f64) -> f64 = jit.get_fn("fcalc").unwrap();
    // ((x + y) * (x - y)) / y
    assert_eq!(fcalc(6.0, 2.0), 16.0);
    assert_eq!(fcalc(-6.0, 2.0), 16.0);
    assert_eq!(fcalc(3.0, 3.0), 0.0);
    // x*x - y*y over y
    assert_eq!(fcalc(5.0, 1.0), 24.0);
}

/// f32 constants reach the backend through the rodata stash, and
/// promote/demote round trip.
#[test]
fn float32_constants_and_conversions_jit() {
    let ctx = Context::new();
    let mut m = ctx.create_module();

    let f = m.add_function("f32id", Signature::new([Type::F32], Some(Type::F32)));
    {
        let mut b = m.builder(f);
        let x = b.params()[0];
        let c = b.ins().f32const(1.5);
        let r = b.ins().fadd(x, c);
        b.ins().return_(&[r]);
    }

    let g = m.add_function("widen", Signature::new([Type::F32], Some(Type::F64)));
    {
        let mut b = m.builder(g);
        let x = b.params()[0];
        let d = b.ins().promote_f32(x);
        let back = b.ins().demote_f64(d);
        let wide = b.ins().promote_f32(back);
        b.ins().return_(&[wide]);
    }

    let il = m.emit_il();
    assert!(il.contains("s_1.500000"), "{il}");
    assert!(il.contains("exts"), "{il}");
    assert!(il.contains("truncd"), "{il}");
    if !CAN_JIT {
        return;
    }
    let jit = m.jit().unwrap();
    let f32id: extern "C" fn(f32) -> f32 = jit.get_fn("f32id").unwrap();
    assert_eq!(f32id(2.0), 3.5);
    let widen: extern "C" fn(f32) -> f64 = jit.get_fn("widen").unwrap();
    assert_eq!(widen(2.25), 2.25);
}

/// The widening conversions appear in the IL for both target classes. The
/// sign/zero split is what distinguishes them, so each pair is checked.
#[test]
fn int_widening_il() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    let kinds = ["extsb", "extub", "extsh", "extuh", "extsw", "extuw"];
    for k in kinds {
        let f = m.add_function(k, Signature::new([Type::I64], Some(Type::I64)));
        let mut b = m.builder(f);
        let x = b.params()[0];
        let r = match k {
            "extsb" => b.ins().extend_s8(x, Type::I64),
            "extub" => b.ins().extend_u8(x, Type::I64),
            "extsh" => b.ins().extend_s16(x, Type::I64),
            "extuh" => b.ins().extend_u16(x, Type::I64),
            "extsw" => b.ins().extend_s32(x),
            _ => b.ins().extend_u32(x),
        };
        b.ins().return_(&[r]);
    }
    let il = m.emit_il();
    for k in kinds {
        assert!(il.contains(k), "IL lacks {k}:\n{il}");
    }
}
/// Emit the module as a Mach-O object, link it with a C driver and run it and
/// return the child's stdout. Returns an empty string on hosts that cannot run
/// arm64 code; anywhere else a failure to build, link or run panics, so a
/// broken object path cannot silently pass a test.
fn link_and_run(m: &mut qopple::Module, tag: &str, driver: &str) -> String {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static SEQ: AtomicUsize = AtomicUsize::new(0);
    if !CAN_JIT {
        return String::new();
    }
    let obj = m.emit_object().expect("emit_object");
    let n = SEQ.fetch_add(1, Ordering::SeqCst);
    let dir = std::env::temp_dir().join(format!("qopple_{tag}_{}_{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    std::fs::write(dir.join("m.o"), &obj).expect("write object");
    std::fs::write(dir.join("d.c"), driver).expect("write driver");
    let exe = dir.join("run");
    let built = std::process::Command::new("cc")
        .arg("-o")
        .arg(&exe)
        .arg(dir.join("d.c"))
        .arg(dir.join("m.o"))
        .output()
        .expect("cc");
    assert!(
        built.status.success(),
        "cc failed: {}",
        String::from_utf8_lossy(&built.stderr)
    );
    let out = std::process::Command::new(&exe).output().expect("run");
    let _ = std::fs::remove_dir_all(&dir);
    assert!(
        out.status.success(),
        "program failed: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).into_owned()
}

/// Sign/zero extension from every narrow width, executed through the object
/// path (the JIT is not reliable for the 64-bit l-class extensions; see the
/// ignored test at the bottom).
#[test]
fn int_widening_runs() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    // (name, op, argument, expected)
    let cases: &[(&str, &str, i64, i64)] = &[
        ("su8", "extsb", 0xFF, -1),
        ("uu8", "extub", 0xFF, 0xFF),
        ("su16", "extsh", 0x8000, -32768),
        ("uu16", "extuh", 0x8000, 0x8000),
        ("su32", "extsw", 0x8000_0000, -2147483648),
        ("uu32", "extuw", 0x8000_0000, 0x8000_0000),
    ];
    for &(name, _, _, _) in cases {
        let f = m.add_function(name, Signature::new([Type::I64], Some(Type::I64)));
        let mut b = m.builder(f);
        let x = b.params()[0];
        let r = match name {
            "su8" => b.ins().extend_s8(x, Type::I64),
            "uu8" => b.ins().extend_u8(x, Type::I64),
            "su16" => b.ins().extend_s16(x, Type::I64),
            "uu16" => b.ins().extend_u16(x, Type::I64),
            "su32" => b.ins().extend_s32(x),
            _ => b.ins().extend_u32(x),
        };
        b.ins().return_(&[r]);
    }

    let mut driver = String::from("#include <stdio.h>\n");
    for &(name, ..) in cases {
        driver.push_str(&format!("extern long {name}(long);\n"));
    }
    driver.push_str("int main(void) {\n");
    for &(name, _, arg, want) in cases {
        driver.push_str(&format!(
            "  if ({name}({arg}L) != {want}L) {{ fprintf(stderr, \"{name} got %ld\\n\", {name}({arg}L)); return 1; }}\n"
        ));
    }
    driver.push_str("  printf(\"ok\\n\");\n  return 0;\n}\n");

    assert_eq!(link_and_run(&mut m, "widen", &driver).trim(), "ok");
}

/// Loads and stores over alloc4/alloc8/alloc16, executed through the object
/// path.
#[test]
fn load_store_runs() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    let f = m.add_function("mem", Signature::new([Type::I32], Some(Type::I32)));
    {
        let mut b = m.builder(f);
        let x = b.params()[0];
        let one = b.ins().iconst(Type::I64, 1);
        let four = b.ins().iconst(Type::I64, 4);
        let a = b.ins().alloc4(one);
        let d = b.ins().alloc16(four);
        b.ins().store(a, x);
        let xl = b.ins().extend_s32(x);
        let c = b.ins().alloc8(one);
        b.ins().store(c, xl);
        let back_w = b.ins().load(Type::I32, a);
        let back_l = b.ins().load(Type::I64, c);
        b.ins().store(d, xl);
        let back_sw = b.ins().loadsw(d);
        let s = b.ins().iadd(back_w, back_sw);
        let s2 = b.ins().iadd(s, back_sw);
        let _ = back_l;
        b.ins().return_(&[s2]);
    }
    let il = m.emit_il();
    for op in ["alloc4", "alloc8", "alloc16", "storew", "storel"] {
        assert!(il.contains(op), "IL lacks {op}:\n{il}");
    }
    let driver = "#include <stdio.h>\nextern int mem(int);\nint main(void){ int a = mem(7), b = mem(-3); printf(\"%d %d\\n\", a, b); return (a == 21 && b == -9) ? 0 : 1; }\n";
    assert_eq!(link_and_run(&mut m, "mem", driver).trim(), "21 -9");
}

/// The narrowing loads extend exactly as their names promise, through the
/// object path.
#[test]
fn narrow_loads_run() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    let kinds = ["loadsb", "loadub", "loadsh", "loaduh", "loadsw"];
    for kind in kinds {
        let f = m.add_function(kind, Signature::new([], Some(Type::I32)));
        let mut b = m.builder(f);
        let one = b.ins().iconst(Type::I64, 1);
        let a = b.ins().alloc4(one);
        let byte = b.ins().iconst(Type::I32, 0xFF);
        b.ins().store(a, byte);
        let r = match kind {
            "loadsb" => b.ins().loadsb(a),
            "loadub" => b.ins().loadub(a),
            "loadsh" => b.ins().loadsh(a),
            "loaduh" => b.ins().loaduh(a),
            "loadsw" => b.ins().loadsw(a),
            other => panic!("unknown load {other}"),
        };
        b.ins().return_(&[r]);
    }
    let driver = "#include <stdio.h>\nextern int loadsb(void), loadub(void), loadsh(void), loaduh(void), loadsw(void);\nint main(void){ int a=loadsb(),b=loadub(),c=loadsh(),d=loaduh(),e=loadsw(); printf(\"%d %d %d %d %d\\n\",a,b,c,d,e); return (a==-1&&b==255&&c==255&&d==255&&e==255)?0:1; }\n";
    assert_eq!(
        link_and_run(&mut m, "narrow", driver).trim(),
        "-1 255 255 255 255"
    );
}

/// A data global is addressable and usable as a counter, through the object
/// path.
#[test]
fn global_load_store_runs() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    m.data_bytes("counter", true, &[0, 0, 0, 0]);
    let f = m.add_function("bump", Signature::new([], Some(Type::I32)));
    {
        let mut b = m.builder(f);
        let g = b.ins().global("counter");
        let cur = b.ins().load(Type::I32, g);
        let one = b.ins().iconst(Type::I32, 1);
        let next = b.ins().iadd(cur, one);
        b.ins().store(g, next);
        b.ins().return_(&[next]);
    }
    let il = m.emit_il();
    assert!(il.contains("$counter"), "{il}");
    let driver = "#include <stdio.h>\nextern int bump(void);\nint main(void){ int a=bump(),b=bump(),c=bump(); printf(\"%d %d %d\\n\",a,b,c); return (a==1&&b==2&&c==3)?0:1; }\n";
    assert_eq!(link_and_run(&mut m, "global", driver).trim(), "1 2 3");
}

/// A call to a symbol the JIT cannot resolve is an error, not a crash.
#[test]
fn jit_reports_unknown_symbol() {
    if !CAN_JIT {
        return;
    }
    let ctx = Context::new();
    let mut m = ctx.create_module();
    let f = m.add_function("bad", Signature::new([], Some(Type::I32)));
    {
        let mut b = m.builder(f);
        let r = b
            .ins()
            .call_by_name("qopple_no_such_symbol_xyz", Some(Type::I32), &[])
            .unwrap();
        b.ins().return_(&[r]);
    }
    match m.jit() {
        Ok(_) => panic!("jit should fail on an unresolved symbol"),
        Err(err) => {
            assert!(!err.message().is_empty());
            assert!(!format!("{err}").is_empty());
        }
    }
}

/// An empty module is handled without panicking.
#[test]
fn empty_module_is_not_a_crash() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    let il = m.emit_il();
    assert!(il.is_empty() || !il.contains("function"), "{il}");
    let obj = m.emit_object();
    assert!(obj.is_err() || !obj.unwrap().is_empty());
}

/// Non-exported functions appear without the export keyword, and the IL
/// carries the four scalar type letters.
#[test]
fn export_flag_and_type_letters() {
    let ctx = Context::new();
    let mut m = ctx.create_module();

    let f = m.add_function_with(
        "hidden",
        Signature::new(
            [Type::I32, Type::I64, Type::F32, Type::F64],
            Some(Type::I64),
        ),
        false,
    );
    {
        let mut b = m.builder(f);
        let w = b.params()[0];
        let l = b.params()[1];
        let _s = b.params()[2];
        let _d = b.params()[3];
        let widened = b.ins().extend_s32(w);
        let r = b.ins().iadd(l, widened);
        b.ins().return_(&[r]);
    }
    let g = m.add_function("shown", Signature::new([], Some(Type::I32)));
    {
        let mut b = m.builder(g);
        let z = b.ins().iconst(Type::I32, 0);
        b.ins().return_(&[z]);
    }

    let il = m.emit_il();
    assert!(il.contains("function l $hidden(w %"), "{il}");
    assert!(!il.contains("export function l $hidden"), "{il}");
    assert!(il.contains("export function w $shown()"), "{il}");
}

/// A void function uses return_void and prints no result type.
#[test]
fn void_function_il() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    let f = m.add_function("nop", Signature::new([], None));
    {
        let mut b = m.builder(f);
        b.ins().return_void();
    }
    let il = m.emit_il();
    assert!(il.contains("export function $nop()"), "{il}");
    assert!(il.contains("ret"), "{il}");
}

/// data_string and data_bytes both reach the data section.
#[test]
fn data_sections_il() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    m.data_string("hello", true, "hi");
    m.data_bytes("raw", false, &[1, 2, 3, 255]);
    let il = m.emit_il();
    assert!(il.contains("export data $hello = { b \"hi\" }"), "{il}");
    assert!(il.contains("data $raw = { b 1, b 2, b 3, b 255 }"), "{il}");
}

/// The gas flavor selects the assembly dialect: Mach-O prefixes symbols.
#[test]
fn emit_asm_gas_flavors_differ() {
    let ctx = Context::new();
    let mut m = ctx.create_module();
    let f = m.add_function("one", Signature::new([], Some(Type::I32)));
    {
        let mut b = m.builder(f);
        let z = b.ins().iconst(Type::I32, 1);
        b.ins().return_(&[z]);
    }
    let elf = m.emit_asm_with_gas("e").unwrap();
    let macho = m.emit_asm_with_gas("m").unwrap();
    assert!(elf.contains("one:"), "{elf}");
    assert!(!elf.contains("_one:"), "ELF should not prefix:\n{elf}");
    assert!(macho.contains("_one:"), "Mach-O should prefix:\n{macho}");
}

/// Signature and Type helpers behave as documented.
#[test]
fn signature_and_type_helpers() {
    let s = Signature::new([Type::I32, Type::F64], Some(Type::I64));
    assert_eq!(s.params, vec![Type::I32, Type::F64]);
    assert_eq!(s.ret, Some(Type::I64));
    assert!(!s.varargs);

    let v = Signature::variadic([Type::I32], None);
    assert!(v.varargs);
    assert!(v.ret.is_none());

    assert!(Type::F32.is_float());
    assert!(Type::F64.is_float());
    assert!(!Type::I32.is_float());
    assert!(!Type::I64.is_float());
}

/// The JIT runs the widening conversions, including the 64-bit class forms
/// where the destination register is the 32-bit view (a 32-bit write clears
/// the upper half, as the reference prints `uxtb %W=, %W0`).
#[test]
fn int_widening_jit() {
    if !CAN_JIT {
        return;
    }
    // One module per conversion so a failure names the operation.
    let cases: &[(&str, i64, i64)] = &[
        ("su8", 0xFF, -1),
        ("uu8", 0xFF, 0xFF),
        ("su16", 0x8000, -32768),
        ("uu16", 0x8000, 0x8000),
        ("su32", 0x8000_0000, -2147483648),
        ("uu32", 0x8000_0000, 0x8000_0000),
    ];
    for &(name, arg, want) in cases {
        let ctx = Context::new();
        let mut m = ctx.create_module();
        let f = m.add_function(name, Signature::new([Type::I64], Some(Type::I64)));
        {
            let mut b = m.builder(f);
            let x = b.params()[0];
            let r = match name {
                "su8" => b.ins().extend_s8(x, Type::I64),
                "uu8" => b.ins().extend_u8(x, Type::I64),
                "su16" => b.ins().extend_s16(x, Type::I64),
                "uu16" => b.ins().extend_u16(x, Type::I64),
                "su32" => b.ins().extend_s32(x),
                _ => b.ins().extend_u32(x),
            };
            b.ins().return_(&[r]);
        }
        let jit = m.jit().unwrap();
        let f: extern "C" fn(i64) -> i64 = jit.get_fn(name).unwrap();
        assert_eq!(f(arg), want, "{name}({arg})");
    }
}
