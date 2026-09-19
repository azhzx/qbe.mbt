# `abi_la64` Package API Reference

Package path: `azhzx/qbe/abi_la64`

[中文版本 (Chinese Version)](zh/abi_la64.md)

LoongArch 64 (la64) LP64D ABI lowering. Replaces abstract parameter/return
references with concrete LoongArch calling-convention registers before
instruction selection. Structurally mirrors `abi_rv64` (LP64D's parameter
classification is register-wise identical to RISC-V lp64d).

## Entry Point

```moonbit
pub fn abi_la64(
  @types.Fn,             // function to lower (modified in place)
  Array[@types.Typ],     // function-local type table
  Bool,                  // debug switch (-dA dump)
  @util.Interner,        // string interner
  Array[@types.Typ],     // global type table
) -> String
```

## Calling Convention (LP64D)

| Category | Registers |
| --- | --- |
| Integer arguments | `LA_A0`–`LA_A7` |
| Float arguments | `LA_FA0`–`LA_FA7` |
| Integer returns | `LA_A0`, `LA_A1` |
| Float returns | `LA_FA0`, `LA_FA1` |
| Caller-saved | `LA_T0`–`LA_T7`, `LA_A0`–`LA_A7`, `LA_FA0`–`LA_FA7`, `LA_FT0`–`LA_FT15` |
| Callee-saved | `LA_S0`–`LA_S8`, `LA_FS0`–`LA_FS7` |
| Globally live | `LA_FP`, `LA_SP`, `LA_TP`, `LA_RA` |

Registers are tmp ids (see `types/target_la64.mbt`, QBE-style renumbering):
`LA_T0=1..LA_A7=16`, `LA_S0..S8=17..25`, `LA_FP=26 SP=27 TP=28 RA=29`,
`LA_T8=30` (emitter scratch / env), `LA_FT0..FT15=32..47`,
`LA_FA0..FA7=48..55`, `LA_FS0..FS7=56..63`, first non-register temp
`La64Tmp0=64`.

Aggregates: at most 16 bytes are classified per member (all-int → GPRs,
all-float → FPRs, mixed → one of each), matching the rv64 port's
convention; alignment above 16 bytes passes by reference (`Cptr`).

## Notes

- LoongArch64 has no upstream C QBE reference (`vendor/qbe` only has
  amd64/arm64), hence no differential baseline; correctness rests on unit
  tests and e2e snapshots (`qbe_la64_snapshot_test.mbt`) hand-verified
  against the LoongArch ELF psABI and the GNU assembler syntax.
- `selcall` encodes the return-value register counts into the low 4 bits of
  the call ref — spill/rega rely on this to know which registers a call
  defines, keeping call results out of callee-saved registers (fixed for the
  shared rv64-port defect; see `doc/abi_rv64.md`).
