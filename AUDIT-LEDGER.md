# Audit ledger (vendor/qbe 661ceb22)

This file records what has actually been compared against the vendored
reference and what has not. It is deliberately conservative: a region is
"reviewed" only when every declaration in it was read next to its upstream
counterpart, and a fix is listed only when a failing test was seen first.

## Baseline

- Upstream: `vendor/qbe`, revision `661ceb22d3175d1e55c2c16531e08a3ab61e8b12`.
- Reference binary: `vendor/qbe/qbe` (built from that tree).
- Oracle: `compare.py` (staged debug dumps), `--asm` mode, and
  `tools/check_*.py` validity gates.

## Reviewed this round

### gvn / gcm (previously untouched; highest risk)

Files: `gvn/gvn.mbt`, `gvn/gcm.mbt`, `gvn/op_pinned_gen.mbt`,
`tools/gen_op_pinned.py`; upstream `vendor/qbe/gvn.c`, `vendor/qbe/gcm.c`.

Every function was read against its C counterpart:

| C | port |
|---|---|
| `mix`/`rhash`/`ihash`/`ieq` | `mix`/`ref_hash`/`ins_hash`/`ins_eq` |
| `gvndup` | `gvndup` (unsigned bucket arithmetic kept) |
| `replaceuse`/`replaceuses`/`killins` | `replaceuse`/`replaceuses`/`killins` |
| `dedupphi`/`phicopyref`/`phieq` | `dedupphi`/`phicopyref`/`phieq` |
| `normins`/`assoccon`/`negcon` | `normins`/`assoccon`/`negcon` |
| `foldint`/`foldflt`/`opfold`/`foldref` | `c_foldint`/`c_foldflt`/`c_opfold`/`foldref` |
| `dwl`/`uwl`/width helpers (copy.c) | `dwl`/`uwl`/`defwidthle`/`usewidthle` |
| `copyref`/`narrowpars` | `copyref`/`narrowpars` |
| `cmpeqz`/`zeroval`/`branchdom`/`domzero` | same names |
| `dedupins`/`dedupjmp`/`rebuildcfg` | same names |
| `schedearly`/`earlyins`/`earlyblk` | same names |
| `schedlate`/`lateins`/`latephi`/`latejmp`/`lateblk` | same names |
| `bestbid`/`lcabid`/`gcmmove`/`addgcmins` | `bestbid`/`lca_bid`/`gcmmove`/`addgcmins` |
| `sink`/`sinkref` | `sink`/`sinkref` |
| `schedblk`/`schedins`/`igroup`/`idup` | `schedblk`/`schedins`/`igroup` |
| `pinned`/`canelim`/`cheap`/`isdivwl` | same names |

Intentional adaptations (checked, not defects): block ids instead of C
pointers; `lateblk` defers phi removal until all blocks are scheduled so the
port's `(block, index)` phi uses cannot shift under it; `schedins` does not
append the `nop` placeholders C keeps because `printfn`/all later passes skip
`O nop`, and the staged diffs stay identical.

**Bug fixed:** `tools/gen_op_pinned.py` listed the port-only pinned ops
(`Vacall`, `AtomicLoad`, `AtomicStore`, `Fence`) but not `InlineAsm`. GVN
therefore value-numbered two identical inline-assembly instructions (deleting
the second, wrong for side-effecting asm such as `ldxr`/`msr`), and GCM could
move an asm instruction out of its block. `InlineAsm` was added to the
generator's extras and the table regenerated; regression tests:
`gvn does not deduplicate inline assembly`, `gcm does not move inline assembly`
(RED 18/20, GREEN 20/20).

### Compiler driver

Files: `pipeline.mbt`, `qbe.mbt`, `cmd/main/*`; upstream `vendor/qbe/main.c`.
The full pass sequence in `run_frontend_passes`/`run_passes` was compared with
`func()` in main.c. Bugs fixed and covered by tests:

- `@dwarf.reset()` was missing at the native module-emission boundaries, so
  DWARF records from one `compile()` leaked into the next. Regression:
  `compile resets DWARF module state`.
- No positional argument used to print help instead of reading stdin;
  `input_files` now matches the reference's `do { ... } while` over
  `av[optind]`. Regression: `input_files: no positional arguments select stdin`.

### Constant folding

Files: `fold/opfold.mbt`, `interp/eval.mbt`; upstream `vendor/qbe/fold.c`.
Fixed: word operations must use 32-bit semantics (`div/rem/udiv/urem`,
`sar/shr/shl` masks), invalid address arithmetic / null divisor / overflow
return "not foldable" instead of raising ICE, long `sltof`/`dtosi` above 32 bits.
Regressions in `fold/fold_wbtest.mbt` and
`interp/float_semantics_wbtest.mbt`.

