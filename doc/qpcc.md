# QPCC — C language support

[中文版本 (Chinese Version)](zh/qpcc.md)

QPCC (`qpcc/`) is the C front end and code generator that lowers C to the
qbe.mbt IR builder and from there to Mach-O arm64. This page is the feature
matrix: what it accepts and lowers, what is partial, and what is missing.

## Evidence

- `sh qpcc/test.sh` — the clang oracle over `qpcc/tests/*.c` (134 fixtures):
  each file is compiled with clang and with QPCC, both objects are linked, both
  binaries run, and exit code and stdout are compared. All 134 pass.
- `moon test --target native qpcc/front qpcc/sema` — lexer/parser and semantic
  analyser whitebox tests.
- `examples/qpcc-selfhost/` — QPCC compiles the whole of vendored QBE and the
  resulting binary passes 58/58 semantic fixtures.
- `qpcc/chibicc-tests/` — a vendored chibicc subset kept as a reference corpus
  (not run by `test.sh`).

The fixture column below names the oracle cases that cover a feature, or
"sweep" for a hand-run end-to-end check.

## Modes

| Mode | Flag | Notes |
| --- | --- | --- |
| C11 | default, `-std=c11` | the baseline |
| C23 | `-std=c23` | C23 syntax on top of the same front end; partial (see below) |
| C2y | `-std=c2y` | C2y syntax on top of the same front end; see the C2y section |

The C preprocessor is **external**: run `clang -E -P` before QPCC when the
input uses `#include`/`#define`. The driver only strips the remaining lines
that begin with `#`, so a bare `#define`d name is *not* expanded.

## Legend

- **yes** — compiled, linked and run correctly.
- **partial** — accepted, but a semantic or layout detail is missing.
- **no** — rejected or unsupported.

## Types

| Feature | Status | Evidence |
| --- | --- | --- |
| `void`, `_Bool` | yes | `bool` |
| `char`, `signed`/`unsigned char` | yes | `char`, `uchar` |
| `short`, `int`, `long`, `long long` | yes | `short`, `longlong`, `arith` |
| signed/unsigned arithmetic, conversions, usual arithmetic conversions | yes | `unsigned`, `ushr`, `uint_widen`, `shift_signedness`, `op_size` |
| `float`, `double` | yes | `float`, `float2` |
| `long double` (8 bytes on arm64) | yes | sweep |
| `_Complex` (arithmetic, literals, `__real__`/`__imag__`, mixed) | yes | `complex_add`, `complex_addmix`, `complex_cmp`, `complex_compound`, `complex_div`, `complex_float`, `complex_lit`, `complex_mixed`, `complex_mul`, `complex_real_imag`, `complex_sub`, `complex_unary` |
| `__int128` | yes | sweep |
| pointers | yes | `ptr`, `ptr2`, `ptr_index_diff`, `alias_shape` |
| arrays, including multi-dimensional | yes | `arr`, `arr_member`, `arr_member_loop`, `static_ptr2d`, `static_ptr2d_b`, `static_ptr2d_c` |
| variable-length arrays | partial | `sizeof_vec`; indexing works, but `sizeof` returns the pointer/element size, not the runtime length |
| functions and function pointers | yes | `fnptr`, `fnptr2`, `fnptr_param` |
| `_BitInt(N)` | yes (C23) | sweep |
| `char8_t` | yes (C23) | `char8_t`; a built-in name for `unsigned char` |
| `_Decimal*`, `_Fract`, `_Accum` | no | — |

## Declarations and storage

| Feature | Status | Evidence |
| --- | --- | --- |
| `typedef`, typedef chains | yes | `typedef`, `typedefptr`, `typedefstruct`, `bf_typedef` |
| globals, tentative definitions, BSS | yes | `global`, `global2`, `globals`, `bss_zero`, `global_struct`, `global_ptr`, `global_stride`, `global_bitfield` |
| `static` locals and file-scope `static` | yes | `static_ptr`, `static_ptr2d`, `static_desig` |
| `extern` | yes | `chibicc-tests/tests/extern.c` |
| `const`, `volatile` | yes | sweep |
| `restrict` (and `__restrict`) | yes | sweep |
| `inline` (and `__inline`) | yes | sweep |
| `register`, `auto` | yes | sweep |
| `_Thread_local` / `__thread` | yes | sweep |
| `_Alignas` (locals and globals) | yes | `alignas`, `alignas_global` |
| `_Alignof` | yes | `alignof` |
| `_Noreturn` | yes | sweep |
| `__attribute__((unused))`, `((noreturn))` | yes | sweep |
| `__attribute__((packed))` | partial | parsed but ignored — it does not change `sizeof` |
| `__attribute__((aligned(N)))` | partial | parsed but ignored — it does not change alignment |
| `__auto_type` | no | explicit "not supported" error |
| K&R (old-style) function definitions | no | — |
| nested functions | no | parse error |

