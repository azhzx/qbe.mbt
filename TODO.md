# TODO / known issues

Tracked after the `feat/Qiang` self-host work: the QPCC-built `qbe` now passes
all 58 `the semantic-check.sh demo in the Qiang repository` fixtures, and the debug / asm
differentials stay 4908/4908 (amd64, arm64, rv64) and 409/409 (arm64 asm).

## Testing gaps

- **The object-emission path has no differential gate.**
  The arm64 differentials compare assembly text (`compare.py --target arm64
  --asm`, mapped to the reference's `arm64_apple`), but the self-hosted
  `qbe` is produced through `compile_ir_object` / `emit_arm64_object`.
  Commit `9203880` fixed a bug that existed only in the object emitter (the
  IP1 scratch was mapped twice) and was invisible to every gate. Suggested
  gate: compile the corpus with `--emit obj`, disassemble the result and
  compare against the reference, or run the QPCC self-host build as a CI job.

## Known divergences from the reference

- **The `arm64` target is missing the reference `arm64_apple`'s "Apple
  pre-ABI" pass.** The reference's `-dA` dump has an "After Apple pre-ABI"
  section, and its `-dL`/`-dS` dumps contain extra `abi.*` temporaries our
  port does not emit. It shows up on large inputs (e.g. the IL of
  `vendor/qbe/rega.c`) but not on the differential corpus, so it does not
  affect 4908/4908 or the self-host semantic-check. It is a real difference
  from the reference and should be ported.

  pre-ABI" pass.** The reference's `-dA` dump has an "After Apple pre-ABI"
  section, and its `-dL`/`-dS` dumps contain extra `abi.*` temporaries our
  port does not emit. It shows up on large inputs (e.g. the IL of
  `vendor/qbe/rega.c`) but not on the differential corpus, so it does not
  affect 4908/4908 or the self-host semantic-check. It is a real difference
  from the reference and should be ported.

- **Spill slot numbering diverges once register pressure is high enough.**
  `test/stress/_002_wide_300.ssa`, `_006_args_w_32.ssa` and
  `_009_calls_160.ssa` differ from the reference at `-dS` on all three
  targets (and in the emitted assembly): the two agree on the *number* of
  slots but assign different numbers and orders. The existing
  `test/regalloc/` inputs pass, so this is a regime the corpus did not reach.
  Repro: `python compare.py -dS test/stress/_006_args_w_32.ssa`. The three
  files are `_`-prefixed so they stay out of the exact differential until the
  pass matches.
  **Root cause (settled): this is the reference's own nondeterminism, not a
  port bug.** `limit` sorts the candidate temporaries with `qsort`, and when
  the spill costs tie the comparator returns 0, so the order - and therefore
  which temporaries get spilled - is whatever the C library's `qsort` happens
  to do. Our port uses MoonBit's `Array::sort_by`, which is *also* an unstable
  sort. Two unstable sorts agree on every one of the 420 corpus inputs (the
  arm64 assembly differential is 420/420 with the port as it stands) but part
  company on a handful of tie-heavy stress inputs.

  Evidence:
  - instrumenting `limit` on both sides shows the same input set, the same
    `k`, the same empty `fst`, and different sorted orders: the reference
    produces `16 15 67 ... 79 81 66` where we produce the collected order
    `15 16 66 ... 79 81`, so a different temporary is spilled;
  - rebuilding the reference with a *stable* insertion sort in place of
    `qsort` (Apple's is unstable there) makes it **byte-identical** to the
    port at `-dS` for the 15..32 argument repros - zero differences;
  - conversely, making *our* sort explicitly stable is not an option: it
    changes which temporary is spilled and drops the corpus arm64 assembly
    differential from 420/420 to 71/420.

  So the port matches the reference on the whole corpus, and the divergence
  is confined to inputs that tie on spill cost. Matching those would mean
  reimplementing one specific libc's `qsort` (Apple's locally, glibc's in
  CI), which would make the compiler's output depend on the build host - the
  opposite of what a byte-exact port wants. The three inputs stay
  `_`-prefixed, and anyone who wants to verify them locally can rebuild the
  reference with a stable sort.

- **`test/stress/_006_args_w_32.ssa` makes the emitter ICE.** Plain
  assembly emission (no `-d` flag) fails with `ICE: invalid second
  argument`; the reference, and our own `-dS` dump, handle the input. Most
  likely the same high-pressure regime as the slot divergence above.
  Repro: `_build/native/debug/build/cmd/main/main.exe -t arm64 test/stress/_006_args_w_32.ssa`.

- **`test/_bfmandel.ssa` is ~16x slower than the reference** (1.14s vs 71ms
  at `-dR`, amd64), far outside the 1.2-1.7x the rest of the corpus shows.
  That input is the only one where the gap is not explained by process startup,
  so it is worth a profile. Repro:
  `python tools/bench.py --all test/_bfmandel.ssa`.

## C2y (`-std=c2y`)

- `_Defer` diagnoses a jump out of its own statement and a `goto` into it,
  but a `longjmp` past a defer is left undefined (as the TS says) and is not
  diagnosed.


- clang implements `_Countof` but not `_Maxof`/`_Minof`, named loops or
  `_Defer`, so `maxminof.c`, `named_loops.c`, `defer_basic.c` and
  `defer_header.c` are QPCC-only (`// expect-exit N`) and are checked
  against their expected exit code instead of a clang reference.
- `<stdmaxof.h>`/`<stdminof.h>` are QPCC extensions (no WG14 proposal
  defines them), unlike `<stdcountof.h>` (N3469) and `<stddefer.h>`
  (TS 25755).


- **`char` and `signed char` are the same type to QPCC.** `CType` has
  `CChar(Bool)`, so plain `char` is modelled as `CChar(true)`, the same as
  `signed char`. C keeps `char`, `signed char` and `unsigned char` apart,
  so `_Generic(x, char: a, signed char: b)` cannot tell them apart, which is
  why the `_Generic` duplicate-association check skips that pair. Giving
  `CChar` a third state touches every `CChar(_)` match in the port.

- **A global variable cannot be initialised with a closure.** The environment
  is a local of the enclosing function, so there is none at file scope. This is
  now a diagnostic rather than a null function pointer. Decision (2026-10-11):
  do not lower it into a static pair; the environment would have to become a
  global object of its own, which is a new feature rather than a bug fix.

- **A C99 `inline` definition must not be emitted as a strong global.** Fixed for
  the linkage (an `inline` without `static`/`extern` is now non-exported, which
  is what unblocked Lua's link), but Qiang makes the symbol local where C says
  the definition simply is not external; a library that relies on one external
  definition from an `extern inline` in a chosen translation unit is not
  modelled.
- **FIXED: the frame was truncated, and shadowed locals shared a slot.** Two
  bugs, both fixed (commits bbe4827 and the one adding large-offset handling):
  the emitter truncated a frame larger than 4095 bytes to its low 12 bits, and
  the code generator bound locals by name in one flat map so a shadowing
  declaration shared a slot and was read through the other one's type. All 34
  Lua files now build, link and run: `lua -v`, `lua -e 'print(1+1, 2*3, "ok")'`
  and `for k=1,2 do print(k) end` all work.
  Large frame offsets now go through IP1 (a scratch): **IP0 is allocated by the
  register allocator** in this port even though `arm64_bin_loadcon` uses it
  transiently, so using IP0 clobbered live values. `enc_ldst` now aborts rather
  than truncating.
- **FIXED: integer promotion.** C promotes char and short to int before the
  usual arithmetic conversions, so `int >= unsigned char` is a SIGNED
  comparison; Qiang asked only whether either operand was unsigned. Lua's
  freereg does `if (reg >= luaY_nvarstack(fs))` with reg an int and
  luaY_nvarstack returning lu_byte, so a -1 register was compared as
  0xFFFFFFFF, freereg was decremented when it should not have been, and every
  later register in the emitted bytecode shifted by one. That is why
  `local i=1 while i<=3 do print(i) i=i+1 end` overwrote i with print's value.
  The differential never caught it because it feeds IR, not C, so Qiang's C to
  IR conversion for comparison operators was untested there. Fixture:
  Qiang/tests/promote_cmp.c; oracle 167/167.
- **RESOLVED (Lua): it builds, links and runs correctly.** All 34 sources
  compile, and lua -v, arithmetic, strings, tables, closures, metatables,
  coroutines, pcall, numeric and float for loops, while loops and recursion
  (fib(20) = 6765, fact(20) = 2432902008176640000) all produce the right answers.
  The historical notes below record how it was found.
- **REMAINING (Lua), localized to lcode.o: the emitted bytecode has the wrong
  register.** \`local i=1 while i<=3 do print(i) i=i+1 end\` prints a function
  instead of 1, 2, 3, and swapping Qiang-compiled objects into a clang-built Lua
  gives a single offender: lcode.o. The bytecode itself is the oracle - the
  clang-built luac says
      GETTABUP 1 0 0 / MOVE 2 0 / CALL 1 2 1   and 3 slots
  while luac with Qiang's lcode.o says
      GETTABUP 0 0 0 / MOVE 1 0 / CALL 0 2 1   and 2 slots
  so the call's base register is one too low and maxstacksize is one too small -
  the register-reservation path in lcode.c assigns R0, which holds the local.
  Probes in luaK_reserveregs/freereg/luaK_checkstack show Qiang calling
  luaK_reserveregs before the freereg of freeexp, i.e. the calls are ordered
  differently; FuncState's layout and its lu_byte arithmetic match clang
  exactly, so the fault is in how Qiang compiles that ordering. Next: reduce
  \`luaK_exp2nextreg\` (dischargevars/freeexp/reserveregs) to a standalone case.
- **FIXED (Lua): missing declarations in the bundled headers.** An implicitly
  declared function returns int, so pointer results were truncated: string.h had
  no strpbrk, and Lua's l_str2d opens with \`const char *pmode = strpbrk(s,
  ".xXnN")\`, so any literal containing a '.' crashed. stdio.h lacked
  freopen/tmpfile (FILE* truncated) and fseek/ftell/feof/ferror/clearerr/
  setvbuf/tmpnam; ctype.h lacked iscntrl/isgraph; stdlib.h lacked system.
  __builtin_fabs*/sqrt* rewrites now supply the libm prototype. A scan of all 34
  Lua sources for "implicit declaration" now prints nothing.
- **REMAINING (Lua), localized to lobject.o: a float constant.** `print(1.0)`
  segfaults, and so does the bare statement `local x = 1.0`; integers
  (`print(1)`) and runtime floats (`print(math.pi)`, which is a table field)
  are fine. The bytecode for `print(1.0)` is GETTABUP/LOADF/CALL, so it is the
  LOADF of a float constant. Swapping Qiang-compiled objects one at a time into
  a clang-built Lua shows a single offender: lobject.o. That object was fine
  before this round's changes, so it is worth checking how the two fixes here
  (the shadowed-local rename and the large-offset scratch) interact with
  lobject.c - start by swapping in a lobject.o built with the rename disabled.
- **REMAINING (Lua):** `for i=1.0,3.0 do print(i) end` segfaults, and a local
  becomes garbage in a `while` whose body calls out:
      local i=1 while i<=3 do print(i) i=i+1 end   -->  i prints as a function
  `local n=0 while n<3 do n=n+1 end print(n)` is correct, so the trigger is a
  call inside the loop body, not the loop. Both are execution-time (the bytecode
  and the compiler are fine), so look at how `luaV_execute` handles OP_CALL
  around the loop - likely another instance of a value landing in the wrong
  slot.
- **ROOT CAUSE (historical, now fixed): the frame does not cover the local slots.**
  `forprep`'s IR contains 18 `alloc8` slots (144 bytes), but the emitted
  prologue is `stp x29, x30, [sp, #-0x50]!` - an 80-byte frame - and the only
  frame offsets used anywhere in the function are the four callee-saved saves.
  Not one slot offset appears, so all 18 slots were promoted away, the register
  allocator had nowhere to spill, and the locals land *outside* the frame, on
  the caller's stack. That is why the probe saw `init == step == L`: those
  locals read the caller's parameter-spill area.
  Evidence: (a) the qabec IR for `forprep` is byte-identical whether `lvm.c` is
  compiled alone or wrapped in another translation unit; (b) the emitted machine
  code is identical too (only branch displacements differ); (c) the "harness
  works" result was a coincidence - the overflow landed on `main`'s `stk[]`,
  which happened to hold 1. Suspect the promotion in `mem/promote.mbt`
  (pitfalls 3.4) and the frame-size computation in `mem/`.
  Refinement: the frame is not too small, the slots are *aliased*. The machine
  code addresses exactly two slots, `add x1, x29, #0x20` and `add x1, x29,
  #0x28`, for 18 allocations, so the lifetime analysis merged slots that are
  live at the same time. The one unusual construct in `forprep` is the
  variadic `luaG_runerror` call; replacing the six `luaG_*` calls in
  `forprep`/`forlimit` with `abort()` makes the loop *run* (two iterations)
  though the control variable is still garbage - so varargs feed into the
  liveness used for coalescing. Next: `mem/coalesce.mbt`'s liveness around
  variadic calls (`call ... ...`), with `doc/live.md` as the reference.
- **Lua's VM is miscompiled; localized to lvm.o only.** Method: build all of
  Lua with clang (correct), then swap in one Qiang-compiled object at a time and
  rerun `for k=1,2 do print(k) end`. Only `lvm.o` breaks it, so the defect is in
  Qiang's compilation of `src/lvm.c`, not in the backend or the other 33 files.
  Ruled out along the way: the bytecode (Qiang-built `luac -l` matches), pointer
  arithmetic on 16-byte structs and typedef'd pointers, and `io.write` itself.
  Instrumentation evidence (insert `fprintf` probes into `forprep`, compile that
  one object with Qiang, keep the other 33 from clang, and run the same probe
  build with clang):
      Qiang : init=8462350312 step=4376879632 raw=1 raw1=2 raw2=1
      clang: init=1          step=1          raw=1 raw1=2 raw2=1
  So the expressions are right - `pinit->value_.i`, `plimit->value_.i`,
  `pstep->value_.i` all read 1/2/1 - and the tags are right, but the *locals*
  `init` and `step` hold garbage; `step` is even exactly the pointer `pinit`
  (4376879632 == 0x104e1e210). A local declared with an initializer is read back
  from the wrong slot. Extracting `forprep` + `forlimit` verbatim into a
  standalone file is *correct* under Qiang, even with a variadic `luaG_runerror`,
  so the trigger is elsewhere in `lvm.c`; the next step is to binary-search the
  file by `#if 0`-ing ranges with the swap test as the oracle.
  The symptom - a numeric `for` never entering its body, and a local becoming
  garbage (a function value) in a `while` that calls out - looks like a value
  live across a call being clobbered inside `forprep`, which keeps `pinit`,
  `plimit` and `pstep` live across `forlimit`. Next: shrink `lvm.c` (or split
  `forprep`/`forloop` out with stubs) until the swap test stops breaking.
- **Lua builds, links and runs, but some programs are miscompiled.** After the
  fixes above, all 34 Lua 5.5.1 sources compile, the interpreter links, `lua -v`,
  `lua -e 'print(1+1)'` and a script printing "hi" all work - but
  `for i=1,3 do io.write(i, " ") end print()` prints nothing, and a larger
  script segfaults. So there is at least one arm64 code generation bug left that
  the 5040-case core differential does not cover. Next step: reduce the empty
  for-loop to a minimal case.

## Latent risk

- The byte-identical differentials only cover the corpus under `test/`
  (409 exact-differential inputs plus the `test/stress/` scale series).
  Inputs outside it — in particular the IL QPCC's front end
  produces for the QBE C sources — can still expose latent backend differences;
  the `260d556` / `9203880` pair was exactly such a case, so treat the
  self-host build as an integration test.
