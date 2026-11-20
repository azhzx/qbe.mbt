# Shared types/util audit 3 — all.h / ops.h / util.c / abi.c

Worker: types, shared task task-2. Baseline: 2026-11-13, vendor/qbe 661ceb22,
binary vendor/qbe/qbe. Isolated build build/a3-types. Reconstructed by the Lead
from the worker's final message.

Files read completely: vendor/qbe/all.h, ops.h, util.c, abi.c, the
type/constant/declaration parts of parse.c, plus libc printf/qsort behaviour the
reference links. Port files: types/ (op, opinfo, ref, tmp, ins, blk, fn, typ,
dat, constant, jump, class, bset, target*, dump, debug, data_string, cmpneg,
fpstash) and util/ (error, fmt, pad, print, qsort, sym, interner, debug).

Status: V verified, A adaptation, D divergence (fixed), M missing (none).

## Fixed defects

### TYPES3-1 fmt_fixed printed "-nan"; the reference host's printf prints "nan"
Valid input: the reference lexer accepts `s_-nan`/`d_-nan`. `qbe -dP` prints
`s_nan`/`d_nan`; the port printed `s_-nan`/`d_-nan`. Host printf verified with
cc: negative NaN prints "nan" (negative infinity keeps its sign). Fixed; corpus
test/_audit3_types_nan.ssa is byte-identical on amd64_sysv/arm64/rv64 for dumps
and assembly. This is the same host-libc choice already made for qsort.

### TYPES3-2 fp-constant stash deduplicated by byte prefix instead of C's full word
C emit.c stashbits reuses an entry iff `size <= b->size && b->n == n` (full
64-bit word). The port compared only the first `size` bytes, so a later 4-byte
constant whose word equals the low half of an 8-byte entry reused that entry and
one .Lfp pool label was lost. Trigger: double `d_0x1.000003f8p0` (low word =
1.0f) stashed before single `s_1.0`; reference emits .Lfp0 (8) + .Lfp1 (4) and
`addss ".Lfp1"`, port emitted only .Lfp0 and `addss ".Lfp0"`. Fixed in
types/fpstash.mbt; corpus test/audit3_types_fpstash.ssa identical on
amd64_sysv/arm64/rv64.

### Rule-3 consolidations
- types/target.mbt: amd64 retregs/argregs were a second body; now delegate to
  Ref::retregs/argregs (arm64/rv64 already did).
- types/opinfo.mbt: op_loadsz/op_storesz were a second body; now delegate to
  Ins::load_size/store_size (the single C load.c transcription).
- Lead: mem/mem.mbt's local loadsz/storesz removed, call sites use Ins methods;
  la64/rv64/amd64 emit sign_ext29 copies replaced by types.sign_ext29 (made
  public and used by Ref::rsval); mem/coalesce fmt_space3 use util.fmt_space.

### Added helper
- types.ref.Ref::rsval (C all.h rsval) and types.sign_ext29; parser/print.mbt
  and ir_builder/print.mbt now print RInt/RSlot through it (valid IL
  `dbgloc 268435456` dumps as `dbgloc -268435456` like the reference).

## Mechanical checks (all run)

1. Pinned table: tools/gen_op_pinned.py in a scratch copy produces bytes equal
   to gvn/op_pinned_gen.mbt (44 ops). No drift.
2. Optab vs ops.h: 157 upstream ops identical in a0/a1 classes, canfold and
   X(nmem,zf,lf); 5 port-only entries (atomicload, atomicstore, fence, vacall,
   asm). All 8 GVN flag predicates match the 10 F() columns; Op::index/from_index
   is a bijection consistent with optab order.
3. Op numeric order differs from C (port-only ops appended). All base+offset
   relations used in the code are contiguous and pinned by tests (A).
4. JumpKind absolute numbering differs from C (returns grouped); every use is
   name-based or Jjfieq/Jretsb-relative; is_ret/is_ret_bh equal to the C sets,
   pinned by tests (A).
5. Target constants: amd64/arm64/rv64 register numbers, rsave/rclob order, rglob,
   retregs/argregs bit layouts, Win64 tables and win_retregs quirk, TargetCfg
   all match targ.c/abi.c/all.h.
6. Con interning: con[0]=UNDEF (CBits 0xdeaddead), con[1]=zero, interning skips 0,
   identity = kind + bits.i + sym(label,sym_type), never flt; getcon compares
   CBits only. New whitebox test pins symbol-type identity.
7. util/qsort_c vs the host libc qsort: 1092 scenarios + 696 pathological cases
   (ties, all-equal, sorted, n up to 500) -> 0 permutation differences.
8. BSet rounding/range/iteration semantics: no divergence found.
9. fmt_fixed vs printf("%.6f") over 2054 values (subnormals, inf, NaN, +/-0,
   10^k, half-way decimals): all finite values identical, NaN sign fixed.
10. fmt_space (C "% wd") verified against cc.

## Residual / not claimed

- Ref::rint is not masked to 29 bits at construction (C INT() masks); all parser
  paths bound the value, programmatic IR could differ (rsval is now used by the
  printer).
- types/cmpneg.mbt is a semantic-negation table, not a C transcription
  (upstream has cmptab/cmpop/cmpwlneg); it equals C's CMP table for every
  condition the amd64 selector can emit. Kept, documented.
- types.constant.Con::add is a simplified addcon (no multiplier, no failure);
  used only by amd64 emit's slot-offset accumulation with a CBits multiplier-1
  operand, where it is equivalent. Kept, documented.
- Hand-written tables that are not generator-backed: Op::index/JumpKind::index,
  opinfo, cmpneg, target register tables (rule 4 gap); only pinned is generated.
- Port-only surfaces (la64/wasm target tables, data_string, debug) not audited.

## Verification

moon test -p types -p util 72/72; full amd64_sysv corpus -dPMNCAGK dumps and
assembly 0 diffs; new corpus files identical on arm64/rv64 too.
