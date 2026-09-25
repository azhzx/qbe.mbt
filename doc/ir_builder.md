# Programmatic IR builder and C ABI

`ir_builder` builds QBE IL **programmatically**: instead of rendering `.ssa`
text and re-parsing it, it constructs the very same in-memory IR the parser
produces (`@types.Fn` / `Blk` / `Ins` / `Phi` / `Jump` / `Con`). That IR is
handed straight to the backend through `@qbe.compile_ir_object` /
`compile_ir_asm` / `compile_ir_bin_module`.

`ir_builder_capi` (`pkgtype(kind: "foreign_library")`) exposes the builder to C
through a stable `qbe_*` symbol set declared in
[`include/qbe_builder.h`](../include/qbe_builder.h).

## Identical IR, verified

The builder is a *front end*, not a second compiler. Assembly emitted from
builder-built IR is byte-identical to assembly from the equivalent `.ssa` text:

- three whitebox tests build a program from `.ssa` text and from the builder and
  compare the assembly (arithmetic, control flow, block parameters/phi);
- `emit_il` prints the constructed IR back to `.ssa`, and a round-trip test
  re-parses that text and checks the assembly is byte-identical.

```moonbit
let b = @ir_builder.Builder::new()
// ... build `add` ...
let il = b.emit_il()   // "export function w $add(w %p.1, w %p.2) { ... }"
```

## MoonBit API

Handles are plain `Int`s. A value handle of `-1` means "none".

```moonbit
let b = @ir_builder.Builder::new()

// export function w $add(w %a, w %b) { @start  %r =w add %a, %b  ret %r }
let f = b.add_func("add", @ir_builder.Ret::Word, [@types.Kw, @types.Kw], true)
let a = b.param(f, 0)
let c = b.param(f, 1)
let r = b.arith(f, @types.Add, @types.Kw, a, c)
b.ret(f, r)

// Print the constructed IR back as QBE IL, or compile it:
let il = b.emit_il()
let asm = b.emit_asm()
// let obj = b.emit_object()
```

Building blocks:

| Method | Meaning |
| --- | --- |
| `add_func(name, ret, params, is_export)` | Define a function; the entry block `start` gets one `Par` per class in `params`. Returns the function id. |
| `param(fid, i)` | Value handle of parameter `i`. |
| `add_block(fid, label)` / `switch_to(fid, bid)` | Define / select a basic block. |
| `block_param(fid, bid, cls)` | A block parameter (phi at the top of `bid`). |
| `iconst` / `fconst` / `sconst` / `global` | Integer / double / single / address-of-global constants. |
| `arith` / `cmp` / `unop` | Binary ALU, comparison (word result), extension/truncation. |
| `load` / `store` | Memory access. |
| `call(fid, callee, args, ret)` | Direct call; emits the `Arg` instructions too. |
| `jmp(fid, dest, args)` / `jnz(...)` | Branches; `args` feed the target block parameters. |
| `ret(fid, v)` | Return. |
| `emit_ins` / `emit_void` | Generic escape hatch: any `@types.Op` with explicit classes. |
| `data_string` / `data_bytes` / `data_ref` | Data sections. |
| `emit_il` | Serialize the constructed IR back to QBE IL text (re-parseable by the textual parser). |
| `emit_asm` / `emit_object` / `emit_bin_module` | Compile. (`emit_bin_module` feeds `run_asm.ExecBlock` for in-process execution.) |

Branch arguments are bound lazily, so a block may declare its parameters either
before or after the branches that feed them (exactly like `phi` lines in text).

## C ABI

The foreign library exports one symbol per operation. Strings cross the
boundary as MoonBit `Bytes` (UTF-8); the header provides `qbe_cstr`,
`qbe_bytes`, and `qbe_params` helpers built on `moonbit_make_bytes`. Class codes
are plain ints (`QBE_W`/`QBE_L`/`QBE_S`/`QBE_D`, `QBE_VOID = -1`).

```c
#include "qbe_builder.h"

int32_t ps[2] = { QBE_W, QBE_W };
qbe_builder_t b = qbe_builder_new();
qbe_func_t f = qbe_add_func(b, qbe_cstr("add"), QBE_W, /*export=*/1,
                            qbe_params(ps, 2));
qbe_value_t a = qbe_func_param(b, f, 0);
qbe_value_t c = qbe_func_param(b, f, 1);
qbe_value_t r = qbe_emit(b, f, qbe_cstr("add"), QBE_W, QBE_W, a, c);
qbe_ret(b, f, r);
moonbit_bytes_t il  = qbe_emit_il(b);       /* QBE IL text */
moonbit_bytes_t obj = qbe_emit_object(b);   /* Mach-O arm64, no runtime deps */
```

Because a `foreign_library` is not an executable, the package carries a
tiny `native_stub.c` with a no-op `main`; the artifact that matters is the
object file `_build/native/debug/build/ir_builder_capi/__moonbit_link_core__/ir_builder_capi.o`.
It links against the MoonBit runtime:

```sh
cc -I include -I "$HOME/.moon/include" my_prog.c \
   ir_builder_capi.o "$HOME/.moon/lib/libmoonbitrun.o" \
   _build/native/debug/build/libruntime.a -lm "$HOME/.moon/lib/libbacktrace.a"
```

Call `moonbit_runtime_init(argc, argv)` and then `moonbit_init()` once at
program start, before the first `qbe_*` call.

## Smoke test

`scripts/build_capi.sh` builds the foreign library, compiles
`examples/capi/capi_smoke.c` (which emits `add.o` and `fib.o` through the C
ABI), links them with `examples/capi/capi_driver.c`, runs the result and checks
`add(20,22) == 42` and `fib(10) == 55`:

```sh
bash scripts/build_capi.sh
```

`demo/12_builder_capi.c` is a fuller example: it constructs a `$tri` loop with
two block parameters (phi) plus `$add`, prints their arm64 assembly, writes
`12_tri.o` / `12_add.o` and links them with `demo/12_builder_capi_driver.c`:

```sh
bash scripts/run_builder_demo.sh
# tri(10)=55 add(20,22)=42
```

On the MoonBit side, `moon test --target native ir_builder` also JITs the
builder-built `fib` in-process and checks `fib(10) == 55`, `fib(20) == 6765`.

## Limitations

- Object/JIT emission is arm64 (macOS/aarch64) only, matching route B.
- Aggregate (`:type`) parameters and returns, variadic calls, and dynamic
  `alloc` are not wrapped by the C ABI yet; the MoonBit `emit_ins` escape
  hatch can still express them.
- `emit_il` binds branch arguments in place and can be called before (or without)
  `emit_asm`/`emit_object`; the compiling emitters run the backend passes and
  consume the IR, so a `Builder` compiles at most once.
- Float literals are printed with six fractional digits, so `emit_il` round-trips
  most, but not every, arbitrary `Double` bit pattern exactly.