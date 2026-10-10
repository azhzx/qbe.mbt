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
  **Root cause (settled): this is the reference's own nondeterminism, not a
  port bug.** `limit` sorts the candidate temporaries with `qsort`, and when
  the spill costs tie the comparator returns 0, so the order - and therefore
  which temporaries get spilled - is whatever the C library's `qsort` happens
  to do. Our port uses MoonBit's `Array::sort_by`, which is *also* an unstable
  sort. Two unstable sorts agree on every one of the 420 corpus inputs (the
  arm64 assembly differential is 420/420 with the port as it stands) but part
  company on a handful of tie-heavy stress inputs.

  Evidence:
  - instrumenting `limit` on both sides shows the same input set, the same
    `k`, the same empty `fst`, and different sorted orders: the reference
    produces `16 15 67 ... 79 81 66` where we produce the collected order
    `15 16 66 ... 79 81`, so a different temporary is spilled;
  - rebuilding the reference with a *stable* insertion sort in place of
    `qsort` (Apple's is unstable there) makes it **byte-identical** to the
    port at `-dS` for the 15..32 argument repros - zero differences;
  - conversely, making *our* sort explicitly stable is not an option: it
    changes which temporary is spilled and drops the corpus arm64 assembly
    differential from 420/420 to 71/420.

  So the port matches the reference on the whole corpus, and the divergence
  is confined to inputs that tie on spill cost. Matching those would mean
  reimplementing one specific libc's `qsort` (Apple's locally, glibc's in
  CI), which would make the compiler's output depend on the build host - the
  opposite of what a byte-exact port wants. The three inputs stay
  `_`-prefixed, and anyone who wants to verify them locally can rebuild the
  reference with a stable sort.

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
