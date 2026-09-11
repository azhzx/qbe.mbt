# `emit_rv64` 包接口介绍

包路径: `azhzx/qbe/emit_rv64`

RISC-V 64 GAS 汇编输出。在 `isel_rv64` 与 `spill`/`rega` 完成后运行，把已分配
物理寄存器的函数渲染成 RISC-V 汇编文本，对应上游 QBE 的 `rv64/emit.c`。

## 入口

```moonbit
pub fn emit_rv64(
  @types.Fn,          // 已完成寄存器分配的函数
  @util.Interner,     // 字符串驻留器
  Bool,               // 调试开关
  Array[@types.Typ],  // 全局类型表
) -> String
```

返回该函数的 RISC-V 汇编文本。模块级的发射（函数按输入顺序拼接）封装在
`pipeline.mbt` 的 `emit_rv64_module`，对库用户由 `@qbe.compile_rv64` 调用。

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
| 数据段 | `gasemitdat` | 模块内 memory/data | 暂未输出（待完善） |
| 浮点常量 | `.LfpN` rodata 暂存 | 常量指令 | 暂未输出（待完善） |

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- rv64 后端目前没有差分参考验证（上游 C QBE 的 rv64 目标尚未纳入
  `compare.py` 基线），输出格式以 RISC-V psABI 与 GAS 语法为准。
- `data` 段与浮点字面量的 rodata 输出尚未实现，`emit_rv64_module`
  当前只发射函数部分。
