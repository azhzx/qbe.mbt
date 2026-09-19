# `emit_rv64` 包接口介绍

包路径: `azhzx/qbe/target_rv64/emit`

RISC-V 64 GAS 汇编输出。在 `isel_rv64` 与 `spill`/`rega` 完成后运行，把已分配
物理寄存器的函数渲染成 RISC-V 汇编文本，对应上游 QBE 的 `rv64/emit.c`。

## 入口

```moonbit
pub fn emit_rv64(
  @types.Fn,          // 已完成寄存器分配的函数
  @util.Interner,     // 字符串驻留器
  String,             // gasloc：局部标签前缀（ELF 为 ".L"）
  String,             // gassym：全局符号前缀（ELF 为 ""）
  Bool,               // 调试开关
  Array[@types.Typ],  // 全局类型表
) -> String

pub fn gasemitdat_rv64(@types.Dat, String, String, StringBuilder) -> Unit
pub fn gasemitfin_rv64(String, StringBuilder) -> Unit
pub fn rv64_emit_reset() -> Unit
```

返回该函数的 RISC-V 汇编文本。模块级发射（函数与 data 按输入顺序交错，末尾
跟随浮点常量池）封装在 `pipeline.mbt` 的 `emit_rv64_module`，对库用户由
`@qbe.compile_rv64` 调用。`gasemitdat_rv64` 对应 C 的 `emitdat`，
`gasemitfin_rv64` 对应 C 的 `emitfin`/`elf_emitfin`。

## 输出形态

对一个 `export function w $add(w %a, w %b)` 生成：

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

要点：

- **帧链布局**：帧指针 `fp`（= `s0`）与返回地址 `ra` 保存在调用者帧顶
  （`-16(sp)` / `-8(sp)`），`fp`/`ra` 恢复经由帧指针寻址。
- **栈对齐**：按 16 字节对齐分配栈帧，被调用者保存寄存器
  （`s1..`/`fs0..`）在序言压栈、尾声弹出。
- **符号**：`export` 函数输出 `.globl` + `.type`/`.size`；局部标签使用
  `.L` 前缀。
- **寄存器名**：由 `types/target_rv64.mbt` 的寄存器名表渲染
  （`t0..t6`、`a0..a7`、`s0..s11`、`fa0..fa7`、`fs0..fs11`）。

## 与其它输出后端的关系

| | `emit` (amd64) | `emit_wasm` | `emit_rv64` |
| --- | --- | --- | --- |
| 输出格式 | x86-64 GAS | WAT 文本 | RISC-V GAS |
| 栈帧 | `pushq %rbp`/`leave` | 无（栈机） | `sd fp`/`ld fp` 帧链 |
| 数据段 | `gasemitdat` | 模块内 memory/data | `gasemitdat_rv64` |
| 浮点常量 | `.LfpN` rodata 暂存 | 常量指令 | `.section .rodata` 中的 `.LfpN` |

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- 与上游 C QBE 的字节级对齐：`compare.py --target rv64` 比较 `-d*`
  IR/调试 dump，`tools/check_rv64_asm.py` 用 clang 集成汇编器对每个发射模块
  做独立可编码性验证。
- `data` 段（默认 `.balign 8`，纯零数据走 `.bss`）与浮点常量池
  （`.section .rodata`、`.p2align`、`.quad`/`.int`）与
  `vendor/qbe/qbe -t rv64` 逐字节一致；`emit_rv64` 支持 `-G e`
  （`gasloc=".L"`、`gassym=""`）。
