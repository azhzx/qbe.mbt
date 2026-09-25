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

## Cross-target verification

`compare.py` compares any of the three backends against the vendored
reference:

    python compare.py --target arm64              # arm64 debug dumps
    python compare.py --target rv64 --asm         # rv64 assembly

The port is byte-for-byte identical to the reference on all three targets
(amd64_sysv, arm64, rv64), for both the debug-dump differential suite
(`compare.py`, every `-d` flag) and the emitted assembly
(`compare.py --asm`) on all 406 tests (406/406 per target).
`tools/check_arm64_asm.py` and `tools/check_rv64_asm.py` additionally run
clang's integrated assembler over the emitted output as an independent gate.

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

    python compare.py                     # all debug flags x all tests
    python compare.py --cat programs      # only one category
    python compare.py --jobs 1            # single-worker (default 4)
    python compare.py test\programs\003_arr_max.ssa   # one file, all flags

Expected baseline: every case passes for the default debug differential
suite. `compare.py --asm` must also be byte-identical for each target.

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
