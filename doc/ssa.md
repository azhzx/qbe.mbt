# `ssa` Package API Reference

Package path: `azhzx/qbe/ssa`

SSA (Static Single Assignment) construction and optimization. Contains use chain maintenance, memory optimization (memopt), load elimination (loadopt), copy propagation (copy), phi insertion and block renaming, SSA validity checking. Corresponds to `ssa.c` / `mem.c` / `load.c` / `copy.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/ssa.md)

## Use Chain - `filluse`

```moonbit
pub fn filluse(@types.Fn) -> Unit
```

Scans all phi/ins/jmp, maintaining a `uses` list, `ndef`/`nuse` counts for each `Tmp`. Must be re-called after any change to CFG or instructions. Corresponds to `filluse()` in C.

## Memory Optimization - `memopt`

```moonbit
pub fn memopt(@types.Fn) -> Unit
```

Counterpart of `mem.c`. Eliminates redundant alloc/load/store (e.g., replacing a `load` from memory allocated by `alloc` with the corresponding SSA temporary variable). Called once before SSA construction. The `-dM` debug output prints the state after memopt.

## SSA Construction

```moonbit
pub fn phiins(@types.Fn) -> Unit     // insert phi nodes at dominance frontiers
pub fn renblk(@types.Fn) -> Unit      // block and variable renaming, establish SSA form
pub fn ssacheck(@types.Fn) -> Unit    // validity check (debug assertion, throws Ice on problems)
```

Typical sequence:

```moonbit
@cfg.filldom(fn_)
@cfg.fillfron(fn_)
@util.eprint(@live.filllive(fn_, false))   // pre-ABI liveness analysis (no dump)
@ssa.phiins(fn_)                            // insert phis
@ssa.renblk(fn_)                            // renaming
@ssa.filluse(fn_)                           // rebuild use chains
@ssa.ssacheck(fn_)                          // verify
```

## Load Elimination - `loadopt`

```moonbit
pub fn loadopt(@types.Fn, Bool, @util.Interner, Array[@types.Typ]) -> String
```

Counterpart of `load.c`. Identifies eliminable loads (same basic block, no intervening store to same address), replacing them with the result of the previous load. The `Bool` parameter is the `-dM` debug switch; when `true`, the dump text is returned as the output string (same pattern as `copy`/`fold`).

## Copy Propagation - `copy`

```moonbit
pub fn copy(@types.Fn, Bool, @util.Interner, Array[@types.Typ]) -> String
```

Counterpart of `copy.c`. Identifies the transitive closure of `copy` instructions, merging equivalent temporary variables. Corresponds to `-dC` debug output.

## Length Queries

```moonbit
pub fn loadsz(@types.Ins) -> Int    // byte count read by this load instruction
pub fn storesz(@types.Ins) -> Int   // byte count written by this store instruction
```

## Helpers

```moonbit
pub fn kcode(@types.Class) -> Int   // class -> hardware encoding
pub fn kx() -> Int                  // Kx class encoding
pub fn phicls(Int, Array[@types.Tmp]) -> Int   // determine phi's class
pub fn clsmerge(@ref.Ref[Int], Int) -> Bool     // class merge helper
```

## Debug Output Convention

`loadopt`, `copy` both return `String`:
- Debug mode (`Bool = true`): returns text to output to stderr;
- Non-debug mode: returns empty string.

The caller uses `@util.eprint(...)` in [cmd/main/main.mbt](../cmd/main/main.mbt), so non-debug mode is effectively a no-op.

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`
- `moonbitlang/core/ref` (used for `clsmerge`'s mutable reference)
