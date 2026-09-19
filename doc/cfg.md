# `cfg` Package API Reference

Package path: `azhzx/qbe/cfg`

Control Flow Graph (CFG) analysis. Computes predecessors, reverse postorder, dominators, dominance frontiers, loop depth, alias information, and other structural properties on `Fn`'s `blks` array, used by SSA, live, spill, rega, and other subsequent phases. Corresponds to `cfg.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/cfg.md)

## Main Functions (in main.c call order)

| Function | Purpose |
| --- | --- |
| `fillrpo(@types.Fn) -> Unit` | Compute reverse postorder (`rpo` array and each block's `rpo_id`) |
| `fillpreds(@types.Fn) -> Unit` | Fill each block's `pred` and `npred` from `jmp.s1/s2` |
| `filldom(@types.Fn) -> Unit` | Compute immediate dominators (`idom`), build dom tree (`dom_link`/`dom_next`) |
| `fillfron(@types.Fn) -> Unit` | Compute dominance frontiers (`fron`) |
| `fillloop(@types.Fn) -> Unit` | Mark loop back edges, compute each block's `loop_depth` |
| `fillalias(@types.Fn) -> Unit` | Alias analysis, fill `alias_info` for each temporary variable |
| `simpljmp(@types.Fn) -> Unit` | Jump simplification: merge `jnz`/`jmp` that jump to the next block (RPO) |

Typical call order (see [cmd/main/main.mbt](../cmd/main/main.mbt)):

```moonbit
@cfg.fillrpo(fn_)       // 1. reverse postorder
@cfg.fillpreds(fn_)     // 2. predecessor list (recompute after any CFG rewrite)
@cfg.filldom(fn_)       // 3. dominators
@cfg.fillfron(fn_)      // 4. dominance frontiers (used for SSA construction)
...
@cfg.fillloop(fn_)      // 5. loop detection (affects register allocation priority)
@cfg.fillalias(fn_)     // 6. alias analysis
```

## Dominator Tree Queries

```moonbit
pub fn dom(@types.Fn, Int, Int) -> Bool    // does i dominate j
pub fn sdom(@types.Fn, Int, Int) -> Bool    // does i strictly dominate j
```

## Loop Iteration

```moonbit
pub fn loopiter(@types.Fn, (Int, Int) -> Unit) -> Unit
```

Iterates over all loop back edges `(head, latch)`, calling the callback for each pair.

## Alias Queries

```moonbit
pub fn getalias(@types.Ref, @types.Fn) -> @types.AliasInfo
pub fn escapes(@types.Ref, @types.Fn) -> Bool
pub fn AliasType::astack() -> Bool
pub fn check_alias(@types.Ref, Int, @types.Ref, Int, @types.Fn) -> (AliasResult, Int64)
```

`AliasResult` values:
- `MustAlias` - two references definitely point to the same address
- `MayAlias` - possibly aliased (conservative estimate)
- `NoAlias` - definitely not aliased

`check_alias(r1, sz1, r2, sz2, fn)` returns both the alias relationship and byte offset.

## CFG Editing

```moonbit
pub fn edgedel(@types.Fn, Int, Int) -> Unit
```

Deletes edge `i -> j`, updating predecessor/successor information accordingly. Use with caution, typically only called within optimization phases.

## Types

```moonbit
pub enum AliasResult { MustAlias; MayAlias; NoAlias }
```

## Dependencies

- `azhzx/qbe/types`

## Notes

- All `fill*` functions **mutate** `Fn`'s fields in place, not returning new objects.
- `fillpreds` needs to be recomputed after every CFG rewrite (e.g., phi insertion, post-register-allocation simplification).
- `fillrpo` traverses by linked list order when `def_order` is established, otherwise by block array index (used in unit tests).
