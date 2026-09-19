# `abi_wasm` Package API Reference

Package path: `azhzx/qbe/target_wasm/abi`

Wasm ABI processing. Before instruction selection, replaces abstract function parameter/return value references with wasm local variable references. Unlike amd64, wasm is a stack machine architecture with no registers; parameters are passed directly through the function signature's parameter list.

[中文版本 (Chinese Version)](zh/abi_wasm.md)

## Entry Point

```moonbit
pub fn abi_wasm(
  @types.Fn,
  Array[@types.Typ],     // global type table
  Bool,                  // debug switch
  @util.Interner,        // string interner
  Array[@types.Typ],     // typs copy
) -> String
```

`abi_wasm()` performs the following work:

1. **Parameter passing**: Replaces `Par`/`Arg` instructions with `Nop`. Wasm parameters are passed directly through the function signature, requiring no explicit copy instructions.
2. **Return values**: Replaces the return value reference in `Ret` jumps with assignment to local variables.
3. **Call simplification**: Replaces `Arg` operands in `Call` instructions with `copy` to local variables, maintaining SSA form.

## Differences from amd64 ABI

| Feature | amd64_sysv | wasm |
|------|-----------|------|
| Parameter passing | Registers (rdi, rsi, ...) | Function signature parameters |
| Return values | Registers (rax, rdx) | Function signature return values |
| Stack frame | Manually managed | Managed by runtime |
| Variadic arguments | vastart/vaarg | Requires manual implementation |
| Aggregate types | Split into registers or memory based on size | Always via memory pointer |

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- `abi_wasm` is the **key transformation point** from abstract SSA to wasm-related SSA. Before this function returns, all references are abstract `RTmp`/`RCon`; after returning, parameter/return-value-related instructions become `Nop`.
- wasm32 pointer width is 32 bits (`Km = Kw`), no `Kl` type.
- Currently does not support wasm variadic arguments or aggregate types larger than 16 bytes (different from amd64 behavior).
