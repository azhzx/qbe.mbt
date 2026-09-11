# `spill` Package API Reference

Package path: `azhzx/qbe/spill`

Register Spilling. When register pressure is too high, selects some temporary variables to spill to stack slots, loading them back into registers when needed. Contains two steps: spilling cost estimation and actual spilling. Corresponds to `spill.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/spill.md)

## 1. Cost Estimation - `fillcost`

```moonbit
pub fn fillcost(
  @types.Fn,
  Bool,                  // -dS debug switch
) -> String
```

Computes and writes the `cost` field for each `Tmp`:

- **Use cost**: +1 for each use point, -1 for definition point (approximate);
- **Loop weighting**: cost inside loops is amplified by `10^loop_depth`;
- **Register class**: computed separately for `Kw`/`Kl` (word) and `Ks`/`Kd` (double) channels, corresponding to register counts `NGPS`/`NFPS`.

Higher `cost` temporary variables are more worth keeping in registers; lower cost ones are more worth spilling. Returns `-dS` debug text.

## 2. Spilling - `spill`

```moonbit
pub fn spill(
  @types.Fn,
  Bool,                  // -dS debug switch
  @util.Interner,
  Array[@types.Typ],
) -> String
```

`spill` performs the following work:

1. Checks if the liveness count at each basic block boundary (`nlive_w`/`nlive_d`) exceeds the available register count (`NGPS=9`/`NFPS=15`);
2. If exceeded, inserts `copy` to/from new stack slots (`RSpill`) at the corresponding positions;
3. Spilled temporary variables are loaded before their original use points and stored after their original definition points;
4. Recomputes live sets, iterating until convergence.

If one round of spilling is still insufficient, it continues iterating (worst case: spill all non-loop-invariant temporaries).

## Typical Calls

```moonbit
@util.eprint(@live.filllive(fn_, dbg.l))      // must compute liveness first
@util.eprint(@spill.fillcost(fn_, dbg.s))     // estimate cost
@util.eprint(@spill.spill(fn_, dbg.s, interner, typs))  // perform spilling
@util.eprint(@rega.rega(fn_, dbg.r, interner, typs))    // then register allocation
```

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- `spill` is an **iterative** process: each insertion of spill code changes the live sets, requiring `live.filllive` to re-analyze.
- The number of stack slots used by spilling is accumulated via `Fn.slot`, ultimately affecting stack frame size, written into the function prologue by the `emit` phase.
- In the original QBE project, the spill algorithm is inspired by Pan, Andersson, et al.'s linear scan approach, but simplified to cost-based local selection.
