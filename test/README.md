# Test suite

This directory holds the `.ssa` inputs used by `compare.py` to verify the
MoonBit QBE implementation against the vendored reference C QBE.
All 406 non-underscore files must compile identically on both implementations
for the default `amd64_sysv` target.

## Reference binary

`compare.py` locates the reference binary in this order:

1. the `QBE_REF` environment variable;
2. `vendor/qbe/qbe(.exe)`, built with `make -C vendor/qbe`.

The vendored submodule is the only reference implementation used by this
repository. If its output differs from historical snapshots, update the
expected baseline rather than maintaining a second reference tree.

## ARM64 target

The vendored binary also supports `arm64` (`vendor/qbe/qbe -t arm64`),
which is the byte-level oracle for target-independent IR/debug behavior. Run:

    python compare.py --target arm64              # IR/debug dumps, 5684/5684

The port matches the reference for every corpus file, including the handful
where the reference itself aborts (e.g. `dynalloc.ssa`). Assembly output is
validated independently because the vendored fork has different prologue,
label, and platform-emission policies than this port. The assembly gate is
`python tools/check_arm64_asm.py`, which runs clang's aarch64 integrated
assembler over the emitted output.

## Layout

- `*.ssa` — the 32 upstream QBE examples at the repository root.
- `core/` — generated arithmetic/compare/memory/conversion/constant tests
  (`arith` 86, `compare` 56, `mem` 18, `conv` 14, `const` 24).
- `fold/` — constant-folding / dead-code tests (23).
- `abi/` — argument/return ABI and call conventions (48).
- `isel/` — instruction-selection shapes (34).
- `regalloc/` — register allocation / spilling stress (17).
- `emit/` — output emission shapes, incl. float constants (15).
- `programs/` — 55 hand-written realistic programs (number theory, sorting,
  strings, floats, recursion, nested loops).

## Running

From the repository root:

    python compare.py                     # all debug flags x all tests (5684)
    python compare.py --cat programs      # only one category
    python compare.py --jobs 1            # single-worker (default 4)
    python compare.py test\programs\003_arr_max.ssa   # one file, all flags

Expected baseline: 5684/5684 for the default debug differential suite.

## Regenerating generated tests

    python tools\gen_tests.py
    python tools\gen_programs.py

`gen_programs.py` applies an internal SSA fix-up (renames duplicate
definitions, corrects phi predecessor labels incl. fall-through edges) so the
emitted files are valid strict SSA out of the box.

## Constraints honored by the generators

The reference binary rejects some inputs, so generated tests avoid:

- `sltof` with a word operand (use `swtof`; `sltof` needs a long).
- unsigned comparisons spelled `cs...` (use `cu...`, e.g. `cugew`).
- decimal-point literals in `data` (e.g. `d 1.5`); use raw integer bits.
- duplicate definitions and mislabeled phi predecessors (both reject at
  `-dA` ssacheck).
