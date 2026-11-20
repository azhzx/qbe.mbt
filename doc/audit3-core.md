# Core optimisation audit 3 — cfg/alias/ssa/load/copy/gvn/gcm/fold/ifopt/simpl

Worker: core, shared task task-3. Baseline 2026-11-13, vendor/qbe 661ceb22,
binary vendor/qbe/qbe. Isolated build build/a3-core. Reconstructed by the Lead
from the worker's final message.

Upstream read completely: cfg.c, alias.c, ssa.c, load.c, copy.c, gvn.c, gcm.c,
fold.c, ifopt.c, simpl.c, plus the util.c helpers. Port files: cfg/*, ssa/*,
fold/*, gvn/*, ifopt/*. Prior notes doc/audit-2026-11-08-core.md used as leads.

## Fixed / changed

1. cfg/alias.mbt fillalias: the final phi-argument escape loop walked every
   stored block, including blocks pruned from the CFG; C walks the start link
   chain (reachable blocks only). A phi argument in a dead block could mark a
   live alloc slot AEsc and change escapes()/load merging. Now iterates
   fn.def_order. Regression: cfg/audit3_core_wbtest.mbt.
2. cfg/simplcfg.mbt: C ends simplcfg with fillcfg (fillrpo+fillpreds+fixphis);
   the port called only fillrpo+fillpreds, so a phi argument whose predecessor
   edge a rewrite removed could survive. Now calls fillcfg. No reference-pipeline
   trigger was found (the existing alias walk also redirects folded phi args),
   so this is a completeness/transcription fix; an invariant test pins
   rpo_id==index and phi-arg edge consistency.
3. gvn/gcm.mbt igroup: C util.c groups a sel1 run into the preceding sel0
   (and a sel0 with following sel1s); the port returned each instruction alone.
   GCM runs before if-conversion in the reference pipeline, so the grouping was
   not reference-observable, but it is part of the transcription. Test added.
4. ifopt/ifopt.mbt: removed a ~175-line duplicate IL printer (dump_fn/
   class_char/jump_name) and the stale placeholder-op comments; the -dK dump
   now uses @parser.printfn (the single printer), matching C. No valid-IR
   output change (57-file corpus -dPMNCK identical).

## Confirmed but not fixed (test-only duplicates, reported for the Lead)

- ssa/memopt.mbt is a drifted second copy of mem/promote (production uses
  @mem.promote; only test helpers call memopt). Drift: Ice vs C error for
  read-before-write, k/2 base compare, Class::from_code(-1), no -dM output.
- fold/fold.mbt is an old SCCP pass with no counterpart in the vendored
  fold.c (whose functions live in gvn.mbt); production never calls it but test
  helpers do. fold/opfold.mbt duplicates gvn.mbt's c_fold* (two copies of one
  algorithm); its CAddr result uses add_con instead of C newcon interning.
- ssa/load.mbt load()/LLoad odd-slice and symbol-bit branches are unreachable in
  the current pass order (fillloop runs after loadopt, so b->loop==0 and no
  fresh load is ever inserted); documented, not changed.
- Rule-4 gap: the GVN optab flag predicates (commutes/assoc/hasid/idval/idemp/
  cmpeqwl/cmplgtewl/eqval, extcpy_width, width maps) are hand-written; every
  entry was checked against ops.h (0 diffs) but should be generated.

## Verification

moon test cfg/gvn/ifopt 56/56; 57-file corpus -dPMNCK 0 diffs; new corpus files
(test/audit3_core_{cfg,load,gvn,simpl,ifconv}.ssa) -dPMNCKGA 0 diffs on
amd64_sysv/arm64/rv64; baseline 489-check sweep 0 diffs pre-edit. The Lead
re-ran compare.py over the whole corpus after integration (see the ledger).
