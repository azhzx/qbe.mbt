# `emit_arm64` Package API Reference

Package path: `azhzx/qbe/target_arm64/emit`

[中文版本 (Chinese Version)](zh/emit_arm64.md)

ARM64 (AArch64) GAS assembly emission. Ported 1:1 from
`vendor/qbe/arm64/emit.c`; emits bare `xN`/`vN`/`sp` register names,
`[base, offset]` memory operands, indirect `blr` calls and `.L<id>` local
labels.

## Entry Point

```moonbit
pub fn emit_arm64(
  @types.Fn,             // fully lowered function
  @util.Interner,        // string interner
  Array[@types.Typ],     // type table
) -> String

pub fn arm64_emit_reset() -> Unit
```

Data sections and the float constant pool are emitted by the shared
`emit.gasemitdat` / `emit.gasemitfin` (the reference uses the same `gas.c`
for every target); `emit_arm64_module` (in `pipeline.mbt`) interleaves them
with functions.

## Highlights

- **Frame layout**: `framelayout` packs spill slots and callee-save register
  pairs; the prologue uses `stp x29, x30` plus `str`/`ldp` for saved
  registers, with the variadic register save area (`str q0..q7`, `str
  x0..x7`) emitted up front.
- **Constant materialisation**: `loadcon` uses `mov`/`movk` chains with
  `arm64_logimm`, and `adrp`/`add #:lo12:` for symbol addresses (local `.L`
  labels for the float pool).
- **Branches**: fall-through elimination for `Jjmp`; conditional branches use
  the reference's single-column condition table with `cmpneg`.
- **Unsupported inputs** (dynamic `alloc`, `truncd`, unsigned float
  conversions) raise an ICE so the CLI writes nothing to stdout, matching the
  reference snapshot's failure.

## Notes

- Validated byte-for-byte against `vendor/qbe/qbe -t arm64` for both the
  ELF (`-G e`) and Mach-O (`-G m`, `-t arm64_apple`) flavors (408/408 each):
  labels, `sym@page`/`@pageoff`, `.balign 4`, `_` prefixes, Mach-O literal
  sections, the Apple ABI (4-byte stack slots for non-wide scalars,
  `apple_selvastart`/`apple_selvaarg`) and no ELF directives. The reference's
  `apple_extsb` pre-pass is a no-op here because this port has no narrow
  `parsb..paruh`/`argsb..arguh` forms.
- An independent assemblability gate is available at
  `tools/check_arm64_asm.py` (clang aarch64 integrated assembler).