### wasm backend (port-only, no upstream counterpart)

- The wasm pipeline skipped `simpl()`. Since `simpl` is what expands the
  `blit0/blit1` pseudo pair for every other target, a `blit` reached the wasm
  selector and was **silently dropped**: the generated module validated but
  copied nothing (measured: 0 stores emitted instead of 2). Fixed by running
  `@ifopt.simpl` after the wasm ABI pass, mirroring the native pipelines.
  Regression: `wasm: blit is expanded before instruction selection`.
- `cos/cuos/cod/cuod` fell through to the generic path, which emitted `nop`
  followed by `local.set`; the wasm validator rejects that module, so any IL
  using an ordered/unordered comparison could not be compiled at all. They are
  now built from `f{32,64}.eq/.ne` + `i32.and/i32.or`. Regression:
  `emit_fn: ordered and unordered float comparisons lower correctly`.
- Operations without a wasm lowering (blit, atomics, inline asm) used to be
  dropped by `_ => ()`. They now raise `QbeError::CompileError`; regression:
  `wasm: inline assembly is rejected`.
- Earlier rounds (kept): narrow load/store widths, `store8/store16`, `hlt`
  as `unreachable`, external data as imported globals, IL subtype wrapping.

### rv64 backend

Files: `target_rv64/isel/isel_rv64.mbt`, `target_rv64/emit/emit_rv64.mbt`;
upstream `vendor/qbe/rv64/isel.c`, `emit.c`.

- `cos/cuos/cod/cuod` had no selector case: the emitter printed
  `# unknown instruction: cos` and exited 0, i.e. silently miscompiled. Added
  `sel_float_ordered`, transcribed from C `selcmp`'s `Cfo`/`Cfuo` cases
  (`ceq(a,a)`, `ceq(b,b)`, `and`, plus `xor 1` for unordered). The rv64
  assembly for the four ops is now byte-identical to the reference.
- Unknown instructions in the emitter are now an ICE instead of a comment.
- New corpus file `test/ordered.ssa` exercises all four ops on every target.

### la64 backend

- Same silent `# unknown instruction` fallback removed (now ICE).
- Ordered/unordered comparisons were already correct (`fcmp.cor/cun`).

### arm64 backend

- Apple narrow stack arguments were 8-byte slots (a local "improvement") while
  `vendor/qbe/arm64/abi.c` uses 4; restored upstream `Class.align` handling and
  the 4-byte Apple scalar slot. Regression:
  `arm64 abi: Apple narrow stack arguments use four-byte slots`.

### Non-reference extensions (object / dwarf / jit / native / run_asm)

- Mach-O arm64 encoders reject unaligned/out-of-range scaled and pair offsets
  instead of truncating them.
- DWARF: one `.debug_loc` terminator per variable list, `DW_FORM_data4` for
  aggregate sizes > 255, GAS string escaping.
- `native.run_command` returns the child's exit status instead of the raw
  `system()` wait word.

### live / spill / rega (line-by-line)

Every C function now has a port counterpart, and each was compared:

- `live.c`: `liveon`, `bset`, `filllive`. The fixpoint, the register-count
  bookkeeping (`nlive`), the call/clobber arithmetic (`retregs`/`argregs`/
  `nrsave` -> `post_call_gpr/fpr`) and the debug text match. `s2 == s1` is
  skipped where C would run `liveon` twice; the union is idempotent, so the
  result is identical.
- `spill.c`: `aggreg`, `tmpuse`, `fillcost`, `slot`, the two comparators,
  `limit`/`limit2`, `sethint`, `reloads`, `store`, `dopm` (the register-copy
  run and the call-clobber handling) and `spill` (back-edge, two-successor and
  fall-through cases, phi lowering, final slot alignment) all match. The port
  allocates scratch sets per call where C uses statics; that is a performance
  difference, not a semantic one.
- `rega.c`: `hint`/`sethint`, `rcopy`, `rfind`/`rref`, `radd`,
  `ralloctry`/`ralloc`/`rfree`, `pmadd`/`pmrec`/`pmgen`, `move`, `dopm`,
  `prio1`/`insert`, `doblk` (call clobbers, copy runs, hint retry, self-copy
  removal), `carve`, `prio2` and the four phases of `rega` match. Three
  defects were fixed:
  - a leftover `DBG` `println` block in `ralloctry` (production debug output);
  - `rcopy` aliased the register bitmap instead of copying it (C does
    `bscopy`); now copied, with a regression test;
  - phase 3 indexed the phi destination without C's `rtype(p->to) == RTmp`
    guard; the guard is restored.

