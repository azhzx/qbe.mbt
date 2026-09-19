# `isel_wasm` Package API Reference

Package path: `azhzx/qbe/target_wasm/isel`

Wasm instruction selection. Maps QBE's generic SSA opcodes to wasm's equivalent operations, while handling address mode decomposition and CFG-to-structured control flow conversion.

[中文版本 (Chinese Version)](zh/isel_wasm.md)

## Entry Point

```moonbit
pub fn isel_wasm(
  @types.Fn,
  Array[@types.Typ],     // global type table
  Bool,                  // debug switch
  @util.Interner,        // string interner
  Array[@types.Typ],     // typs copy
) -> String
```

`isel_wasm()` performs the following work:

1. **Instruction selection**: Traverses all instructions in all blocks, mapping QBE Op to wasm Op:
   - Arithmetic: `add`/`sub`/`mul` → `i32.add`/`i32.sub`/`i32.mul`
   - Bitwise: `and`/`or`/`xor`/`shl`/`shr`/`sar` → corresponding wasm bitwise operations
   - Comparison: `ceql`/`cnel`/`cgtl` etc. → `i32.eq`/`i32.ne`/`i32.gt_s` etc.
   - Conversion: `extsb`/`extub`/`extsw`/`extuw` → `i32.extend8_s` etc.
   - Load/Store: `load`/`store` → `i32.load`/`i32.store` (with type suffix)
   - Function call: `call` → `call`
   - Jump: `jmp`/`jnz`/`jz` → `br`/`br_if`

2. **Address mode decomposition**: `addr_wasm` decomposes complex addresses `base + index * scale + offset` into wasm-representable form:
   - Only supports `base + offset` form
   - `index * scale` must be pre-computed into a temporary variable

3. **CFG → Structured control flow**: `ctrl_wasm` converts arbitrary CFG to wasm structured control flow:
   - Detects loop heads (back edges) and builds loop nesting
   - Uses dominator tree to determine nesting depth
   - Generates `block`/`loop`/`if`/`br` instructions
   - Handles multi-target jumps (via jump depth calculation)

## wasm Opcode Mapping

| QBE Op | wasm Op | Description |
|--------|---------|------|
| `add` | `i32.add` | Integer addition |
| `sub` | `i32.sub` | Integer subtraction |
| `mul` | `i32.mul` | Integer multiplication |
| `udiv`/`sdiv` | `i32.div_u`/`i32.div_s` | Integer division |
| `and`/`or`/`xor` | `i32.and`/`i32.or`/`i32.xor` | Bitwise operations |
| `shl`/`shr`/`sar` | `i32.shl`/`i32.shr_u`/`i32.shr_s` | Shifts |
| `ceql`..`cofl` | `i32.eq`..`f64.le` | Comparisons (return 0/1) |
| `extsb`/`extub` | `i32.extend8_s`/`i32.extend8_s` | Byte extension |
| `extsw`/`extuw` | `i32.extend_i32_s`/`i32.extend_i32_u` | Word extension |
| `storeb`/`storeh`/`storew`/`storel` | `i32.store8`/`i32.store16`/`i32.store`/`i64.store` | Store |
| `loadsb`/`loadub` | `i32.load8_s`/`i32.load8_u` | Load byte |
| `loadsw`/`loaduw` | `i32.load16_s`/`i32.load16_u` | Load halfword |
| `load`/`loadl` | `i32.load`/`i64.load` | Load word/dword |
| `truncd` | `i32.trunc_f64_s` | Float truncation |
| `truncf` | `i32.trunc_f32_s` | Float truncation |
| `extsd` | `f64.promote_f32` | Single-precision promotion |
| `truncsd` | `f64_demote_f64` | Double-precision demotion |
| `stosi`/`stoui` | `i32.trunc_f64_s`/`i32.trunc_f64_u` | Float→integer |
| `dtosi`/`dtoui` | `i32.trunc_f64_s`/`i32.trunc_f64_u` | Float→integer |

## Structured Control Flow Conversion

wasm does not support arbitrary jumps, only structured `block`/`loop`/`if`/`br`. `ctrl_wasm` converts QBE's CFG to nested structure:

```
QBE CFG:                    Wasm structured:
  A ──► B                     (block $exit
  A ──► C                       (loop $continue
  B ──► D                         ;; A's code
  C ──► D                         br_if $continue  ;; jump to B
                                   ;; B's code
                                   br $exit
                                 ) ;; C's code
                               ) ;; D's code
```

Key algorithm:
1. Compute each block's nesting depth via dominator tree
2. Detect back edges (target depth ≥ source depth) to identify loop heads
3. Generate `loop` + `continue` label for each loop
4. Generate `block` + `exit` label for each function
5. Jump depth = target block's nesting depth

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`
- `azhzx/qbe/parser`

## Notes

- wasm32 pointer width is 32 bits (`Km = Kw`), no `Kl` type.
- `Tmp0 = 0` means "no physical registers", different from amd64's `Tmp0 = 64`.
- Skips `spill`/`rega` phases — wasm is a stack machine, no register allocation needed.
- Address mode only supports `base + offset`, not `base + index * scale`.