## Aggregates and layout

| Feature | Status | Evidence |
| --- | --- | --- |
| `struct` | yes | `struct`, `structarr`, `structptr`, `structsz`, `struct_ptr_index`, `global_struct` |
| `union` | yes | `union` |
| anonymous `struct`/`union` members | yes | sweep |
| empty `struct`/`union` (GNU extension, no members) | yes | a zero-sized type: `sizeof` is 0 and `_Alignof` is 1 |
| `enum` (explicit values, gaps, duplicates) | yes | `enum`, `enum_gap`, `shift_enum` |
| C23 `enum E : T` fixed underlying type | yes | `enum_fixed`; the enum is its underlying integer type |
| by-value struct arguments and returns, nested aggregates | yes | `ins_byval`, `ref_byval`, `nested`, `aggregate_double` |
| bitfields — unsigned fields, globals, arguments | yes | `bitfield`, `bitfield_2929`, `bitfield_top`, `bf_arg`, `bf_global`, `bf_pos`, `global_bitfield` |
| bitfields — some signed combinations | partial | `struct { int a:3; int b:2; }` misreads the field values |
| flexible array members | partial | `sizeof` is right, storage is the caller's job |
| `#pragma pack` | no | preprocessor is external |

## Initializers

| Feature | Status | Evidence |
| --- | --- | --- |
| scalar and aggregate initializers | yes | `initarr`, `initstruct`, `compound_char`, `compound_zero` |
| designated initializers (arrays, structs, order, gaps) | yes | `designated_dec`, `designated_gap`, `designated_inc`, `designated_int`, `designated_order`, `designated_ptr` |
| compound literals, including at file scope | yes | `file_compound_ptr` |
| string initializers | yes | `str`, `string` |
| address-constant initializers and relocations | yes | `static_desig`, `global_ptr` |
| `sizeof` of a string literal or a string-initialised `char[]` | partial | `sizeof("ab")` is 8 and `sizeof(char s[] = "ab")` is 0, not 3 |

## Expressions and operators

| Feature | Status | Evidence |
| --- | --- | --- |
| arithmetic, bitwise, comparison, logical operators | yes | `arith`, `logic`, `op_tab`, `optab_shape` |
| short-circuit `&&` / `\|\|` and `\|\|` chains | yes | `shortcircuit`, `or_short` |
| conditional `?:`, including the GNU `a ?: b` | yes | `cond`, `cond_arm_width` |
| assignment and compound assignment, `++`/`--` | yes | sweep |
| casts, integer promotions, word/wide conversions | yes | `cast`, `widen_word_const`, `store_wide_const`, `uint_widen` |
| `sizeof` of types, expressions and arrays | yes | `sizeof`, `sizeof_ins`, `sizeof_vec`, `op_size` |
| `_Generic` | yes | `generic`, `generic2` |
| `_Static_assert` | yes | `staticassert` |
| C2y `_Countof(expr)` / `_Countof(type-name)` | yes | `countof` |
| C2y `_Maxof(type-name)` / `_Minof(type-name)` | yes | `maxminof` |
| `__builtin_offsetof`, `__builtin_types_compatible_p`, `__builtin_constant_p`, `__builtin_expect`, `__builtin_unreachable` | yes | sweep |
| `typeof`/`__typeof__`/`typeof_unqual`, `__alignof__` | yes | sweep |
| statement expressions `({ ... })`, including inside macros | yes | sweep |
| `__extension__` | yes | sweep |
| `__real__`, `__imag__` | yes | `complex_real_imag` |
| `__builtin_va_arg`, `<stdarg.h>` | yes | after `clang -E`; sweep |
| `__builtin_va_list` as an assignable value | no | `aq = ap` hits an internal error |
| C23 `auto` inference and `__auto_type` | yes | `auto_infer`; a single plain declarator with an initializer |

