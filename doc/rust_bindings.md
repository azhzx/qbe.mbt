# Rust bindings (qbe-builder)

`rust/` contains a Rust glue layer over the programmatic QBE IL builder, built
**on top of the C ABI** in [`include/qbe_builder.h`](../include/qbe_builder.h).
Its API follows Cranelift/inkwell.

See [`rust/README.md`](../rust/README.md) for the full guide. Summary:

```rust
use qbe_builder::{Context, Signature, Type};

let ctx = Context::new();
let mut module = ctx.create_module();
let f = module.add_function("add", Signature::new([Type::I32, Type::I32], Some(Type::I32)));
{
    let mut b = module.builder(f);
    let a = b.params()[0];
    let c = b.params()[1];
    let r = b.ins().iadd(a, c);
    b.ins().return_(&[r]);
}
let il = module.emit_il();
let asm = module.emit_asm()?;
let obj = module.emit_object()?;
```

## How it links

The crate build script (`rust/build.rs`):

1. runs `moon build --target native ir_builder_capi` (unless `QBE_CAPI_OBJ` or
   `QBE_NO_MOON_BUILD` is set) and locates `ir_builder_capi.o`;
2. compiles `rust/src/shim.c`, a small C shim for the MoonBit `Bytes` helpers
   (`moonbit_make_bytes`, `Moonbit_array_length`, `moonbit_decref`) and the
   one-shot `moonbit_runtime_init` + `moonbit_init`;
3. combines the foreign-library object, `libmoonbitrun.o`, `libruntime.a` and
   `libbacktrace.a` into `libqbe_builder_native.a` and links it (plus `-lm`).

## API mapping

| Rust | C ABI |
| --- | --- |
| `Context::new` / `create_module` | runtime init + `qbe_builder_new` |
| `Module::add_function` | `qbe_add_func` / `qbe_func_param` |
| `Module::builder` / `switch_to_block` | `qbe_entry_block` / `qbe_switch_to` |
| `append_block_param` | `qbe_block_param` |
| `ins().iadd/..` | `qbe_emit` with typed classes |
| `ins().icmp/fcmp` | `ceqw`/`ceql`/`ceqs`/... / `cgtd`/... |
| `ins().load/store` | `loaduw`/`load`/`loads`/`loadd` / `storew`/... |
| `ins().call` | `qbe_arg` + `qbe_call` |
| `ins().jump/brif` | `qbe_jmp_n` / `qbe_jnz_n` |
| `ins().return_` | `qbe_ret` |
| `emit_il` / `emit_asm` / `emit_object` | `qbe_emit_il` / `qbe_emit_asm` / `qbe_emit_object` |
| `Module::jit` / `JitModule::get_fn` | `qbe_jit_load` / `qbe_jit_symbol` |
| `Module::jit_with_symbols` | `qbe_jit_symbol_define` / `qbe_jit_symbol_clear` |
| `JitModule::get_data_ptr` | `qbe_jit_global` |
| `JitModule` drop | `qbe_jit_free` |

## Verification

```sh
cargo test --manifest-path rust/Cargo.toml
```

Unit tests cover the IL text and the assembly; the end-to-end tests JIT the
functions and call them directly (`add(20,22)=42 tri(10)=55 fib(10)=55`), emit
a Mach-O object, link it with `cc` and run it (macOS/aarch64).