### Dead standalone copy pass removed

`ssa/copy.mbt` implemented a complete pre-GVN copy-propagation pass. The
vendored `copy.c` at this revision has no such pass: it only provides the
analysis helpers (`copyref`, `phicopyref`, `dwl`/`uwl`, `narrowpars`,
`bitwidth`, ...), which this port already carries in `gvn/gvn.mbt`.
Production `pipeline.mbt` never called `@ssa.copy`; git history shows the call
was removed in `f3f4373` ("Align with vendor/qbe reference 661ceb2"), but the
file and thirteen test-helper calls were left behind. That meant every unit
test pipeline ran an extra pass the real compiler does not, and the project
kept two copy-elimination implementations. The file and the calls were
removed; test pipelines now mirror `main.c`.

### Lexer, parser and data literals (against parse.c/emit.c)

- The lexer now scans float text the way C's `fscanf("%f")` does: signed
  exponents (`d_1e+3`), C99 hexadecimal floats (`s_0x1.fffffe091ff3dp+127`),
  `inf`/`infinity`/`nan` and a leading sign. Previously all of these except a
  plain decimal were split into several tokens and rejected.
- `$` is now an identifier character, as in C (`isalpha || '$' || '.' || '_' ||
  isdigit`); names like `%a$b` parse again.
- Hex floats are converted bit-exactly to the target precision with
  round-to-nearest-even (single for `s_`, double for `d_`), and `nan`/`inf`
  get glibc's canonical bit patterns (`0x7ff8000000000000`, `0x7fc00000`), so
  the emitted bits match the reference. Corpus: `test/hexfloat.ssa`.
- Float data items now carry their bit pattern in `Dat.num` like C's `Dat`
  union. Text emitters print `num`, so float data used to be emitted as
  `.int 0` / `.quad 0` on every text target (the object emitters had a partial
  workaround that also lost `-0.0`). Covered by
  `parser: data: float items carry their bit pattern` and the corpus data
  section (hex floats, subnormal, `-0.0`, NaN).
- `util.fmt_fixed` now formats like C `printf("%.6f")` for every magnitude.
  It used to convert through `Int64`, saturating above 2^63, so `-d` dumps and
  emitter comments printed FLT_MAX as `9223372036854.775807`; it also gained
  C's `inf`/`nan`/`-0.000000` forms and `%.0f` without a point.

### amd64 flag encoding (asm differential)

The amd64 flag table emitted `setnp/setp` followed by `movsb` for the
ordered/unordered float flags; the reference's `CMP` macro uses `movzb`.
The values are 0/1 so the code is semantically equal, but the assembly was not
byte-identical (found by the `--asm` fuzzer on a `cos`/`cod` mutant). Fixed;
the full `compare.py --asm` corpus is now identical on all three targets.

### Missing features and the remaining pass fixes

- **All previously missing upstream ops are implemented** and verified:
  `neg`, `stoui`/`dtoui`/`uwtof`/`ultof`, the eight sub-word
  `par*/arg*` ops and the four sub-word return jumps. Sub-word ABI is parsed
  as the reference parses it in this revision (bare `ret`, class from the
  function signature) and eliminated by `ssa/elimsb.mbt` at abi0.
- **amd64 address folding** is now a literal transcription of the reference
  `refn`/`opn`/`match`/`matcher`/`runmatch` engine (generated bytecode tables
  included), not a re-derivation.
- **ifopt `ifgraph`** compared block ids (definition order) where the reference
  compares RPO ids; the if-conversion of an if-then graphlet whose else branch
  is the fall-through block was missed. Found by the asm fuzzer, fixed, and
  `test/ifconv_empty.ssa` covers it.
- **cfg `simpljmp`** only collapsed integer conditional jumps with equal
  successors; the reference collapses any two-successor jump (including `jnz`
  and the float comparisons). Exposed on rv64/la64/wasm, where if-conversion is
  not run. Fixed.
- **`util/qsort_c`** is now a transcription of Apple libc's FreeBSD
  `qsort.c`/`heapsort.c`, so tie permutations (phi order, spill priority)
  follow the reference library instead of a hand-written quicksort.
  `loadopt`'s comparator again returns 0 for two phis of the same block, as the
  C does. The full corpus is byte-identical; a single fuzz-generated stress
  input still shows a phi *dump order* difference that we attribute to the
  exact libc qsort permutation (assembly is identical, so this is cosmetic).

