# ARM64 backend audit 3 — target_arm64 vs vendor/qbe/arm64/*.c

Worker: arm64, shared task task-6. Baseline 2026-11-13, vendor/qbe 661ceb22.
Isolated build build/a3-arm64. Reconstructed by the Lead from the worker's
final message; doc content supplied by the worker.

Upstream read completely: arm64/all.h, targ.c, abi.c, isel.c, emit.c, plus the
shared util.c/all.h/main.c behaviour arm64 uses. Port: target_arm64/{abi,isel,
emit} (text backend); the port-only binary/object emitters are out of scope.

## Fixed defects (RED observed against the reference unless noted)

1. Huge-frame callee-save save/restore bypassed fixarg. For frames beyond the
   scaled immediate range the port printed `str x19, [x29, 70024]` while the
   reference materialises the address (mov/movk/add + str [x18]); C's prologue/
   epilogue loops go through emitins, so fixarg rewrites the slot. Fixed;
   corpus test/audit3_arm64_bigframe.ssa is byte-identical on arm64 and
   arm64_apple.
2. Frame/padding/slot arithmetic was Int32 where C is uint64: a >2GB frame
   emitted `stp x29,x30,[sp,--1894967264]!` and negative offsets; the reference
   emits the two-movk form and its 29-bit-wrapped slot. Fixed with Int64
   frame/padding and a single arm64_slot_off64 (Int32 wrapper kept only for the
   port-only binary emitter). Corpus: audit3_arm64_frame_bounds.ssa.
3. Direct call validation missing: `call thread $thr()` emitted `bl thr`
   (exit 0) while C dies with "invalid call argument". Transcribed C's
   condition (not a CAddr, thread bit, or nonzero offset) and kept quoted-name
   prefix skipping.
4. Dynamic-alloc size slot guard missing (util.c salloc): a stack-passed
   aggregate parameter used as alloc size compiled a stack address as the size;
   C rejects "unlikely alloc argument". Fixed in the isel alloc branch and
   fixarg applied to the Osalloc instruction as C sel() does.
5. Apple huge-frame store scratch text: C selects `fmov d31, x17` for a
   Kw-class store ("ds"[i->cls==Kw]); port always emitted fmov s31, w17.
   Transcribed (defensive C path, whitebox evidence only).

## Verified (current code)

Prior-round items 1-10 (HFA-before-dark/size classification, Cptr ninth
aggregate, env x9/bit14, incoming register mask, Apple narrow ABI/apple_extsb,
extern offset + Apple TLS resolver, large fixarg/materialisation (fixed here),
Apple function alignment 4, comparison swap table, dynamic-alloc guard (fixed
here)) re-checked: byte-identical on arm64 and arm64_apple on the corpus.

## Residual / not fixed

- Port-only emit_arm64_bin/obj defects from the prior audit (CAddr offset
  Int64->Int32 truncation, IP0/IP1 scratch clobbering, data/function pointer
  relocations, object reloc addend wrap, atomics offset/fp-register handling)
  are untouched and out of scope this round.
- Invalid-IR diagnostics differ (Ice vs C err/die); exit status is non-zero.
- Frames above C's own two-movk range are transcribed arithmetic, not validated.

## Verification

moon test target_arm64/{abi,isel,emit} 41/41; 87-file corpus assembly and 8
dump flagsets x 2 flavours 0 diffs except non-arm64 files
(audit3_types_nan.ssa data comment - fixed by the types owner; tls_link.ssa
transient section quoting - fixed by the Lead). The five new corpus files are
byte-identical on arm64, arm64_apple, amd64_sysv, amd64_win and rv64.
