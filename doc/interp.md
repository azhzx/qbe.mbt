# `interp` Package API Reference

Package path: `azhzx/qbe/interp`

[中文版本 (Chinese Version)](zh/interp.md)

A direct SSA interpreter for QBE IL: it executes the pre-isel IR produced by
the parser, playing the role `lli` plays for LLVM IR. Values are carried as
raw 64-bit words (word temporaries sign-extended, floats bitcast) with
semantics identical to the constant folder in `fold/opfold.mbt`.

## Entry Point

```moonbit
pub fn run_module(
  funcs : Array[@types.Fn],          // all functions in the module
  datas : Array[@types.Dat],         // data segment (laid out into memory)
  interner : @util.Interner,         // symbol interner
  entry : String,                    // entry function name
  args : Array[InterpValue],         // positional arguments
  max_steps~ : Int = 10_000_000,     // step limit (guards against loops)
  max_depth~ : Int = 10_000,         // call depth limit
  hook~ : ((String, Array[InterpValue]) -> InterpValue?)? = None,
) -> Result[(InterpValue, String), @util.QbeError]
```

The top-level facade `@qbe.interpret(src, ...)` (async) parses the module and
delegates here. `hook~` is the analogue of LLVM ORC's SymbolResolver: external
calls consult it first, then the built-in runtime, then fail with
`QbeError::CompileError("unknown external function ...")`.

## Value Type

```moonbit
pub(all) enum InterpValue {
  VVoid
  VInt(Int64)
  VFloat(Float)
  VDouble(Double)
} derive(Debug, Eq)
```

`w`/`l` parameters take `VInt` (low 32 bits for `w`), `s` takes `VFloat`, `d`
takes `VDouble`.

## Semantics

- **Evaluation**: C QBE integer semantics — `w` arithmetic truncates to 32
  bits and sign-extends; `udiv`/`urem` on `w` operate on zero-extended 32-bit
  operands; division by zero raises `CompileError`. Float operations are IEEE;
  division by zero yields infinities.
- **Memory**: flat little-endian sparse byte memory. Data base `0x10_0000`,
  heap (malloc) base `0x80_0000`, stack (`alloc4/8/16`) growing down from
  `0x1000_0000_0000`, reclaimed per frame.
- **Control flow**: block dispatch is an iterative loop (the host stack does
  not grow with interpreted loops); `phi` values are selected by matching
  `PhiArg.blk_id` against the predecessor. Calls are real host recursion,
  bounded by `max_depth`.
- **Calls**: the contiguous `Arg/Argc/Arge` cluster before a `Call` forms the
  argument list; `Argc` (aggregates) pass by address. Function pointers are
  code-region addresses (base `0x40_0000`) and support indirect calls.

## Built-in Runtime

Pure MoonBit (works on every backend target); text output goes through
`@util.iprint` (async):

| Symbol | Meaning |
| --- | --- |
| `putchar(c)` | write a char, returns `c` |
| `puts(s)` | write NUL-terminated string plus newline, returns len+1 |
| `printf(fmt, ...)` | subset: `%d %i %u %x %c %s %ld %li %lu %lx %f %lf %e %g %%` |
| `malloc(sz)` | 16-byte aligned bump allocation, zero-initialized |
| `free(p)` | no-op (bump allocator; fine for test programs) |
| `exit(n)` | stop interpretation, `run_module` returns `Ok(VInt(n))` |

## Limitations

- `vastart`/`vaarg` are unsupported (explicit error).
- Interprets the source-semantics IR: no ABI/isel/back-end lowering runs.
- `free` is a no-op; programs depending on malloc reuse are not supported.