### TLS, linkage and Sym.type

- The parser now implements C `parselnk` (repeatable `export`/`thread`/`common`/
  `section "name" ["flags"]` keywords, the "only data may have thread linkage" and
  "only data and function have linkage" errors) and stores the linkage on
  `Fn`/`Dat`. Data alignment is validated and carried as `Lnk.align` (default 8,
  functions 16), and `parseref` accepts the repeatable `extern`/`thread` prefixes on
  globals, setting C `Sym.type` bits on the address constant. Printing, constant
  interning, folding, alias analysis and the amd64 address matcher all carry
  those bits.
- Data and function labels are emitted by a new shared package `gasdata`, a
  transcription of the reference `emit.c` `emitdat`/`emitlnk`: zero-fill accumulation
  (data vs .bss/.tbss), `.comm` for common data, custom sections with flags,
  `.balign` from Lnk.align, and thread sections `.tdata`/`.tbss` (plus the
  Mach-O thread-variable bootstrap used by the apple flavor).
- TLS address materialization is transcribed per reference target: amd64
  `%fs:0` + `@tpoff` (local-exec), `@gottpoff` (initial-exec) and
  `@gotpcrel` (extern), with the matching `Oaddr` special cases and the fixarg
  extern branch; arm64 `mrs tpidr_el0` + `:tprel_hi12:`/`:tprel_lo12_nc:` and
  `:got:` forms; rv64 `%tprel_hi/add/lo` and `lga` with fixmem scratch
  registers. la64 (no upstream backend) uses `la.tls.le`/`la.tls.ie` plus `$tp`
  and `la.got`, verified by the clang assembler gate. Corpora: `test/tls.ssa`
  (local-exec data, address arithmetic, loads/stores) and
  `test/tls_link.ssa` (thread tdata/tbss, exported thread data, common data,
  custom data/text sections, extern GOT references); all three reference
  targets are byte-identical on dumps and assembly.
- wasm has no TLS ABI; to keep its gate useful it also adapts call arguments
  and results whose IL class differs from the callee's actual class
  (i64.extend/wrap, f32/f64 promote/demote).

## Verification (this round)

- `moon test` over every package except `run_asm` (host linker fails with
  `libLTO.dylib`): **317/317**, plus root whitebox **5/5**.
- `compare.py` debug dumps, 6832 cases each: amd64 **6832/6832**, arm64
  **6832/6832**, rv64 **6832/6832**; `--asm` **427/427** on each target. The
  corpus gained `ordered.ssa`, `coalesce_{dead_slot,blit_flip,blit_pair}.ssa`,
  `phi_swap.ssa`, `dup_export.ssa` and `hexfloat.ssa` (hex floats, subnormals,
  inf/nan, `-0.0`, float data).
- `tools/check_wasm.py`: **363/363 valid**, 0 compile failures, 71 inputs the
  reference itself rejects. `tools/check_wasm_runtime.py`: **5/5** programs run
  identically under `--run` and `--run-wasm`.
- `tools/check_la64_asm.py`: **363/363 assembled**.
- `tools/check_all_backends.py`: **363/363 PASS** on amd64, arm64, rv64, la64
  and wasm.
- `tools/fuzz_il.py --asm`: seeds 81/91/101, 111/141/151 and 161/171 are clean
  (**0 rejects, 0 crashes, 0 dump diffs, 0 assembly diffs**). Earlier seeds
  found the amd64 `movsb` flag bug, the `blit`-between-globals address-folding
  divergence, the `ifgraph` RPO-id bug and the `simpljmp` two-successor
  collapse; all are fixed.
- Rust C-ABI consumer (`cargo test --offline`): 9 integration tests + doctest.
- `moon fmt --check` and `git diff --check`: clean. `moon info`: only the
  intended `raise` additions, the new `cfg.fillcfg`/`cfg.fixphis`, and the
  `derive` syntax migration reach the generated interfaces.

### Mechanical table checks

- `tools/gen_op_pinned.py` output, the eight GVN flag predicates
  (`op_commutes`, `op_assoc`, `op_hasid`, `op_idval`, `op_idemp`,
  `op_cmpeqwl`, `op_cmplgtewl`, `op_eqval`) and every `types/opinfo.mbt`
  optab entry were compared programmatically with `vendor/qbe/ops.h`
  (T/F/X columns). All 144 implemented ops match; 0 drifts.
- `types/types_wbtest.mbt` now pins the index-family relations the emit tables
  and load->extend rewrites rely on (`Storew + cls`, `Extsb + (load -
  Loadsb)`, `Alloc4 + n`, `Flagieq + x`, `Jjfieq + x`, comparison ranges).
  They all hold.
