# Debug information

qbe.mbt carries source locations through the IL and emits the assembler
directives a debugger needs. The directives are the ones the frozen reference
QBE already defines, so debug output is byte-identical to `vendor/qbe` too.

## IL syntax (already part of QBE)

Two statements, taken verbatim from upstream QBE:

    dbgfile "path/to/source.c"   # top level: declare a source file
    dbgloc LINE                  # inside a function: a source line
    dbgloc LINE, COL             # ... with a column

Example:

    dbgfile "hello.c"
    export function w $main() {
    @start
        dbgloc 2
        %y =w add 1, 2
        dbgloc 4, 3
        ret %y
    }

`dbgfile` may appear anywhere between functions/data; repeated paths are
deduplicated and numbered in first-appearance order. `dbgloc` is an
instruction with no result: it flows through the SSA passes and is ignored by
code generation.

## What is emitted

Every GAS-text backend (amd64, arm64, rv64, la64) emits:

    .file 1 "hello.c"
    ...
        .loc 1 2
    ...
        .loc 1 4 3

The assembler turns these into a DWARF `.debug_line` section. `--jit`,
`--run-asm`, `--emit obj` and the interpreter skip `dbgloc` (metadata only).

## Verification

    python compare.py test/dbg           # byte-identical to vendor/qbe
    moon test -p parser -p util          # parser + directive tests

`test/dbg/` holds line-info cases (ordering, file dedup, column, multiple
files); the three differential targets pass under every debug flag.

## Trying it

    M=./_build/native/debug/build/cmd/main/main.exe
    $M -t arm64 -G m test/dbg/001_loc.ssa > out.s
    clang -c -g out.s -o out.o        # -> __debug_line in the object
    llvm-dwarfdump --debug-line out.o

## Limitations and roadmap

- Line tables only. There is no DWARF `.debug_info` yet, so:
  - on ELF (Linux) `lldb`/`gdb` already do source breakpoints and stepping;
  - on macOS the linker builds its DWARF debug map only when an object carries
    a compilation unit, so a terminal `lldb` session needs the `.debug_info`
    milestone below. The `.file`/`.loc` output itself is unchanged.
- No CFI (`.cfi_*`) yet, so unwinding of optimized frames is not guaranteed.
- Planned: CFI/`.eh_frame`, then a minimal `.debug_info` compilation unit, then
  builder-side variable/type metadata (`ir_builder` + C ABI + Rust).
