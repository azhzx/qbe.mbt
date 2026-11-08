# Frontend parity audit — 2026-11-08

Baseline: HEAD938fc19 + pre-existing lexer/parser edits; upstream661ceb22. This report is a live audit, not a completion certificate.

## Full source reads
Read all of vendor/qbe/parse.c (1–1449) and every production lexer/*.mbt and parser/*.mbt declaration. Floating-literal helpers received a second independent review by registers and are now assigned there for exact-rounding repairs.

| C declaration | MoonBit counterpart | Status |
|---|---|---|
| PState,Token,kwmap,lexinit,tokval | lexer TokenKind/Token,keyword_of,Op.from_string | enum decomposition; parser validates op keywords; missing alloc1/2 sent to types owner |
| getint | parser.parse_int64 | wrapping Int64 arithmetic matches uint64 bits; validate boundaries through token scanner |
| lex,Alpha,Quoted | Lexer.tokenize,read_ident,read_string,scan_float_tail and scanners | full read; pre-existing identifier validation preserved; fscanf whitespace omission fixed |
| peek,next,nextnl,expect,err | Parser peek/next/next_kind/next_nl/expect/error | eager token array vs stream; malformed-type EOF panic fixed at missing closing-brace check |
| tmpref,findblk | Parser.tmpref/findblk,Fn arrays | linear search vs hash is safe identity adaptation; no truncation |
| parseref,parsecls,findtyp | same named methods | extern/thread incorrectly accepted on non-global fixed; backwards type shadowing preserved |
| parserefl | same method | pre-existing ellipsis validation retained and inspected; arg types and environment dispatch fully read |
| closeblk,parseline,parsefn | parsefn/parseline/parse_phi/parse_call/parse_ins_args | array block representation; subword call accepted, aggregate noncall/start phi rejected; extra args still validated; 29-bit debug/blit ranges restored |
| usecheck,typecheck | tc_usecheck/tc_argcls/typecheck,clsmerge | full branch comparison; class merge duplicate with SSA tracked for centralization |
| parsefields,parsetyp | same methods | missing brace, bounded NField32, unsigned size max, negative alignment division, distinct single-alt union flag fixed |
| parsedatref,parsedatstr,parsedat | parsedat + Dat constructors | omitted adjacent string/global list tokens and wrong ref/string width fixed |
| parselnk,parse | same methods + Linkage/Parser state | full read; empty-section presence distinct from absent still outstanding |
| printcon,printref,printfn | same + ktoc,jtoa,hex4,hex_digit,printmem | sentinel identity correction after Fn reserves con0; RNone prints R; full remaining branches read |

## Confirmed RED/GREEN evidence
- parser/upstream_parity_wbtest: initial 8 cases: missing-brace SIGABRT, then1/8 pass; after fixes8/8. Expanded15 cases had6 failures (29-bit bounds, ignored invalid operand, unsigned size, signed division, float whitespace), then all pass.
- parser/printing_parity_wbtest: RED0/3 then GREEN3/3 (literal3735936685 is not UNDEF; absent ref prints R; sentinel is con0 identity only).
- Parser suite39/39 at checkpoint; lexer+parser51/51 before printing cases.
- test/audit_frontend_data.ssa: vendor accepts adjacent strings/global symbols, narrow refs and sb call; assembly compare1/1 after repair.
- Float independent oracle has decimal single double rounding, hex subnormal double rounding, and decimal overflow; registers owns fixes.

## Open checks / required follow-through
- C NPred63/NIns instruction limits, extra operands count, malformed EOF and empty-section sentinels.
- Resultful vastart must apply nonvariadic guard too; class/op public boundaries need final regression.
- CLI/multisource lifecycle and shared GAS emission owned driver-review.
- No claim all port-only targets, interpreter, object writer, IR builder or bindings are upstream transcriptions; upstream counterparts do not exist for those. Shared field changes need consumer checks.
