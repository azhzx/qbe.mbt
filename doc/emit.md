# `emit` Package API Reference

Package path: `azhzx/qbe/target_amd64/emit`

Assembly Output. After register allocation, renders `Fn` to the target platform's GAS assembly (GNU Assembler syntax). Corresponds to `amd64/emit.c` + `gas.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/emit.md)

## Function Output

```moonbit
pub fn emitfn(
  @types.Fn,
  @util.Interner,
  String,                // gasloc - global local label prefix (".L" or "L")
  String,                // gassym - global symbol prefix ("" or "_")
  StringBuilder,         // accumulated output
) -> Unit
```

`emitfn` outputs a single function's complete assembly, including:

1. **Prologue**: Stack frame allocation (`sub $size, %rsp`), saving callee-saved registers (determined by `Fn.reg`), setting up register save area if vararg;
2. **Instruction sequence**: Each basic block's instructions output in RPO order, including labels (`<gasloc><name>:`), operands replaced with register names or memory references;
3. **Jumps**: `jmp`/`jnz` converted to `.L<blockname>`, conditional jumps to `je`/`jl`/...;
4. **Epilogue**: Restoring callee-saved, reclaiming stack frame, `ret` instruction;
5. **Comments**: `/* end function <name> */` at the end for debugging.

`gasloc` and `gassym` control GAS style:
- Linux default: `gasloc = ".L"`, `gassym = ""`
- macOS (osx): `gasloc = "L"`, `gassym = "_"` (leading underscore)

## Data Segment Output

```moonbit
pub fn gasemitdat(
  @types.Dat,            // single data item
  String,                // gasloc
  String,                // gassym
  StringBuilder,
) -> Unit
```

Outputs a `Dat` item as assembly: `.data` / `.text` segment switching, `.align`, `.long`/`.quad`/`.byte`, etc. Used with `DStart`/`DEnd`/`DName` to delimit a group of data definitions.

## Segment Finalization

```moonbit
pub fn gasemitfin(
  String,                // gasloc
  StringBuilder,
) -> Unit
```

Called after all functions and data segments are output, outputs `.section .note.GNU-stack,"",@progbits` and other ending metadata to avoid linker warnings about non-executable stack.

## Typical Calls

```moonbit
let sb = StringBuilder::StringBuilder()
for item in order {
  if item == "f" {
    run_passes(fn_, interner, typs, dbg)
    @emit_amd64.emitfn(fn_, interner, gasloc, gassym, sb)
    sb.write_string("/* end function \{fn_.name} */\n\n")
  } else {
    while di < datas.length() {
      let d = datas[di]
      di = di + 1
      @emit_amd64.gasemitdat(d, gasloc, gassym, sb)
      if d.kind == @types.DEnd {
        sb.write_string("/* end data */\n\n")
        break
      }
    }
  }
}
@emit_amd64.gasemitfin(gasloc, sb)
let asm = sb.to_string()
```

## Dependencies

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## Notes

- `emit` is a **read-only** phase: it does not modify any fields of `Fn`, only renders content to strings.
- Generated assembly uses GAS syntax and can be assembled and linked directly with `gcc`/`clang`: `gcc -o out out.s`.
