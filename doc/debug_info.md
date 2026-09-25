# Debug information

qbe.mbt carries source locations through the IL and emits the assembler
directives a debugger needs. The line directives are the ones the frozen
reference QBE already defines, so their output is byte-identical to
`vendor/qbe` as well.

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
code generation. A `dbgfile` must precede the first `dbgloc`: with no current
file the reference also emits `.loc 0`, which assemblers reject.

## Line tables

Every GAS-text backend (amd64, arm64, rv64, la64) emits:

    .file 1 "hello.c"
    ...
        .loc 1 2
    ...
        .loc 1 4 3

The assembler turns these into a DWARF `.debug_line` section. `--jit`,
`--run-asm`, `--emit obj` and the interpreter skip `dbgloc` (metadata only).

## Unwinding (CFI, `-g`)

`-g` / `--debug-info` additionally emits DWARF call-frame information for
amd64 and arm64; the assembler turns it into `.eh_frame` (and `.debug_frame`):

    fact:
        .cfi_startproc
        endbr64
        pushq %rbp
        .cfi_def_cfa_offset 16
        .cfi_offset %rbp, -16
        movq %rsp, %rbp
        .cfi_def_cfa_register %rbp
        ...
        leave
        .cfi_def_cfa %rsp, 8
        .cfi_restore %rbp
        .cfi_endproc

arm64 emits the analogous `w29`/`w30` and callee-saved register offsets
(`x19..`, `d8..`). CFI is off by default so the plain output stays
byte-identical to the reference (which emits none). rv64/la64 do not emit CFI
yet.

## Compilation unit (`.debug_info`, `-g`)

`-g` also emits a minimal DWARF5 compilation unit, so a debugger can turn a
code address back into a source file/line:

    .section .debug_abbrev,"",@progbits   # Mach-O: __DWARF,__debug_abbrev
    ...
    .section .debug_info,"",@progbits
        .long 37          # unit length
        .short 5          # DWARF version
        .byte 1           # DW_UT_compile
        .byte 8           # address size
        .long 0           # abbrev offset
        .byte 0x01        # DW_TAG_compile_unit
        .asciz "qbe.mbt"  # producer
        .short 12         # DW_LANG_C99
        .asciz "hello.c"  # CU name (first dbgfile)
        .asciz "."        # comp_dir
        .byte 0           # DW_AT_low_pc  -> addrx 0
        .byte 1           # DW_AT_high_pc -> addrx 1
        .long 0           # DW_AT_stmt_list (the assembler's .debug_line)
        .long 8           # DW_AT_addr_base
    .section .debug_addr,"",@progbits
        ...
        .quad main        # addrx 0
        .quad .Ldbgend    # addrx 1 (end of .text)

The CU's `DW_AT_low_pc`/`high_pc` use `DW_FORM_addrx`, so the addresses live in
`.debug_addr` (as clang does); `.debug_info` therefore carries no Mach-O
relocations, and the linker's debug map relocates `.debug_addr`. ELF uses
`.debug_*,"",@progbits`, Mach-O uses `__DWARF,__debug_*`.

Working end to end on macOS (no dSYM needed - lldb reads the object debug map):

    $M -g -t arm64 -G m demo.ssa > demo.s
    clang -c -g demo.s -o demo.o
    clang demo.o -o demo_prog
    lldb -o 'b one.c:3' -o run -o bt ./demo_prog

## Verification

    python compare.py test/dbg           # byte-identical to vendor/qbe (no -g)
    moon test -p parser -p util          # parser + directive tests

    M=./_build/native/debug/build/cmd/main/main.exe
    $M -g -t arm64 -G m demo/04_recursion.ssa > out.s
    clang -c -g out.s -o out.o
    llvm-dwarfdump --eh-frame out.o      # CFA rules per PC

`test/dbg/` holds line-info cases (ordering, file dedup, column, multiple
files); the three differential targets pass under every debug flag.

## Trying it

    M=./_build/native/debug/build/cmd/main/main.exe
    $M -t arm64 -G m test/dbg/001_loc.ssa > out.s
    clang -c -g out.s -o out.o        # -> __debug_line in the object
    llvm-dwarfdump --debug-line out.o

## Limitations and roadmap

- Line tables, a minimal DWARF5 compilation unit and (amd64/arm64) CFI. There
  are no variable/type DIEs yet: a debugger shows files/lines and can unwind,
  but `frame variable` is empty.
- On macOS, delete any stale `*.dSYM` before debugging an assembly-only build:
  an empty dSYM shadows the object debug map lldb would otherwise use.
- Planned: builder-side variable/type metadata (`ir_builder` + C ABI + Rust),
  CFI for rv64/la64, and DWARF in the self-contained object / JIT path.
