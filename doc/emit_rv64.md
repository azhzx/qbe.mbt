# `emit_rv64` Package API Reference

Package path: `azhzx/qbe/target_rv64/emit`

RISC-V 64 GAS assembly output. Runs after `isel_rv64` and `spill`/`rega` completion, rendering functions with assigned physical registers into RISC-V assembly text. Corresponds to upstream QBE's `rv64/emit.c`.

[中文版本 (Chinese Version)](zh/emit_rv64.md)

## Entry Point

```moonbit
pub fn emit_rv64(
  @types.Fn,          // function with completed register allocation
  @util.Interner,     // string interner
  String,             // gasloc: local-label prefix (".L" for ELF)
  String,             // gassym: global-symbol prefix ("" for ELF)
  Bool,               // debug switch
  Array[@types.Typ],  // global type table
) -> String

pub fn gasemitdat_rv64(@types.Dat, String, String, StringBuilder) -> Unit
pub fn gasemitfin_rv64(String, StringBuilder) -> Unit
pub fn rv64_emit_reset() -> Unit
```

Returns the function's RISC-V assembly text. Module-level emission (functions and
data interleaved in input order, followed by the floating-point constant pool)
is encapsulated in `pipeline.mbt`'s `emit_rv64_module`, called by
`@qbe.compile_rv64` for library users. `gasemitdat_rv64` mirrors C's
`emitdat` and `gasemitfin_rv64` mirrors C's `emitfin`/`elf_emitfin`.

## Output Form

For `export function w $add(w %a, w %b)` generates:

```asm
	.globl add
	.type add, @function
add:
	sd fp, -16(sp)
	sd ra, -8(sp)
	add fp, sp, -16
	add sp, sp, -32
	sd s1, 0(sp)
	sd s2, 8(sp)
	addw a0, a0, a1
	ld s1, 0(sp)
	ld s2, 8(sp)
	add sp, fp, 16
	ld ra, 8(fp)
	ld fp, 0(fp)
	ret
	.size add, .-add
```

Key points:

- **Frame chain layout**: Frame pointer `fp` (= `s0`) and return address `ra` are saved at caller frame top (`-16(sp)` / `-8(sp)`), `fp`/`ra` restoration addressed via frame pointer.
- **Stack alignment**: Stack frames allocated with 16-byte alignment; callee-saved registers (`s1..`/`fs0..`) pushed in prologue, popped in epilogue.
- **Symbols**: `export` functions output `.globl` + `.type`/`.size`; local labels use `.L` prefix.
- **Register names**: Rendered from `types/target_rv64.mbt`'s register name table (`t0..t6`, `a0..a7`, `s0..s11`, `fa0..fa7`, `fs0..fs11`).

## Relationship with Other Output Backends

| | `emit` (amd64) | `emit_wasm` | `emit_rv64` |
| --- | --- | --- | --- |
| Output format | x86-64 GAS | WAT text | RISC-V GAS |
| Stack frame | `pushq %rbp`/`leave` | None (stack machine) | `sd fp`/`ld fp` frame chain |
| Data segment | `gasemitdat` | Module-internal memory/data | `gasemitdat_rv64` |
| Floating-point constants | `.LfpN` rodata stash | Constant instructions | `.LfpN` in `.section .rodata` |

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- Byte-level parity against upstream C QBE: `compare.py --target rv64` compares the
  `-d*` IR/debug dumps, and `tools/check_rv64_asm.py` assembles every emitted
  module with clang's integrated assembler as an independent encodability gate.
- `data` segments (including default `.balign 8`, zero runs emitted to `.bss`) and
  the floating-point constant pool (`.section .rodata`, `.p2align`, `.quad`/`.int`)
  match `vendor/qbe/qbe -t rv64` byte-for-byte; `emit_rv64` supports `-G e`
  (`gasloc=".L"`, `gassym=""`).
