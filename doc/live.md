# `live` Package API Reference

Package path: `azhzx/qbe/live`

Liveness Analysis. Computes in/out live sets for each basic block in an SSA function, and writes liveness count information back to `Blk`'s `nlive_w`/`nlive_d` fields. Corresponds to `live.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/live.md)

## Entry Point

```moonbit
pub fn filllive(
  @types.Fn,
  Bool,                  // -dL debug switch
) -> String
```

`filllive` performs the following work:

1. Allocates `gen_set`/`in_set`/`out_set` (`BSet?`) for each basic block;
2. Iterates backward in RPO to a fixed point, propagating live sets;
3. At each block boundary, counts word and double liveness, writing to `nlive_w`/`nlive_d` (used for subsequent register pressure estimation).

Return value follows the same convention as other phases: debug mode returns dump text (list of live temporaries at each block), non-debug mode returns empty string.

## Helper

```moonbit
pub fn liveon(
  @types.BSet,           // target block's in set
  Int,                   // current temporary variable id (start position)
  @types.Blk,            // target block
  @types.Fn,
) -> Unit
```

`liveon` marks all live temporaries in the specified set onto the target block, accumulating `nlive_w`/`nlive_d`. Used internally in SSA construction, register allocation, and other phases.

## Typical Calls

`filllive` is called **multiple times** during the compilation flow:

```moonbit
// 1. Before SSA construction (pre-ABI liveness analysis, C ssa() sets -dL=false)
@util.eprint(@live.filllive(fn_, false))

// 2. After instruction selection
@cfg.fillrpo(fn_)
@util.eprint(@live.filllive(fn_, dbg.l))

// 3. Final liveness analysis before register allocation (also called within spill/rega)
```

## Dependencies

- `azhzx/qbe/types`

## Notes

- Liveness analysis is based on **backward data flow**: propagating upward from exit.
- `gen_set` is preserved once first built; subsequent calls only recompute in/out — this is QBE's optimization strategy to avoid redoing full work each time.
- `nlive_*` fields determine spill phase cost evaluation (more live = more likely to spill).
