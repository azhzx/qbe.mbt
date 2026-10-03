# QPCC / qbe.mbt Pitfalls Compendium

[中文版本 (Chinese Version)](zh/pitfalls.md)

This document collects the **real bugs already fixed** in this repository, along with the toolchain pitfalls surrounding them.

Two sources:
- **Writing QPCC (A1–A9 + self-hosting)**: C semantic details swallowed by shortcuts taken during implementation
- **The qbe.mbt backend itself**: IR passes, register allocation, instruction selection, the encoder

> Conclusion first: **self-hosting is not "proof that the compiler works", but a machine purpose-built to expose the compiler's assumptions.**
> And more dangerous than these bugs is that **the acceptance script itself lies.**

---

## Contents

1. QPCC front end / sema
2. QPCC codegen / initializers / data
3. qbe.mbt: IR and passes
4. qbe.mbt: arm64 backend
5. qbe.mbt: other backends
6. Debug info and tools
7. Toolchain / environment pitfalls
8. Notes on vendor/qbe
9. Debugging methodology
10. Current status

---

## 1. QPCC front end / sema

### 1.1 `typedef` loses its own signedness (`3f36ffc`)

**Symptom**: the self-hosted qbe reports `missing first operand in par` for every floating-point-class parameter.

**Root cause**: when `declspec_to_type` handled `uint x` (`uint` = `typedef unsigned int`), it found that the declaration did not spell out `unsigned`, so it re-derived the type with `CInt(!uns)`, turning `uint` into a **signed** type.

The consequence was amplified in QBE:

```c
struct Ins { uint op:30; uint cls:2; };   /* cls is the top two bits of a 32-bit word */
```

When `cls` is signed it is read with an **arithmetic right shift**, so `cls=2` reads as **-2** → array index out of bounds.

**Lesson**: a typedef's signedness/width must be **inherited** and must not be overwritten a second time by declaration specifiers. Symptoms show up in places that look completely unrelated (floating-point parameters, array out-of-bounds), because the real propagation path is "does the bitfield read choose `Shr` or `Sar`".

### 1.2 Variadic arguments lack default argument promotion (`baade27`)

**Symptom**: the self-hosted qbe segfaults on **any conditional branch**.

**Root cause**: `check_call` passed every argument at its original type, performing neither array decay nor `float`→`double` conversion.

```c
fprintf(f, "%sbb%d\n", T.asloc, id0 + b->id);
```

`T.asloc` is the `char asloc[4]` inside `struct Target`; it was **copied by value** instead of passed by address → the two bytes `.L` were treated as a pointer.

**Lesson**: default argument promotion is a **semantic requirement** of C, not an optimization.

### 1.3 `->` is not dereferenced; `&&`/`||` do not short-circuit (`2ab37cd`)

Three bugs exposed by self-hosting:

1. sema built `TMember`/`PBitField` from the **pointer itself** rather than its dereference, so `p->f` read and wrote the pointer's stack slot
2. Conditions evaluated both sides of `&&`/`||`, so `if (!f || strcmp(...))` dereferenced NULL
3. The stdio shim did not declare `ungetc`/`fscanf`/`getc`/`putc`, turning them into implicit variadic calls

Incidentally: `ARM64_RELOC_ADDEND` was removed — `adrp`/`ldr` compute only the base address and the offset is added with an extra instruction, matching clang.

### 1.4 Incomplete array bounds are not inferred from the initializer (`2835172`)

```c
int x[] = { 1, 2, 3 };   /* the type bound stays 0 */
```

The local alloca was only 8 bytes, so the initializer wrote out of bounds and corrupted the adjacent slot. The bound is now inferred from the initializer (including designators).

### 1.5 `static` locals do not go into the data segment (`0c78f61`)

`static` locals now go into the data segment (zero-initialized, persistent), as C requires; but if the initializer contains `&&label` (a code-generation-time constant), it must remain function-local.

### 1.6 A `case` nested in an `if` inside a switch body is dropped entirely (`6bdaae1`)

**Symptom**: the self-hosted qbe cannot parse `vastart`/`blit` and reports `label, instruction or jump expected`.

**Root cause**: `check_switch` scanned only the **top-level items** of the switch body. QBE's instruction parser is a Duff's device:

```c
switch (t) {
case Ttmp: ... break;
default:
	if (isstore(t)) {
	case Tblit:
	case Tcall:
	case Ovastart:          /* ← nested in the if */
		r = R; k = Kw; op = t;
		break;
	}
	err("label, instruction or jump expected");
}
```

**Lesson**: `case` is a **label in a statement list** and can appear at any nesting depth.

### 1.7 `case X:` does not fall through into `default:` (`ecfefa9`)

**Symptom**: `-h` on the self-hosted qbe prints nothing.

**Root cause**: QPCC treated `default` as a catch-all after all cases:

```c
switch (c) {
case 'd': ... break;
case 'h':
default:                    /* ← shared function body */
	... usage ...
	exit(c != 'h');
}
```

Ironclad IR evidence:

```
@switch.test.41
	%t.223 =w ceqw %t.219, 104          ; match for 'h' succeeded
	jnz %t.223, @switch.case.36, @switch.default.37
@switch.case.36
	jmp @switch.end.32                  ; empty block, jumps away ✗
```

**Lesson**: `default` is **not** an out-of-band branch; it is a position in the statement list. The fallthrough chain must follow **source order**: `case... → default → case...`.

**After this one was fixed, the self-hosting score jumped from 21/76 to 53/76** — QBE's own code is full of `case X: default:`.

---


### 1.8 A pointer difference is inferred as a pointer type (`c1e7596`)

**Symptom**: six test cases `abi5 abi6 abi8 env queen tls` report `sysv abi requires alignments of 16 or less`, while the reference qbe handles them without any problem.

**The root cause is one type inference**:

```moonbit
// qpcc/sema/expr.mbt  check_binary
(CPtr(e), _) => if op == "+" || op == "-" { CPtr(e) } else { lt }
```

The result type of `p - q` (two pointers) was judged to be **`CPtr(elem)`**. In C it is `ptrdiff_t`, an integer.

Then codegen used the **index's type** to decide whether to scale:

```moonbit
// qpcc/codegen/codegen.mbt  gen_bin
(CPtr(el), _) =>
  if !is_ptr_ty(r.ty) {        // scale only when the index type is an integer
    ... idx * sizeof(el) ...
  } else if op == "-" { ... }  // otherwise treat it as ptr+ptr, no scaling at all
```

So `&arr[b - a]` was computed as a **byte offset**. QBE's amd64 ABI is written exactly this way:

```c
// vendor/qbe/amd64/sysv.c  selcall
for (stk=0, a=&ac[i1-i0]; a>ac;)
	if ((--a)->inmem) {
		if (a->align > 4)
			err("sysv abi requires alignments of 16 or less");
```

`&ac[2]` should have been `ac+80` but was `ac+2` → `--a` landed at `ac-38` → it read garbage **outside the allocated region** → spurious error.

**Localization process** (worth reusing):

```
1. Add a self-check to alloc() to confirm the returned memory really is all zeros → rules out "uninitialized"
2. Write alias_shape.c to assert the AClass layout (40/offsets) → rules out "struct offset"; sizeof=40 ✓
3. Print the pointers at the checkpoint: off=-38, start=ac+2 → deduce "scale = 1"
4. Bisect the eight subscript forms one by one:
     ac[n] with a long variable      ✓
     ac[(long)(i1-i0)]               ✓
     ac[i1-i0]  bare pointer diff    ✗   ← exact localization
     ac[3] / ac[d] / ac[(int)(...)]  ✓
```

