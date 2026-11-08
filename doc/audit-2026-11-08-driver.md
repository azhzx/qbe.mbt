# Driver/shared emission audit — 2026-11-08

Baseline HEAD `938fc19ee7a9ca80b7f21fb45f713887f8b82289`; upstream `661ceb22d3175d1e55c2c16531e08a3ab61e8b12`. Working tree contains concurrent compiler repairs. All requested production files read in full: pipeline.mbt (707 lines), qbe.mbt (893), cmd/main/main.mbt (615), gasdata/gasdata.mbt (215), dwarf/module.mbt (333), upstream main.c (212), emit.c (272). Read applicable instructions and skills. Declaration inventory and final verification pending below; do not treat this checkpoint as completion.

## Confirmed findings / pending repairs

1. CLI output write failures return success: main.mbt 598–602 only eprints. Existing binary probe `printf 'export function w $one() {\n@start\n ret 1\n}\n' | _build/native/debug/build/cmd/main/main.exe -o .` exited 0 with `IOError("Is a directory")`; upstream `-o .` exits 1 before parsing (main.c 150–155).
2. Multi-file output resets module state per source and concatenates completed outputs: main.mbt 592–597; pipeline per-module stash/file/reset and finalization. Probe arm64 with test/dbg/001_loc.ssa and test/dbg/002_files.ssa produced `.file 1 "one.c"`, `.file 1 "a.c"`, `.file 2 "b.c"` versus upstream 1,2,3. Reference parses all inputs independently and calls emitfin once (main.c 192–209); parse.c 1228 resets type namespace per file. Never concatenate IL strings.
3. Apple TLS synthetic section incorrectly quoted: gasdata 99–112 emits `.section "__DATA","__thread_data,thread_local_regular"`; upstream emit.c 24–46 emits `.section __DATA,__thread_data,thread_local_regular`. Exact binary differential confirmed. RED regression `moon test gasdata --target-dir build/audit-driver`: 2 tests, 1 expected TLS failure, user-section quoting control passes.
4. Native pipelines omit `fillloop` after instruction selection/liveness (main.c 102). fillcost only calls loopiter for aggregation; GVN/GCM earlier fillloop does not substitute after CFG-changing passes.
5. Debug CLI nonalphabetic `-d 1` suppresses assembly while upstream does not enable debug; exact differential confirmed. Debug compile also discards dbgfile directives: `-d P test/dbg/001_loc.ssa` upstream stdout `.file 1 "one.c"`, port stdout empty; stderr parsing dump otherwise matches.
6. Target table lacks upstream amd64_apple/amd64_win/arm64_apple names and `-t ?`; -G is a port addition, not upstream option. Apple ABI/isel threading needs coordinated repairs.
7. DWARF is entirely a port addition, not parity: UTF-16 `String.length` offsets disagree with emitted UTF-8 byte lengths; persistent dbg_fns retains most recent module until reset; unvalidated negative register location passed to uleb loops forever. Confirmed source-level, targeted regressions pending.
8. CLI continues compiling later inputs after errors; upstream exits immediately. Run-asm loaded module lacks close API (dependency traced) and output error paths may bypass JIT close; port additions, not upstream parity.

## Probe provenance
Existing main executable SHA256 `af97f0b2d2d9e135dc0b0e2f7210d06c9486488b4aef789e10f2a4b82b9def87`; oracle `5c13073534cd92512e8f0735b3cda6594b532a24f7f03852d4388ed9df97199b`. Main _build is mutable and not called a frozen baseline. No global build/test/format. Isolated target dir only.

## Authorization / handoff
Initially report-only; Lead subsequently authorized bounded RED-first CLI/gasdata/dwarf repairs, then transferred pipeline.mbt/qbe.mbt/root audit_driver_wbtest.mbt ownership. Full inventory, fresh verification, and exact unresolved list will replace this checkpoint before task completion.
