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

Remaining: encode the full arm64 instruction set the text emitter produces and
drive it from the same post-`rega` IR (a binary arm64 emitter replacing the
string one), plus relocation application for `adrp`/`add`/`bl`.

## Tests

    moon test --target native -p run_asm      # FFI, route A, route B slice
    moon test --target native -p object   # encoder vs clang, object layout
