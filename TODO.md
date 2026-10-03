# TODO / known issues

Tracked after the `feat/qpcc` self-host work: the QPCC-built `qbe` now passes
all 58 `examples/qpcc-selfhost/semantic-check.sh` fixtures, and the debug / asm
differentials stay 4908/4908 (amd64, arm64, rv64) and 409/409 (arm64 asm).

## Testing gaps

- **The object-emission path has no differential gate.**
  The arm64 differentials compare assembly text (`compare.py --target arm64
  --asm`, mapped to the reference's `arm64_apple`), but the self-hosted
  `qbe` is produced through `compile_ir_object` / `emit_arm64_object`.
  Commit `9203880` fixed a bug that existed only in the object emitter (the
  IP1 scratch was mapped twice) and was invisible to every gate. Suggested
  gate: compile the corpus with `--emit obj`, disassemble the result and
  compare against the reference, or run the QPCC self-host build as a CI job.

## Known divergences from the reference

- **The `arm64` target is missing the reference `arm64_apple`'s "Apple
  pre-ABI" pass.** The reference's `-dA` dump has an "After Apple pre-ABI"
  section, and its `-dL`/`-dS` dumps contain extra `abi.*` temporaries our
  port does not emit. It shows up on large inputs (e.g. the IL of
  `vendor/qbe/rega.c`) but not on the differential corpus, so it does not
  affect 4908/4908 or the self-host semantic-check. It is a real difference
  from the reference and should be ported.

## C2y (`-std=c2y`)

- `_Defer` diagnoses a jump out of its own statement and a `goto` into it,
  but a `longjmp` past a defer is left undefined (as the TS says) and is not
  diagnosed.
- clang implements `_Countof` but not `_Maxof`/`_Minof`, named loops or
  `_Defer`, so `maxminof.c`, `named_loops.c`, `defer_basic.c` and
  `defer_header.c` are QPCC-only (`// expect-exit N`) and are checked
  against their expected exit code instead of a clang reference.
- `<stdmaxof.h>`/`<stdminof.h>` are QPCC extensions (no WG14 proposal
  defines them), unlike `<stdcountof.h>` (N3469) and `<stddefer.h>`
  (TS 25755).

- `_Tagged_union`: a member read used in an arithmetic expression is not yet
  reliable (e.g. `(int)(v.as_float * 2.0f)` gives 0 while the same float read
  in a comparison is correct). Reads, comparisons, tag stores and
  initializers all work; the arithmetic path needs a look at how
  `TTaggedMember` feeds a float binary op.
- Pre-existing, unrelated to `_Tagged_union`: a 16-byte struct containing a
  `double` is passed by value incorrectly (8- and 12-byte structs are fine,
  and clang agrees on the 16-byte case).


## Latent risk

- The byte-identical differentials only cover the corpus under
  `vendor/qbe/test`. Inputs outside it — in particular the IL QPCC's front end
  produces for the QBE C sources — can still expose latent backend differences;
  the `260d556` / `9203880` pair was exactly such a case, so treat the
  self-host build as an integration test.
