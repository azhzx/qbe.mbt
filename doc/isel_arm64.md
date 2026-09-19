# `isel_arm64` Package API Reference

Package path: `azhzx/qbe/isel_arm64`

[中文版本 (Chinese Version)](zh/isel_arm64.md)

ARM64 (AArch64) instruction selection. Ported 1:1 from
`vendor/qbe/arm64/isel.c`. Turns abstract operations into arm64 machine
operations and assigns stack slots to fast allocations.

## Entry Point

```moonbit
pub fn isel_arm64(
  @types.Fn,             // function whose ABI is already lowered
  @util.Interner,        // string interner
  Bool,                  // debug switch (-dI dump)
  Array[@types.Typ],     // type table
) -> String
```

## Highlights

- **Fast allocations**: `alloc4`/`alloc8`/`alloc16` with constant sizes are
  folded into stack slots (`fn.slot`), matching the `NAlign == 3` layout of
  the reference.
- **Constant materialisation** (`fixarg`): integer constants become `copy`
  instructions; float constants are stashed in the rodata pool (`gasstash`)
  and loaded through a `.LfpN` address, matching the reference's
  `/* floating point constants */` section.
- **Comparisons**: `selcmp` folds 12-bit `cmp`/`cmn` immediates and swaps a
  constant left operand; `seljmp` merges a compare whose only use is the
  branch into a `Jjf` conditional jump (`acmp`/`afcmp` + `cset`/flags).
- **No `callable()` shortcut**: like the reference snapshot, call targets are
  materialised as ordinary operands (indirect `blr`).

## Notes

- The reference snapshot has no `Iplo24`/`Inlo24` classification impact
  (24-bit immediates fall through to the materialise path), matching the port.
- Validated byte-for-byte against `vendor/qbe/qbe -t arm64` (`-dI` dumps).
