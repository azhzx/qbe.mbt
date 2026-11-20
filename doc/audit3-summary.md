# Audit round 3 — summary (2026-11-13)

Baseline: port v0.44.0 worktree, vendored reference `vendor/qbe` revision
661ceb22 (binary `vendor/qbe/qbe`). Scope: every file/function/struct that has
an upstream counterpart, per-domain; port-only surfaces (wasm, la64, jit,
object writer, interpreter, ir_builder, dwarf, native/run_asm) were not audited
this round.

Method: seven workers (frontend, types/util, core passes, registers,
amd64, arm64, rv64) plus the Lead (driver/CLI/emit). Each built a declaration
inventory against the C, reproduced behaviour-affecting divergences against the
reference binary (RED), then transcribed the C (GREEN) and added a whitebox and/
or `test/audit3_*.ssa` regression. Per-domain reports:
`doc/audit3-{frontend,types,core,regs,amd64,arm64,rv64,driver}.md`; the
consolidated record is in `AUDIT-LEDGER.md`.

## Defects found and fixed (36)

Front-end: resultful blit and extra blit operands; NPred=63; resultful vastart
guard; data-ref offset newline; section presence/quoting and duplicate empty
sections; C99 nan(n-char-seq) payload bits; exact single-precision rounding for
dyadic midpoints; truncated-input parser panic; `argv` accepted as an op;
NIns=1<<20; two diagnostic texts.

Types/util: `fmt_fixed` printed `-nan` (host prints `nan`); fp-constant stash
identity was a byte-prefix compare instead of C's full-word `stashbits`
(changed pool labels/assembly); rule-3 consolidations (retregs/argregs,
loadsz/storesz in two places, sign_ext29 in four emitters, mem fuse width);
`Ref::rsval` added and used by the printers.

Core: fillalias phi-escape no longer walks dead blocks; simplcfg ends with
`fillcfg` (fixphis); gcm `igroup` sel0/sel1 groups; ifopt duplicate printer
removed (uses `@parser.printfn`).

Registers: `-dS` lost C's printf space flag for wide nlive/loop values (visible
on the stress series); one shared `util.fmt_space`; stale second mem alias table
removed.

amd64: sysv selpar aggregate-chunk temp class (Tmp.cls feeds liveness/regalloc);
`%k` with a Kx class is an error, not a panic; all hand-copied tables numerically
verified against C (0 diffs).

arm64: huge-frame callee-save through fixarg; uint64 frame/padding/slot math
(>2GB frames); direct-call validation; dynamic-alloc size-slot guard; Apple
large-store V31 scratch text.

rv64: negative symbol offsets printed `g+-8`; selpar Cfpint cast order/temp
numbering; dynamic-alloc size-slot guard; fixarg Oaddr class; Oaddr -2048
boundary; typclass align err() was a panic; dead duplicate emitdat removed.

Driver/CLI: `-t ?`; repeated -t/-o/-d/-G; `-t amd64_apple`/`-t arm64_apple`;
`-o` fopen-at-parse-time with `cannot open '<path>'`; input open message;
section verbatim emission; RInt/RSlot dumps through rsval.

## Verification (final tree)

- `moon test --target native`: **591/591** (all packages incl. run_asm with
  Apple clang on PATH).
- `compare.py` dump differentials: **7312/7312** on amd64_sysv, arm64, rv64 and
  both Apple flavours; **7264/7264** on amd64_win (documented reference-side
  TLS/thread aborts skipped). Assembly: **457/457** on amd64_sysv/arm64/rv64,
  **454/454** on amd64_win.
- `tools/check_all_backends.py` PASS (amd64/arm64/la64 386/386, rv64 385/386
  documented clang quoted-symbol, wasm 372/386 skips);
  `tools/check_la64_asm.py` 386/386; `tools/check_wasm.py` 372/372 valid, 0
  compile failures (port-only backends, not audited).
- Excluded/stress corpus (`test/_*.ssa`, `test/stress/*`): 1683 checks, 0 real
  diffs (`_009_calls_160.ssa` is invalid IL rejected by the reference too).
- Whole-corpus single invocation (255 valid files): byte-identical assembly on
  amd64_sysv/arm64/rv64, identical -dPMN dumps (session-state check).
- Mutation fuzzing (`tools/fuzz_il.py --asm`, seeds 701-703, 8101-8103): 0
  diffs/crashes/rejects; per-domain fuzz runs also clean.
- `moon fmt --check` and `git diff --check` clean; `moon info` only the intended
  interface changes (new raise, removed dead emitter helper, `fmt_space`,
  `sign_ext29`, `Ref::rsval`, Parser field).

## Explicitly not claimed / residual

- The reference streams partial output before a late parse error; the port
  parses first (valid-input output identical).
- Test-only duplicated implementations kept: `ssa/memopt.mbt` (drifted second
  promote), `fold/fold.mbt` (old SCCP, no vendored counterpart),
  `fold/opfold.mbt` (second copy of the gvn c_fold* helpers),
  `types.constant.Con::add` (simplified addcon, equivalent at its one call
  site).
- Rule-4 hand-written tables remain (gvn flag predicates, opinfo, Op/JumpKind
  index tables, cmpneg, target and emit tables, amd64 matcher bytecode); all
  were numerically verified against C this round, only `pinned` is generated.
- Rule-3 `salloc` is still transcribed per backend.
- Port-only backends: two pre-existing gaps are exposed by new regression
  inputs and are documented for the next round (not regressions from this
  round): the la64 emitter does not lower an `Ocopy` whose destination is
  RNone/a slot (prints `or , reg, $zero`), and the wasm emitter prints
  `f64.const NaN` (not WAT syntax). Their inputs are `_`-prefixed
  (`_audit3_regs_dbg_width.ssa`, `_audit3_arm64_spill_huge.ssa`,
  `_audit3_types_nan.ssa`) per the repository convention.
- Invalid-input diagnostics are not byte-identical in general (Ice vs C
  err/die text; error-position differences); valid-input behaviour is what the
  gates cover.
