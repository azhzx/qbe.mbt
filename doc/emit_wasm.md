# `emit_wasm` Package API Reference

Package path: `azhzx/qbe/target_wasm/emit`

Wasm assembly output. Converts SSA functions after instruction selection into WAT (WebAssembly Text) format text.

[中文版本 (Chinese Version)](zh/emit_wasm.md)

## Entry Point

```moonbit
pub fn emit_fn(
  @types.Fn,
  Array[@types.Typ],     // global type table
  @util.Interner,        // string interner
) -> String

pub fn emit_wat_module(
  Array[@types.Fn],
  Array[@types.Typ],
  @util.Interner,
) -> String
```

`emit_fn()` outputs a single function's WAT text; `emit_wat_module()` outputs a complete module.

## Output Format

### Function Signature

```wasm
(func $add (param $a i32) (param $b i32) (result i32)
  ;; function body
)
```

### Local Variables

```wasm
(local $s i32)
(local $tmp i32)
```

### Opcode Mapping

| SSA Op | WAT Instruction | Description |
|--------|----------|------|
| `add` | `i32.add` | Integer addition |
| `sub` | `i32.sub` | Integer subtraction |
| `mul` | `i32.mul` | Integer multiplication |
| `div` | `i32.div_s`/`i32.div_u` | Signed/unsigned division |
| `rem` | `i32.rem_s`/`i32.rem_u` | Remainder |
| `and`/`or`/`xor` | `i32.and`/`i32.or`/`i32.xor` | Bitwise operations |
| `shl`/`shr`/`sar` | `i32.shl`/`i32.shr_u`/`i32.shr_s` | Shifts |
| `eq`/`ne`/`lt`/`gt`/`le`/`ge` | `i32.eq`/`i32.ne`/`i32.lt_s`/... | Comparison (signed) |
| `load` | `i32.load` | Load 32-bit |
| `store` | `i32.store` | Store 32-bit |
| `load8` | `i32.load8_s`/`i32.load8_u` | Load byte |
| `load16` | `i32.load16_s`/`i32.load16_u` | Load halfword |
| `store8` | `i32.store8` | Store byte |
| `store16` | `i32.store16` | Store halfword |
| `call` | `call $fn` | Function call |
| `jmp` | `br $label` | Unconditional jump |
| `jnz` | `br_if $label` | Conditional jump |
| `ret` | `return`/`end` | Return |

### Control Flow

```wasm
;; loop
(loop $continue
  ;; loop body
  br_if $continue  ;; continue loop
)

;; conditional branch
(if (result i32)
  (i32.eqz (local.get $cond))
  (then
    ;; true branch
  )
  (else
    ;; false branch
  )
)
```

## Debug Output

`emit_wat_module()` returns complete WAT module text, including:
- Module header `(module ...)`
- Function definitions `(func ...)`
- Export declarations `(export ...)`

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- WAT is WebAssembly's text representation, directly parseable by tools like `wasm-tools`.
- wasm32 uses 32-bit pointers, all `i32` operations correspond to wasm's `i32` type.
- Emits `f32`/`f64` operations, including floating-point comparisons, mapped to the matching wasm instructions.
- Loops and phi nodes lower to a dispatch loop with `br_table`; global `data` definitions become a `(data ...)` segment and `$global` references resolve to linear-memory addresses.
- Does not support memory growth (`memory.grow`) — requires linear memory usage.
- Output WAT format conforms to WebAssembly specification 1.0.
