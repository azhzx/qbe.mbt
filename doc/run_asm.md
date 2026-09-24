# JIT and object emission

qbe.mbt can turn a .ssa file into machine code two ways, currently for
**macOS / aarch64**:

    qbe --emit obj -o fib.o demo/10_fibonacci.ssa    # Mach-O object file
    qbe --run-asm fib,10 demo/10_fibonacci.ssa           # 55

Both go through the same pipeline (front-end -> arm64 ABI -> isel -> rega)
and the byte-exact arm64 text emitter.

## Route A - toolchain backed (default)

`run_asm/` (native only) drives the system toolchain:

- `--emit obj` writes the Mach-O assembly to a temp `.s` and runs `clang -c`
  to produce the `.o`.
- `--run-asm FUNC[,ARG]` writes the Mach-O assembly to a temp `.s`, runs
  `clang -dynamiclib`, `dlopen`s it, resolves `FUNC` with `dlsym` and calls it.

The pieces MoonBit cannot express itself live in `run_asm/run_asm_stub.c` behind a
typed FFI (`run_asm/ffi.mbt`): `mmap`/`mprotect` executable memory, temp files,
process spawn, `dlopen`/`dlsym`, and calling a code address.

Pros: works today, tiny, reuses the verified emitter. Cons: needs Xcode/clang
at run time.

## Route B - self contained (in progress)

Goal (Cranelift style): emit the object and run the code entirely in process,
without a toolchain.

Done and validated:

- `object/macho.mbt` - a Mach-O (`MH_OBJECT`, arm64) writer: header,
  `LC_SEGMENT_64` with sections, `LC_BUILD_VERSION`, `LC_SYMTAB`, `nlist_64`
  and external relocations. A hand-built object links with `ld` and runs.
- `object/arm64_enc.mbt` - an instruction encoder slice (`add` immediate,
  `movz`, `movk`, `ret`), validated byte-for-byte against `clang`.
- `run_asm/module.mbt` - `ExecBlock`: `mmap` + copy + `mprotect` + call, so
  in-memory arm64 code executes.

Route B progress: `target_arm64/emit/emit_arm64_bin.mbt` now drives the same
post-`rega` IR and emits raw arm64 words (prologue/epilogue, integer and double
ALU, loads/stores, comparisons via `cset`, constant materialization and local
branch fixups). It is byte-for-byte identical to clang's encoding of the text
emitter for the `add` and loop/branch cases, and a native test runs the emitted
code in `ExecBlock` (`sum_to`).

The module emitter (`emit_arm64_bin_module`) links all functions into one text
blob, patches intra-module `bl` calls, lays out the `data` section in the same
image and patches global `adrp`/`add` addresses. `ExecBlock::load_module` maps
the image and makes only the code region executable, so globals stay writable.
Native tests cover recursion (`fact`), cross-function calls and global-data
read/write.

Also supported: parallel-copy `swap`, single-precision arithmetic, FP
conversions and the floating-point rodata pool (`Lfp0`, `Lfp1`, ...).

Object emission (`emit_arm64_object`) builds a multi-section Mach-O object with
real relocations: `BRANCH26` for calls, `PAGE21`/`PAGEOFF12` for global
addresses, over `__text`/`__data`/`__TEXT,__const`. `--emit obj --route b`
writes it and it links with clang/ld (a native test links and runs one).

`--run-asm --route b` executes the same module image directly (no clang). Both
routes agree on the demos.

Remaining: external symbols in the JIT (libc calls need `dlsym`/`BRANCH26`
resolution), byte-for-byte parity with clang on the full 406-case arm64 suite,
and eventually making route B the default.


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

    moon test --target native -p run_asm      # FFI, route A, route B slice
    qbe --run-wasm add,2,3 demo/01_arith.ssa  # wasm via node
    moon test --target native -p object   # encoder vs clang, object layout