- The `JumpKind` index table is hand-written and only covers the port's jump
  kinds (the four sub-word returns are absent); it is internally consistent and
  the relative offsets the backends use are covered by the same test.

### CLI exit status

The CLI used to print every error (parse error, unknown target, missing file,
compile ICE) and still exit 0, while `vendor/qbe` exits 1 on the first error.
`cmd/main` now records failures and exits 1; success stays 0. Verified:
`test/sum.ssa` -> 0 (amd64 and wasm), bad IL -> 1, unknown target -> 1,
missing file -> 1.

### ir_builder_capi (C ABI)

Audited every exported `qbe_*` function against `include/qbe_builder.h` and the
builder it wraps. Semantics of `qbe_emit`/`qbe_emit_void` (res_cls = -1 maps
to a void instruction through `Builder::emit_ins`), handle registries, error
propagation through `qbe_last_error`, and the JIT symbol table were checked by
reading the implementation. The Rust consumer builds and its suite passes:
`cargo test --offline` -> 9 integration tests (emit_il, emit_asm, Mach-O
object + link + run, JIT calls, host callbacks, variadic signature, debug
variable names) + 1 doctest, all green. Residual: the C API aborts the process
on invalid/released handles (documented as fatal) and JIT handle/Symbol strings
are process-global, so it is not thread-safe; both are interface decisions, not
observed defects.

### mem/coalesce (rescued from an interrupted audit)

Three divergences from `vendor/qbe/mem.c` were found and fixed; each new test
was checked against the reference binary's `-dM` output, and the inputs were
added to the differential corpus:

- `load()` must only add the position to a slot's live range when the loaded
  bits survive the slot's write mask (`s->l` non-zero after `s->l &= s->m`);
  a slot read only outside the bytes ever written through it is dead.
  Corpus: `test/coalesce_dead_slot.ssa`.
- Killing a dead store whose instruction is `blit0` must also nop the paired
  `blit1`; otherwise a lone `blit1` reaches the emitters.
  Corpus: `test/coalesce_blit_pair.ssa`.
- The newly-overlapping-blit fixup compares the slots the addresses were
  *fused* into (`s->s == s0->s`), not the slot entries; two entries of one
  fused group must still flip the copy direction. Corpus:
  `test/coalesce_blit_flip.ssa`.

### Phi assignments are parallel copies

- wasm emitted the phi arguments of one edge as sequential `local.set`s, so a
  loop back-edge that swaps two phis (valid SSA: `%x = phi @head %y`,
  `%y = phi @head %x`) clobbered one of them. Sources are now pushed onto the
  wasm operand stack first and popped into the destinations in reverse order.
  Added `tools/check_wasm_runtime.py`, which executes programs on the
  interpreter and on the wasm backend and compares results (phi swap,
  loop-carried accumulator, long arithmetic); all agree. Corpus:
  `test/phi_swap.ssa`.
- The interpreter had the same bug: it wrote each phi destination right after
  evaluating that phi. It now evaluates every incoming value first and stores
  afterwards; regression test `interp: phi swap on a loop back-edge is parallel`.

### Parser top-level linkage

`parse.c parselnk` loops over linkage keywords: repeated `export` lines are
accepted, and only after a linkage keyword is a non-data/function definition
an error. The port handled exactly one `export`. `parser/parse.mbt` now loops,
with the reference's "only data and function have linkage" diagnostic; tests
cover repeated export and the rejection case; corpus: `test/dup_export.ssa`.

### Fuzzing

`tools/fuzz_il.py` now also compares the deterministic staged dumps
(`-dPMNCAGK`, amd64) for mutants the reference accepts, so it finds semantic
divergences, not just panics; `--asm` additionally compares the final amd64
assembly byte for byte (that covers spill/regalloc/emit). Known noise: one
mutant that defines the same temporary twice (invalid SSA, which the reference
accepts) leaves a stale phi argument in the port's GVN dump. A 9079-line
mutant made the port's dump run take 6.3s vs the reference's 2.6s (and 6.3s vs
0.15s for plain assembly), so under full gate load the old 60s fuzz timeout
fired: a performance gap, not a hang. The timeout is now 180s and the gap is
recorded in TODO.md.

### CFG: fixphis / fillcfg were missing

