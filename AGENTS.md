# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.

## No simplified implementations (project rule)

This project is a port: whenever upstream QBE (`vendor/qbe`) has an
implementation, the port must transcribe it, not re-derive it.

The rule exists because every re-derivation has been a bug source:

- `pinned` was hand-copied from `ops.h` and drifted, dropping `blit0`/`blit1`,
  so gvn deleted half of a blit; it is generated now;
- `cfg/alias.mbt`'s `fillalias` had dropped five things from `alias.c`
  (`loc.sz`, `store()`, the blit store, the plain-store bookkeeping, the Jretc
  guard and the phi-argument escape), and `mem` had grown a private second
  copy that drifted from it;
- Qiang implemented its own aggregate convention (hidden first argument plus
  `memcpy`) instead of emitting `function :type $f` and `ret %addr`, so its
  objects could not be linked against clang's;
- `typ_of` picked `:type` field kinds from member size, making a `double` an
  integer field, so an HFA return was read from x0/x1 instead of d0/d1.

Practical consequences:

1. Before writing a function, look for its counterpart in `vendor/qbe` and
   transcribe it, including the corner cases (unreachable blocks, empty
   blocks, `-1` sentinels, C's unsigned arithmetic).
2. Do not add conditions the C does not have. Three of the bugs above were
   'improvements' (a guard on `slot_load`'s `radd`, a skip for zero-use allocs
   in `promote`, an inferred fall-through jump in the parser).
3. Do not keep two copies of one algorithm. If a pass needs another package's
   helper, make it public instead of duplicating it; duplication drifts and a
   fix to one copy does not reach the other.
4. Hand-written tables are forbidden. Parse them from `vendor/qbe` with a
   generator in `tools/` (see `tools/gen_op_pinned.py`).
5. A deviation is allowed only if upstream has no counterpart (the object
   writer, the JIT, the interpreter, the extra targets), and then it needs its
   own tests.
6. When a mismatch is found, compare against the reference binary, not against
   the port: `cd vendor/qbe && make` builds it, and `compare.py` plus the
   oracle are the judges.