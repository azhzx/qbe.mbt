# `emit_arm64` 包接口介绍

包路径: `azhzx/qbe/target_arm64/emit`

ARM64 (AArch64) GAS 汇编写出。逐行移植自 `vendor/qbe/arm64/emit.c`；输出
裸 `xN`/`vN`/`sp` 寄存器名、`[base, offset]` 内存操作数、间接 `blr` 调用
以及 `.L<id>` 本地标签。

## 入口

```moonbit
pub fn emit_arm64(
  @types.Fn,             // 已完成全部 pass 的函数
  @util.Interner,        // 符号名驻留器
  Array[@types.Typ],     // 类型表
) -> String

pub fn arm64_emit_reset() -> Unit
```

数据段与浮点常量池复用共享的 `emit.gasemitdat` / `emit.gasemitfin`
（参考对所有目标使用同一份 `gas.c`）；`emit_arm64_module`（`pipeline.mbt`）
按输入顺序把它们与函数交错输出。

## 要点

- **帧布局**：`framelayout` 打包溢出槽与被调用者保存寄存器对；序言用
  `stp x29, x30` 与 `str`/`ldp` 保存/恢复寄存器，变参寄存器保存区
  （`str q0..q7`、`str x0..x7`）在函数开头输出。
- **常量物化**：`loadcon` 用 `mov`/`movk` 链配合 `arm64_logimm`；符号地址用
  `adrp`/`add #:lo12:`（浮点池的本地标签加 `.L` 前缀）。
- **分支**：`Jjmp` 落穿消除；条件分支使用参考的单列条件表 + `cmpneg`。
- **不支持的输入**（动态 `alloc`、`truncd`、无符号浮点转换）抛出 ICE，使
  CLI 不向 stdout 写任何内容，与参考快照的失败行为一致。

## 说明

- 通过 `vendor/qbe/qbe -t arm64` 对 ELF（`-G e`）与 Mach-O（`-G m`，
  `-t arm64_apple`）两种风格均逐字节验证（各 406/406）：标签、
  `sym@page`/`@pageoff`、`.balign 4`、`_` 前缀、Mach-O 字面量段、
  Apple ABI（非宽标量占 4 字节栈槽、`apple_selvastart`/`apple_selvaarg`）、
  且不输出 ELF 指令。参考的 `apple_extsb` 预处理在本移植中是空操作，因为
  本移植没有窄参数 `parsb..paruh`/`argsb..arguh` 形式。
- 独立的可汇编性校验脚本：`tools/check_arm64_asm.py`（clang aarch64 集成
  汇编器）。