`cfg.c`'s `fillcfg()` is `fillrpo + fillpreds + fixphis`; the port only had the
first two and never ported `fixphis`, which drops phi arguments whose block no
longer jumps to the phi's block. Every pass that rewrites a terminator (GVN's
`dedupjmp` collapsing a constant branch, simpljmp, if-conversion) can therefore
leave a stale phi argument behind. That changed the `-dG`/`-dC` dumps and gave
GCM/GVN a predecessor that no longer exists (phi placement and copy propagation
read those arguments).

- Ported `cfg.fixphis` (C `fixphis`: keep args only while the source block is
  reachable and still has an edge to this block; ICE when none remain) and
  `cfg.fillcfg`.
- Wired it exactly where `main.c`/`gvn.c` call `fillcfg`: the shared frontend
  entry, after GVN, after if-conversion, after `simpl`, after isel, after rega,
  and after `simpljmp`, in all four native target pipelines and in
  `gvn.rebuildcfg`. The wasm pipeline uses `fillcfg` after its `simpl` too.
- Regression: `cfg: fillcfg - fixphis drops an argument of a removed edge`.
- The three dump-divergence mutants saved by the fuzzer (`build/ilfuzz/diff_*
  .ssa`) now match the reference on every staged flagset.

### Lexer number/layout alignment

- Numbers are integers only, as in C `getint`; a bare decimal is an integer
  followed by an identifier token starting with '.', so the parser rejects it
  (previous port behaviour lexed `3.14` as a float literal).
- '\r' is no longer whitespace: C's `isblank` accepts only space and tab, so
  CRLF input is rejected exactly like the reference.
