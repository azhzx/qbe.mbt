# `emit` 包接口介绍

包路径: `azhzx/qbe/emit`

汇编输出。在寄存器分配之后，把 `Fn` 渲染为目标平台的 GAS 汇编（GNU Assembler 语法）。对应 QBE 原项目的 `amd64/emit.c` + `gas.c`。

## 函数输出

```moonbit
pub fn emitfn(
  @types.Fn,
  @util.Interner,
  String,                // gasloc - 全局局部标签前缀 (".L" 或 "L")
  String,                // gassym - 全局符号前缀 ("" 或 "_")
  StringBuilder,         // 累积输出
) -> Unit
```

`emitfn` 输出单个函数的完整汇编，包括：

1. **序言** (prologue)：分配栈帧 (`sub $size, %rsp`)、保存 callee-saved 寄存器（由 `Fn.reg` 决定）、若是 vararg 设置寄存器保存区；
2. **指令序列**：每个基本块的指令按 RPO 顺序输出，包括标签 (`<gasloc><name>:`)、操作数替换为寄存器名或内存引用；
3. **跳转**：`jmp`/`jnz` 转为 `.L<blockname>`，条件跳转转为 `je`/`jl`/...；
4. **尾声** (epilogue)：恢复 callee-saved、回收栈帧、`ret` 指令；
5. **注释**：末尾写 `/* end function <name> */` 便于调试。

`gasloc` 与 `gassym` 控制 GAS 风格：
- Linux 默认：`gasloc = ".L"`, `gassym = ""`
- macOS (osx)：`gasloc = "L"`, `gassym = "_"`（前导下划线）

## 数据段输出

```moonbit
pub fn gasemitdat(
  @types.Dat,            // 单个数据项
  String,                // gasloc
  String,                // gassym
  StringBuilder,
) -> Unit
```

把一条 `Dat` 输出为汇编：`.data` / `.text` 段切换、`.align`、`.long`/`.quad`/`.byte` 等。配合 `DStart`/`DEnd`/`DName` 起止一组数据定义。

## 段收尾

```moonbit
pub fn gasemitfin(
  String,                // gasloc
  StringBuilder,
) -> Unit
```

在所有函数与数据段输出之后调用，输出 `.section .note.GNU-stack,"",@progbits` 等结尾元信息，避免链接器警告不可执行栈。

## 典型调用

```moonbit
let sb = StringBuilder::new()
for item in order {
  if item == "f" {
    run_passes(fn_, interner, typs, dbg)
    @emit.emitfn(fn_, interner, gasloc, gassym, sb)
    sb.write_string("/* end function \{fn_.name} */\n\n")
  } else {
    while di < datas.length() {
      let d = datas[di]
      di = di + 1
      @emit.gasemitdat(d, gasloc, gassym, sb)
      if d.kind == @types.DEnd {
        sb.write_string("/* end data */\n\n")
        break
      }
    }
  }
}
@emit.gasemitfin(gasloc, sb)
let asm = sb.to_string()
```

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- `emit` 是**只读**阶段：不修改 `Fn` 的任何字段，只把内容渲染为字符串。
- 生成的汇编用 GAS 语法，可以用 `gcc`/`clang` 直接汇编链接：`gcc -o out out.s`。
