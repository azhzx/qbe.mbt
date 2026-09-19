# `abi_rv64` Package API Reference

Package path: `azhzx/qbe/target_rv64/abi`

RISC-V 64 (rv64) ABI processing. Before instruction selection, replaces abstract function parameter/return value references with concrete register references per the RISC-V calling convention. On the same level as `abi` (amd64 System V), corresponding to upstream QBE's `rv64/abi.c`.

[中文版本 (Chinese Version)](zh/abi_rv64.md)

## Entry Point

```moonbit
pub fn abi_rv64(
  @types.Fn,             // function to process (modified in place)
  Array[@types.Typ],     // function-local type table
  Bool,                  // debug switch (-dA dump)
  @util.Interner,        // string interner
  Array[@types.Typ],     // global type table
) -> String
```

Returns `-dA` debug text (empty string when `print_dbg == false`).

## Calling Convention

| Category | Registers |
| --- | --- |
| Integer parameters | `A0`–`A7` (`t` class parameters borrow `T0`–`T5`, see below) |
| Floating-point parameters | `FA0`–`FA7` |
| Integer return values | `A0`, `A1` |
| Floating-point return values | `FA0`, `FA1` |
| Caller-saved | `T0`–`T5`, `A0`–`A7`, `FA0`–`FA7`, `FT0`–`FT10` |
| Callee-saved | `S1`–`S11`, `FS0`–`FS11` |

Registers are numbered by tmp id (see `types/target_rv64.mbt`): `T0=1..A7=14`, `S1..S11=15..25`, `FP=26 SP=27 GP=28 TP=29 RA=30`, `FT0..FA7=31..49`, `FS0..FS11=50..61`, first non-register temporary `Rv64Tmp0=64`.

## Work Performed

1. **Parameter lowering (`selpar`)**: Replaces `Par` instructions in the entry block with copy from `A0..`/`FA0..` (overflow goes to stack slots `Salloc`); aggregate types are classified by `rv64_typclass` to use registers or memory, with field-by-field movement (`rv64_ldregs`/`rv64_sttmps`).
2. **Call lowering (`selcall`)**: Replaces `Arg` with copy to parameter registers/stack slots; parameters exceeding register count reserve space on stack; aggregate parameters are split via `rv64_blit`/`rv64_fpstruct`.
3. **Return value lowering**: Before `Ret` jumps, copies result to `A0`/`A1`/`FA0`/`FA1`; large aggregates returned via hidden pointer.
4. **vararg**: `vastart`/`vaarg` processed per RISC-V `va_list` layout register save area.

## Differences from Other Backend ABIs

| Feature | amd64_sysv (`abi_amd64`) | wasm (`abi_wasm`) | rv64 (`abi_rv64`) |
|------|--------------------|--------------------|-------------------|
| Integer parameters | RDI,RSI,RDX,RCX,R8,R9 | Function signature parameters | A0–A7 |
| Floating-point parameters | XMM0–XMM7 | Function signature parameters | FA0–FA7 |
| Return values | RAX,RDX / XMM0,XMM1 | Function signature return values | A0,A1 / FA0,FA1 |
| Aggregate types | Split into registers if ≤8 bytes | Via memory pointer | Classified by field, uses registers or memory |
| Variadic arguments | Register save area | Not supported | Register save area + stack |

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- The rv64 backend currently has no differential reference validation (upstream C QBE's rv64 target has not yet been added to the `compare.py` baseline); behavior is based on IL semantics and the RISC-V calling convention.
- `spill`/`rega` are target-independent: after `abi_rv64` lowering completes, `pipeline.mbt` calls `@types.init_rv64_target()` to switch the global `TargetCfg`, and subsequent `spill`/`rega` allocates by RISC-V register numbers.