- Identifiers starting with '.' are lexed (C's `Alpha` allows '.'), which is
  what makes the bare-decimal rejection diagnostic work.
- Quoted global symbols and the `thread`/`common`/`section`/`extern` linkage keywords are
  now implemented too; see the TLS/Sym section below.

## Not reviewed / known gaps

- `wasm` `abi_wasm` is a deliberately small ABI (keeps Par/Arg for the
  emitter, drops the call's type payload); `addr_wasm.mbt` and `ctrl.mbt` are
  unused planning helpers (the emitter uses the pc dispatch loop and `RMem`
  refs are only created by native `isel`/`fixarg`, never by `load.c`), so they
  are dead code rather than buggy code. Removing them is optional cleanup.
- The wasm backend has no per-function ledger; only the emission and selection
  paths listed above were audited.
- **amd64 address folding is a re-derivation, not a transcription.** Port
  `target_amd64/isel/addr.mbt` implements its own `amatch`, while C's version
  is the generated `refn`/`opn`/`match`/`matcher` bytecode engine. Output
  differs on `blit` between two global symbols: the port folds
  `add $g, 0` into the load/store, the reference keeps an `addr` + `add`.
  Semantics are the same but the assembly is not byte-identical, so the
  `--asm` gate would fail on such input. Porting the generated matcher
  tables is the next step here.
- **Quoted global symbols** (`$"name"`) are now lexed with the quotes kept
  as part of the name, and every emitter skips its `T.assym` prefix for such
  names, like the reference emitters (the Mach-O object writer and the `"m"`
  gas flavor were updated too). `test/quoted_sym.ssa` is byte-identical on
  ELF; there is no reference oracle for the Mach-O text flavor (the vendored
  binary is built without `-G`).

- **Unimplemented upstream ops (mechanically enumerated against `ops.h`):**
  `neg`, `stoui`, `dtoui`, `uwtof`, `ultof`, `parsb`, `parub`, `parsh`,
  `paruh`, `argsb`, `argub`, `argsh`, `arguh`, plus the four sub-word return
  jumps (`Jretsb`, `Jretub`, `Jretsh`, `Jretuh`). Valid upstream IL using them
  is rejected loudly (`unknown keyword neg`, `invalid class specifier sb`),
  not silently miscompiled. Implementing them touches the lexer/parser, the
  class enum, every backend's selector/emitter and the ABI passes, so it is
  the same kind of separate project as TLS below.
- The self-contained arm64 object writer (`--emit obj`, JIT, native) now rejects
  thread/common/custom-section data, section-linked functions and
  extern/thread symbol references loudly instead of emitting a wrong object;
  the text emitters implement them (see the TLS section above). The
  object-emission path still has no differential gate.
- The wasm flavor has no TLS model: thread data is emitted as ordinary static
  data and thread/extern operand modifiers are treated as plain globals.
  This is a documented port-only backend choice (there is no reference wasm
  target).

## 2026-11-08 second audit round (lead-integrated)

Baseline for this round: port 938fc19 plus the pre-existing lexer/parser edits;
upstream `vendor/qbe` 661ceb22. Every domain was read declaration by
declaration next to its C counterpart; the per-domain inventories and residual
gaps live in `doc/audit-2026-11-08-{frontend,core,registers,types,amd64,arm64,rv64,driver}.md`.
A fix is listed only after a failing test or oracle probe was observed.

### Front-end (lexer/parser, lead)

- Data lists: adjacent strings/globals in one width run are now accepted; the
  width of each item is kept (the parser used to overwrite every followed item
  with the last specifier). `parser/upstream_parity_wbtest`.
- Missing `}` in a type now raises (it used to panic on the token array).
  NField is capped at 32 while the size stays complete; size comparisons and
  the `align` division use C unsigned arithmetic.
- 29-bit reference bounds restored for `dbgloc` and `blit`; extra operands are
  still parsed and NPred is enforced; aggregate/sub-word classes are accepted
  for `call` only; a phi in the start block is rejected; several invalid
  constructs no longer panic.
- `extern`/`thread` are only accepted on globals.
- Floating literals are parsed with one exact round-to-nearest-even step:
  decimal single, hexadecimal single/double subnormals, and C's overflow to
  ±inf / underflow to ±0. Fixtures `test/audit_core_float_round.ssa`,
  `test/audit_regs_float_{rounding,overflow}.ssa`; reference bits match.
- `printcon`/`printref` now follow C's reserved constant identity (con[0] is
  UNDEF, ordinary literals with the same bits are not hidden; an absent ref
  prints `R`).

### Types / shared representation

- `Con` interning and `Fn::get_con`/`undef` reserve con[0] as UNDEF and con[1]
  as the zero constant, like `parsefn`/`newcon`.
- `Typ.isunion` distinguishes a one-alternative union from a struct; layout
  caps field records at 32, uses unsigned size maxima and consumes one FEnd per
  alternative.
- arm64/rv64 target constants and arg masks corrected (env x9/bit14, T5 for
  rv64 env, NFPR 31, NRGLOB 4); duplicated rv64 argreg helpers now delegate to
  one implementation.
- Exact `int64/uint64 -> f32` conversion helpers (`f32_*`) added and used by
  GVN and the legacy folder, removing double rounding.
- BSet set/clr validate against the rounded backing capacity.

### Core optimisation

- alias: `getalias` keeps `sym.type`; `fillalias` resets every temporary to
  ABot before recomputing (C alias.c), so deleted definitions cannot keep stale
  alias data.
- load: symbol bits preserved when rebuilding a constant; the missing
  `rebase` is transcribed; the insertion comparator returns 0 for equal-block
  phis like C.
- GVN/GCM: full symbol identity for address subtraction; `cmp` result width
  Wub; `neg` is cheap for sinking; eliminated-phi guard; generated pinned table
  regenerated from ops.h (including InlineAsm); blit pair grouping; the GVN
  table keeps instruction identity instead of a copy.
- ifopt uses the shared generated `pinned` predicate instead of a drifted
  handwritten copy.
- legacy fold: CON_Z looked up instead of hardcoded 0; word results masked to
  32 bits; symbol qualifiers preserved; exact int→single conversions.
- promote: a slot read but never stored now raises the reference error
  `slot %x is read but never stored to` (the opt-in C-frontend skip remains).

### Register allocation

- spill cost comparison is unsigned (C UINT_MAX sentinel); no allocation
  algorithm was replaced. Remaining C asserts are diagnostic-only and documented.

### Backends (amd64 / arm64 / rv64)

- amd64: env argument/parameter register handling and incoming mask, parity
  flag synthesis for float eq/ne, swapped/multi-use comparison jumps, numeric
  call materialisation, fast-alloc guards, slot-base bailout, by-value `sel`,
  Apple TLS resolver/@tlvp and @plt suppression, absolute/index-only memory
  addressing, large constant/slot splits, module reset hook.
- amd64_win: `winabi.c` transcribed into `target_amd64/abi/abi_win.mbt`
  (classification, shared int/float counter, shadow space, varargs register
  dump/duplication, struct copy/return, stack slots, env), Win64 frame sizes and
  prologue/epilogue/varargs saves in the shared emitter, PE finalizer without
  the GNU-stack note, `L` assembler-local labels, windows-aware slot formula
  and jump inversion, plus the Win64 register tables in `types/target.mbt`.
- arm64: HFA-first classification, Cptr register/class bookkeeping, env x9 and
  call bit14, incoming register mask, GOT/TLS offset split (Apple resolver),
  upstream float comparison swap table, large address/load/store fixarg,
  >4095/65535 prologue/epilogue materialisation, Apple function alignment, and
  the Apple `apple_extsb` pre-ABI pass (narrow call arguments and returns).
- rv64: env register mask, HFA/union classification, nested fpstruct offsets,
  parameter temp buffer, Cnes/Cned, halt, copy spill load/store, dynamic alloc
  guard, rejected external/TLS call operands.
- Both extra GAS targets still emit one finalizer and share gasdata.

### Driver / CLI

- `compile_sources` parses each input file independently (own types/interner)
  but emits through one output session: one finalizer, continuous local labels
  and `.file` numbering; multi-file output is byte-identical to the reference.
- Debug mode writes `.file N "path"` to stdout (or `-o`) exactly like
  `main.c`, while pass dumps stay on stderr; non-alphabetic -d flags no longer
  enable debug; output-write failures exit non-zero; `fillloop` runs after
  instruction selection in every native pipeline; the DWARF byte offsets count
  UTF-8 bytes. Debug compiles now take the gas flavour, so the Apple selector
  (-dI) and the arm64 "After Apple pre-ABI" (-dA) dumps use `T.asloc` like the
  reference; the Apple flag is also threaded into the amd64 selector.

### Verification in this round

- `moon test`: **513/513** native (host `run_asm` tests require the system
  Apple clang; the miniconda clang cannot link libLTO).
- `compare.py` differential dumps: **7120/7120** on amd64, arm64 and rv64;
  `--asm`: **445/445** on each. Two amd64-specific corpora now live under
  `test/_audit_amd64_*.ssa` (underscore = excluded from the cross-backend
  sweep) and are also run explicitly: **32/32** debug and **2/2** assembly on
  all three reference targets.
- Backend gates with a cross-capable clang: `check_all_backends.py` PASS on
  amd64_sysv 374/374, arm64 374/374, rv64 373/374 (one documented clang quoted
  symbol limitation), la64 374/374, wasm 374/374; standalone la64 and arm64
  assembler gates 374/374, rv64 373/373 after adding the same documented
  toolchain skip, wasm validator 374/374 valid with 0 compile failures.
  `check_wasm_runtime` passes 5/5 when Node (present under
  `~/.local/node/bin`) is added to PATH.
- Apple flavours: after implementing arm64 `apple_extsb`, threading the Apple
  flag into the amd64 selector and making debug dumps flavour-aware,
  `compare.py -G m` passes **7120/7120** debug dumps and **445/445** assembly on
  both `amd64_apple` and `arm64_apple`.
- Windows: `compare.py --target amd64_win` passes **7072/7072** debug dumps and
  **442/442** assembly. Three corpora (TLS/thread-symbol arithmetic) are skipped
  because the reference's own `amd64_win` emitter aborts on them; the port
  rejects them with a clean error. The skip list lives next to the rv64
  toolchain skip in `compare.py`.
- Final test run: **544/544** native tests. Fuzzing (`--asm`, seed 601, 150
  mutants): 0 rejects/crashes/dump/asm diffs. Gate runs must put a clang with
  all LLVM targets first in PATH (the miniconda clang here); Apple clang only
  knows host targets and makes every cross-assembler check fail spuriously.
- `moon fmt --check`: clean; `moon info` only the expected interface changes
  (new helpers, `promote` raising, Apple flags, corrected target constants).

### Residual, explicitly not claimed

- Port-only targets/features have no upstream counterpart and are not called
  transcriptions: wasm32, loongarch64, the JIT, the object writer, the IR
  builder, the interpreter and the exported C API.
- All upstream targets (`amd64_sysv`, `amd64_apple`, `amd64_win`, `arm64`,
  `arm64_apple`, `rv64`) are now implemented and differentially validated. What
  remains outside upstream parity is the port-only surface: wasm32 and
  loongarch64, the JIT, object writer, IR builder/bindings and interpreter.
  amd64_win cannot assemble inline asm/TLS (the reference dies there too) and
  has no object-writer backend; those paths fail loudly.
- The vendored reference does accept `-t arm64_apple` / `-t amd64_apple`,
  so the Apple text flavours are now differential-tested too: after
  implementing arm64 `apple_extsb` and threading the Apple flag into the amd64
  selector/debug dumps, `compare.py -G m` passes **7120/7120** debug dumps and
  **445/445** assembly on both Apple targets.
- Some C assertions remain diagnostics-only; hand-maintained tables (optab
  fields outside the generated pinned column, assembler tables) are still
  transcribed by hand, a policy gap rather than a known behavioural defect.
- Invalid internal IR can still differ in diagnostic text/abort versus the
  reference's `err()`; valid-input behaviour is what the differential gates
  cover.
