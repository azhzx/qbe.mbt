# `isel_rv64` Package API Reference

Package path: `azhzx/qbe/isel_rv64`

RISC-V 64 instruction selection. Runs after `abi_rv64` lowering, mapping generic SSA instructions to RISC-V instruction forms. Corresponds to upstream QBE's `rv64/isel.c`.

[中文版本 (Chinese Version)](zh/isel_rv64.md)

## Entry Point

```moonbit
pub fn isel_rv64(
  @types.Fn,          // function to process (modified in place)
  @util.Interner,     // string interner
  Bool,               // debug switch (-dI dump)
  Array[@types.Typ],  // global type table
) -> String raise
```

Returns `-dI` debug text (empty string when `print_dbg == false`).

## Instruction Mapping Summary

| QBE IL | RISC-V |
| --- | --- |
| `add`/`sub`/`mul` | `add`/`sub`/`mul` (select `addw` etc. based on class `w`/`l`) |
| `div`/`rem`/`udiv`/`urem` | `div`/`rem`/`divu`/`remu` |
| `and`/`or`/`xor` | `and`/`or`/`xor` |
| `shl`/`sar`/`shr` | `sll`/`sra`/`srl` (word variants `*w`) |
| `loadsb/ub/sh/uh/sw/uw/l` | `lb/lbu/lh/lhu/lw/lwu/ld` |
| `storeb/h/w/l` | `sb/sh/sw/sd` |
| `loads`/`stores` | `flw`/`fsw` |
| `loadd`/`stored` | `fld`/`fsd` |
| `extsb`/`extsh`/`extsw` | `sext.b`/`sext.h`/`sext.w` (or merged into load) |
| Floating-point ops | `fadd.s`/`fsub.s`/`fmul.s`/`fdiv.s` and `d` variants |
| Comparison | First `slt`/floating-point comparison, then via `beq`/`bne` etc. branches |

Compare + branch combinations are rewritten at the instruction selection level to RISC-V branch instructions directly consuming comparison results (RISC-V has no independent flags state).

## Differences from amd64 isel

- **No flags register**: amd64 uses `xcmp` + flag-op + `jX...`, rv64 directly generates compare + branch sequences.
- **No complex addressing**: amd64 can fold `add` chains into `[base + index*scale + offset]` addressing operands; RISC-V only supports `[rs1 + imm]`, `isel_rv64` only does `base + offset` form recognition (`decompose_addr`/`is_simple_addr` semantics), complex addresses keep explicit `add` instructions.
- **No magic number division**: amd64 converts constant division to multiply + shift sequence; rv64 directly uses `div`/`rem` instructions.
- **Immediates**: RISC-V instruction immediate bit-width is limited; large constants are first loaded into registers with `li`.

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- Instruction selection runs after ABI lowering, at which point parameters/return values are already concrete register references.
- rv64 reuses amd64's `spill`/`rega` (via `types.target_cfg` target switching), so register numbers referenced by isel_rv64 output follow the numbering scheme in `types/target_rv64.mbt`.