## Statements and control flow

| Feature | Status | Evidence |
| --- | --- | --- |
| `if`/`else`, `for`, `while`, `do`/`while` | yes | `if`, `for`, `while`, `dowhile` |
| `switch`/`case`/`default`, fallthrough, jump into `default` | yes | `switch`, `switchfall`, `switch_into_default`, `switch_duff2` |
| `break`, `continue`, `goto` (forward and loops) | yes | `gotofwd`, `gotoloop` |
| computed goto `goto *p` and `&&label` | yes | `computed_goto` |
| Duff's device | yes | `duff`, `switch_duff2` |
| case ranges `case 1 ... 5:` | yes | sweep |
| C2y named loops: `label:` on a loop/switch, `break label;`, `continue label;` | yes | `named_loops` |
| C2y `_Defer` statements | yes | `defer_basic`, `defer_header` |
| C23 `[[fallthrough]]` in statement position | yes | `fallthrough_attr` |

## Functions

| Feature | Status | Evidence |
| --- | --- | --- |
| definitions, prototypes, K&R-free declarations | yes | `fib`, `m0_return42`, `three_ref` |
| variadic definitions (`va_start`/`va_arg`/`va_end`/`va_copy`) | yes | `vararg`, `vararg_def` |
| indirect calls | yes | `fnptr`, `fnptr2`, `fnptr_param` |
| inline assembly / `asm` labels | no | `asm` label panics; inline `asm` is not lowered |

## Literals and strings

| Feature | Status | Evidence |
| --- | --- | --- |
| integer literals (decimal, hex, octal, binary), suffixes | yes | `big_const`, `widen_word_const` |
| floating literals | yes | `float`, `float2` |
| character literals, `u8'x'` | yes | sweep |
| string literals with escapes | partial | a plain string works; `"a\nb"` can fail to parse |
| wide/UTF strings `L`, `u`, `U` | no | parses, but the elements are wrong at run time |
| C23 digit separators (`1'000`) | no | parse error |

## Atomics

| Feature | Status | Evidence |
| --- | --- | --- |
| sequentially consistent load/store (`ldar`/`stlr`) and fences (`dmb ish`) | yes | `atomics` |
| read-modify-write forms (exchange, compare-exchange, fetch-add, ...) | no | needs LL/SC or LSE lowering |

## C23 (`-std=c23`)

| Feature | Status | Evidence |
| --- | --- | --- |
| `bool`/`true`/`false`, `nullptr` | yes | sweep |
| `constexpr` | yes | `constexpr_assert`; an object usable in constant expressions |
| `_BitInt(N)` | yes | sweep |
| `typeof_unqual`, `alignas`/`alignof` | yes | sweep |
| C23 attributes `[[...]]` (`[[maybe_unused]]`, `[[noreturn]]`) | yes | sweep |
| `static_assert` over literal constants | yes | sweep |
| binary literals `0b1010`, `u8'x'` | yes | sweep |
| `auto` type inference | yes | `auto_infer` |
| `char8_t` | yes | `char8_t` |
| digit separators (`1'000`) | yes | `digit_sep` |
| fixed underlying enum types (`enum E : unsigned char`) | yes | `enum_fixed` |
| `[[fallthrough]]` in statement position | yes | `fallthrough_attr` |

## C2y (`-std=c2y`)

C2y syntax is opt-in through `-std=c2y`; C11 and C23 are unchanged.

| Feature | Status | Evidence |
| --- | --- | --- |
| `_Maxof(type-name)` / `_Minof(type-name)` (N3628) | yes | `maxminof`; an integer type is required, `_Bool` is rejected, and the result is a constant of that same type |
| `_Countof(expr)` / `_Countof(type-name)` (N3369) | yes | `countof`; the operand must have array type |
| named loops (N3355): `label:` on a loop or switch, `break label;`, `continue label;` | yes | `named_loops` |
| `_Defer` statements (TS 25755 / N3590) | yes | `defer_basic`, `defer_header` |

