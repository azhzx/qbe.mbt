# JIT and object emission

qbe.mbt turns a `.ssa` file into arm64 machine code for **macOS / aarch64**
without any toolchain (route B, the default), or by borrowing clang
(route A, `--clang`):

    qbe --emit obj -o fib.o demo/10_fibonacci.ssa    # Mach-O object file
    qbe --run-asm fib,10 demo/10_fibonacci.ssa       # 55

## Trying it

Build once (`moon build --target native`), then:

    M=./_build/native/debug/build/cmd/main/main.exe

    # Run a function in-process: mmap + mprotect + call. No clang, no linker.
    $M --run-asm fib,10 demo/10_fibonacci.ssa        # 55
    $M --run-asm sum_to,100 demo/03_loop_phi.ssa     # 5050
    $M --run-asm fact,10 demo/04_recursion.ssa       # 3628800
    $M --run-asm global_demo demo/06_memory.ssa      # 1
    $M --run-asm sign,-5 demo/08_compare.ssa         # 4294967295 (-1 as u32)

    # Emit a Mach-O object. Without -o it goes to .qbe_build/<name>.o.
    $M --emit obj demo/10_fibonacci.ssa                     # .qbe_build/10_fibonacci.o
    $M --emit obj --out-dir build demo/10_fibonacci.ssa     # build/10_fibonacci.o
    $M --emit obj -o fib.o demo/10_fibonacci.ssa            # exact path
    printf 'long fib(long);\nint main(void){ return fib(10)==55?0:1; }\n' > drv.c
    clang -o fib .qbe_build/10_fibonacci.o drv.c && ./fib; echo $?   # 0

`--run-asm` needs macOS/aarch64 (it executes the code); `--emit obj` is pure
MoonBit and works on any host. `--clang` switches both back to the
clang-backed route A.

## Route B - self contained (default)

`target_arm64/emit/emit_arm64_bin.mbt` drives the same post-`rega` IR and
emits raw arm64 words directly: prologue/epilogue, integer and double ALU,
loads/stores, comparisons via `cset`, constant materialization
(`MOVZ`/`MOVN`/`ORR` bitmask), single-precision ops, FP conversions and the
floating-point rodata pool (`Lfp0`, `Lfp1`, ...), parallel-copy `swap`, and
local branch fixups.

The module emitter (`emit_arm64_bin_module`) links all functions into one text
blob, patches intra-module `bl` calls, lays out the `data` section in the same
image and patches global `adrp`/`add` addresses. `ExecBlock::load_module`
maps the image and marks only the code region executable (RX), so globals stay
writable (RW).

`target_arm64/emit/emit_arm64_obj.mbt` builds a multi-section Mach-O object
(`__text` / `__data` / `__TEXT,__const`) with the four relocation kinds:
`PAGE21`/`PAGEOFF12` (global addresses), `BRANCH26` (calls) and `UNSIGNED`
(data pointers).

`object/macho.mbt` writes the object; `object/arm64_enc.mbt` holds the
instruction encoders, each validated byte-for-byte against `clang`.
`run_asm/run_asm_stub.c` supplies the pieces MoonBit cannot express itself
(`mmap`/`mprotect`, temp files, process spawn, `dlopen`/`dlsym`, calling a
code address) behind a typed FFI (`run_asm/ffi.mbt`).

## Route A - toolchain backed (fallback, `--clang`)

`run_asm/` (native only) writes the Mach-O assembly to a temp `.s` and runs
`clang -c` for `--emit obj`, or `clang -dynamiclib` + `dlopen`/`dlsym` for
`--run-asm`. It needs Xcode/clang at run time and exists mainly as a reference
and as a fallback.

## Verification

    moon test --target native          # 315 unit/whitebox tests
    python tools/check_route_b.py      # 336/336 compilable arm64 cases match clang

`tools/check_route_b.py` compares route B's Mach-O `__text` against clang's
assembly of the route A text for every non-`_` file under `test/`. The other
70 files are rejected identically by the frozen reference QBE, so there is no
assembly to compare. A native test also links a route-B object and runs it, and
another dereferences a `$r -> $t` data pointer to exercise `UNSIGNED`.

## Limitations

- JIT: external symbols (libc `printf` et al.) are not resolved yet, so
  `--run-asm` is limited to self-contained functions.
- The QBE vararg ABI is not implemented (vararg prologues are skipped).
- `--emit obj` writes `__text`/`__data`/`__TEXT,__const`; `__bss` and
  `__cstring` are folded into `__data`.

## Running wasm (`--run-wasm`)

`qbe --run-wasm FUNC[,ARG]...` compiles to wasm (the `-t wasm` backend), turns
the WAT into a module with `moon-wasm-opt` (binaryen, shipped with MoonBit) and
runs the export under `node`. Example:

    qbe --run-wasm add,2,3 demo/01_arith.ssa   # 5

The wasm backend lowers QBE's CFG to a dispatch loop (`br_table`), so loops and
phi nodes work, and it also supports internal calls/recursion, floating-point
comparisons and `data` segments. External imports (`printf` et al.) and
variadic calls are not emitted yet.

## Tests

    moon test --target native -p run_asm      # FFI, route A, route B, object linkage
    moon test --target native -p object       # encoder vs clang, object layout
    qbe --run-wasm add,2,3 demo/01_arith.ssa  # wasm via node
