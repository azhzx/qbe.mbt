# AMD64 backend audit 3 — target_amd64 vs vendor/qbe/amd64/*.c

Worker: amd64, shared task task-5. Baseline 2026-11-13 (vendor/qbe 661ceb22).
Isolated build build/a3-amd64. Reconstructed by the Lead from the worker's
final message; doc content supplied by the worker.

Upstream read completely: amd64/all.h, targ.c, sysv.c, winabi.c, isel.c,
emit.c. Port: target_amd64/{abi,isel,emit}/*.

## Fixed defects

- D1 (transcription): C sysv selpar creates both register-chunk temporaries
  with class Kl and emits the copies with the eightbyte class (a->cls[0/1]);
  the port created the temporary with a->cls[n] and then re-read Tmp.cls as the
  copy class. Tmp.cls drives live.c nlive buckets, rega ralloctry/hints and
  pmadd; now the C form. New abi whitebox test (temp class Kl, copy class the
  eightbyte class).
- D2 (crash on valid IL): an aggregate whose eightbytes classify as Kx (dark
  type) reached emitf's %k and indexed clstoa out of bounds (C is undefined
  here; the port panicked with a stack trace, exit 134). Now raises
  QbeError::Ice("invalid instruction class"), exit 1. Trigger
  `type :dk = align 8 { 16 }`, `type :st = { :dk }`.

## Verified rather than modified

- all.h enums/tables (register numbers, NFPR/NGPS/NCLR/win tables), Amd64Op
  nmem/zf/lf, targ.c, isel.c (fixarg/seladdr/selcmp/sel/selsel/seljmp/opn/refn/
  anumber/adisp/amatch/amd64_isel) and emit.c (E/CMP/omap/cmov/rname/slot/
  emitcon/emitf/negmask/emitins/framesz/emitfn/winabi) all read and compared.
- All tables checked mechanically against C with scripts: omap (68 entries),
  ctoa/cmov (CMP macro), rname, clstoa, addr Oaddtbl (91), match[], the six
  matcher bytecode arrays -> 0 diffs. Only flag+13/14 differ, where C has
  unreachable "set?" placeholders and the port has setbe/setb (unreachable in
  both: sel/seljmp/selsel canonicalise Cfle/Cflt via cmpswap+cmpop).
- Prior-note gaps re-verified fixed: Apple TLS in isel+emit, @plt suppression,
  fast-local operand rejection, seladdr non-RTmp bailout, fsz Int64, uint AClass
  fields, cmpneg-vs-ctoa equivalence, addr.mbt matcher transcription.

## Residual / not fixed

- F2 (policy, rule 4): amd64 tables are hand-copied (verbatim equal today), not
  produced by a generator in tools/.
- F3 (policy, rule 3): salloc is inlined in every backend's isel while C has one
  util.c salloc.
- Dark-type aggregates: C reads uninitialised Typ fields (UB); the port reports
  an ICE. Invalid-IR diagnostics differ in text; valid-input output is covered
  by the differential gates.

## Verification

moon test target_amd64/{emit,abi,isel} 76/76; corpus dump/asm differential via
compare.py (Lead, final run in the ledger); dedicated sweeps 884 + 741 checks
0 failures; mutation fuzz seeds 7002/9101, 0 diffs/crashes.
