# `isel_la64` Package API Reference

Package path: `azhzx/qbe/isel_la64`

[中文版本 (Chinese Version)](zh/isel_la64.md)

LoongArch 64 (la64) instruction selection: checks constants, materializes
immediates, exposes machine register constraints, and assigns slots to fast
allocs.

## Entry Point

```moonbit
pub fn isel_la64(
  @types.Fn,             // function to select (modified in place)
  @util.Interner,        // string interner
  Bool,                  // debug switch (-dI dump)
  Array[@types.Typ],     // global type table
) -> String raise
```

## Differences from the rv64 port

The driver follows the amd64 pattern: block instructions are processed in
**reverse** order and the selection buffer is written back (reversed) into
the block. The rv64 port discarded the buffer (isel was effectively inert);
la64 implements the write-back from the start.

- **Comparison lowering**: LoongArch has no flags register; all 20 integer
  comparisons lower to `slt`/`sltu` + `xor`/`copy` sequences (word compares
  unify to the long forms — QBE keeps `Kw` values sign-extended, so 64-bit
  compares are equivalent).
- **Constant materialization**: integer constant operands are materialized
  into registers for every op except `Copy` (LoongArch ALU/compare
  instructions have no immediate forms); float constants go to `fp_stash`
  and are loaded (`fld`) into a fresh FPR immediately.
- **Aggregates**: constant-size `Alloc4/8/16` become slots; dynamic ones
  generate `salloc` plus an alignment sequence.

## Notes

No upstream C reference, no differential baseline; behavior is pinned by the
lowering-sequence assertions in `isel_la64_wbtest.mbt` and the e2e snapshots.
