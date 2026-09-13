# `isel_arm64` 包接口介绍

包路径: `azhzx/qbe/isel_arm64`

ARM64 (AArch64) 指令选择。逐行移植自 `tools/qbe-ref/arm64/isel.c`。把抽象
操作转换为 arm64 机器操作，并为快速分配分配栈槽。

## 入口

```moonbit
pub fn isel_arm64(
  @types.Fn,             // ABI 已降级的函数
  @util.Interner,        // 符号名驻留器
  Bool,                  // 调试开关（-dI dump）
  Array[@types.Typ],     // 类型表
) -> String
```

## 要点

- **快速分配**：常量大小的 `alloc4`/`alloc8`/`alloc16` 折叠为栈槽
  （`fn.slot`），与参考的 `NAlign == 3` 布局一致。
- **常量物化**（`fixarg`）：整型常量生成 `copy`；浮点常量进入只读池
  （`gasstash`）并通过 `.LfpN` 地址加载，对应参考的
  `/* floating point constants */` 段。
- **比较**：`selcmp` 折叠 12 位 `cmp`/`cmn` 立即数并交换常量左操作数；
  `seljmp` 把仅用于分支的比较合并为 `Jjf` 条件跳转（`acmp`/`afcmp` +
  `cset`/flags）。
- **无 `callable()` 快捷路径**：与参考快照一致，调用目标按普通操作数物化
  （间接 `blr`）。

## 说明

- 参考快照的 `Iplo24`/`Inlo24` 分类不影响结果（24 位立即数走物化路径），
  移植保持一致。
- 通过 `tools/qbe-ref -t arm64`（`-dI` dump）逐字节验证。
