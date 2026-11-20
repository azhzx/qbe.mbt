# Register pipeline audit 3 — live / spill / rega / mem

Worker: `regs`, shared task task-4. Baseline: port working tree at
2026-11-13 20:00 (mid-integration, other owners' files dirty), reference
`vendor/qbe` revision 661ceb22, binary `vendor/qbe/qbe`. Isolated target
dir `build/a3-regs`; binary
`build/a3-regs/native/debug/build/cmd/main/main.exe`.

Upstream files read completely: `vendor/qbe/live.c` (144), `spill.c` (531),
`rega.c` (700), `mem.c` (488), plus the `util.c` helpers they call
(`getalias`/`fillalias`, `loopiter`, `phicls`, `isreg`, `qsort`,
`dumpts`, `printfn`). Port files read completely: `live/live.mbt`,
`spill/spill.mbt`, `spill/fillcost.mbt`, `rega/rega.mbt`, `mem/mem.mbt`,
`mem/promote.mbt`, `mem/coalesce.mbt`. Prior notes
`doc/audit-2026-11-08-registers.md` and `doc/audit-2026-11-08-core.md` were
used as leads, not as proof; their claims were re-checked against the current
tree and the reference binary. No `vendor/qbe` file, no file outside this
worker's write scope, and no shared `_build` output was modified.

Status legend: **V** verified branch-by-branch against the named C
declaration; **A** safe representation adaptation, justified below; **D**
divergence (fixed ones listed with RED/GREEN evidence); **M** missing (none in
this domain).

## 1. Confirmed defect and fix: REGS3-FMT1 (-dS debug width)

**Symptom.** The staged spill debug dump (`-dS`) was not byte-identical to
the reference for wide values: `fillcost`'s loop information and the
post-spill block information lost C's printf space flag.

**C reference.**

* `vendor/qbe/spill.c:57-60` — `fprintf(stderr, "\t%-10s", b->name);`
  `fprintf(stderr, " (% 3d ", b->nlive[0]);` `fprintf(stderr, "% 3d) ", b->nlive[1]);`
* `vendor/qbe/spill.c:523-526` — `fprintf(stderr, "\t%-10s (% 5d) ", b->name, b->loop);`

The space flag is a *prefix*, not width padding: for a non-negative value it
emits one space even when the value already reaches (or exceeds) the field
width, so 100 with `% 3d` is `" 100"` and 10000 with `% 5d` is `" 10000"`.
`util.rpad` only right-justifies to a minimum width and therefore printed
`"100"` / `"10000"`.

**Port before.** `spill/fillcost.mbt:52,54` used
`@util.rpad(b.nlive_w, 3)` / `@util.rpad(b.nlive_d, 3)`;
`spill/spill.mbt:492` used `@util.rpad(b.loop_depth, 5)`.

**Trigger (RED).** `test/_bfmandel.ssa` reaches loop weight 10000 (four
nested loops; `fillloop` multiplies by 10 per nesting level). Lowercase-free
corpus file `test/_audit3_regs_dbg_width.ssa` (new) puts 100 call results live
at a 4-deep loop header, so both widths trigger:

```
$ ./vendor/qbe/qbe -t amd64_sysv -dS test/_bfmandel.ssa 2>ref.err
$ PORT -t amd64_sysv -dS test/_bfmandel.ssa 2>port.err
$ diff ref.err port.err
<   .L75       ( 10000) [ v.104 ptr.5103 ptr.5104 ]
>   .L75       (10000) [ v.104 ptr.5103 ptr.5104 ]
```

`test/_audit3_regs_dbg_width.ssa` additionally shows the `% 3d` case on
arm64/rv64 (`( 205   0)` vs `(205   0)`) and the `% 5d` case on all
targets (`( 10000)` vs `(10000)`).

**Change.** Wire the shared formatter `util.fmt_space(v, w)` (types owner,
exact C `"% wd"`) in at the three sites:
`spill/fillcost.mbt:54,56` and `spill/spill.mbt:494`. The private
`mem/coalesce.mbt` `fmt_space3` copy (C `mem.c:467` `"% 3db"`) was deleted
and replaced by `util.fmt_space(sl[s0].sz, 3)` (`mem/coalesce.mbt:553`) so
there is one implementation of the C format (AGENTS rule 3). For the reachable
slot sizes this is output-identical: `fillalias` caps
`alias.u.loc.sz` at 64 (`vendor/qbe/alias.c:171-172`), so `% 3d` never
reaches its width there; the unification is about one copy, not about an
observed divergence.

**GREEN.**

```
$ moon test --target native --target-dir build/a3-regs \
    -p azhzx/qbe/live -p azhzx/qbe/spill -p azhzx/qbe/rega -p azhzx/qbe/mem
Total tests: 25, passed: 25, failed: 0.
```

`-dS` stderr now identical for `test/_bfmandel.ssa`, `test/_bf.ssa`,
`test/_bf99.ssa`, `test/_audit3_regs_dbg_width.ssa` and a generated 9-deep
nested-loop input on `amd64_sysv`, `arm64`, `rv64`, `amd64_win`.
Regressions added: whitebox `spill/audit_regs_wbtest.mbt`
("fillcost debug keeps C % 3d space flag", "spill block info keeps C % 5d
space flag") and corpus file `test/_audit3_regs_dbg_width.ssa`.

## 2. Cleanups (no behaviour change)

* **REGS3-DUP1: stale second alias table in mem/mem.mbt.** `mem.mbt` still
  carried `AliasL`/`alias_default`/`alias_copy`/`load_alias_from_fn`
  (a partial copy of `fillalias`'s result) although `cfg.@getalias` is now
  public and every `slot_of`/`slot_load`/`slot_store` call actually used
  `@cfg.getalias` and ignored the pre-built table. That is a second copy of
  one algorithm (AGENTS rule 3) and a stale header comment claiming
  `getalias` is package-private. Removed the dead table and the `al`
  parameter threading; `slot_of` now reads the alias directly, exactly like
  C `mem.c:slot()` (`getalias` + `ALoc` + `visit >= 0`). No output
  changed: full corpus and all package tests pass.
* **REGS3-DUP2 (reported, not fixed): `mem/mem.mbt` `loadsz`/`storesz`
  duplicate `ssa/use.mbt`.** They mirror C `load.c` helpers that the port
  already implements in `ssa/use.mbt`; the package boundary forced a copy
  (the ssa versions are package-private). This needs `ssa/use.mbt` exports,
  which are outside this worker's write scope; the copy is byte-equivalent to
  C `loadsz`/`storesz` today and is reported to the lead.

## 3. Mission items settled

### 3.1 mem/promote — slot read but never stored

C (`mem.c:61-64`) removes the alloc and then calls
`err("slot %%%s is read but never stored to", fn->tmp[l->arg[0].val].name)`.
The port has an opt-in `skip_read_before_write` extension for the port-only
C-frontend/JIT routes (passed `from_c=true` from `qbe.mbt:738+`); the QBE IL
pipeline passes `from_c=false` (`pipeline.mbt:124,148`, all `compile`
entries), so it must raise.

Verified against the reference on all four targets with

```qbe
export function w $f() {
@start
  %x =l alloc4 4
  %v =w load %x
  ret %v
}
```

Reference: `qbe:<file>:<line>: slot %x is read but never stored to`, exit 1.
Port: `qbe: error: slot %x is read but never stored to`, exit 1. The message
body is identical; the reference prefixes the parser's last file/line because
C's `err()` lives in `parse.c`, while the port reports a pass-time
`QbeError::CompileError` and the driver prints `qbe: error:` (driver-level
diagnostic difference, outside this scope). Both remove the alloc before
raising, so no dump is produced by either.

New whitebox tests: `mem/mem_wbtest.mbt` "promote: slot read but never stored
raises like C" and "promote: skip_read_before_write leaves a read-only slot in
memory". Also probed (identical dumps on amd64/arm64): zero-use alloc,
uniform slot promotion, two stores, mixed load/store sizes, load-before-store
mixed sizes.

### 3.2 Known stress inputs (previously excluded from the corpus)

`test/stress/_002_wide_300.ssa` and `test/stress/_006_args_w_32.ssa`:
now **identical** to the reference on all four targets with the full debug
flagset `-dFLSRMNCAGPK` and identical assembly. No emitter ICE and no
slot-number difference is reproducible with the current tree, so the earlier
"invalid second argument" ICE and slot-number divergences are stale: settled
as fixed (the current port passes these inputs byte-for-byte).

`test/stress/_009_calls_160.ssa`: **invalid IL** (`call %plus1(...)` instead
of `call $plus1(...)`). Both compilers reject it with the same diagnostic
body. The only difference is streaming: the reference compiles function by
function and prints the debug dumps of the already-parsed first function
before erroring, while the port parses the whole module first
(`pipeline.parse_module`) and therefore prints nothing on a parse error. That
is a driver/parser architecture difference on invalid input, not a
register-pass defect; not claimed as fixed and not added to the corpus.

The equal-cost spill-tie question is settled the same way: generated
30-temp equal-cost pressure inputs and a 9-level nested-loop input (loop
weight 10^9, per-temp costs up to 3e9 so the C uint costs wrap past
INT_MAX) are byte-identical (dumps and assembly) on amd64_sysv/arm64/rv64/
amd64_win, i.e. the `util.qsort_c` transcription and the unsigned spill-cost
comparison reproduce the reference's decisions on this host.

### 3.3 mem.c areas

* Slot/load/store mask and liveness (`load`/`store`/`slot`, `Range`,
  `rin/rovlap/radd`): V. In particular `load()` only adds `ip` when the
  loaded bits survive the write mask (`s->l &= s->m`, `mem.c:162-165`),
  `store()` only queues a dead-store candidate when no bits are live
  (`mem.c:176-183`), and the blit pair uses `x = sz>=NBit ? ~0 : BIT(sz)-1`
  with `store` at `ip--` and `load` at `ip` (`mem.c:282-291`). Port
  `mem/coalesce.mbt` matches, including `shl_bits` for the mask shifts.
* Blit pair handling: V, including dead-store kill of both halves
  (`mem.c:279-282`) and fused-slot direction flip / nop-on-equal-offset
  (`mem.c:312-327`, port `coalesce.mbt:505-535`). Corpus
  `coalesce_blit_pair.ssa`, `coalesce_blit_flip.ssa`, `coalesce_dead_slot.ssa`
  are byte-identical on all targets (they were three defects fixed in the
  previous round; the current code still carries the fixes).
* Coalesce fusion order, transposition of the selected alloc def, dead-code
  nops, and the loop-live-range extension
  (`radd(&s->r, br[b->loop].b - 1)`): V. Port computes the loop maximum in a
  private `max_loop` table (C temporarily reuses `b->loop`) because the
  port's `fillloop` afterwards needs the real depths; same (hd,b) iteration
  via `@cfg.loopiter`, same order, same value.
* Def pointer emulation: C compares/stores `Tmp.def` (an `Ins *` in the
  parse arena) and re-points the fused representative's def at the dominating
  alloc. Port keeps `(blk, idx)` per temp and a monotonic `def_pos` for the
  cross-block fallback; C asserts the two fusing allocs are in the same block
  (`mem.c:171`), so the (blk,idx) comparison is the reachable path. A.

### 3.4 spill.c areas

Every C function has a port counterpart and was compared: `aggreg`,
`tmpuse`, `fillcost`, `tcmp0`, `tcmp1`, `slot`, `limit`, `limit2`,
`sethint`, `reloads`, `store`, `regcpy`, `dopm`, `merge`, `spill`.
Notable verified corners: unsigned cost compare with C `UINT_MAX` sentinel
(prior-round fix still present, `spill.mbt:82-93`, `fillcost.mbt:61-65`);
ascending `bsiter` scans and the `-1`-`k` `limit` loops; hole-packing slot
allocator and final `slot8 += slot8 & 3`; back-edge header choice
(`s1/s2` with `id <= b->id`, largest id wins) and the `live through` budget
`limit(w, n - (l - j), 0)`; two-successor preferred intersection; call
clobber/retreg/argreg/nrsave arithmetic in `dopm` and the instruction loop;
`memargs` decrement and `lvarg` dead-operand rule
(`if (!lvarg[n]) bsclr(u,t)`); phi lowering (live phi -> store, dead phi ->
slot); replacement of `in`/`out`. The three `% d` formats above were the
only divergence found.

### 3.5 rega.c areas

Every C declaration has a port counterpart: `RMap`, `NPm`, `hint`,
`sethint`, `rcopy`, `rfind`, `rref`, `radd`, `ralloctry`, `ralloc`,
`rfree`, `mdump`, `pmadd`, `PMStat`, `pmrec`, `pmgen`, `move`,
`regcpy`, `dopm`, `prio1`, `insert`, `doblk`, `carve`, `prio2`, and
the four phases of `rega`. Verified corners: two-pass (try/force) allocation
in phase 2, the `prio2` insertion order from the out-set bitmap, physical
self-mappings before virtual allocation, `end`/`beg` snapshot points around
`doblk` and phi-destination removal; phase 3 consensus map including the
`rl[r]==0 -> -1` sentinel and the `x > 0` guard; phase 4 phi/edge copies,
new-block loop depth averaging, reverse-creation-order append and
`pmgen` order; `pmrec` cycle closing (no swap on cycle close) and class OR
through `Class.code()` (`Kw=0,Kl=1,Ks=2,Kd=3`, exactly C). No divergence
found; the previously fixed defects (rcopy bitmap copy, phase-3
`rtype(p->to)==RTmp` guard, leftover `DBG` println) are still fixed in the
current tree.

### 3.6 live.c areas

`liveon`, `bset`, `filllive` V. Fixpoint with `out` comparison, phi
transfer (clear all phi destinations, add the predecessor's selected
arguments), class counts, `T.rglob` OR, call handling
(`in &= ~retregs`, `nlv -= m; nlv += T.nrsave`, peak update,
`nlv -= nrsave; nlv += argregs`, `in |= argregs`), definition kill/gen,
memory base+index uses, and `nlive` updates. The `retregs`/`argregs`/
`nrsave` tables were re-checked per target against
`amd64/sysv.c`, `amd64/winabi.c`, `arm64/abi.c`, `rv64/abi.c` (they
*assign* `p[0]/p[1]`, which is what `filllive`'s call path relies on) and
the port's `Ref::retregs`/`Ref::argregs` wrappers return the same triples;
`rsave` arrays have the same members as C's `-1`-terminated lists, and the
port's `for r in 0..<rsave.length()` is the same set. No divergence found.

## 4. Declaration inventory

### live.c -> live/live.mbt

| C | port | status / notes |
|---|---|---|
| `liveon(BSet*,Blk*,Blk*)` 3-20 | `liveon` :7-27 | V; block pointers -> stable block ids; equal ids are not structural equality |
| `bset(Ref,Blk*,int*,Tmp*)` 22-33 | `bset` :30-46 | V; only temp refs, gen always set, class count only on first insertion |
| `filllive(Fn*)` 38-144 | `filllive` :51-169 | V; `chg` loop, reverse RPO, `nlive` bookkeeping, -dL text; A: per-call BSet allocation (C statics), `s2==s1` liveon skipped (union idempotent) |

### spill.c -> spill/spill.mbt, spill/fillcost.mbt

| C | port | status / notes |
|---|---|---|
| `aggreg` 3-14 | `aggreg` fillcost:7-15 | V |
| `tmpuse` 16-33 | `tmpuse` fillcost:18-29 | V; virtual-only, `ndef += !use`, cost word wraps like C uint |
| `fillcost` 39-95 | `fillcost` fillcost:34-99 | V incl. -dS texts and UINT_MAX sentinel (-1 bit pattern); D fixed: `% 3d` |
| static `fst/tmp/ntmp/locs/slot4/slot8/mask` 97-103 | `SpillState` :7-16 | A: instance state per call; fields int/Int32 like C |
| `tcmp0` 105-113 | `tcmp0` spill:82-93 | V; unsigned compare via reinterpret |
| `tcmp1` 115-122 | `tcmp1` :95-104 | V |
| `slot` 124-156 | `sp_slot` :57-79 | V; -1 sentinel, wide/narrow packing, `locs` offset |
| `limit` 164-194 | `limit` :108-133 | V; dynamic array replaces static `tarr` cache; C skips qsort for nt==1 (port sorts 1 element = no comparator calls) |
| `limit2` 202-214 | `limit2` :137-151 | V |
| `sethint` 216-223 | `sethint` :172-177 | V; phicls representative, OR mask |
| `reloads` 228-236 | `reloads` :180-193 | V |
| `store` 238-243 | `store` :196-203 | V; `Storew+class` via `Op::from_index`, cls Kw |
| `regcpy` 245-249 | `is_regcpy` :51-53 | V |
| `dopm` 251-298 | `dopm` :208-256 | V; copy-run reversal, call clobber/limit2/rsave hint/argregs, reloads, re-emission order |
| `merge` 300-311 | `sp_merge` :157-169 | V; loop-depth compare, slot==-1 filter |
| `spill` 326-531 | `spill` :261-502 | V; all three end-of-block cases, masks, jump-arg slot, border slots, reverse instruction walk, limit2+hints, phi lowering, final align; D fixed: `% 5d` |

### rega.c -> rega/rega.mbt

| C | port | status / notes |
|---|---|---|
| `struct RMap` 8-16 | `RMap` :7-13, `rmap_new` :16-24 | A: `t/r/w` as 64-int arrays, BSet object; C allocates zeroed and reuses `cur` |
| `NPm` 18-20 | `pm` 64 entries :340-345 | V; C `die` on overflow vs port index failure (residual, both fail) |
| static `regu/tmp/mem/pm/npm/loop/stmov/stblk` 22-33 | `RState` :41-50 | A: per-call state; `regu` UInt64, stats Int32 |
| `hint` 35-39 | `hint` :61-63 | V (scalar re-read instead of C pointer) |
| `sethint` 41-52 | `sethint` :66-73 | V incl. `tmp[t].visit=-1` reset |
| `rcopy` 54-62 | `rcopy` :30-38 | V; arrays + bitmap copied (not aliased) |
| `rfind` 64-73 | `rfind` :102-109 | V |
| `rref` 75-87 | `rref` :112-120 | V; missing-slot assert omitted (diagnostics) |
| `radd` 89-105 | `radd` :123-130 | V; C asserts omitted |
| `ralloctry` 107-153 | `ralloctry` :133-192 | V; phys fast path, visit/hint, avoid mask incl. `b->t[0]`, class first-free then relaxed scan, wait list; A: writes `tmp.reg` for debug info only |
| `ralloc` 155-159 | `ralloc` :195-197 | V |
| `rfree` 161-179 | `rfree` :200-218 | V; absent-> -1, clear t and r bits, stable compaction |
| `mdump` 181-192 | `mdump` :952-966 | V; virtual mappings only, map order |
| `pmadd` 194-203 | `pmadd` :231-239 | V |
| `PMStat` 205 | `TOMOVE/MOVING/MOVED` :243-249 | V (0/1/2) |
| `pmrec` 207-251 | `pmrec` :252-336 | V; class OR, dependency search, cycle close suppresses swap, acyclic copy |
| `pmgen` 253-264 | `pmgen` :339-347 | V |
| `move` 266-285 | `r_move` :349-366 | V; destination free, relocation with temp exclusion, radd |
| `regcpy` 287-291 | `is_regcpy` :226-228 | V |
| `dopm` 293-334 | `rega_dopm` :371-421 | V; m0 snapshot of t/r/n only (b/w unused by rfind), call retregs/rglob/rsave moves, pm entries, release/re-add copies, pmgen |
| `prio1` 337-345 | `prio1` :425-428 | V; second arg intentionally ignored |
| `insert` 348-357 | `insert` :432-450 | V; re-reads current refs, insertion order |
| `doblk` 360-447 | `doblk` :509-618 + `doblk_def` :489-505 | V; jump allocation, call masks, copy-run group, dest/rglob/dead handling, ordered arg slots + insertion sort, self-copy removal, hint retry and arg rewriting |
| `carve` 452-463 | `carve_cmp` :626-642 | V; total order (loop desc, rpo id desc), so unstable sort is unobservable |
| `prio2` 466-475 | `prio2` :646-654 | V; sign xor visit/hint, C's uint-difference-as-int retained |
| `rega` 481-700 | `rega` :659-919 | V, four phases; A: debug text returned as string, phase-3 `rl==0 -> -1` write omitted (output-equivalent), self-copy `continue` skips a retry whose condition is necessarily false, both successor slots iterated (invalid-CFG only) |

### mem.c -> mem/promote.mbt, mem/coalesce.mbt, mem/mem.mbt

| C | port | status / notes |
|---|---|---|
| `promote` 8-92 | `promote` promote:5-164 | V for the QBE path (alloc range `Alloc4/8/16`, ndef!=1, use validation load/store sizes + `argcls` class, alloc->nop, store->copy, load->copy/cast/extend, read-never-stored error); A: `skip_read_before_write` opt-in extension used only by the port's C-frontend/JIT routes, zero-use alloc special case is C's empty-use-loop behaviour; D: pass-time error printed without C's `file:line` prefix (driver) |
| `struct Range`, `rin`, `rovlap`, `radd` 94-136 | `Range`, `rin`, `rovlap`, `radd` coalesce:8-41 | V |
| `struct Store` 99-102 | `StoreRec` :45-49 | A: `(blk,idx)` instead of `Ins*` |
| `struct Slot` 104-113 | `Slot` :53-62 | V incl. `nst`/store list, `s` fusion index (-1 = none) |
| `slot` 138-153 | `slot_of` :77-93 | V; `@cfg.getalias`, `ALoc`, `visit >= 0`, offset |
| `load` 155-167 | `slot_load` :95-119 | V; `l |= x<<off; l &= m; if(l) radd` |
| `store` 169-185 | `slot_store` :121-146 | V; live -> radd+mask clear, dead -> record candidate |
| `scmp` 187-196 | `scmp` :148-154 | V; size desc, then range start |
| `maxrpo` 198-203 | inline in `coalesce` :246-254 | A: private `max_loop` table (C reuses `b->loop`; the port's later `fillloop` needs the real field) |
| `coalesce` 205-488 | `coalesce` :197-583 | V; slot collection, one-pass backward liveness incl. `Argc`/`Jretc`/`blit0` and loop range extension, dead-store kill incl. blit pair, empty-range slot kill, use rewrite, size-desc fusion with overlap check, fused-slot substitution + dominating def transplant, overlapping-blit fixup, `%d`/`%u` debug text; A: `shl_bits` defines C-UB out-of-range shifts as 0; A: (blk,idx) def/blit references |

## 5. Adaptations kept, with justification

1. **Block ids instead of C block pointers.** Stable indices are the project's
   representation; every comparison (`s1/s2`, phi `blk`, preds, rpo, loop
   header choice) uses the same identity the C pointer comparison would.
2. **Per-call state (SpillState/RState) instead of C file statics.** The C
   statics are reset at the top of `spill()`/`rega()`; instance state is
   equivalent and reentrant.
3. **Reverse-push emission buffer.** C's `emiti` prepends into `insb`;
   the port appends and reverses when materialising the block. Same final
   order, verified by all summary/instruction dumps.
4. **Dep-value copies vs reference.** `mem/coalesce` stores `(blk,idx)` for
   `Tmp.def`-equivalent and blit instructions; instruction objects are not
   replaced while coalescing runs, so the references stay valid. Handcrafted
   IR that puts the same `Ins` object in several positions is not certified
   (same open question as the previous round).
5. **`shl_bits`** (`mem/coalesce.mbt:65-73`) defines a shift outside
   `0..63` as 0; C has undefined behaviour there (the host masks the count).
   Reachable only for addresses partially outside the promoted slot's offset
   range; not claimed equivalent for such (UB) inputs.
6. **`liveon` skipped when `s2 == s1`**, **`limit` sorting a single
   element**, **phase-3 `rl==0` sentinel omitted**, **self-copy
   `continue`**, **both successor slots in phase 4**: all argued
   output-equivalent above; no "improvement" changes a valid-input decision.
7. **Debug text returned as a string.** Passes return the text the driver
   concatenates into the staged dump. Order and bytes are verified by the
   `-dL/-dS/-dR` differentials (corpus now 264 files x 4 targets x
   `-dFLSRMNCAGPK`, 0 diffs).
8. **`tmp.reg` debug write in `ralloctry`** does not feed any allocation
   decision (checked all readers).

## 6. Residual gaps (explicitly not claimed)

* C assertions omitted throughout; invalid-state failure modes differ
  (e.g. missing mapping in `rref`, physical register in `sp_slot`,
  `NPm` overflow: C `die`, port array bound failure). Valid-input results
  are covered; diagnostics/ICE parity is not claimed.
* `coalesce`'s shift UB (above) is not reproduced; no claim for inputs that
  address bytes outside the bytes stored through a slot with an out-of-range
  shift count.
* The `mem/mem.mbt` `loadsz`/`storesz` duplicate of `ssa/use.mbt` remains
  (needs an `ssa` export, outside this write scope).
* Pass-time error text does not reproduce C `err()`'s `file:line:` prefix
  (driver-owned), and the port parses whole modules before running passes, so
  the reference's partial debug dumps before a parse error are not
  reproduced (visible only on `test/stress/_009_calls_160.ssa`, invalid IL).
* `qsort` tie equivalence is verified on this host's reference binary and a
  large generated tie-heavy input; the transcription in `util/qsort_c`
  remains the authority for other libc variants.
* `-d` output of other passes (`-dP/-dG/-dC/-dK/-dA/-dI/-dF`) is compared
  but is owned by other workers.
* Shared formatting helpers (`util.fmt_space`, `dumpts`, `printfn`) are
  types/parser-owned; this audit only verified the sites in this domain.

## 7. Verification summary (all run after the final rebuild)

* `moon test --target native --target-dir build/a3-regs -p azhzx/qbe/live
  -p azhzx/qbe/spill -p azhzx/qbe/rega -p azhzx/qbe/mem` ->
  **25/25 passed**.
* Corpus debug differential, all non-`_` files (264 incl. newly added
  `audit3_*` files), targets `amd64_sysv`, `arm64`, `rv64`, `amd64_win`,
  flags `-dFLSRMNCAGPK`: **264/264 identical stderr and stdout**.
* Corpus assembly differential (no `-d`), same targets: **264/264 identical
  stdout**, with 3 inputs (`audit_core_sym_sub.ssa`, `tls.ssa`,
  `tls_link.ssa` on `amd64_win`) where the **reference itself aborts**
  (`amd64/emit.c: dying: extern/thread unsupported on amd64_win`, exit 134)
  and the port exits 1 cleanly; both reject the input.
* Stress differential `test/stress/*.ssa`, four targets, full debug flags:
  `_002_wide_300` and `_006_args_w_32` identical; `_009_calls_160` (invalid
  IL) same diagnostic, partial-dump streaming differs as described.
* Targeted probes: 4-nested wide-live loop corpus file, 9-nested-loop
  unsigned-cost input, equal-cost tie inputs, promote zero-use/uniform/
  mixed-size/read-before-store inputs, read-only slot error: identical dumps/
  assembly (or identical exit+message) on all four targets.
* Mutation fuzzing with a harness over the corpus (mutate lines, keep only
  mutants the reference accepts, compare `-dPMNCAGKLSR` stderr+stdout on the
  four targets): seeds 1-7, 120 mutants each, **0 diffs / 0 crashes**; seeds
  1, 6 and 7 were re-run against the final binary (also 0).
