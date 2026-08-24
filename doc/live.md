# `live` 包接口介绍

包路径: `azhzx/qbe/live`

活跃变量分析 (Liveness Analysis)。在 SSA 函数上计算每个基本块的 in/out 活跃集合，并把活跃数信息写回 `Blk` 的 `nlive_w`/`nlive_d` 字段。对应 QBE 原项目的 `live.c`。

## 入口

```moonbit
pub fn filllive(
  @types.Fn,
  Bool,                  // -dL 调试开关
) -> String
```

`filllive` 完成以下工作：

1. 为每个基本块分配 `gen_set`/`in_set`/`out_set`（`BSet?`）；
2. 按 RPO 反向迭代到不动点，传播活跃集合；
3. 在每个块边界处统计 word 与 double 活跃数，写入 `nlive_w`/`nlive_d`（用于后续寄存器压力估计）。

返回值约定同其它阶段：调试模式返回 dump 文本（每个块的活跃临时变量列表），非调试模式返回空串。

## 辅助

```moonbit
pub fn liveon(
  @types.BSet,           // 目标块的 in 集合
  Int,                   // 当前临时变量 id (开始位置)
  @types.Blk,            // 目标块
  @types.Fn,
) -> Unit
```

`liveon` 把指定集合中所有活跃临时变量标记到目标块上，并累加 `nlive_w`/`nlive_d`。在 SSA 构造、寄存器分配等阶段内部使用。

## 典型调用

`filllive` 在编译流程中被调用**多次**：

```moonbit
// 1. SSA 构造前 (预 ABI 活跃分析，C ssa() 设置 -dL=false)
@util.eprint(@live.filllive(fn_, false))

// 2. 指令选择后
@cfg.fillrpo(fn_)
@util.eprint(@live.filllive(fn_, dbg.l))

// 3. 寄存器分配前的最终活跃分析 (在 spill/rega 内部也会调用)
```

## 依赖

- `azhzx/qbe/types`

## 备注

- 活跃分析基于**反向数据流**：从出口向上传播。
- `gen_set` 一旦首次构建就保留，后续调用只重新计算 in/out；这是 QBE 的优化策略，避免每次重做完整工作。
- `nlive_*` 字段决定 spill 阶段的代价评估（活跃越多越可能溢出）。
