# `isel` Package API Reference

Package path: `azhzx/qbe/target_amd64/isel`

Instruction Selection. After ABI processing, replaces abstract SSA instruction patterns with more efficient concrete instructions on amd64. Corresponds to `amd64/isel.c`, `amd64/addr.c`, `amd64/cmp.c`, `amd64/sel.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/isel.md)

## Entry Point

```moonbit
pub fn isel(
  @types.Fn,
  @util.Interner,
  Bool,                  // -dI debug switch
  Array[@types.Typ],     // global type table
) -> String
```

`isel()` performs the following work (major items only):

1. **Immediate optimization**: Converts instructions like `%r = add %x, c` (c is constant) to amd64 immediate form (avoiding occupying a register). Corresponds to regression tests like `_test/isel/001_imm_add_*.ssa`.
2. **Address mode**: Combines `add` chains into `[base + index*scale + offset]` addressing, directly feeding load/store. Implemented in `addr.mbt`.
3. **Division constant magic numbers**: Converts `div`/`rem` (especially constant divisors) to magic number multiply + shift form, avoiding division instructions. Corresponds to `001_div_c_w_7` test cases.
4. **Comparison patterns**: Converts `ceq`/`cslt` etc. comparison + `jnz` patterns to amd64 conditional jumps (`je`/`jl`/...). Implemented in `cmp.mbt`.
5. **Comparison result normalization**: Normalizes comparison instruction output width to 1 byte.
6. **`alloc*` handling**: Stack allocation converted to `slot` references.

Return value follows `ssa.copy`/`abi.abi` convention: debug mode (`Bool = true`) returns dump text, non-debug mode returns empty string.

## Internal Modules

File [isel/addr.mbt](../isel/addr.mbt) implements address mode recognition;
File [isel/cmp.mbt](../isel/cmp.mbt) implements compare + jump pattern recognition;
File [isel/sel.mbt](../isel/sel.mbt) implements main selection logic;
File [target_amd64/isel](../target_amd64/isel) is the entry point.

## Typical Calls

```moonbit
@util.eprint(@isel.isel(fn_, interner, dbg.i, typs))
@cfg.fillrpo(fn_)       // basic block structure may change after instruction selection
```

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- `isel` only does "strength reduction that preserves semantics", not changing the control flow structure of instructions. Further control flow simplification is done by the subsequent `cfg.simpljmp`.
- Currently only supports amd64_sysv. Other targets' isel should be placed under `isel/<target>/`.
