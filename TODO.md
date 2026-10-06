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

  pre-ABI" pass.** The reference's `-dA` dump has an "After Apple pre-ABI"
  section, and its `-dL`/`-dS` dumps contain extra `abi.*` temporaries our
  port does not emit. It shows up on large inputs (e.g. the IL of
  `vendor/qbe/rega.c`) but not on the differential corpus, so it does not
  affect 4908/4908 or the self-host semantic-check. It is a real difference
  from the reference and should be ported.

- **Spill slot numbering diverges once register pressure is high enough.**
  `test/stress/_002_wide_300.ssa`, `_006_args_w_32.ssa` and
  `_009_calls_160.ssa` differ from the reference at `-dS` on all three
  targets (and in the emitted assembly): the two agree on the *number* of
  slots but assign different numbers and orders. The existing
  `test/regalloc/` inputs pass, so this is a regime the corpus did not reach.
  Repro: `python compare.py -dS test/stress/_006_args_w_32.ssa`. The three
  files are `_`-prefixed so they stay out of the exact differential until the
  pass matches.
  Narrowed so far: the two implementations agree on `limit`'s input and
  output sets *and* on the order `slot()` is called in (verified with matching
  instrumentation on both sides), so the difference is upstream of the rewrite,
  in the per-block live-set computation inside `spill` (`dopm` / `merge` /
  the section-2 instruction scan). It is a tie-break among temps whose spill
  cost is equal, not a wrong result, and swapping the reference's unstable
  `qsort` for a stable sort does *not* remove it, so there is a real
  algorithmic deviation to find. Cost is all-equal here, which is why
  `test/regalloc/` never hit it.
  Localized to a single instruction: with the 16-word-argument repro, the
  first difference in `callee_w` (a one-block function, so section 1 is
  trivial) is at instruction 17. The live set after it is
  {15,16,67..79,81} for the reference and {15,16,66..79} for us: the reference
  turns arg[0] (temp 66) into a slot and keeps 81 live, we keep 66 and see no
  second operand. Every instruction up to and including 16 agrees, as does
  `to=82` at 17, so the two agree entering the scan and part company inside
  it. When aligning dumps: C's `i->op` is an optab index while our
  `Op::index()` is a different numbering, and `st.buf` is the *output*
  buffer, not `b.ins` - compare the block's input instruction stream.

- **`test/stress/_006_args_w_32.ssa` makes the emitter ICE.** Plain
  assembly emission (no `-d` flag) fails with `ICE: invalid second
  argument`; the reference, and our own `-dS` dump, handle the input. Most
  likely the same high-pressure regime as the slot divergence above.
  Repro: `_build/native/debug/build/cmd/main/main.exe -t arm64 test/stress/_006_args_w_32.ssa`.

- **`test/_bfmandel.ssa` is ~16x slower than the reference** (1.14s vs 71ms
  at `-dR`, amd64), far outside the 1.2-1.7x the rest of the corpus shows.
  That input is the only one where the gap is not explained by process startup,
  so it is worth a profile. Repro:
  `python tools/bench.py --all test/_bfmandel.ssa`.

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


## Latent risk

- The byte-identical differentials only cover the corpus under `test/`
  (409 exact-differential inputs plus the `test/stress/` scale series).
  Inputs outside it — in particular the IL QPCC's front end
  produces for the QBE C sources — can still expose latent backend differences;
  the `260d556` / `9203880` pair was exactly such a case, so treat the
  self-host build as an integration test.
