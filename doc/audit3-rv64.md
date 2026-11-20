# RV64 backend audit 3 — target_rv64 vs vendor/qbe/rv64/*.c

Worker: rv64, shared task task-7. Baseline 2026-11-13, vendor/qbe 661ceb22,
binary vendor/qbe/qbe. Isolated build build/a3-rv64. Reconstructed by the Lead
from the worker's final message; doc content supplied by the worker.

Upstream read completely: rv64/all.h, targ.c, abi.c, isel.c, emit.c, plus the
shared util.c helpers (salloc, stashbits via types/fpstash, emitfnlnk).
Port: target_rv64/{abi,isel,emit,emit/data}.

## Fixed defects (each reproduced RED against the reference)

1. Negative symbol offset printed as `g-8` instead of C's `g+-8` in emitaddr
   and in loadaddr's tprel/lla offset string (C uses "+%PRIi64" unconditionally).
   Corpus: test/audit3_rv64_neg_sym.ssa.
2. selpar numbered and ordered Cfpint casts outside C's parameter loop (float
   arg passed in a GPR after 8 FP args, mixed with an aggregate parameter):
   -dA dumps and asm diverged. Transcribed the per-parameter loop (cast emitted
   with sttmps/stkblob, rewrites *c->cls and i->to). Corpus:
   test/audit3_rv64_abi_cfpint.ssa; 500 generated ABI cases 0 diffs.
3. Dynamic alloc accepted a size temporary that already owns a stack slot; C
   util.c salloc rejects "unlikely alloc argument". Fixed (isel wbtest).
4. fixarg hard-coded Kl for the Oaddr it materialises; C uses the operand class
   k for both newtmp and Oaddr. Fixed (wbtest).
5. Oaddr -2048 boundary: C's `if (-s < 2048)` one-instruction form means
   s > -2048, so -2048 uses li+add; the port's 12-bit test used add. Fixed;
   corpus test/audit3_rv64_oaddr.ssa.
6. C typclass err() was a MoonBit panic for `align 32` aggregate parameters
   (exit 134) instead of a clean error (exit 1); raise threaded through
   fpstruct/typclass/argsclass/selret/selcall/selpar/abi_rv64.
7. Removed the unused second copy of C emitdat in target_rv64/emit/data.mbt
   (gasemitdat_rv64; dead, shared gasdata is the single implementation).

## Adaptation kept (documented, deliberate)

For Oaddr with s >= +2048 C prints an out-of-range 12-bit immediate
(`add r, fp, 2048`), which no assembler accepts (reproduced with a
263-parameter function). The port keeps the two-instruction li/add form; for
every offset where C's output is assemblable the bytes are identical. This is
the single intentional divergence in the domain.

## Verified rather than modified

rv64 imm table (ops.h V(1)), retregs/argregs, fpstruct/typclass/argsclass,
sttmps/ldregs, selret/selcall/selpar (after fix), selvaarg/selvastart, isel
fixarg/selcmp/sel/seljmp/rv64_isel, emit omap (80/80), rname, slot, emitaddr,
emitf, fixmem, loadaddr, loadcon, emitins, rv64_emitfn. ABI stress (700 cases,
0-22 scalar/aggregate params, calls, struct returns, varargs): 0 asm/dA/dI diffs.

## Residual / not claimed

- Shared packages (gasdata, types/fpstash, parser, cfg, simpl) only exercised
  through rv64-facing behaviour, not re-audited.
- No emitter unit regression for emitaddr/Oaddr boundaries (the corpus files
  cover them); Apple text flavours not re-checked for the new corpus files.
- Invalid internal IR diagnostics can differ from C err/die text.

## Verification

moon test target_rv64/{abi,isel,emit} 15/15 (+2 new isel tests 7/7);
compare.py --target rv64 16 staged flagsets 7280/7280 dumps, --asm 456/457 (the
one failure was types/fpstash, fixed by the types owner). New corpus files
byte-identical on amd64_sysv/arm64/rv64/amd64_win.
