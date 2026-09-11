# `rega` Package API Reference

Package path: `azhzx/qbe/rega`

Register Allocation. After spilling, binds each virtual temporary variable to a specific physical register. Corresponds to `rega.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/rega.md)

## Entry Point

```moonbit
pub fn rega(
  @types.Fn,
  Bool,                  // -dR debug switch
  @util.Interner,
  Array[@types.Typ],
) -> String
```

`rega` performs the following work:

1. **Graph coloring**: Based on liveness sets computed by the `live` package, builds an interference graph (edges between simultaneously live temporary variables).
2. **Priority sorting**: Sorted by `cost` (already computed in spill phase) and `hint` (register hints, e.g., return values favor RAX).
3. **Register selection**: Greedy color selection (first available non-conflicting register), updating each `Tmp`'s `slot` field to the physical register number.
4. **`copy` insertion**: At block boundaries, if temporary variables on both sides are assigned to different registers, inserts `copy` instructions to synchronize at block boundaries.
5. **`Fn.reg` mask**: Accumulates all used registers into the `Fn.reg` mask, used by the emit phase to determine which callee-saved registers to save.

Returns `-dR` debug text: mapping of each temporary variable to its final register.

## Typical Calls

```moonbit
@util.eprint(@spill.spill(fn_, dbg.s, interner, typs))
@util.eprint(@rega.rega(fn_, dbg.r, interner, typs))
@cfg.fillrpo(fn_)        // rega may add block boundary copies, recompute
@cfg.simpljmp(fn_)       // simplify jumps
@cfg.fillrpo(fn_)
@cfg.fillpreds(fn_)
```

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- `rega`'s output is no longer "virtual" SSA: each `Tmp` has a concrete physical register (or `RSpill` indicating it has been spilled).
- Actual register numbers follow `types` package's `RAX=1`...`RSP=16`, `XMM0=17`...`XMM15=32`.
- If `rega` still cannot allocate (spill not aggressive enough), it throws `Ice` indicating an internal error.
