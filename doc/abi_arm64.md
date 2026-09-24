# `abi_arm64` Package API Reference

Package path: `azhzx/qbe/target_arm64/abi`

[中文版本 (Chinese Version)](zh/abi_arm64.md)

ARM64 (AArch64) AAPCS64 ABI lowering, ELF flavor. Replaces abstract
parameter/return references with concrete calling-convention registers before
instruction selection. Ported 1:1 from `vendor/qbe/arm64/abi.c`.

## Entry Point

```moonbit
pub fn abi_arm64(
  @types.Fn,             // function to lower (modified in place)
  Array[@types.Typ],     // function-local type table
  Bool,                  // debug switch (-dA dump)
  @util.Interner,        // string interner
  Array[@types.Typ],     // global type table
) -> String
```

## Calling Convention (AAPCS64)

| Category | Registers |
| --- | --- |
| Integer arguments | `ARM64_R0`–`ARM64_R7` (x0-x7) |
| Float arguments | `ARM64_V0`–`ARM64_V7` (v0-v7) |
| Integer returns | `ARM64_R0`, `ARM64_R1` |
| Float returns | `ARM64_V0`–`ARM64_V3` |
| Hidden result pointer | `ARM64_R8` (x8) |
| Caller-saved | x0-x18 (`NGPS=19`), v0-v7 and v16-v30 (`NFPS=23`) |
| Callee-saved | x19-x28, v8-v15 (`NCLR=18`) |
| Globally live | `ARM64_FP` (x29), `ARM64_SP`, `ARM64_R18` (`NRGLOB=3`) |

Registers are tmp ids (see `types/target_arm64.mbt`, QBE-style renumbering):
`R0=1..IP1=18 R18=19..SP=32`, `V0=33..V30=63`, first non-register temp
`Arm64Tmp0=64`.

Aggregate classification (`typclass`): homogeneous float aggregates (HFA) of
up to 4 `s`/`d` elements go in consecutive FP registers; other aggregates of
up to 16 bytes use 8-byte GP blocks; dark/oversized/zero-sized values are
replaced by a pointer (`Cptr`) and copied through a stack blob
(`blit`/`Oblit`).

## Notes

- The byte-level oracle is `vendor/qbe/qbe -t arm64`; the backend
  matches it for both IR dumps (5684/5684) and ELF assembly (406/406, `-G e`).
  The Mach-O (`-G m`) flavor, which the reference exposes as
  `-t arm64_apple`, is not yet aligned.
- Narrow `parsb..paruh`/`argsb..arguh` forms do not exist in this port.
- Aggregate `Cptr` copies are expanded into explicit `blt.`-prefixed
  load/store chunks (the reference snapshot's `blit`), since this port predates
  `Oblit0`/`Oblit1`.
