# `isel_la64` 包接口介绍

包路径: `azhzx/qbe/isel_la64`

LoongArch 64 (la64) 指令选择。对应上游假设的 `loongarch64/isel.c`：检查
常量、物化立即数、暴露机器寄存器约束、为快速分配（fast alloc）指派栈槽。

## 入口

```moonbit
pub fn isel_la64(
  @types.Fn,             // 待处理的函数（就地修改）
  @util.Interner,        // 字符串驻留器
  Bool,                  // 调试开关（-dI dump）
  Array[@types.Typ],     // 全局类型表
) -> String raise
```

## 与 rv64 移植的差异

驱动采用 amd64 的正确模式：块内指令**逆序**处理、选择缓冲经
`emit_block` 反转后**写回**块。rv64 移植曾丢弃缓冲（isel 实际未生效），
la64 从一开始就实现了写回。

- **比较降低**：LoongArch 无 flags 寄存器，20 个整数比较全部降低为
  `slt`/`sltu` + `xor`/`copy` 序列（word 比较统一为 long 形式——QBE 保持
  `Kw` 值符号扩展，64 位比较等价）。
- **常量物化**：除 `Copy` 外所有操作数中的整型常量物化进寄存器
  （LoongArch ALU/比较指令无立即数形式）；浮点常量进 `fp_stash` 并立即
  `fld` 到 FPR。
- **聚合体分配**：`Alloc4/8/16` 的常量尺寸版本转栈槽，动态版本生成
  `salloc` + 对齐序列。

## Notes

无上游 C 参考实现，无差分基线；行为由 `isel_la64_wbtest.mbt` 的降低序列
断言与 e2e 快照保证。
