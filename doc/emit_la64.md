# `emit_la64` Package API Reference

Package path: `azhzx/qbe/target_la64/emit`

[中文版本 (Chinese Version)](zh/emit_la64.md)

LoongArch 64 (la64) GAS assembly emission. GNU-as LoongArch syntax:
destination first, `$`-prefixed ABI register names (`$a0`, `$ft15`, ...),
memory operands written as `$base, si12`.

## Entry Point

```moonbit
pub fn emit_la64(
  @types.Fn,             // fully lowered function
  @util.Interner,        // string interner
  String,                // local label prefix (gasloc: ".L" / "L")
  String,                // symbol prefix (gassym: "" / "_")
  Array[@types.Typ],
) -> String

pub fn gasemitdat_la64(@types.Dat, String, String, StringBuilder) -> Unit

pub fn gasemitfin_la64(String, StringBuilder) -> Unit
```

`emit_la64_module` (in `pipeline.mbt`) interleaves functions and data
sections following `order`, then calls `gasemitfin_la64` for the float
constant pool.

## Highlights

- **Prologue/epilogue**: `$fp/$ra` frame chain (same frame math as the rv64
  port); variadic functions reserve a 64-byte register save area
  (`LA_A0`-`LA_A7`).
- **Branches**: `Jjnz` has three fall-through shapes - false target next:
  `bnez` + fall through; true target next: `beqz` + fall through; otherwise
  `beqz` + `b`. Semantics are pinned by snapshots on both la64 and rv64
  (fixing the inverted-condition defect inherited from the rv64 port).
- **Addresses**: symbol addresses use `la.local` (the analogue of rv64's
  `lla`: local PC-relative; cross-object references rely on the linker);
  slot offsets beyond a 12-bit immediate go through `$t8`.
- **Data sections**: portable ELF spellings - `.balign` (LoongArch gas
  treats `.align` as a power of two), `.byte/.half/.word/.quad`, `.fill`.
- **Float constant pool**: `fp_stash` emitted as `.balign` + `.word`
  sequences with a value comment (`/* 2.500000 */`). rv64 now emits the pool
  too (as `.section .rodata` + `.p2align` + `.quad`/`.int`).
