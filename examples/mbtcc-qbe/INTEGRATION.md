# mbtcc -> qbe.mbt integration

Status: **work in progress (P0, blocked on a front-end migration)**.

## Goal

Replace mbtcc's code generator (currently MoonLLVM) with the qbe.mbt
programmatic QBE IL builder (`azhzx/qbe`, package `ir_builder`) and link the
result through the in-process `emit_object()` Mach-O arm64 object emitter.
This is a real-world exercise for the qbe.mbt builder.

Decisions:

- vendored into this repository (this directory), module name kept as
  `Kaida-Amethyst/mbtcc`;
- the LLVM codegen is replaced (not kept side by side);
- in-process `emit_object()` + `clang` linking;
- arm64 macOS only for now.

## Provenance

- upstream: <https://github.com/moonbitlang/mbtcc>
- commit: `39d58ef3a405f1118199cace27e4d7f6d2a6f7b6`
- licenses: mbtcc Apache-2.0, chibicc MIT (see `LICENSE`, `chibicc/LICENSE`,
  `NOTICE`).

No source changes have been made yet; this is the pristine upstream tree.

## Blocker (why the codegen swap has not started)

mbtcc targets an older MoonBit and does **not** build with the qbe.mbt
toolchain (moonc v0.10.14). `moon build` reports 493 errors, concentrated in
two places:

1. **Old dependency versions** - `moonbitlang/x@0.4.38` and friends no longer
   compile (`moonbitlang/x/path/win32/*`, `Yoorkin/trie`, ...).
2. **Old `lexmatch` syntax** - string patterns are rejected; the current
   compiler requires anchored regex patterns, e.g.:

   ```
   lexer/number_literal.mbt:40:7  Parse error, unexpected token string, you may expect regex
   lexer/lexer.mbt:460:6         Parse error, unexpected token string, you may expect regex
   [4218] Regex patterns ... must be anchored at the beginning of the input
   ```

The 400+ errors are mostly **cascades** from these two roots. Reproduce with:

```sh
cd examples/mbtcc-qbe
moon update
moon build
```

## Remaining plan

| Phase | Work |
| --- | --- |
| P0a | Migrate `lexmatch` patterns to the anchored regex syntax (`lexer/`) |
| P0b | Bump/replace dependencies (`moonbitlang/x` -> 0.5.5, drop `MoonLLVM`, revisit `path`/`ArgParser`) |
| P1 | New `codegen/` over `ir_builder::Builder`; `int main(){return 42;}` -> `emit_object()` -> clang link |
| P2 | Expressions, locals, arithmetic, comparisons, assignment, casts |
| P3 | Statements, control flow, functions/calls, `switch` lowered to branches |
| P4 | Pointers, arrays, structs, globals, strings, `sizeof` |
| P5 | Run the `ctest/` passing list; delete the MoonLLVM code and dependency |
| P6 | `test_qbe.sh`, CI job, docs |

See the PR description for the full plan and status.
