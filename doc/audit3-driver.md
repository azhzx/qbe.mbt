# Driver / emit / CLI audit 3 — main.c, emit.c, pipeline.mbt, qbe.mbt, gasdata

Worker: Lead. Baseline 2026-11-13, vendor/qbe 661ceb22, binary vendor/qbe/qbe.
This domain was audited directly by the Lead (no teammate).

Port files: pipeline.mbt, qbe.mbt, cmd/main/main.mbt, gasdata/gasdata.mbt,
util/debug.mbt (debug-file directives), root tests.

## Pass sequence (pipeline.mbt vs main.c func())

run_frontend_passes now matches main.c exactly: abi0 (elimsb, or apple_extsb
for arm64_apple), fillcfg, filluse, promote, filluse, ssa (filldom/fillfron/
filllive/phiins/renblk), filluse, ssacheck, fillalias, loadopt, filluse,
fillalias, coalesce, filluse, filldom, ssacheck, gvn, fillcfg, simplcfg,
filluse, filldom, gcm, filluse, ssacheck, [cansel: ifconvert, fillcfg, filluse,
filldom, ssacheck]. Per-target drivers then do abi1, simpl, fillcfg, filluse,
isel, fillcfg, filllive, fillloop, fillcost, spill, rega, fillcfg, simpljmp,
fillcfg (+ a final fillloop that is bookkeeping only; main.c relinks the block
chain here, which the port does not need). The multi-file output session
(single finalizer, continuous fp pool/label/.file numbering) matches main.c's
process-wide statics; a 255-file single-invocation compile is byte-identical.

## Fixed in this round

1. CLI `-t ?`: the reference prints the currently selected target name and
   exits 0 (default amd64_sysv); the port treated "?" as an unknown target and
   exited 1. Implemented with getopt-order semantics.
2. Repeated options: the reference getopt accepts -t/-o/-d/-G repeatedly; the
   last -t and -o win and every -d flag byte accumulates. The port rejected a
   second occurrence ("cannot be used multiple times"). Now Append actions with
   last-wins for -o/-t and accumulation for -d; `-t arm64 -t ?` prints arm64.
3. `-t amd64_apple` / `-t arm64_apple`: accepted like the reference tlist,
   mapping to the sysv/arm64 backend with the Mach-O gas flavor (the port's
   -G m remains as an extension). Repeated -t order preserved.
4. Output file handling: `-o` opens/truncates at option-parse time like C's
   fopen, and failures print `cannot open '<path>'` and exit 1 (previously
   "IOError(...)"). Input open failures print `cannot open '<file>'` like
   main.c (previously a raw IOError). The last -o wins.
5. Section presence (gasdata): C emit.c stores Lnk.sec/secf as the raw Tstr
   token text, quotes included, so a present-but-empty section (`section ""`)
   is distinct from an absent one. The parser now stores the quoted text (also
   fixing "only one section allowed" for duplicate empty sections), and
   gasdata prints sec/secf verbatim: `.section ""`, `.section "x",""` and the
   normal cases are byte-identical; the synthesized Apple TLS fields stay bare.
6. RInt/RSlot dump printing: parser/print.mbt now uses types.Ref::rsval (C
   all.h rsval) so `dbgloc 268435456` dumps as `dbgloc -268435456` like the
   reference; ir_builder's printer follows the same rule.

## Data / linkage emission checked (gasdata vs emit.c)

emitdat (serialization, zero-fill accumulation, .comm, .balign, .fill,
.ascii/.quad masks, %+offset refs), emitlnk (thread .tdata/.tbss, section+flags,
export, Apple __thread_vars bootstrap), emitfin (fp pool sizes 16/8/4 with the
literal zero high half, -dS/-dM comments), elf/macho/pe finalizers and
emitdbgfile/emitdbgloc all read and compared. Probes over empty data, string
escapes, octal escapes, multi-width runs, z-fill, float/hex-float data,
align 1..256, export/thread/common, custom sections/section flags, quoted
symbols, data refs with offsets, adjacent definitions and data/function
interleaving: byte-identical on amd64_sysv and (where applicable) other
targets; tls_link.ssa identical on amd64_sysv/arm64.

## Residual, explicitly not claimed

- The reference parses and emits per function, so a late parse error leaves
  partial stderr/stdout; the port parses the whole module first and emits
  nothing (valid-input output is identical; exit status matches). Matching the
  streaming behaviour would require callbacks throughout the parser.
- The reference has no -G option; the port's gas-flavor option and its
  amd64_apple/arm64_apple aliases are additive CLI surface.
- GNU-style option permutation after positional arguments (argparse) vs BSD
  getopt stopping at the first positional: a trailing `-dP` is parsed as an
  option by the port and opened as a file by the reference binary built on
  macOS. Documented, not reproduced (libc-dependent in upstream).
- Invalid-input diagnostic text is not claimed; -h text lists the port's extra
  options.
- Dwarf/native/object/jit/interp are port-only and out of scope.
