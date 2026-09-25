# qbe-builder (Rust glue layer)

Idiomatic Rust bindings over the [qbe.mbt](../) programmatic QBE IL builder
**through its C ABI** (`include/qbe_builder.h`). The API follows
Cranelift/inkwell: a `Context` creates a `Module`, functions are declared with
a `Signature`, and a `FunctionBuilder` emits instructions via `builder.ins()`.

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

println!("{}", module.emit_il());     // QBE IL text
let asm = module.emit_asm()?;         // arm64 assembly
let obj = module.emit_object()?;      // self-contained Mach-O arm64 object
```

Run the full example:

```sh
cargo run --example demo
```

The standalone demo under [`demo/13_builder_rust/`](../demo/13_builder_rust/) (the
Rust counterpart of `demo/12_builder_capi.c`) is run with
`./scripts/run_builder_rust_demo.sh`.

## API shape

- `Context::new()` / `Context::create_module()` - mirrors inkwell.
- `Module::add_function(name, Signature)` - returns a `FunctionId`.
- `Module::builder(fid)` - borrows the module and returns a `FunctionBuilder`.
- `FunctionBuilder::params()`, `create_block`, `switch_to_block`,
  `append_block_param`, `block_params`, `seal_block` (a no-op: QBE binds branch
  arguments lazily).
- `builder.ins().iadd/isub/imul/sdiv/udiv/srem/urem/band/bor/bxor/ishl/ushr/sshr`,
  `fadd/fsub/fmul/fdiv`, `icmp(IntCC, ..)`, `fcmp(FloatCC, ..)`,
  `load/store`, `iconst/f32const/f64const`, `global`, `call`, `return_`,
  `jump`, `brif`, `extend_*`, `promote_f32`, `demote_f64`, `bitcast`,
  `alloc4/8/16`, and the `raw(op, cls, res, a1, a2)` escape hatch.
- `Module::data_string` / `data_bytes`; `emit_il` / `emit_asm` / `emit_object`.

Values carry their `Type`, so arithmetic and comparisons pick the right QBE
class automatically (for example `icmp(IntCC::Equal, a, b)` becomes `ceqw` or
`ceql` depending on the operand).

## In-memory JIT

`Module::jit()` compiles the module to executable memory and returns a
`JitModule`. `get_fn` transmutes a symbol address to a function pointer
(Cranelift-style):

```rust
let jit = module.jit()?;
let add: extern "C" fn(i32, i32) -> i32 = jit.get_fn("add")?;
assert_eq!(add(20, 22), 42);

let tri: extern "C" fn(i32) -> i32 = jit.get_fn("tri")?;
assert_eq!(tri(10), 55);

let msg: *mut u8 = jit.get_data_ptr("msg")?;   // global data
```

The image is self-contained (no linker involved). External symbols such as
libc calls are not resolved yet, so JIT functions must be self-contained.

## Building and testing

Requirements: a Rust toolchain, the MoonBit toolchain (`moon`), and a C
compiler. The build script runs

```sh
moon build --target native ir_builder_capi
```

locates the produced `ir_builder_capi.o`, compiles `src/shim.c`, and combines
the foreign-library object, the MoonBit runtime archives and the shim into one
static archive that is linked into every target. Set `QBE_CAPI_OBJ` to a
prebuilt object to skip the `moon build` step, or `QBE_NO_MOON_BUILD=1` to
forbid it. `MOON_HOME` overrides the MoonBit install location.

```sh
cargo test        # unit + end-to-end tests
cargo run --example demo
```

The end-to-end test emits a Mach-O object, links it with a C driver using `cc`,
runs it and checks `add(20,22)=42 tri(10)=55 fib(10)=55`. It is skipped on
hosts that are not macOS/aarch64; the IL and assembly tests run everywhere the
foreign library builds.

## Notes and limitations

- **Threading**: the C ABI has a process-global builder registry and the
  MoonBit runtime is not thread-safe, so a live `Module` holds a process-wide
  lock and is `!Send`. Build one module at a time.
- **Object emission** is arm64/Mach-O; `emit_asm` and `emit_il` are
  target-independent text.
- **`emit_object`/`emit_asm` consume** the module (the backend passes run
  once); `emit_il` may be called before them.
- Strings and blobs cross the boundary as MoonBit `Bytes`; `src/shim.c` owns
  the `moonbit_make_bytes` / `Moonbit_array_length` / `moonbit_decref` details
  so Rust never touches the object header layout.