The friendly spellings come from hand-written headers under
`qpcc/include/qbe/`: `stddefer.h` (`defer` -> `_Defer`), `stdcountof.h`
(`countof` -> `_Countof`), and the QPCC extensions `stdmaxof.h`
(`maxof` -> `_Maxof`) and `stdminof.h` (`minof` -> `_Minof`). The external
preprocessor finds them with `clang -E -P -I <qpcc>/qpcc/include/qbe`;
QPCC itself only knows the underscore keywords.

Known limitations:

- `_Defer` runs when its enclosing block is left, in reverse order, on any
  exit (falling off the end, `return`, `break`, `continue`, `goto` out).
  A jump that would leave the `_Defer` statement itself, and a `goto` into
  it, are diagnosed; `longjmp` past a defer is undefined, as the TS says.
- clang does not implement `_Maxof`/`_Minof`, named loops or `_Defer` yet,
  so those fixtures are QPCC-only (`// expect-exit N`), checked against their
  expected exit code rather than a clang reference.

## `_Tagged_union` (`-f_tagged_union`)

A QPCC extension with no WG14 proposal behind it. It is opt-in through
`-f_tagged_union`; without the flag the three keywords are ordinary
identifiers, so C11/C23/C2y are unchanged.

```c
_Tagged_union Value {
  int as_int;
  float as_float;
};

_Tagged_union Value x = { .as_int = 100 };
x = (_Tagged_union Value){ .as_float = 1.5f };  /* sets the tag */
switch (_Tag_of(x)) {
  case _Get_tag(_Tagged_union Value, as_int): break;
  case _Get_tag(_Tagged_union Value, as_float): break;
}
```

| Feature | Status | Evidence |
| --- | --- | --- |
| `_Tagged_union Tag { members }` | yes | `tagged_union` |
| natural layout: an `int` tag at offset 0, the members overlapping after it | yes | `{ int; float }` is 8 bytes, `{ int; double }` is 16 |
| `x.m` read | yes | `tagged_union` |
| `_Tag_of(x)`, an `int` rvalue | yes | `tagged_union` |
| `_Get_tag(_Tagged_union T, m)`, an integer constant expression | yes | `tagged_union` (`_Static_assert` and `case`) |
| designated initializers: local, compound literal, global, static | yes | `tagged_union`, `tagged_union_static` |

Semantics and limitations:

- The tag is a synthetic `int` at offset 0 and the members overlap after it,
  so the layout is exactly `struct { int tag; union { members } payload; }`.
- A member cannot be assigned directly: `x.m = v`, `x.m += v`, `x.m++` and a
  store to a nested member are all diagnosed. Change the value as a whole
  instead, e.g. `x = (_Tagged_union T){ .m = v };`, which sets the tag.
  Discriminators are the member declaration order, 0-based.
- Reading a member whose tag is not current is undefined behaviour; there is
  no runtime check. Taking the address of a member and writing through it
  also bypasses the tag: `&x.m` is allowed, but the invariant is then the
  programmer's responsibility.
- An initializer must name a member, as in `{ .as_int = 100 }`. A positional
  element (`{ 1 }`, `{ 0 }`) or an empty list (`{}`) is diagnosed. The last
  designator wins, as for a union.
- Only `_Tagged_union Tag` names the type (there is no bare `Tag` alias), so
  `typedef _Tagged_union Value value_t;` is how to get a short name.
- clang implements none of this, so the fixtures are QPCC-only
  (`// expect-exit N`) and are checked against their expected exit code.
## Known gaps at a glance

- The preprocessor is external (`clang -E`); no `#include`/`#define` handling.
- `sizeof` of a string literal or a string-initialised `char[]`.
- VLA `sizeof`.
- Some signed bitfield widths.
- `__attribute__((packed))` and `__attribute__((aligned(N)))` are ignored.
- Wide/UTF string literals, string escapes in some cases.
- Atomics: no read-modify-write.
- `asm` labels and nested functions.
- Diagnostics carry statement-level positions.

## See also

- `qpcc/README.md` — pipeline, usage and limitations.
- `examples/qpcc-selfhost/` — the self-host build and semantic check.
