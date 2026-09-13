# Test suite

This directory holds the `.ssa` inputs used by `compare.py` to verify the
MoonBit QBE implementation against the reference C QBE built from the pinned
snapshot in `tools/qbe-ref` (see below).
All 406 non-underscore files must compile identically on both implementations
for the default `amd64_sysv` target.

## Reference binary

`compare.py` locates the reference binary in this order:

1. the `QBE_REF` environment variable;
2. `tools/qbe-ref/obj/qbe(.exe)` — the pinned QBE snapshot shipped under
   `tools/qbe-ref`, built with `make -C tools/qbe-ref`;
3. `vendor/qbe/qbe(.exe)` and the legacy `qbe-master/obj_qbe.exe`.

The snapshot in `tools/qbe-ref` is the exact upstream version the port was
validated against byte-for-byte; the `vendor/qbe` submodule is a fork whose
emitted assembly intentionally differs, so do not use it for `--asm`
comparisons.

## ARM64 target

The pinned snapshot also supports `arm64` (`tools/qbe-ref/obj/qbe -t arm64`),
which is the byte-level oracle for the arm64 backend. Run:

    python compare.py --target arm64              # IR/debug dumps, 5684/5684
    python compare.py --target arm64 --asm         # assembly, 406/406
    python compare.py --target arm64 --asm -G m    # Mach-O labels, 406/406

The port matches the reference for every corpus file, including the handful
where the reference itself aborts (e.g. `dynalloc.ssa`); those fail
identically on both sides (empty stdout). An independent assembly gate is
available via `python tools/check_arm64_asm.py`, which runs clang's
aarch64 integrated assembler over the emitted output.

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
    python compare.py --asm               # compare -G e assembly (406)
    python compare.py --asm -G m          # compare -G m assembly (406)
    python compare.py --jobs 1            # single-worker (default 4)
    python compare.py test\programs\003_arr_max.ssa   # one file, all flags

Expected baselines: 5684/5684 (debug), 406/406 (`-G e`), 406/406 (`-G m`).

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