**Lesson**: in C the distinction between "pointer" and "integer" runs through every step of type inference. Inferring `ptrdiff_t` as a pointer made **another module** (codegen's scaling criterion) take a seemingly reasonable decision. The fix added only 3 lines to sema, but it explained 6 test cases.

Incidentally: the same fixture also exposed that QPCC **does not support a declarator referring to itself** (`AClass *ac = f(sizeof ac[0]);` — clang accepts it as a GNU extension, QPCC reports `use of undeclared identifier`); that is another small issue waiting to be fixed.

---
## 2. QPCC codegen / initializers / data

### 2.1 Aggregate initialization: zero fill / bitfields / element types (`83c3d73`)

Compound literals and aggregate initializers now:

1. **zero the whole object first** (C requires members omitted by the initializer to be 0)
2. **convert scalar elements to the target element type** (previously a `char` array literal was stored word-wise)
3. write bitfield members with a **masked read-modify-write**

Self-hosting symptoms: `lnk = (Lnk){0}` did not zero `lnk.thread` → `only data may have thread linkage`; `(char[16]){4,0,1,...}` was written in 4-byte units and clobbered its own `x29` save slot.

### 2.2 A global bitfield initializer overwrites its neighbors (`4554693`)

The initializer for a bitfield member wrote across the **entire declaration width**, overwriting all adjacent bitfields. QBE's `optab` is exactly this structure (`canfold`/`hasid`/`commutes`/`pinned` packed into one word), so `canfold` was always wrong → constant folding failed → `i->to` was invalid → `die("unreachable")`.

### 2.3 Compound members are not copied (`7a60303`)

`store_scalar` had `_ => ()` for aggregate types, so `.to`/`.arg` in `(Ins){ .op = ..., .to = to, .arg = { a0, a1 } }` were **lost entirely**. Switched to `memcpy`.

### 2.4 Nested designators only applied the first level (`e6e591e`)

```c
static char *sec[2][3] = { [0][0] = "ab", [0][1] = "cd", [0][2] = "ef" };
```

All three landed in slot 0, and the last one copied the string's **bytes** into the pointer slot. Discovered in QBE's amd64 emitter.

### 2.5 Global relocations are not sorted (`986ff47`)

Data emission walked relocations in order, but a **decreasing** array designator (such as a keyword table written backwards) produced relocations in a scrambled order, so addresses landed at the wrong offset. They are now sorted by offset.

### 2.6 A file-scope array compound literal has no static object (`30ae032`)

```c
static uchar *matcher[] = {
	[Pob] = (uchar[]){ 1, 3, 0, 3, 1, 0 },
};
```

A file-scope array compound literal has **static storage duration**, but `ptr_reloc` did not generate a relocation → the pointer was NULL → `runmatch` crashed.

### 2.7 The relocation addend is discarded; `&arr[i]` is not recognized (`9f8d2c0`)

- The object-file emitter **zeroed** the 8 bytes at every data relocation site, discarding the addend carried inline by `ARM64_RELOC_UNSIGNED`; `static struct Ins *cur = &buf[4]` therefore pointed at `&buf[0]`
- `ptr_reloc` only recognized `&name`, and `&buf[i]` produced no relocation at all

### 2.8 Duplicate basic block names (`2a88953`)

`new_block` had no per-function serial number, so repeated `switch.case`/`switch.test` labels **collided**. This is both a real codegen bug (fixture `switchfall`) and a prerequisite for running SSA checks on large inputs.

---

## 3. qbe.mbt: IR and passes

### 3.1 gvn's value-number replacement has no dominance guarantee (`aa5494f`)

When `gvn`'s killins replaced a definition with a "canonicalized instruction", it did not check whether the replacement value **dominates** the use site, introducing an SSA dominance violation.

### 3.2 gvn's phi deduplication has no dominance guarantee (`77d45f7`)

`dedupphi` replaced a phi purely because "the arguments are the same"; it now requires the replacement value to dominate the block containing that phi. Together with the previous item, the last failing file disappeared: **all QBE sources compile through QPCC into Mach-O arm64 object files (19/19)**.

### 3.3 No definition deduplication after coalesce / gvn / gcm (`f647da1`)

Added a shared `gvn_dedup_defs` that guarantees **each temporary has exactly one definition** after every pass, and re-enabled slot coalescing.

### 3.4 mem/promote slot promotion is too aggressive (`2835172`, `0c78f61`, `8124942`)

Three stages:

1. Promote only slots whose uses all lie in the same block, avoiding moving a load ahead of the store that defines it
2. Allow slots whose uses **cross blocks** (SSA construction will add phis); but keep **read-before-write** slots in memory, avoiding SSA uses with no definition
3. When no visible definition can be found, no longer abort; just leave the slot in memory

**Lesson**: every "relaxation" of this pass corresponds to a real class of SSA violation; when tightening it, you must be able to say "why this is safe".

---

## 4. qbe.mbt: arm64 backend

### 4.1 `add/sub` immediates do not encode `lsl #12`; overflow slot copies; `nrglob` (`fc9d6f8`)

- `add/sub` immediates lack the `lsl #12` form
- The binary emitter does not handle copies **to/from stack slots**
- `spill` does not reserve a register slot for `nrglob`

This item also re-enabled `gvn`/`gcm`.

### 4.2 Large symbol offsets are truncated (`545f726`)

Symbol constants with offsets above `0xfffff` were emitted with `add #imm12, lsl #12`, **masking off the high bits**. Offsets that do not fit a shifted imm12 now go through `movz`/`movk` into the reserved `IP0` (x16). Found with `&arr[1 << 20]`.

### 4.3 Small PAGEOFF12 addends are not inlined (`98db849`)

The small-offset version of the same problem.

### 4.4 Wrong default for negated comparison conditions (`6eda93f`)

`arm64_cmpop` must be the identity for **self-inverse** conditions (`eq`/`ne`/`fne`/`feq`), but it returned `eq` for every case, so "a comparison after the two constants were swapped" compiled to the wrong condition. **It had previously been masked by gvn's constant folding.**

### 4.5 Floating-point constants (`c0f4c36`, `d04eb96`, `754ebdb`)

- `ir_builder::fconst/sconst` now bind floating-point constants to a temporary (copy), matching QBE's parser, guaranteeing that the backend sees a register operand
- The binary loader must be able to materialize single/double-precision constants (`movz`/`movk` into the GP view and then `fmov`), and **must not depend on the instruction class** (the pipeline may change it)
- A single `MOV` that produces a floating-point constant must be followed by `fmov`; when constants are interned, floating-point constants must be **distinguished from each other**

### 4.6 Bit-operation bugs in the binary encoder (`1f6ef7a`)

Found by differential testing (`tools/check_route_b.py` compares route B's `__text` against the route A text produced by clang assembly):

- `enc_br`/`enc_blr` used `0xD6<<21` instead of `<<24` (**a production bug**)
- `MOVN`, `ORR` bitmask immediates, and the `ADD`/`SUB` extended-register forms
- A complete bitmask immediate encoder (including wraparound protection for `1L<<64` and `>>64`)

**Lesson**: **differential testing is more effective than unit testing**. Comparing a hand-written encoder byte-for-byte against a "reference implementation" catches bugs that are semantically correct but encode incorrectly.

---

## 5. qbe.mbt: other backends

### 5.1 la64: `Addr` is treated as a no-op in isel (`b66d64b`)

`isel_la64` treated `Addr` as an internal no-op, so the addr that `la64_selvastart` materialized for the register save area was dropped, and the emitter stored an **uninitialized register** into the `va_list`. rv64's isel emits it; just do the same.

### 5.2 la64: mnemonics / labels / aggregate ABI (`6b303b7`)

- Emit `add.l`-style mnemonics (LoongArch uses `.d`)
- Per-function block ids were reused → duplicate `.L1` / lost labels
- The aggregate ABI was incomplete

Ported rv64's ABI (aggregate parameter register assignment, `Cfpint` conversion, `Cptr` blob, return registers), fixed FP greater-than comparisons (`clt`/`cle` were reversed), routed int↔float conversions through the FPR, materialized immediates, and preserved scratch registers. **Assemblable reference tests rose from 220 to 338.**

### 5.3 wasm: validator-clean

The same commit made the wasm output pass the validator.

---

## 6. Debug info and tools

### 6.1 Must emit DWARF4, not DWARF5 (`6f9b92f`)

macOS's lldb rejects it outright: `This version of LLDB does not support DWARF version 5 or later`. The compilation unit was changed to DWARF4 (version-4 header, `DW_FORM_addr` for low/high PC, no `.debug_addr`).

**Lesson**: caught by the smoke test in macOS CI — validating DWARF only on Linux misses it.

### 6.2 On GitHub's macOS runner, lldb is not on PATH (`8edcd64`)

Fall back to `xcrun lldb`; also capture the output with `|| true` so that `set -e` does not swallow the diagnostics.

---

## 7. Toolchain / environment pitfalls

### 7.1 macOS has no `timeout(1)`, and `timeout ... || echo ok` gives a false green

The worst mistake I made: the comparison script wrote `timeout 20 $qbe f.ssa`; on macOS `timeout` does not exist → it returns **127** → the output is empty → **two empty strings compare equal** → all 76 cases reported "consistent".

**The real score at the time was 20/76; I reported 76/76.**

**Lesson**: a comparison script must **compare both the exit code and the output**, and treat "the command did not run" (127) as failure; do not use `$(...)` to compare something that "might output nothing"; write the watchdog yourself as `( sleep N; kill -9 $pid ) &`.

### 7.2 zsh does not word-split unquoted variables

```sh
INC="-nostdinc -I a -I b"
clang -E -P $INC file.c        # zsh: $INC is one whole argument → "unknown argument"
```

bash is fine, zsh always blows up. **Either use an array or spell the arguments out in full.** (Likewise zsh's `print -r --` does not exist in bash.)

### 7.3 `vendor/qbe` is a submodule

```sh
git checkout -- vendor/qbe/parse.c          # ✗ pathspec did not match
cd vendor/qbe && git checkout -- parse.c    # ✓
```

After debugging, **always confirm the submodule is clean**, otherwise temporary debug code gets compiled as source into the next conclusion.

### 7.4 QBE's test cases are CRLF

`vendor/qbe/test/*.ssa` are CRLF, so you must first run `tr -d '\r'`.

### 7.5 Link QBE with `xcrun ld`, not clang

```sh
xcrun ld -syslibroot $(xcrun --show-sdk-path) -o qbe -lSystem *.o
```

Linking object files produced by this repository with clang reports `ld: -lto_library library filename must be 'libLTO.dylib'`.

### 7.6 Do not build `vendor/qbe/tools/`

`tools/lexh.c` is a **build-host tool**, not part of qbe; building it fails with `division by zero in constant expression`.

### 7.7 Two scripts must not share an output directory

`build-qbe-with-qpcc.sh` starts by `rm -rf`-ing its own output directory. It once shared `.qpcc_build/` with the quick script, so the corpus was deleted halfway through and the comparison "finished" after only 31/76. They now use separate directories.

---

## 8. Notes on vendor/qbe

- **`alloc()` zeroes memory** (`alloc` → `emalloc` → `calloc(1, n)`). C code relies heavily on "uninitialized fields are 0". When you read garbage, **suspect the struct layout/offsets first**, not "it was not zeroed".
- **`struct Tmp` is 128 bytes**, `struct Alias` is 40 bytes, `alias.slot` is at +32, `tmp[i].alias` is at +72. If these offsets are wrong it does not crash in an obvious place; instead `escapes()` dereferences NULL. See `qpcc/tests/alias_shape.c`.
- **`parseline` is a Duff's device**; the three result-less instructions `blit`/`call`/`vastart` depend on it.
- **`escapes()` assumes that when `alias.type` is odd, `alias.slot` is necessarily non-null**; `fillalias` is responsible for establishing this invariant.
- **`optab`/`kwmap` are filled in at runtime**: `lexinit()` copies `optab[i].name` into `kwmap[i]` and then computes the `lexh[]` hash. Reading `kwmap` with lldb right after the process starts shows only 0; **read it inside `lex()`**.
- The **field widths of `Ins` / `Typ` / `AClass`** determine bitfield reads and pointer scaling; the layout tests are worth keeping permanently.

---

## 9. Debugging methodology

1. **Classify first, then localize.** Grouping 23 failures into 4 root causes is a different amount of work from "23 independent bugs".
2. **Temporary instrumentation + immediate revert.** Add `fprintf(stderr, "DBG ...")` in `vendor/qbe`, build once to see the value, then `cd vendor/qbe && git checkout -- <file>`. Much faster than guessing addresses in lldb.
3. **Instrument only scalars.** The first version printed `a->type->align`, and `a->type` was exactly the garbage pointer → the debug code itself crashed, turning the **key evidence** that "the data is garbage" into an ordinary segfault.
4. **Disassemble and read registers**: `lldb -b -o run -k 'register read x19 x20'`, together with `otool -tvV` to see offsets.
5. **Write a minimal fixture into `qpcc/tests/`**. `sh qpcc/test.sh` is the clang oracle and immediately distinguishes "a QPCC bug" from "an isolated case".
6. **For layout bugs, write `__builtin_offsetof` assertions** into the oracle (`alias_shape.c`).
7. **For hand-written encoders/backends, use differential testing**: compare byte-for-byte against the reference implementation (see 4.6).


### 9.1 Establish the expected value first, then declare a "reproduction"

This one is a pit **I** fell into, and it is worth writing out separately.

To chase the infinite loop in `blit`, I wrote a minimal reproduction in which I expected `probe(11)` to return 11,
so when the program returned 1 I judged the "reproduction successful" and chased it for several more rounds on that basis.

In fact: **recomputing shows that `probe(11)` ends with `off = 11-8-2-1 = 0`**, and returning 1 is the **correct behavior**.
That "reproduction" did not exist at all.

**Lessons**:
- A minimal reproduction's **expected value must be computed by hand or checked against the reference implementation**, not taken from memory
- A more robust approach: have the reproduction **print the value itself**, and **first compile the same source with clang** to confirm it returns 0
- If clang also returns non-zero, then **the test is wrong**, not the compiler

### 9.2 Instrumented prints need `fflush`, otherwise `kill -9` swallows all the evidence

When chasing a hang I used `fprintf(stderr, ...)` to log points, then `kill -9` after 4 seconds.
**stderr was not flushed and every DBG line was lost**, making it look like "this code never ran".

Fix: add `fflush(stderr);` after every print, or simply **do not print** and instead "exit once a limit is reached and watch the exit code change"
(The final confirmation in this document that `blit` was an infinite loop used the latter.)

### 9.3 Instrumented output with many variadic arguments may itself be untrustworthy

The values printed by `fprintf(stderr, "%d %d %d %d", a, b, c, d)` were once misleading.
**A single variadic argument printed several times** is more reliable; or switch to a global counter + exit code to convey the information.

---

## 10. Current status

```
clang oracle       126/126
moon test          353/353
QBE sources → arm64    19/19
self-hosted qbe / 76 cases  53 consistent / 23 different
```

The 23 differences by root cause:

| Group | Count | Cases | Status |
|---|---|---|---|
| Struct pointer arithmetic | 6 | `abi5 abi6 abi8 env queen tls` | Localized to `&ac[i1-i0]`, to be fixed |
| `simpl`/`getcon` hang | 7 | `abi4 abi9 ifc isel2 mem1 mem2 mem3` | To be investigated |
| `escapes` NULL slot | 2 | `_bf99 vararg2` | Out-of-bounds and layout ruled out |
| Output differences (semantics may be correct) | 8 | `abi1 abi3 dark dynalloc fold1 isel5 isel6 max` | Needs review against a semantic criterion |

### 10.1 Not yet fixed: struct pointer arithmetic

The real root cause of `sysv abi requires alignments of 16 or less`:

```
DBG chk ac=0x6000009800a0 a=0x60000098007a off=-38 inmem=196608 align=524288
```

`a` landed **38 bytes before** `ac`. The starting point should have been `&ac[2] = ac+80`, and subtracting one element (40) should give `ac+40`; instead it is `ac-38` — working backwards, the starting point is `ac+2`, i.e. `&ac[i1-i0]` was added as **2 bytes** instead of `2*sizeof(AClass)`.

Ruled out: the `AClass` layout (40 bytes, all offsets correct), `alloc` not zeroing (a self-check confirmed all zeros), and out-of-bounds indexing.

---


## 11. FIXME: the amd64 target has no semantic validation

**Status: a known gap, deliberately left here.**

The default target of the self-hosted qbe is `amd64_sysv`, and all earlier 76-case comparisons used it. The problem is:

| Target | Assembles on this macOS/arm64? | Runs? |
| --- | --- | --- |
| `amd64_sysv` (default) | ❌ it produces **Linux x86-64** assembly, and `.type`/`.size` are ELF directives | — |
| `amd64_apple` | ✅ assembles | ❌ `Bad CPU type in executable` (no Rosetta) |
| `arm64_apple` | ✅ | ✅ |

So **`semantic-check.sh` can only run arm64_apple**. This has two consequences:

1. **The 11 "output-only differences" fixtures in category C cannot be semantically judged on this machine** — their differences appear on
   the amd64 target, and amd64 output can neither be assembled nor run here.
2. **The arm64 target had never been measured even once before** — see below.

**To close this gap, one of the following is needed:**
- A machine that can run x86-64 (an Intel Mac, or Apple Silicon with Rosetta installed)
- A Linux x86-64 environment (qemu-user also works)
- Or an `ubuntu-latest` job in CI that runs `semantic-check.sh` with `-t amd64_sysv`

Until then, **do not claim "the self-hosted qbe is correct" based on amd64 byte-comparison results** —
that path has no semantic validation and is not a target produced by QPCC itself.

---

## 12. The arm64 target: an entire dimension never tested

The first time I ran `semantic-check.sh` with `-t arm64_apple`, the result was:

```
$ qbe-qpcc -t arm64_apple env.ssa
Abort trap: 6          # SIGABRT
$ vendor/qbe/qbe -t arm64_apple env.ssa
(normal)
```

Partial classification from what has run (~29/76):

```
total 59: both correct 6, only reference 52, only qpcc 0, neither 1
```

That is: **on the arm64 target, the self-hosted qbe produces 52 semantic errors out of 59 fixtures** (not "suboptimal code" — genuinely wrong results).
Only 6 are as correct as the reference version.
`dark` is neither: the reference version crashes (rc=139), and the self-hosted version fails to compile outright (rc=134).

**This is no longer a "code quality difference" — it really compiles wrong.** And it is precisely the target that QPCC itself produces —
in other words: **the one backend that matters for the self-hosted qbe had never been validated before.**

The next step starts here: first chase the arm64 SIGABRT on `env.ssa` (an assertion failure usually points directly at the broken invariant,
and one bug may carry a whole batch with it).


## 14. arm64 wrong code from the self-hosted qbe: root cause pinned to `gcm`

This section records a bug that is **already localized but not yet fixed**.

### Localization method (one-step bisection, very effective)

`pipeline.mbt` lists QPCC's optimization passes in order. Commenting them out one at a time and rebuilding the self-hosted qbe
tells you which stretch the wrong code comes from:

```
Turn off all optimization passes  → the self-hosted qbe's arm64 output is byte-for-byte identical to the reference ✓
Turn off only gcm                 → likewise byte-for-byte identical ✓        ← root cause is in gcm
Turn off gvn (alone)              → QPCC itself ICEs (there is a dependency; cannot test this way)
```

`gcm` lives in `gvn/gcm.mbt` (a MoonBit port of QBE's `gcm.c`). Note: this is not about
"QPCC making an error when compiling C", but rather **the gcm pass that qbe.mbt itself wrote in MoonBit miscompiling C code** —
exactly the kind of bug that `/doc/pitfalls.md` wants to collect.

### Further bisection

Inside `gcm` there are three stages, `gcmmove` / `sink` / `schedblk`, and **turning off any one of them alone fixes it**.
This suggests the bug is either in the mechanism they share (`add_one` / `addgcmins` / `gcmbid`),
or in the interaction between the stages.

### The exact divergences from C found so far

| Location | C | MoonBit | Impact |
| --- | --- | --- | --- |
| `cheap()` | includes `Oneg` | **missing `Neg`** | more conservative, sinks less, no wrong code |
| `bestbid()` | compares `blk->loop` (loop header id) | compares `loop_depth` (nesting depth) | heuristic difference; the position is still on the dominance chain, semantically safe |
| Coordinate system | only an rpo index | **two** systems, `Blk.rpo_id` and `Blk.id` | must check one by one which system each array is built on |

### Next steps (by priority)

1. Dump the IL before and after `gcm` (`--emit qbe` plus `-dG`), take a small function from `env.ssa`,
   and compare the IR "after the reference gcm" with "after the MoonBit gcm" instruction by instruction — the differing instruction is the culprit.
2. Pay special attention to the place where `schedins` skips `Nop` but C does not (it may be that instructions that must stay adjacent, such as `Oblit0/Oblit1`,
   get scattered).
3. Check `add_one`: C uses `fn->rpo[t->gcmbid]`, MoonBit uses `fn->blks[gb]` —
   these are equivalent only when `Blk.id == rpo index`.

### Temporary mitigation

Comment out that one `\@gvn.gcm(...)` call in `pipeline.mbt`, and **the self-hosted qbe's arm64 output becomes correct immediately**.
This is a usable fallback, but it sacrifices the code quality gcm provides; it is not a fix.


### 14.1 A failed attempt: the dominance self-check is unreliable

To localize the specific defect in `gcm`, I added a self-check: walk every temporary and assert that
"the defining block dominates all use blocks". It aborted on **every function**, including `blit`, `emitf`, and `classify`.

It looked like I had found an earth-shattering bug that was "wrong everywhere". But when I **moved the same self-check to run before `gcm`**
— where dominance is by definition guaranteed to hold — **it aborted just the same**.

So **the self-check was wrong**, not gcm. Possible reasons:
- QPCC's IR is not strictly SSA at this stage (leftover slots, or different dominance rules for phi)
- The correctness criterion for a phi argument is "the definition dominates the **predecessor** block", not the block containing the phi
- `def_order` may contain stale instructions from unreachable blocks

**Lesson**: before writing an "invariant self-check", you must **first prove that the invariant holds on a known-correct input**.
Run it against a scenario that is necessarily correct (here, "before gcm"); if it also fails, then the self-check is wrong.
This step cost only two rebuilds but avoided an entire round of investigation in completely the wrong direction.


### 14.2 Two negative results from IR comparison (useful; do not walk this road again)

I wanted to directly compare "QPCC's IR" with "the reference qbe's IR" to pin down the one gcm error. Two results:

**Result one: the IR gcm produces is legal, it is simply semantically wrong.**

```sh
qpcc <file>.c --emit qbe > x.ssa      # gcm has already run
./vendor/qbe/qbe -t arm64_apple x.ssa  # the reference version consumes it
→ rc=0, no errors at all
```

If gcm had produced a **structural** error such as use-before-def, the reference qbe's `ssacheck` would have rejected it on the spot.
It did not. So the defect is not "the IR is illegal" but "the IR is legal yet computes the wrong result" — which settles the direction of investigation
(do not look for dominance violations; look for changes in **values**).

**Result two: `--emit qbe` does not go through the optimization pipeline.**

Using two QPCC builds that differ only in the gcm switch, each with `--emit qbe`, the two IL files obtained for `simpl.c` were:

```
off.ssa  649 lines
on.ssa   649 lines
diff     (empty)
```

**Byte-for-byte identical**. That is, the state printed by `b.emit_il()` **does not include gcm's effect** —
`--emit qbe` takes another path and does not go through `pipeline.mbt`'s optimization passes.

So to use IR dumps for comparison, **you must add dump hooks inside the pipeline** (write one before and one after `\@gvn.gcm`),
you cannot rely on `--emit qbe`.


## 15. The third "the checker is wrong": the measured object was stale

The lesson from this section is more expensive than the previous two, because it contaminated **an entire round** of conclusions.

`examples/qpcc-selfhost/semantic-check.sh` reads `QBE_NEW=.qpcc_build/qbe-qpcc` by default.
And that file **is updated only when the demo script runs** — I never rebuilt it after changing QPCC.

So that binary stayed **before `c1e7596` (the pointer-difference fix)**. Every arm64 measurement afterwards,
including the report of "52 semantic errors out of 59", **was measuring the compiler before the fix**.

It was discovered by running the two binaries side by side:

```
.qpcc_build/qbe-qpcc   (old, before c1e7596)   env: SIGABRT
/tmp/v_base/qbe        (rebuilt from the current tree)       env: byte-for-byte identical to the reference
```

**Lesson: when measuring "the compiler", first confirm that the binary being measured is the one you just built.**

### 15.1 A clarification: the scope of "Heisenberg" is not as broad as I said

| Where the print is added | Who compiles it | Heisenberg? |
| --- | --- | --- |
| `vendor/qbe/*.c` (the **input** being compiled) | **QPCC** | yes — it modifies the observed object |
| `gvn/*.mbt` (the **compiler** itself) | `moon build` | no — pure observation |

**QPCC has never been compiled by QPCC.** So instrumenting QPCC's MoonBit source is reliable;
only instrumenting the C source being compiled causes perturbation.

### 15.2 The common shape of the three errors

| # | The role that erred | The tell |
| --- | --- | --- |
| 1 | Dominance self-check | It errors even at a position that is **necessarily correct** (before gcm) |
| 2 | In-block order criterion | Same as above; the phi bookkeeping was wrong |
| 3 | **The measured binary** | **Inconsistent** with the artifact just built |

**The identification method was the same all three times: run it against a scenario whose answer is known.**



### 15.3 The corrected arm64 baseline

Re-running `semantic-check.sh` with a binary **rebuilt from the current tree**:

     both correct          : 23
     only reference correct: 13
     only qpcc correct     :  0
     neither               :  1

Compared with 6 / 52 on the stale binary — **the stale binary explained about 45 of the failures**.

The 13 still failing: `abi1 abi3 abi4 abi5 abi6 abi8 abi9 echo fold1 ifc isel2 isel5 isel6`,
plus `dark` (reference rc=139, self-hosted LINK-FAIL; neither side is right).

**The figure of 52 semantic errors in Section 12 is void**; this section is authoritative.

**Corollary: `c1e7596` (the pointer difference inferred as a pointer type) fixed far more than I saw at the time.**
After that fix commit I kept testing with the old binary, so I neither saw its benefits
nor realized I was chasing a phenomenon that had partly ceased to exist for many rounds.

## 13. One-sentence summary

> Most of these bugs are **not "a missing case"**, but rather **a semantic detail swallowed by a shortcut taken during implementation**: the signedness of a typedef, default argument promotion, the storage duration of compound literals, the position of `default` in a statement list, gvn's dominance, the byte count of pointer scaling…
>
> And more dangerous than these bugs is that **the acceptance script itself lies**.

## 16. Worklist for item 3 (self-hosted qbe correctness)

Goal: make `examples/qpcc-selfhost/semantic-check.sh` report 0
`only reference correct` and 0 `neither`.

### 16.1 Trusted baseline (binary rebuilt from the current tree)

    both correct          : 23
    only reference correct: 13
    neither               :  1

The 13 failures grouped by symptom:

| Symptom | fixtures |
| --- | --- |
| Hang (rc=137) | `abi1` `abi9` `ifc` `isel2` |
| Segfault (rc=139) | `abi4` `abi8` |
| Output differs | `abi3` `abi5` `abi6` `echo` `fold1` `isel5` `isel6` |

### 16.2 The hang group is localized to blit (lldb, non-invasive, no Heisenberg)

    frame #0: getcon + 48/88/136
    frame #1: blit + 812
    frame #2: ins + 904
    frame #3: simpl + 168

All four hanging fixtures are stuck in the inner loop of `simpl.c:blit` calling `getcon` over and over.
This was obtained by **reading the stack on a running binary**, without changing any source, so it is not affected by Heisenberg.

### 16.3 Ruled out: blit's own logic is not miscompiled

Extracted `blit` as-is (keeping the struct table, `abs`, and `p++` walking the table), replaced
`newtmp`/`getcon`/`emit` with stubs, and on the ten sizes **0/1/2/3/4/8/11/15/16/20**
the results of QPCC and clang are **completely identical**. See `qpcc/repro_blit.c` (marked as a negative result).

### 16.4 Next steps

`blit` only spins when **the size passed in is bad**: `fwd = sz >= 0; sz = abs(sz);`
after which `for (p=tbl; sz; p++)` walks off the end of the table, reads a garbage `size`, and the inner loop may never terminate.

So the next target is the **caller** — in `simpl.c:ins`:
`blit((i-1)->arg, rsval(i->arg[0]), fn)`. Need to check:

1. Is `rsval(i->arg[0])` miscompiled (`(int)r.val ^ 0x10000000) - 0x10000000`)
2. Is the `(i-1)->arg` struct-array parameter passed correctly
3. Is the pointer arithmetic on `i` and `i-1` miscompiled

All three can use the 16.3 approach: extract into a C-level minimal reproduction and compare QPCC vs clang.

### 16.5 Final baseline (harness run to completion)

    both correct          : 39
    only reference correct: 20
    neither               :  1

(The 23/13 read midway was from a log that had not finished; the final numbers in this section are authoritative.)

### 16.6 The fourth tooling error: the QPCC driver strips #define

To make a C-level minimal reproduction for `blit`'s caller, I wrote:

```c
#define INT(x)   (Ref){RInt, (x)&0x1fffffff}
...
r = INT(i);
```

After compiling with QPCC, linking reported `Undefined symbols: _INT` — it looked like "the macro did not expand",
and I briefly thought I had caught a real bug.

**Actual cause**: the QPCC driver strips every line beginning with `#` (including `#define`),
so the macro was never defined at all, and `INT(i)` became a call to a function `INT`.

**The right approach**: as with the self-host build, preprocess with clang first:

```sh
clang -E -P foo.c > foo.i && qpcc foo.i -o foo.o
```

**After adding preprocessing, all 7 `INT` cases (constant/variable/array element/function argument/expression/struct field) passed.**
That "miscompilation" did not exist.

### 16.7 The common shape of the four errors

| # | The role that erred | Identification method |
| --- | --- | --- |
| 1 | Dominance self-check | It should stay silent where things are necessarily correct, yet it errors |
| 2 | In-block order criterion | Same as above (phi bookkeeping was wrong) |
| 3 | The measured binary | The timestamp must be from a fresh build |
| 4 | **The test procedure** (missing preprocessing) | First run the same input with the reference implementation |

**The common root cause is unchanged: measuring with an unvalidated apparatus, then believing the result.**
The fourth was caught on the spot because this time the apparatus was tested first: **run it once in a way known to work**.

### 16.8 One objective observation: unreclaimed stack allocations inside the blit loop

Disassembling `_blit` in the self-hosted qbe:

    00000001000489ac	b	0x100048690      ← loop back edge

    00000001000486c0	sub	sp, sp, x1
    0000000100048720	sub	sp, sp, x1
    0000000100048780	sub	sp, sp, x1
    00000001000487dc	sub	sp, sp, x1
    0000000100048878	sub	sp, sp, x1
    0000000100048910	sub	sp, sp, x4
    ...
    00000001000489e0	mov	sp, x29          ← reclaimed only once at the function exit

The back edge jumps to `0x100048690`, and all six `sub sp` instructions lie between `0x100048690` and the back edge —
**that is, every iteration of the loop lowers `sp`, yet there is no matching `add sp` to give it back.**
The whole function restores it only once, at the end, with `mov sp, x29`.

This is an **objective assembly fact** and depends on no inference. But whether it is the cause of the hang is **not yet confirmed**:
I wrote a long-loop C-level reproduction, but the expected value was wrong, the output flooded the screen, and I reached no conclusion —
**it cannot be treated as a confirmed root cause.**

The suspicious part: at 64 bytes/iteration × 4e6 iterations, the stack should overflow; yet the reproduction gave no clean signal,
which means either the trigger condition is wrong or this leak is not yet fatal at that scale.

**Next step**: write a reproduction with a **correct expected value and controlled output** (print only once at the end)
that tests only "whether local variables are still correct after N loop iterations", using clang as the control.

### 16.9 That stack observation is still unconfirmed, and my simplification did not reproduce it

Wrote a controlled reproduction (correct expected value, printing only once at the end):

```c
int main(void) {
  long i, acc = 0, n = 2000000L;
  for (i = 0; i < n; i++) {
    struct T t = { { 1,2,...,16 } };   /* aggregate initialization inside the loop body */
    acc += t.a[0] + t.a[15];
  }
  ... verify acc == 17*n ...
}
```

Results:

    QPCC's main: sub_sp=1  restore=1     ← balanced
    clang's main: sub_sp=0 restore=0
    both print OK, rc=0

**QPCC treated the aggregate initialization inside the loop body as static data and did not lower sp each iteration.**
So this shape **cannot** reproduce the six unpaired sub sp instructions inside blit.

**Conclusion: that pattern inside blit comes from somewhere else** (possibly the by-value struct argument passing of emit(...),
or the way the tbl array itself is constructed); a closer reproduction is still needed.

**Until it is confirmed, the observation in 16.8 is just an observation, not a root cause.**

## 17. A new minimal failure: a negative constant stored into a static 64-bit variable

```c
static long long g;
int main(void) { g = -1; return g == -1 ? 0 : 1; }
```

QPCC stored `0x00000000FFFFFFFF`, but it should be `0xFFFFFFFFFFFFFFFF`.
See `qpcc/repro_neg2.c` for the reproduction.

### 17.1 Scope ruled out

| Hypothesis | Conclusion |
| --- | --- |
| The arm64 backend does not lower `extsw` | ❌ the assembly generated on both sides for the six extensions (extsw/extuw/extsb/extub/extsh/extuh) is **word-for-word identical** |
| `foldint` folds `Extsw` incorrectly | ❌ `fold/fold_wbtest.mbt` already has the assertion `-2147483648`, and it passes |
| `ssa/copy.mbt`'s `iscopy` eliminates it as a copy | ❌ it explicitly returns false when `i.cls == Kl && t.cls == Kw` |
| Local variables are the same | ❌ local `long long` is correct; `static int` is correct; assignment from an int variable is also correct |

### 17.2 Remaining leads

The IR printed by `--emit qbe` is **correct**:

    %t.1 =w sub 0, 1
    %t.2 =l extsw %t.1        ← correct
    storel %t.2, $g

But `--emit qbe` **does not go through the optimization pipeline** (see 14.2), so the IR that actually reaches the backend has already been corrupted.
The real assembly is `mov w0, #-1` / `str x0` — a **32-bit** constant, showing that `extsw` was folded into
a **`Kw`-class constant** instead of `Kl`.

### 17.3 Next steps

Localize on the **optimized** IR (not `--emit qbe`):

1. Check whether, when `fold`/`gvn` fold an extension instruction into a constant, the new constant's **class** is `Kw` or `Kl`
2. Check whether the IR builder's `iconst` writes only the low 32 bits for a negative `Kl`-class constant
3. Dump the optimization stages with the `-d` series (the reference qbe has `-dM`/`-dG` etc.)

### 17.4 Bisected to gvn

Using a C-level minimal reproduction (sub-second feedback) to turn off optimization passes one by one, instead of waiting for a self-host build:

    cp pipeline.mbt.bak pipeline.mbt && moon build      rc=1  (bug present)
    off G (gvn_dedup_defs)                               rc=1
    off C (coalesce)                                     rc=1
    off V (gvn)                                          rc=0  ← fixed
    off S (simplcfg)                                     rc=1
    off M (gcm)                                          rc=1
    off I (ifconvert)                                    rc=1

Turning off gvn makes the problem go away, so the defect is in gvn/gvn.mbt.

Note that the folding expressions in gvn.mbt are themselves correct:

    @types.Extsw => l << 32 >> 32      // sign extension, correct
    @types.Extuw => l & 0xFFFFFFFF

So the problem is not the computed value but how the folding result lands — the generated constant or replacement instruction
uses class Kw instead of Kl, so the backend emits mov w0, #-1 (32-bit) followed by str x0.

Next: in gvn.mbt, find where the folding result is written as a constant or copy, and see whether its cls takes
i.cls or a hard-coded Kw.

Methodological gain: the C-level minimal reproduction cut pass bisection from 3-5 minutes per run to about 2 minutes per run;
six bisections took under 15 minutes. This was the most useful tool combination of this round.

### 17.5 Decisive evidence: gvn deleted the sxtw

Same C file, only the gvn switch toggled, comparing the assembly for `main`:

    gvn off (correct)             gvn on (wrong)
      mov  w1, #0x1                 mov  w0, #-0x1
      mov  w0, #0x0                 str  x0, [x1]     <-- sxtw missing
      sub  w0, w0, w1               cmn  x0, #0x1
      sxtw x0, w0   <-- here        b.eq
      str  x0, [x1]
      cmp  x0, x1
      b.eq

**`gvn` deleted the entire sign-extension `sxtw`**, so the 32-bit `0xFFFFFFFF` is used as a 64-bit value
— exactly the source of `mov w0, #-1` followed directly by `str x0`.

### 17.6 Suspects

`gvn.mbt:1428`:

    if i.cls == Kw && (i.op == Extsw || i.op == Extuw) {
      return i.arg1                      // return the operand unconditionally
    }

and the guard at `gvn.mbt:1435`:

    if i.cls.wide() > fn_.tmps[tid].cls.wide() {
      return Ref::none()                 // only this path blocks widening
    }

**This early return at 1428 happens before the guard at 1435**, and it does not check the operand's class.
If `i.cls` is `Kw` but the operand actually carries a value that needs 64 bits, this line deletes the widening.

Next: confirm whether this early return should require `i.cls == fn_.tmps[tid].cls` (or at least
`i.cls.wide() <= operand.wide()`), and write a whitebox test to pin it down.

### 17.7 Rule out copyref, pin down foldref

There are two branches in `gvn` that replace instructions:

    let r  = copyref(st, b, i)
    if !r.is_none() && gvn_dom_ok(st, r, b.id, idx)      { killins(st, i, r);  return }
    let r2 = foldref(st.fn_, i)
    if !r2.is_none() && gvn_dom_ok(st, r2, b.id, idx)   { ... }

Both **check only dominance, not class**. I added a class guard to the `copyref` branch
(`gvn_class_ok`: the replacement value's class width must not be smaller than the replaced instruction), and after rebuilding rc **was still 1**.

⇒ **The defect is not in copyref but in foldref.**

`foldref` folds `%t.2 =l extsw %t.1` into a constant. The value it folds out should be
`-1` (64-bit), but the assembly actually emitted is `mov w0, #-1` (32-bit) followed by `str x0` —
which shows the folded constant is **treated as 32-bit when used**.

That guard was reverted (it did not fix anything, and the change was risky; it should not stay in the tree).

**Next step**: look at how `foldref` handles extension instructions, and whether, when the constant it produces is substituted into an instruction,
`i.cls` is still correct.

### 17.8 Confirmed to be in foldref, and two ways of "turning off folding" ruled out

Experiments (each starting from a clean gvn.mbt, changing one thing only, rebuilding, then running the sub-second reproduction):

| Change | Reproduction rc | oracle |
| --- | --- | --- |
| Turn off the whole foldref branch | **0** ✓ | 126/129 ✗ (3 broken) |
| Turn off Extsw+Extuw folding | **0** ✓ | 128/129 ✗ (breaks fold_shift) |
| Turn off only Extsw folding | **0** ✓ | 128/129 ✗ (still fold_shift) |
| Add a sext exemption to c_opfold's 32-bit truncation | 1 ✗ | 129/129 |

**Conclusion:**

1. The defect is confirmed to be in `foldref` (turn it off and the reproduction disappears).
2. **It cannot be fixed by turning off folding** — `fold_shift` depends on it.
3. My "add an exemption to truncation" hypothesis **was wrong**: after the change rc was still 1, meaning `cls.wide()` was 1 to begin with,
   the truncation never happened, and the value was already `0xFFFFFFFF` at an earlier point.

`c_opfold`'s tail really does contain such a truncation:

    let c2 = if cls.wide() == 0 {
      Con::{ bits: ConBits::{ i: c.bits.i & 0xFFFFFFFF, ... } }
    } else { c }

And `extsw` does carry the canfold flag in ops.h:

    O(extsw, T(e,w,e,e, e,x,e,e), F(1,0,0,0,0,0,0,0,0,0)) X(0,0,1) V(0)

But since truncation is not the cause, the next question to settle is:
**Is the con folded out by `foldref` actually `-1` or `0xFFFFFFFF`** —
and, after `killins` substitutes it into an instruction, at what width the consumer reads it.

**Next step (specific):**

Print one line of debug output before `foldref` returns (printing `i.op`, `i.cls`, the con value of `i.arg1`,
and the folded `c.bits.i`), only when the op is `Extsw`. This is **not Heisenberg** —
QPCC is compiled by `moon build` and does not go through QPCC itself — so you can look at the real value directly.

**All temporary changes have been reverted; the tree is clean.**

### 17.9 Decisive debugging result: the folding is correct

Added debug output in `foldref` only for `Extsw`/`Extuw` (QPCC is compiled by moon build,
**not Heisenberg**), and ran the minimal reproduction:

    DBG cls=1 a1=4294967295 a2=0 got=-1
    DBG cls=1 a1=4294967295 a2=0 got=-1

Reading:

* `cls=1` means `Kl` (64-bit)
* `a1=4294967295` is the operand constant `0xFFFFFFFF` (from folding `sub 0,1` at word width; correct)
* **`got=-1` — the folding result is completely correct**

**So `foldref` is innocent.** It folded out the correct `-1` and put the correct con into the constant pool
(the debug print reads exactly the value in the constant pool).

### 17.10 The real defect: the wrong instruction width when materializing a Kl constant

The failing program's assembly is:

    mov  w0, #-1      <-- 32-bit move
    str  x0, [x1]     <-- then stores 64 bits

`mov w0, ...` **zeroes the high 32 bits of x0**, so what gets stored is `0x00000000FFFFFFFF`.
For a `Kl` constant, this should emit `mov x0, #-1`.

This code is in `vendor/qbe/arm64/emit.c` — that is, **QPCC miscompiled the constant materialization
when compiling QBE's emit.c**.

### 17.11 Why the bisection pointed at gvn

With `gvn` off, `sub 0,1` and `extsw` are not folded into constants, and `emit.c` gets a **register**,
so it never reaches that wrong constant-materialization path. **gvn is only the "trigger", not the disease.**

This also explains why "turning off the foldref branch" makes the reproduction vanish — as above, it only stops the constant from being produced.

### 17.12 Next steps

In `vendor/qbe/arm64/emit.c`, find the materialization of `Kl` constants (the selection logic around `emitcon`/`mov`)
and look at its branch for **negative numbers** or **values that fit in 32 bits**.

Note: **editing `vendor/qbe/*.c` is Heisenberg** (that is the input under test). So the right path is
to reproduce that decision in `emit.c` with a **minimal C reproduction**, compile it with QPCC, and compare with clang.

### 17.13 The class mismatch is caught directly

In `killins`, print the class code for the replaced temporary and each of its uses (`Kw`=0, `Kl`=1):

    KILL tf=0 con=4294967295 use[0]=1     <-- mismatch
    KILL tf=1 con=-1         use[0]=1     <-- normal

The first line is the bug: a **Kw** temporary was folded into `0xFFFFFFFF`, while the use is `Kl` (64-bit),
so what is read becomes `0x00000000FFFFFFFF`.

The second line is fine (`Kl` -> `-1`). **This also explains why last round I saw the folding as correct** —
I was looking at the second line, not the failing first line.

### 17.14 Fixes already ruled out

| Fix | Result |
| --- | --- |
| Do not truncate with the 32-bit mask at the end of `c_opfold` | rc still 1 — the value was already `0xFFFFFFFF` earlier |
| Exempt sign extensions from truncation | rc still 1 |
| Turn off `foldref` / extension folding | rc=0, but breaks `fold_shift` |

### 17.15 Facts currently in hand

* In `c_foldint`, `Sub => l - r` has **no** internal mask; `0 - 1` should yield `-1`
* `c_opfold`'s tail does `& 0xFFFFFFFF` when `cls.wide() == 0` (`Kw`)
* But **disabling this mask did not fix it** — so the problem is not the mask itself
* The class codes of the two KILLs are measured values, not inferences

### 17.16 Next step (specific)

The order of the two KILLs and their relationship have not yet been clarified. The next round should:

1. In the `killins` print, **also output `i.op`** (the opcode before replacement) and **the use's opcode**,
   to tell which KILL belongs to `sub` and which to `extsw`
2. Confirm whether, when the `extsw` fold happens, its operand is already **another constant** (that is, the result of the first KILL)
3. If both folds are present, which constant the final `Kl` use actually receives

**All temporary changes have been reverted; the tree is clean.**

## 18. The second real fix: gvn folded a word-width constant into a 64-bit use

### 18.1 Symptom

```c
static long long g;
int main(void) { g = -1; return g == -1 ? 0 : 1; }
```

QPCC stored `0x00000000FFFFFFFF`, but it should be `-1`. The assembly is:

    mov  w0, #-1      <-- 32-bit materialization
    str  x0, [x1]     <-- yet stores 64 bits

### 18.2 Localization process (took three rounds of instrumentation to converge)

| Step | Conclusion |
| --- | --- |
| pass bisection (C-level reproduction, ~2 minutes each) | turning off `gvn` fixes it -> the defect is in gvn |
| `foldref` instrumentation | folds out `-1`, **looks correct** -> briefly thought gvn was innocent |
| `killins` instrumentation (printing class codes) | caught a `Kw` temporary being consumed by a `Kl` use |
| dumping once before and after `abi`/`simpl` | neither changes it; it was already `0xFFFFFFFF` before `abi` |

**The wrong directions along the way**: adding a guard to the `copyref` branch (ineffective, reverted),
adding a sign-extension exemption to `c_opfold`'s truncation (ineffective, reverted),
turning off `foldref` entirely (passes but breaks `fold_shift`).

### 18.3 Root cause

After `gvn` folds an instruction into a constant, it **rewrites all uses of the temporary that instruction defines**.
When the folded instruction is a **`Kw` (word-width)** instruction, the constant is a 32-bit word; but a use that needs `Kl`
reads all 64 bits. **When the top bit of the word is 1, the two readings differ**:

    `0xFFFFFFFF` as a word = 4294967295
    `0xFFFFFFFF` sign-extended = -1

So the 64-bit `storel` received the former and stored `0x00000000FFFFFFFF`.

### 18.4 The fix

Added `gvn_widen_ok`, which judges the **intersection of two conditions** on the `foldref` branch:

    fn gvn_widen_ok(st, i, r) -> Bool {
      if i.cls != Kw || !r.is_con() || !i.to.is_tmp() { return true }
      let v = st.fn_.cons[r.con_val()].bits.i
      if (v & 0x80000000L) == 0L { return true }        // positive: both extensions agree
      ... if any use has a cls wider than i.cls -> reject the fold ...
    }

**Both conditions are indispensable**:

* Checking only the use width -> too broad, breaks the snapshot test `001_add_w` (`2000000000+2000000000`
  is a word-width constant with its top bit set, but has no wider use; it **should be folded**)
* Checking only the top bit -> likewise too broad
* **Taking the intersection** -> oracle 129/129 and moon test 362/362 all green

Also: the use records may be **stale**, so the index must be bounds-checked —
the first version did not check, and panicked with an out-of-bounds index in the oracle's `cls_index`.

### 18.5 Effect

* `qpcc/tests/widen_word_const.c` covers: wide store, word-width use, unaffected positive folding
* After rebuilding the self-hosted qbe, **3 of the 20 failures became fully identical** (including `max` and `queen`)

### 18.6 Methodological lesson from this round

**Choosing the wrong insertion point leads to a wrong "innocent" conclusion.** When I printed inside `foldref` I saw `-1`,
and nearly judged gvn innocent on that basis — but that was only **one of the two folds**; the other one was wrong.
Only when I printed the **class codes** of both the replaced temporary and the use did I see the mismatch.

**Next time something similar happens, print both sides' class codes first, not just the value.**

## 19. Measured state after three fixes

### 19.1 Direct retest (sub-second, trusted)

    consistent 4/20 : abi3 fold1 max queen

### 19.2 Full harness (midway values at 28/60)

    both correct          19
    only reference correct  7   (abi1 abi4 abi5 abi6 abi8 abi9 echo)
    neither                0   <- [neither cleared]

The baseline was 39/20/1. The `dark` that produced `neither` no longer appears.

### 19.3 The remaining four symptom classes

| Class | fixture | Observation |
| --- | --- | --- |
| Missing stack allocation | abi5 abi6 echo isel5 isel6 | the reference has `sub sp, sp, xN`; QPCC's does not |
| Segfault | abi1 abi4 abi8 abi9 mem1 mem2 mem3 vararg2 | rc=139 |
| Hang | ifc isel2 | rc=137 |
| Output differs | tls | — |

### 19.4 Progress and lessons on the missing-stack-allocation line

Localized to `vendor/qbe/arm64/abi.c:390`:

    stk = align(stk, 16);
    rstk = getcon(stk, fn);
    if (stk)
        emit(Oadd, Kl, TMP(SP), TMP(SP), rstk);

and `abi.c:355`'s `(Ins){Oalloc+al, Kl, r, {getcon(sz, fn)}}` (a computed enum value placed into a compound literal).

Wrote two rounds of construct battery tests, and **neither found a divergence**:

* Round one: `align` / stack-size walkthrough / compound literals — all consistent with clang
* Round two: the `INRANGE` macro (`(unsigned)(x) - l <= u - l`), `isarg`, computed enums — all consistent too

**Both tests themselves made the same mistake**: the first got the expected value wrong, and the second used `#define` again
only to have it stripped by the QPCC driver (this pit was stepped in once already in round 9).

**The lesson repeated three times**: `#define` must first be preprocessed with `clang -E -P`. This one is worth committing to muscle memory.

### 19.5 A new idea for the next step

The missing stack allocation is **not necessarily** QPCC miscompiling `abi.c`. It could also be:

1. QPCC miscompiling **another pass** (such as the stack-slot allocation in `spill.c`), causing `Oalloc` to be eliminated
2. The self-hosted qbe's **own** optimization deleting `add sp, sp, rstk` — but the reference does not, so it is still a QPCC miscompile

Method of discrimination: use the `-d` series of switches (the reference qbe can dump the IR at each stage) to compare the self-hosted and reference versions'
IR **after abi**, and see whether `Oalloc` is already gone.

## 20. A new diagnostic tool: let the self-hosted qbe dump by itself

The self-hosted qbe is a **complete qbe** with all the `-d` switches built in. This means we no longer have to guess at constructs,
but can **compare the IR at each stage on both sides step by step** and directly localize which pass is wrong.

### 20.1 The switches for each stage

| Switch | Stage | Code location |
| --- | --- | --- |
| `-dA` | after Apple pre-ABI | abi |
| `-dM` | after slot promotion | mem.c / load.c |
| `-dI` | after instruction selection | isel |
| `-dS` | after spill | spill.c |
| `-dR` | after register allocation | rega.c |
| `-dL` | liveness analysis | live.c |
| `-dG` | gvn/gcm | gvn.c/gcm.c |
| `-dC` | cfg | cfg.c |
| `-dK` | ifopt | ifopt.c |

### 20.2 Step-by-step comparison for isel6 (the 9th argument goes on the stack)

    -dI : both sides [byte-for-byte identical]  (R32 =l sub R32, %isel.14 both present)
    -dS : both sides [byte-for-byte identical]
    -dR : the self-hosted version [is missing] R1 =l copy 16 and R32 =l sub R32, R1

**Conclusion: the IR is correct after both isel and spill; it is rega that loses the stack adjustment.**

That is: QPCC miscompiles when compiling `vendor/qbe/rega.c`, and the error is on the **path for SP (`R32`)**.

### 20.3 The value of this method

For three previous rounds I kept guessing at `abi.c`'s constructs (the `Oalloc+al` compound literal, the `INRANGE` macro,
`align`'s unsigned negation), and two rounds of battery tests found no divergence.

**Step-by-step `-d` comparison narrowed the scope from "the whole backend" to "one pass"**, with no guessing required.

**Next time a backend problem appears, the first step should be this comparison, not writing construct tests.**

### 20.4 Next steps

In `vendor/qbe/rega.c`, look for the logic involving `T.rglob` (the set of fixed callee-saved registers)
and `R32` (SP), focusing on:

* `rega.c:397`: `if (r < Tmp0 && (BIT(r) & T.rglob))`
* how `rfree`/`ralloc`/`radd` handle fixed registers
* `radd(m, r, r)` (mapping a register to itself)

Then, as usual: extract into a minimal C reproduction and compare QPCC vs clang.

## 21. Another minimal reproduction: a static 64-bit variable cannot hold 1<<32

    static unsigned long rglob;
    rglob = ((unsigned long long)1) << 32;    /* stored value is 0, should be 0x100000000 */

* The expression itself is correct: if (BIT(32) != 0x100000000ULL) return 1; passes
* But after storing into a file-scope static 64-bit variable, the value is 0

### 21.1 Difference from the one in Section 18

| | Section 18 (gvn word-width folding) | Section 21 (this one) |
| --- | --- | --- |
| Constant | 0xFFFFFFFF, a negative word with the top bit set | 0x100000000, only bit 32 |
| Symptom | sign extension and zero extension disagree | the whole word becomes 0 |
| Trigger | there is a wider use | storing into a static 64-bit variable |

### 21.2 Why this explains isel6

In rega.c, T.rglob is the set of fixed registers, and BIT(32) is SP:

    if (r < Tmp0 && (BIT(r) & T.rglob))    /* SP should hit here */

After rglob = BIT(32) | BIT(31) loses BIT(32), SP is no longer treated as a fixed register,
and register allocation treats the stack adjustment R32 =l sub R32, R1 as an ordinary instruction and discards it.

**This matches the -dR observation exactly**: the IR is still right at -dS, and by -dR those two instructions are gone.

### 21.3 Method value

Letting the self-hosted qbe dump by itself was the turning point. The first three rounds guessed at abi.c's constructs, and both battery tests failed;
but the -dI/-dS/-dR step-by-step comparison pinned the scope to rega.c in one round, and then one construct test caught the expression.

**Next time the backend breaks, the first step is a dump comparison, not guessing at constructs.**

### 19.6 Authoritative numbers (full harness run to completion)

    total 59: both correct 42, only reference 16, only qpcc 0, neither 1

| | Baseline | Now |
| --- | --- | --- |
| both correct | 39 | **42** |
| only reference correct | 20 | **16** |
| neither | 1 | 1 |

Three fixtures turned positive (three of abi3 fold1 max queen entered this 42; the other was already counted before).

### 19.7 The remaining 16

    abi1 abi4 abi5 abi6 abi8 abi9 echo ifc isel2 isel5 isel6
    mem1 mem2 mem3 tls vararg2

Among these, abi5 abi6 echo isel5 isel6 belong to the **missing stack allocation** class, and Section 21's minimal reproduction
(`repro_bit32.c`) explained their common root cause: a static 64-bit variable cannot hold 1<<32, causing rega's
fixed register set to lose the SP bit.

**The rest are segfaults (abi1 abi4 abi8 abi9 mem1 mem2 mem3 vararg2) and hangs (ifc isel2),
not yet localized.**

### 21.4 Decisive evidence: folding turns 1<<32 into 0

QPCC's IR (correct):

    %t.3 =l shl %t.1, %t.2
    storel %t.3, $rglob

QPCC's assembly (wrong):

    mov  w0, #0x0          <-- the folded value is 0
    str  x0, [x1]
    mov  x1, #0x100000000  <-- but the constant used for comparison is correct

In the same run, only the folded constant becomes 0.

### 21.5 Why the guard did not catch it

The guard only checks when cls is Kw, but this instruction is Kl, so it passes through.
But the folded constant is truncated to 32 bits by the mask at the end of c_opfold, which only takes effect when cls.wide() is 0.

**So the cls passed to c_opfold is Kw, while the instruction is Kl.**
This also explains why disabling the mask did not help: the mask is a symptom; the wrong class being passed is the cause.

### 21.6 Next steps

Print op and cls at the entry of c_opfold, run repro_bit32.c, and see which class is received when folding shl.
Not Heisenberg, because QPCC is compiled by moon build.

### 21.7 Complete evidence chain: folding is correct all the way, then it is lost

Instrumentation (ZPCC compiled by moon build, not Heisenberg) gave four steps:

    c_opfold entry:   op=13(Shl) cls=1(Kl) a1=1 a2=32
    c_opfold exit:    i=4294967296 wide=1 out=4294967296
    killins receives: op=13(Shl) cls=1(Kl) repl=con(4294967296)
    before isel:      op=53(Storel) cls=1(Kl) a0=con(0) a1=con(0)

**The first four steps are all correct; the fifth step becomes 0.**

So the value is lost **after `killins` and before `isel`**, within the scope of:

* `replaceuses` (the step that rewrites uses)
* `abi` / `simpl` (after gvn and before isel)

### 21.8 Ruled out

| Hypothesis | Result |
| --- | --- |
| The mask truncates the value to 0 | disabling the mask has no effect |
| `con_eq` treats 0 and 0x100000000 as the same | `raw_bits` goes through `bits.i` for integers, exact |
| `get_con_by` returned a different constant | unverified, but what `killins` received is correct |
| The folding computed the wrong value | `c_opfold`'s exit is 4294967296 |

### 21.9 Next steps

At the entry of `replaceuses`, print the `r` it receives and how many uses it rewrote,
and dump `storel` once after `abi` and once after `simpl` (rounds 28 and 29 of this session
each have a verified working set of instrumentation), to see at which step `0x100000000` becomes 0.

### 21.10 This bug is worth chasing to the end

It is **the only root cause that explains the five fixtures `isel6`/`echo`/`abi5`/`abi6`/`isel5`**
(missing stack allocation, because `rega`'s fixed register set `T.rglob` loses `BIT(32)`=SP).
Fixing it is expected to solve all five at once.

### 21.11 Complete results of staged instrumentation

Staged instrumentation for `rglob = ((unsigned long long)1) << 32`:

| Instrumentation point | Reading | Verdict |
| --- | --- | --- |
| c_opfold entry | op=13(Shl) cls=1(Kl) a1=1 a2=32 | correct |
| c_opfold exit | i=4294967296 wide=1 out=4294967296 | correct |
| killins receives | op=13 cls=1 repl=con(4294967296) | correct |
| replaceuses | r1=tmp n=1 repl=con(4294967296) | correct |
| **after frontend (before abi)** | **op=53(Storel) a0=con(0) a1=con(0)** | **already 0** |
| after abi | same as above, still 0 | not abi |
| before isel | same as above, still 0 | not simpl |

**Conclusion: the value is rewritten again inside `gvn`, after `killins` inserts the correct constant.**

### 21.12 gvn-internal steps ruled out

| Step | After turning it off |
| --- | --- |
| 32-bit mask | rc still 2 |
| assoccon | rc still 1 |
| normins | rc still 1 |

**Remaining suspects**: `gvndup` (hash-based deduplication, which may replace the store's arg with the value of another instruction)
and `gvn`'s **fixed-point iteration** (the same block is processed repeatedly).

### 21.13 The exact action for the next round

Print the store's `a1` **after each step** of `dedupins`, or simply print inside `gvndup`
the `i1.to` it returns and the corresponding con value. **One run will show which step changes the store's arg back to 0.**

### 21.14 The closing value of this bug

It is the common root cause of the five fixtures `isel6`/`echo`/`abi5`/`abi6`/`isel5`
(`rega`'s `T.rglob` loses `BIT(32)`=SP). **Fixing it is expected to solve all five at once.**

### 21.15 The last rewrite: the store's arg1 is correctly written as 4294967296

Printing every rewrite inside `replaceuse`:

    WU op=13(Shl)    blk=0 idx=2 a1?true  a2?false ->con(1)
    WU op=13(Shl)    blk=0 idx=2 a1?false a2?true  ->con(32)
    WU op=53(Storel) blk=0 idx=3 a1?true  a2?false ->con(4294967296)

**The store's `arg1` is correctly rewritten to `con(4294967296)`.**

Yet the dump after the frontend finishes shows `op=53 a1=con(0)`.

### 21.16 Passes and steps ruled out

| Ruled-out item | After turning it off |
| --- | --- |
| 32-bit mask | rc still 2 |
| `assoccon` | rc still 1 |
| `normins` | rc still 1 |
| `gvndup` | rc still 1 |
| `mem.coalesce` | rc still 1 |

### 21.17 What remains

After `gvn`, the frontend still has several more `gvn_dedup_defs` (lines 165, 168, 181, 183)
as well as `gvn`/`gcm`/`ifconvert`.

**Next diagnostic**: print the store's `arg1` at the **end** of `dedupins` (this round's instrumentation did not run due to a compile error;
the way to write it is to bind the result of `if a.is_con()` to a local variable before concatenating, avoiding indexing an array directly inside a string).

### 21.18 Overall progress of this session

* Four root causes fixed and verified (both correct 39 -> 42)
* A complete evidence chain for the fifth bug, with staged instrumentation seven times and six possibilities ruled out
* Localized to: in `gvn`'s first `gvn_dedup_defs`, the store's arg1 is correctly rewritten,
  but is changed back to 0 before the frontend finishes

## 22. The fifth bug is fixed (two independent defects)

### 22.1 `gvn`'s `normins` treats the placeholder class as word width

QBE's `normins` uses `!KWIDE(argcls(i,n))` to decide whether to truncate to 32 bits. In QBE's table the `e`
placeholder maps to `Ke = -1` (odd), so it is never truncated; QPCC's encoding is **-2**, and
`-2 & 1 == 0` → the placeholder is judged word-width → the 64-bit constant is truncated to its low 32 bits.
Fix: add `k >= 0` to the test.

### 22.2 `arm64_argcls` maps `Ke` to `Kx`

```moonbit
let code = arr[idx]
if code < 0 { i.cls } else { @types.Class::from_code(code) }
```

`from_code(-2)` falls to `_ => Kx`, and `Kx.wide() == 0` → `fixarg` creates
`Copy(cls=Kx)` → in `loadcon` `KWIDE` is false → `n = (int32_t)n` truncation.
The semantics of Ke is "no constraint in the table"; for a store, the value's class is simply the store's own class.

### 22.3 Verification

    oracle 133/133   moon test 362/362
    all 6 constant cases pass; new regression test qpcc/tests/store_wide_const.c

## 23. `isel6`'s stack allocation: localized to concrete values

Stage-by-stage comparison:

    -dA -dM -dI -dS -dC -dK -dG : all zero difference
    -dR                          : only it differs

Instrumented `rega.c` (for diagnosis; reverted) to print every emission:

    RG op=86 cls=1 to=0/78 a0=1/12            <-- copy constant 12
    RG op=2  cls=1 to=0/32 a0=0/32 a1=0/78    <-- sub R32, R32, %78

**The self-hosted version computed stack size 12; the reference is 16.** Earlier I read `14,15d13` as
"two instructions were dropped", which was wrong — in fact it is a **difference in the constant value**.

Ruled out: the self-copy drop at `rega.c:424` (constant arguments never trigger DROPC), and `align()` itself.

**Next step**: `abi.c`'s `stk = align(stk, 16)` computed 12. In `selcall`,
printing `stk` and each `c->size`/`c->align` will settle whether it is align or a different input.

### 23.1 [Correction] "12 vs 16" was my misreading

Instrumenting `getcon` in the self-hosted version:

    GETCON 16 NEW c=12 stored=16

**`getcon(16)` creates a new constant at index 12, and the value stored is exactly 16.**

The `a0=1/12` in the rega trace should be read as `type=RCon(1) val=12`, where `val` is a **constant index**,
not a constant value ✗. The value placed at index 12 is 16 ✓.

So:

| Stage | Conclusion |
| --- | --- |
| `selcall`'s `stk` | both sides are **16** ✓ |
| `getcon(16)` | what is stored is 16 ✓ |
| the instructions `rega` emits | `copy con#12` and `sub R32, R32, con#12` ✓ correct |

**There is no problem with `selcall` / `getcon` / `rega`.** The earlier statement "the self-hosted version computed stack size 12"
was wrong ✗.

### 23.2 So where is the real boundary

    -dA -dM -dI -dS : zero difference (before rega)
    -dR              : the two are missing ✗
    -dC -dK -dG      : zero difference

But `-dR` **is printed by rega itself**, and the instrumentation shows rega **did emit** those two ✓.
That is:

* **either `printfn` (the text dump) omitted them**, or
* **something after rega changed `b->ins`**

**Passes after rega and before emit**: `fillrpo` / `simpljmp` / `fillrpo` / `fillpreds`.

And the final **assembly is also missing** those two ✗ — so it is not just a printing problem; `b->ins` really was changed ✗.

### 23.3 Next step (very narrow)

`simpljmp()` is the only pass after rega that rewrites instructions. Dump the `R32`-related
instructions once before and after it, or simply turn off `simpljmp` and see whether the self-hosted output recovers.

**Methodological lesson (third of its kind)**: before trusting a printed number, confirm **what it means** —
the 12 in `a0=1/12` is an index, not a value ✗. Last round I read `14,15d13` as "instructions dropped",
and this round I read a constant index as a constant value — both times the **reading** was wrong, not the data.

### 23.4 Ruling out simpljmp; the boundary narrows to rega's buffer write-back

`cfg.c`'s `simpljmp()` rewrites only **jumps** (`b->jmp.type`, `b->s1/s2`)
and does not touch `b->ins` at all ✗ ⇒ **it is not the culprit**.

### 23.5 The precise state now

| Fact | Evidence |
| --- | --- |
| `selcall` computes `stk=16` | instrumentation on both the self-hosted and reference versions prints 16 ✓ |
| `getcon(16)` stores the value 16 | `GETCON 16 NEW c=12 stored=16` ✓ |
| `rega` **did emit** those two | the RG trace has `copy con#12` and `sub R32, R32, con#12` ✓ |
| `RG-END count=16 nins=16` | the counts are self-consistent ✓ |
| **but they are not in the `-dR` dump** | ✗ |
| **nor in the final assembly** | ✗ |

**⇒ the loss happens at the step where rega's internal buffer is written back to `b->ins`** ✗
(that is, `idup(b, curi, &insb[NIns]-curi)`, rega.c:446), or in the `-dR` printing path.

Because the **assembly is also missing them** ⇒ they really are lost ✗, not a printing problem.

### 23.6 Next steps

Print `b->nins` and the `op` of `b->ins[0..3]` once before and after rega.c:446,
as well as `(int)(&insb[NIns]-curi)`:

* If after `idup` `b->ins[0].op` is not those two ⇒ **`idup`/counting is wrong**
* If it is correct after `idup` but `printfn` prints fewer ⇒ **the printing path is wrong** (but that does not explain the assembly)

You can also directly compare `b->nins` with the argument passed to `idup`: the two should be equal.

### 23.7 The third methodological error of the same kind

* The 1st time: read `14,15d13` as "instructions dropped" ✗ (actually a different constant)
* The 2nd time: read constant **index** 12 as a constant **value** ✗
* The 3rd time: took the missing `-dR` output as rega's decision ✗ (rega clearly emitted them)

**All three were reading errors, not data errors.** Before trusting anything printed, confirm what it means.

### 24. [Important correction] rega did not drop that instruction

Instrumented the decision point at `rega.c:397` to print:

    RGLOBCHK r=32 rglob=1400c0000 bitr=100000000 in=1 to=0/32

`T.rglob = 0x1400C0000` = `BIT(FP)|BIT(SP)|BIT(IP1)|BIT(R18)` — **completely correct** ✓,
`BIT(32) & T.rglob` is **1** ✓ ⇒ it takes `break` (**keeps the instruction**) ✓,
**not `curi++` dropping it** ✗.

**Section 23's conclusion that "rega.c:402 drops the instruction" is void.**

### 24.1 Facts now established (all backed by instrumentation evidence)

| Stage | Conclusion |
| --- | --- |
| `selcall`'s `stk` | **16** ✓ (consistent with the reference) |
| `getcon(16)` | the stored value is **16** ✓ |
| `T.rglob` / `BIT(SP)` | **correct** ✓, the decision takes `break` and keeps ✓ |
| `rega` emission | `copy con#12` + `sub R32, R32, con#12` ✓ |
| `idup` write-back | self-consistent before and after ✓ |

**⇒ The instructions really are emitted, kept, and written back — yet they are not in the `-dR` text dump,
nor in the final assembly.** ✗

### 24.2 Next time, do not localize by "reading the printout" again

Four errors of the same kind in this session:

1. Read the diff `14,15d13` as "instructions dropped" ✗
2. Read constant **index** 12 as a constant **value** ✗
3. Took the missing `-dR` output as rega's decision ✗
4. Read the repeated count as dropping at `rega.c:402` ✗

**All four were reading errors.** The next step should be:

* Have the self-hosted version **print the raw `b->ins[]` array directly** (`op`/`cls`/`to`/`arg`),
  instead of reading `printfn`'s text — the text formatting itself may be the problem
* Or look directly at the **emit stage** (`arm64/emit.c`) and print every instruction it traverses

**Note that `printfn` and emit are two different read paths**, and both are missing them ⇒ so `b->ins` really is missing them,
but it is self-consistent after `idup` ⇒ the change happened **after** `idup` and **before** `printfn`.

### 24.3 The first construct to test this time

Between `idup` and `printfn` there is only `free(uf)` and `*p = ret` (both inside `simpljmp`).
So it is more likely that **`idup`'s `b->nins` is computed wrong** (the `i1 - i0` pointer difference),
while `IDUP-AFTER nins=16` looks correct — in that case, look again at the bounds `printfn` traverses.

**Specific next action**: print `b->nins` and `b->ins[0].op` at the start of `printfn`,
and compare with `IDUP-AFTER`'s 16/86. If they differ ⇒ it was changed in between; if they are the same ⇒ `printfn` itself missed them.

### 25. [Final localization] those two instructions are not in the function

Instrumented both the write-back at `rega.c:446` and `printfn` in `parse.c`:

    IDUP-AFTER  nins=16 ins0op=86 ins1op=1 ins2op=86
    PRINTFN blk=start nins=16 i0op=86 i1op=1

**The two are completely consistent** ⇒ `b->ins` really does not contain those two ✗, **so it is neither a printing problem nor a later modification** ✓.

And rega's emission trace counted up to **17**, while the write-back was **16** ✗ ⇒
**the last emission happened [after] the write-back**, landing in the same static buffer `insb`,
but **did not enter the function's block chain** ✗.

`PRINTFN` printed only one block (`start`) ⇒ **that newly created block was not linked into the `fn->start` chain** ✗.

### 25.1 Mapped to the source

`rega.c` has two write-back sites:

* `rega.c:446` — at the end of the main loop, write back **every block** (`idup(b, curi, ...)`) ✓ executed
* `rega.c:616-679` — **"emit remaining copies in new blocks"**:

```c
curi = &insb[NIns];
pmgen();
j = &insb[NIns] - curi;
if (j == 0) continue;
s = alloc(...);
b1 = newblk();
...
idup(b1, curi, &insb[NIns]-curi);
b1->jmp.type = Jjmp;
b1->s1 = s;
**ps = b1;
```

**`b1` is created and linked only when `j != 0`** ✗ — if `j` is computed as 0, no new block is produced,
and those two instructions disappear too ✓✓.

**`j = &insb[NIns] - curi`** is exactly a **pointer difference** (`Ins *` subtraction, then scaling by `sizeof(Ins)`) ✗.

### 25.2 Next step (the only one)

Print `j` and `curi` at `rega.c:618`; if `j == 0` while `curi != &insb[NIns]`,
then **the pointer difference is computed wrong** ✓ — which returns to the **same class of bug** fixed at the start of this session
(`c1e7596`: "a pointer difference is an integer, not a pointer") ✗.

**This is the same class of problem as line 402 of `doc/pitfalls.md`, "the field widths of `Ins`/`Typ`/`AClass` determine bitfield reads and
pointer scaling"** — pointer scaling depends on `sizeof(Ins)` and the field layout ✓.

## 26. [Major overnight discovery] the segfault group and the hang group share one root cause: `strf`

### 26.1 Crash stack (lli db, task bash-82)

```
frame #0: __sfvwrite
frame #1: __vfprintf
frame #2: _vsnprintf
frame #3: qbe-qpcc`strf + 72
frame #4: qbe-qpcc`newtmp + 280
frame #5: qbe-qpcc`blit + 632      <-- the blit that hung earlier
frame #6: qbe-qpcc`ins + 904
frame #7: qbe-qpcc`simpl + 168
```

**It crashes in `strf` (a variadic function)** ✓ — and `blit` → `newtmp` → `strf`
is exactly the path the earlier "hang" group (`ifc`/`isel2`) took ✓.

### 26.2 Minimal reproduction: `qpcc/repro_strf.c`

```
clang rc=0
qpcc  rc=19      <- bit1 + bit2 + bit16
```

The shape of `strf` (`vendor/qbe/util.c`):

```c
p = (pool == PFn ? alloc : emalloc)(n + 1);
```

| Variant | Result |
| --- | --- |
| `strfA`: ternary chooses the allocator | **wrong** |
| `strfB`: **if/else** chooses the allocator | **wrong** |
| `strfC`: always uses `emalloc` | **right** |

**⇒ it is not a problem with the ternary** (if/else is wrong too).

### 26.3 Ruled out

* The return value of `vsnprintf(NULL, 0, ...)` is **completely correct** (`len1`/`len2`/`len3` all pass ✓)
* Branching on a parameter to call (A/B) inside a variadic function is **correct in an independent test** ✓
* Pointer differences, bitfields, nested designators, `emit` shape, and `getcon` lookup all pass in independent tests ✓

### 26.4 The one last step still missing

In `strfA`/`strfB`, `alloc` **is called yet returns a pointer outside the pool**, while `strfC` (which does not call `alloc`) is correct.
Need to print `pooloff` and the returned address inside `alloc`, to confirm:

* whether `alloc` was not called (it took `emalloc`)
* or whether `pooloff` was corrupted

The difference between `alloc` and `emalloc` is: **`alloc` uses two file-scope statics (an array + a counter)** ✗,
while `emalloc` only uses `calloc` ✓. **This is the next construct to test.**

### 26.5 Scope of impact

`strf` is called heavily by `newtmp`/`newname` and others in QBE ✓ ⇒ one fix may solve both:

* The segfault group: `abi1 abi4 abi8 abi9 mem1 mem2 mem3 vararg2`
* The hang group: `ifc isel2`

**This is the widest-reaching discovery of this session.**

## 27. [Root cause identified] the return value of a variadic call is read one step late

In `qpcc/repro_strf.c`, after each `p = strf...(...)`, print
`pooloff` / `inpool(p)` / `strlen(p)`:

```
  off=8  in=0 len=0     <- strfA has just returned, p is still empty
  off=8  in=1 len=5     <- only the next print sees the [previous] result
  off=16 in=0 len=0
  off=16 in=1 len=5
  off=24 in=0 len=0
  off=24 in=0 len=5
  off=32 in=0 len=5
  off=32 in=0 len=3
  off=32 in=0 len=0
  off=32 in=0 len=3
  off=72 in=0 len=0
  off=72 in=0 len=36
```

**Key observations**:

1. **`pooloff` advances correctly every time** ⇒ `alloc` really is called and the pool state is correct ✓
2. **But the `p` the caller just received is still empty; only after the next call does it see the previous value** ✗
   ⇒ **the return value of a variadic call is read one step late** ✗
3. The last time, `off=72 in=0 len=36`: `off` advanced by 40 (= align(37)) ✓,
   and the content is right too (len=36) ✓ — **but `inpool(p)` uses the stale `p`** ✗,
   **so the rc=19 of `repro_strf.c` is caused by this stale read** ✓

### 27.1 Why this explains the crash

In `strf`:

```c
p = (pool == PFn ? alloc : emalloc)(n + 1);   /* return value is one step late */
va_start(ap, s); vsnprintf(p, n + 1, s, ap);  /* uses stale p -> out of bounds */
```

**Writing into the wrong buffer ⇒ corrupting the heap/`FILE*` ⇒ `__sfvwrite` segfault** ✓
— matching the lldb stack exactly ✓.

### 27.2 Constructs ruled out (all pass in independent tests)

* Ternary selecting a function pointer (if/else fails the same way) ✗
* The return value of `vsnprintf(NULL, 0, ...)` ✓
* The alignment expression `(n+7) & ~(size_t)7` ✓
* Pointer differences, bitfields, nested designators, `emit` shape, `getcon` lookup ✓
* Simplified single-call version (all four hand-written variants rc=0) ✓

**⇒ The trigger condition is [the same variadic function being called multiple times] and its return value being used** ✓.

### 27.3 Next step (very narrow)

Write a minimal version that **does not depend on the allocator**:

```c
static char *g(char *s, ...) { va_list ap; va_start(ap,s); va_end(ap);
                                return s; }
int main(void) {
  char *a = g("A"); char *b = g("B"); char *c = g("C");
  if (a[0] != 'A') return 1;   /* the late read would fail here */
  if (b[0] != 'B') return 2;
  return 0;
}
```

If the contents of a/b are late ⇒ we get a minimal reproduction that does not involve libc ✓,
then go look at QPCC's **variadic call return convention** (the arm64 ABI's return value/call sequence).

**This belongs to the same family as the `argcls`/`normins` already fixed in this session** (calling-convention encoding) ✓.

### 27.4 [Correction] "return value is late" was a misreading; the real conclusion is [the wrong branch was chosen]

Validated the return value with a minimal variadic test that does not depend on libc:

```c
static char *g(char *s, ...) { va_list ap; va_start(ap,s); va_end(ap); return s; }
static int  h(int k, ...)    { va_list ap; int v; va_start(ap,k);
                               v = va_arg(ap,int); va_end(ap); return v + k; }
```

**clang rc=0, qpcc rc=0** ⇒ **the return value of the variadic function is completely normal** ✗,
Section 27's "one step late" conclusion is **void** ✗.

Looking at the trace again:

```
  off=8  in=0 len=0     <- the pool state of alloc advanced by 8 ✓
  off=8  in=1 len=5
```

**`len=0` means that memory is all zeros ⇒ it came from `calloc`** ✓
⇒ **`strfA` took `emalloc`, not `alloc`** ✗
⇒ **the branch `pool == PFn ? alloc : emalloc` chose wrong** ✓
⇒ fully consistent with `strfB` (the if/else version) failing the same way ✓

**The advance of `off` was not done by `alloc`** ✗ — it is leftover from the **previous** successful call,
or the advance of `pooloff` happens somewhere else ✓. Section 27 was wrong to treat it as evidence that "alloc was called" ✗.

### 27.5 The only conclusion currently certain

**In this `strf` shape, `emalloc` is still taken even when `pool == PFn` is true** ✗.

Ruled out (all pass in independent tests):

* Variadic return value (the g/h tests above) ✓
* Ternary vs if/else (both wrong, so it is unrelated to the ternary) ✗
* Simplified single-call version (all four hand-written variants rc=0) ✓
* Branching on a parameter to call inside a variadic function ✓
* `vsnprintf` length, alignment expression, pointer differences, bitfields, nested designators,
  `emit` shape, `getcon` ✓

**The trigger condition is [the same variadic function being called multiple times] and [a function that modifies global state being called inside the branch body]** ✓.
Next step: replace `strfA`'s `alloc`/`emalloc` with two functions that **do not modify any global state**;
if it still fails ⇒ unrelated to global state; if it passes ⇒ the problem is in the read-modify-write of `pooloff`/`poolbuf` ✓.

### 27.6 The fifth methodological error of the same kind

Five times in this session I misread the meaning of a printed number:

1. Read the diff `14,15d13` as "instructions dropped"
2. Read constant **index** 12 as a constant **value**
3. Read the missing `-dR` output as rega's decision
4. Read the repeated count as dropping at `rega.c:402`
5. Read `len=0` + the advance of `off` as "the return value is late"

**All five were reading errors; the data was always right.** Lesson: any conclusion must be validated with an **independent minimal test**;
you cannot infer from instrumented output alone ✓.

## 28. [Unambiguous hard facts] alloc's call count and the pool state differ from clang

Added a global counter to each of the two allocators in `qpcc/repro_strf.c`, and printed at the end of `main`:

```
clang: alloc=41  emalloc=2  pooloff=360  last_in=1  last_len=36   rc=0
qpcc:  alloc=5   emalloc=2  pooloff=72   last_in=0  last_len=36   rc=19
```

**Two independent indicators corroborate each other**:

* **Counter**: `alloc` was called **5 times vs 41 times** ✗
* **Pool state**: final `pooloff` **72 vs 360** ✗ (= 9×8 vs 45×8 ✓)

⇒ **it is not a problem with reading the counter; the pool state itself is short by 288 bytes** ✓,
**the 36 `alloc` calls really did not happen** ✗.

And `emalloc`'s count is **2 on both sides** ✓ ⇒ in those 36 iterations **`strfA` was never called at all** ✗,
rather than "it took the other branch" ✓.

### 28.1 Ruled out (all have independent minimal tests; both clang and qpcc give rc=0)

| Construct | Result |
| --- | --- |
| Return value of a variadic function (`g`/`h`) | correct ✓ |
| Ternary selecting a function pointer (including `pool == PFn`) | correct ✓ |
| if/else selecting a function pointer | correct ✓ |
| Calling an ordinary function 20 times in a loop | cnt=20 ✓ |
| Calling a variadic function 20 times in a loop | cnt=20 ✓ |
| Accumulating a variadic function's return value in a loop | sum=190 ✓ |
| Allocator counters (simple version) | alloc/emalloc fully consistent ✓ |
| Four hand-written single-call variants | all rc=0 ✓ |

### 28.2 Conclusion

**The trigger condition must include all of**:

1. A variadic function (`strfA`/`strfB`)
2. **Being called multiple times in a loop**
3. **And there being other variadic functions in the same translation unit** (`strfB`/`strfC`)

Only with all three present does it reproduce ✓ (the hand-written version kept only 1+2, hence rc=0 ✓).

### 28.3 Next steps (specific)

Starting from `repro_strf.c`, **delete function bodies one by one** (not the calls) to find the minimal combination:

* Keep `strfA` + `strfB` (two variadic functions), delete `strfC`
* Keep `strfA` + `strfC`, delete `strfB`
* Change `strfB`'s loop from 20 to 0 (keeping only the function definition)

**Key criterion**: whether `alloc`'s count recovers to 41 ✓.

**Note**: the sixth misreading of this session (interpreting `len=0` as `calloc` giving zeroed memory ✓, when in fact it was not called ✓),
so this section keeps only **two mutually corroborating hard indicators** (the counter + `pooloff`) ✓, and no longer uses single-point inference ✓.

## 29. [Milestone] Item three achieved: all self-hosted qbe fixtures are semantically correct

```
total 58: both correct 58, only reference 0, only qpcc 0, neither 0, skipped 1
```

**The acceptance criterion (`only reference correct` = 0 and `neither` = 0) is satisfied.**

### 29.1 The path to achievement

The two branches each fixed half; only after merging was it enough:

| Fix | Source |
| --- | --- |
| `lsl #12` shifted immediate | both sides fixed it independently, equivalent; took the colleague's `dpr_addsub_imm_packed` version (with whitebox tests) |
| Shift result type and signedness | colleague's sema `promote_shift_operand` + codegen using `result_ty` (more fundamental than only changing `uns`) |
| Conditional-expression branches converted to a common type | both sides fixed it independently (equivalent) |
| **`&&`/`||` short-circuit when used as a value** | **colleague** (missing on my side) |
| `coerce` word-width widening signedness | me |
| `gvn` wide-constant guard | me |
| Wide-constant truncation (`normins` placeholder + `argcls`'s `Ke`) | me |

### 29.2 The last one is a harness defect, not a compiler bug

The first line of `dark.ssa` is:

```
# skip arm64 arm64_apple rv64 amd64_win
```

It is a hack test that takes a stack pointer in the dark-type style, and it **explicitly declares that it does not run on arm64_apple**;
the reference qbe also gives rc=139 on this machine ✓. The harness previously ignored that directive and counted it as `neither` ✗.

Now `semantic-check.sh` reads the first line of every fixture, and when it matches the current target it **reports it separately as skipped**,
not counted as a failure — consistent with the behavior of `vendor/qbe/tools/test.sh` ✓.

### 29.3 Lessons

* **"The reference fails too" must be verified first** — a `neither` may not be a problem of the compiler under test at all ✓
* QBE's own fixtures carry `# skip <targets>`, and any custom runner must respect it ✓
* When two forked branches each fix half, **merging is faster than continuing to investigate separately** (this merge turned 14 positive at once) ✓
