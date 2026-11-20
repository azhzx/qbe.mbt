# Frontend audit 3 — lexer + parser vs vendor/qbe/parse.c

Worker: frontend, shared task task-1. Baseline: port tree at 2026-11-13 20:00,
reference vendor/qbe revision 661ceb22, binary vendor/qbe/qbe. Isolated build
build/a3-frontend. Report reconstructed by the Lead from the worker's final
message (the worker's turn ended before writing this file).

Upstream read completely: vendor/qbe/parse.c (all of it: lex/Alpha/Quoted,
getint, PState, tmpref/findblk, parseref/parsecls/findtyp/parserefl,
closeblk/parseline/parsefn, usecheck/typecheck, parsefields/parsetyp,
parsedatref/parsedatstr/parsedat, parselnk, parse, printcon/printref/printfn),
plus all.h tokens/limits and the ops.h keyword table.

Status legend: V verified against the C; A safe representation adaptation;
D divergence (fixed); M missing.

## Declaration coverage

| C | port | status |
|---|---|---|
| PState, Token, kwmap, lexinit, tokval | lexer TokenKind/Token, keyword_of, Op::from_string | V/A (eager token array; "argv" rejected like C) |
| getint | parser parse_int64 | V (wrapping Int64 matches the uint64 bits) |
| lex, Alpha, Quoted, fscanf float tail | Lexer.tokenize/read_ident/read_string/scan_float_tail | V; C99 nan(n-char-seq) added |
| peek/next/nextnl/expect/err | Parser.* | V (clamped at trailing TEof like C) |
| tmpref/findblk | Parser.tmpref/findblk | V (map instead of linear list) |
| parseref/parserefl/parsecls/findtyp | same | V (env check position, sub-word classes, aggregate rules) |
| closeblk/parseline/parsefn | parsefn/parseline/parse_operands/build_blit | V (rewritten to the C operand loop) |
| usecheck/typecheck/clsmerge | typecheck/tc_* | V |
| parsefields/parsetyp | same | V (NField cap, unsigned sizes) |
| parsedatref/parsedatstr/parsedat | same | V (adjacent lists, widths, ref offsets) |
| parselnk/parse | same | V (section text verbatim with quotes) |
| printcon/printref/printfn | printcon/printref/printfn | V (rsval for RInt/RSlot fixed in integration) |

## Fixed defects (RED observed against vendor/qbe/qbe, then GREEN)

1. Resultful blit: `%r =w blit %p,%q,4` accepted by the reference (result dropped);
   port rejected "unknown keyword blit".
2. Extra blit operands: `blit %p,%q,4,5` accepted (extra discarded); port rejected.
3. NPred: 63-argument phi accepted, 64th is "too many arguments"; port had no
   bound (NPRED=63 restored, also enforced for ordinary operands).
4. Resultful vastart in a non-variadic function: reference rejects, port compiled.
5. Data ref offset: `l $a + <newline> 8` rejected (parsedatref uses next(), not
   nextnl()); port accepted.
6. Section presence: `section ""` emitted `.data` and duplicate sections were
   accepted; section/secf are now stored as C does (verbatim token text with
   quotes; absent = ""), so `.section ""`, `,""` and "only one section allowed"
   all match. See doc/audit3-driver.md for the gasdata half.
7. nan(n-char-seq): d_nan(foo)/d_nan(123)/d_nan(00123)/d_nan(0x10)/nan()/d_-nan(1)
   payload bits (Darwin strtod rules); port rejected the literal.
8. Exact single-precision rounding: 63 adversarial dyadic midpoints, 4 differed
   by 1 ulp because decimal_digits truncated at 60 significant digits with a
   sticky bit; now all digits are kept and the tie is exact (376 random decimals,
   260 hex mantissas, 5000-digit and exponent-extreme cases identical).
9. Parser panic on truncated input (`%x =sb call<EOF>`): peek/next ran off the
   token array (PanicError, rc 134) where the C lexer keeps returning Teof; now
   the same clean "`( expected, got ?? instead`" message. 2403 corpus truncations:
   0 rc diffs, 0 panics.
10. `%x =w argv`: the reference lexer does not know argv (internal op); port compiled.
11. NIns limit (1<<20 instructions per function): `too many instructions` now
    matches the reference line for a 1,048,578-instruction block.
12. Diagnostic drifts: "invalid size specifier %c in data" and
    "data name, then = expected" now byte-identical.

## Residual (confirmed, not fixed)

- ABI over-alignment diagnostics: reference prints "qbe:file:line: sysv abi
  requires alignments of 16 or less" / arm64 "... larger than 8 ..."; the port
  reports QbeError::Ice (no file:line) and rv64 previously panicked (rv64 owner
  converted it to a QbeError in this round).
- The port lexer emits TId for bare identifiers, so an unknown keyword in a
  skipped position is reported by the parser at a later token rather than
  eagerly by the lexer; diagnostic text/line only, both reject.
- The reference streams partial assembly/dumps before a late parse error; the
  port parses the module first (valid-input output is identical).
- Port-only ops readable from source (asm, atomicload/atomicstore/fence) stay;
  argv is now rejected (it is not in the reference lexer).

## Verification

- moon build (isolated) OK; moon test -p parser: green after the Lead repaired
  one test-fixture interpolation bug (the only failure in the full run).
- Corpus -dPMNCAGK amd64_sysv: 57/57 identical; assembly 58/58 identical on
  amd64_sysv/arm64/rv64; tls_link.ssa byte-identical.
- Float oracle: 15 nan payload forms, 376 decimal, 260 hex-mantissa, 63
  midpoint, 60 long-digit/exponent-extreme cases identical.
- Mutation fuzz (ref-accepted mutants, -dPMNCAGK + asm): no valid-input
  divergence; only the -nan asm comment, fixed by the types owner.
