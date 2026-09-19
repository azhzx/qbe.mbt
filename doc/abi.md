# `abi` Package API Reference

Package path: `azhzx/qbe/abi`

ABI (Application Binary Interface) processing. Before instruction selection, replaces abstract function parameter/return value references with concrete platform register/stack slot references. The current implementation targets the **amd64_sysv** ABI (System V AMD64 calling convention). Corresponds to `abi.c` + target-specific `amd64/sysv.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/abi.md)

## Entry Point

```moonbit
pub fn abi(
  @types.Fn,
  Array[@types.Typ],     // global type table
  Bool,                  // -dA debug switch
  @util.Interner,        // string interner (generates symbol labels)
  Array[@types.Typ],     // typs copy (compatible with main.c calling convention)
) -> String
```

`abi()` performs the following work:

1. **Parameter passing**: Replaces `Arg`/`Par`/`Argc`/`Arge`/`Parc`/`Pare` instructions with `copy` to/from concrete registers; parameters exceeding register count are spilled to stack slots.
2. **Return values**: Based on return type (`ret_ty`), determines whether to return via registers (RAX/RDX/XMM0) or memory, replacing `Ret*` jump's `arg` with concrete references.
3. **Variadic arguments (`is_vararg`)**: Prepares register save area for `vastart`/`vaarg`.
4. **Aggregate types**: Per System V rules, structure parameters larger than 16 bytes are passed via memory.

Return value follows `ssa.copy`/`ssa.loadopt` convention: debug mode returns dump text, non-debug mode returns empty string.

## Register Mask Helpers

```moonbit
pub fn argregs(@types.Ref) -> (UInt64, Int, Int)   // parameter register mask
pub fn retregs(@types.Ref) -> (UInt64, Int, Int)   // return register mask
```

Returns a triple `(mask, n_int_regs, n_fp_regs)` used by the register allocation phase to compute liveness constraints.

## Register Lists

```moonbit
pub let rsave : Array[Int]    // callee-saved register list
pub let rclob : Array[Int]    // caller-saved (may be clobbered by callee) register list
```

These lists share the same data as the identically-named fields in the `types` package (amd64_sysv-specific configuration).

## Typical Calls

```moonbit
@util.eprint(@abi_amd64.abi(fn_, typs, dbg.a, interner, typs))
@cfg.fillpreds(fn_)      // ABI rewrites CFG, must recompute
@ssa.filluse(fn_)        // also must recompute use chains
```

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- `abi` is the **key transformation point** from abstract SSA to platform-specific SSA. Before this function returns, all references are abstract `RTmp`/`RCon`; after returning, parameter/return-value-related instructions become `copy` to `RSlot`/concrete `RTmp`.
- Currently only supports `amd64_sysv`. Future wasm/arm64 etc. targets need new implementations under `abi/`, keeping the same entry signature.
