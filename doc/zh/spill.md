# `spill` 包接口介绍

包路径: `azhzx/qbe/spill`

寄存器溢出 (Spill)。当寄存器压力过大时，选择一些临时变量溢出到栈槽，在需要时再加载回寄存器。包含溢出代价估算与实际溢出两步。对应 QBE 原项目的 `spill.c`。

## 1. 代价估算 - `fillcost`

```moonbit
pub fn fillcost(
  @types.Fn,
  Bool,                  // -dS 调试开关
) -> String
```

为每个 `Tmp` 计算并写入 `cost` 字段：

- **使用代价**：每条使用点代价 +1，定义点代价 -1（粗略）；
- **循环加权**：在循环内的代价按 `10^loop_depth` 放大；
- **寄存器类**：分别对 `Kw`/`Kl`（word）与 `Ks`/`Kd`（double）通道计算，对应寄存器数 `NGPS`/`NFPS`。

`cost` 越高的临时变量越值得留在寄存器里，反之越值得溢出。返回值为 `-dS` 调试文本。

## 2. 溢出 - `spill`

```moonbit
pub fn spill(
  @types.Fn,
  Bool,                  // -dS 调试开关
  @util.Interner,
  Array[@types.Typ],
) -> String
```

`spill` 完成以下工作：

1. 检查每个基本块边界的活跃数 (`nlive_w`/`nlive_d`) 是否超过可用寄存器数 (`NGPS=9`/`NFPS=15`)；
2. 若超过，在对应位置插入 `copy` 到/从新的栈槽（`RSlot`）；
3. 被溢出的临时变量在原使用点之前 `load`，在原定义点之后 `store`；
4. 重算活跃集合，迭代到收敛。

如果一次溢出仍未满足，会继续迭代（最坏情况溢出所有非循环不变量）。

## 典型调用

```moonbit
@util.eprint(@live.filllive(fn_, dbg.l))      // 必须先算活跃
@util.eprint(@spill.fillcost(fn_, dbg.s))     // 估算代价
@util.eprint(@spill.spill(fn_, dbg.s, interner, typs))  // 执行溢出
@util.eprint(@rega.rega(fn_, dbg.r, interner, typs))    // 再寄存器分配
```

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- `spill` 是一个**迭代**过程：每次插入溢出代码都会改变活跃集合，需要 `live.filllive` 重新分析。
- 溢出使用的栈槽数通过 `Fn.slot` 累加，最终影响栈帧大小，由 `emit` 阶段写入函数序言。
- 在 QBE 原项目中，spill 算法由 Pan, Andersson 等的线性扫描思路启发，但简化为基于代价的局部选择。
