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

`-g` also emits a minimal DWARF4 compilation unit, so a debugger can turn a
code address back into a source file/line:

    .section .debug_abbrev,"",@progbits   # Mach-O: __DWARF,__debug_abbrev
    ...
    .section .debug_info,"",@progbits
        .long 46          # unit length
        .short 4          # DWARF version
        .long 0           # abbrev offset
        .byte 8           # address size
        .byte 0x01        # DW_TAG_compile_unit
        .asciz "qbe.mbt"  # producer
        .short 12         # DW_LANG_C99
        .asciz "hello.c"  # CU name (first dbgfile)
        .asciz "."        # comp_dir
        .quad main        # DW_AT_low_pc
        .quad .Ldbgend    # DW_AT_high_pc (end of .text)
        .long 0           # DW_AT_stmt_list (the assembler's .debug_line)

DWARF4 rather than 5: Apple's lldb rejects version 5. The CU's low/high PC are
plain `DW_FORM_addr` values that the linker's debug map relocates. ELF uses
`.debug_*,"",@progbits`, Mach-O uses `__DWARF,__debug_*`.

Working end to end on macOS (no dSYM needed - lldb reads the object debug map):

    $M -g -t arm64 -G m demo.ssa > demo.s
    clang -c -g demo.s -o demo.o
    clang demo.o -o demo_prog
    lldb -o 'b one.c:3' -o run -o bt ./demo_prog

## Variables and types (`-g`, builder / C ABI / Rust)

Line info comes from the IL, but QBE IL cannot express variables or types, so
they are supplied by the **programmatic builder** (the same split Cranelift
uses: the embedder owns the language types):

    let mut module = ctx.create_module();
    module.enable_debug_info(true);
    module.dbg_compile_unit("demo.c", ".");
    // ... builder for `f` ...
    {
        let mut b = module.builder(f);
        let sum = b.ins().iadd(x, one);
        b.declare_var("sum", DebugType::W, sum);
    }

The emitter then writes, under `-g`:

- `DW_TAG_subprogram` per function (name, low/high PC, `DW_AT_frame_base`);
- `DW_TAG_variable` per declared variable (name, `DW_AT_type`);
- base/pointer/aggregate `DW_TAG_*_type` DIEs;
- a `.debug_loc` entry per variable giving its `DW_AT_location` over the
  function - `DW_OP_regx` for a register value or `DW_OP_fbreg` for a stack
  slot, resolved after register allocation.

`declare_var` is the Cranelift `ValueLabel` role: the front end names a value
and its type; the final register/slot is derived from the backend. `dbg_loc` /
`set_source_loc` attach exact source locations; the builder inserts a default
line-1 location at each function start so the debugger can associate the code
with the CU. The C ABI mirrors this as `qbe_dbg_enable`, `qbe_dbg_compile_unit`,
`qbe_dbg_var` and `qbe_dbg_loc`.

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

`scripts/run_dbg_demo.sh` does the whole flow (emit `-g`, link, set a breakpoint
under `lldb`) and is part of the macOS CI job.

## Limitations and roadmap

- Line tables, a DWARF4 compilation unit with subprograms/variables/types, and
  (amd64/arm64) CFI. `frame variable` works for builder-declared variables.
- Locations are one range per function (the whole subprogram), not per lexical
  scope: a register recorded for a variable may be reused later in the
  function, so the value is only reliable while it is live. Per-scope ranges
  (`ValueLabel` ranges) are the next step, as is `DW_TAG_formal_parameter`.
- Variable locations are emitted for arm64; amd64/rv64/la64 record the
  subprogram but not the variable location yet.
- On macOS, delete any stale `*.dSYM` before debugging an assembly-only build:
  an empty dSYM shadows the object debug map lldb would otherwise use.
- Planned: per-scope ranges, CFI for rv64/la64, and DWARF in the
  self-contained object / JIT path.
