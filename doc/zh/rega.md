# `rega` 包接口介绍

包路径: `azhzx/qbe/rega`

寄存器分配 (Register Allocation)。在 spill 之后，把每个虚拟临时变量绑定到具体的物理寄存器。对应 QBE 原项目的 `rega.c`。

## 入口

```moonbit
pub fn rega(
  @types.Fn,
  Bool,                  // -dR 调试开关
  @util.Interner,
  Array[@types.Typ],
) -> String
```

`rega` 完成以下工作：

1. **图染色**：基于 `live` 包计算的活跃集合，构建干涉图（同时活跃的临时变量之间有边）。
2. **优先级排序**：按 `cost`（spill 阶段已算好）与 `hint`（寄存器提示，比如返回值倾向 RAX）排序。
3. **寄存器选择**：贪心选色（最先可用的非冲突寄存器），更新每个 `Tmp` 的 `slot` 字段为物理寄存器编号。
4. **`copy` 插入**：块边界处若两边的临时变量被分到不同寄存器，插入 `copy` 指令在块边界同步。
5. **`Fn.reg` 掩掩码**：把所有用到的寄存器累计到 `Fn.reg` 掩码，供 emit 阶段决定保存哪些 callee-saved 寄存器。

返回 `-dR` 调试文本：每个临时变量与其最终寄存器的映射。

## 典型调用

```moonbit
@util.eprint(@spill.spill(fn_, dbg.s, interner, typs))
@util.eprint(@rega.rega(fn_, dbg.r, interner, typs))
@cfg.fillrpo(fn_)        // rega 可能新增块边界 copy，重算
@cfg.simpljmp(fn_)       // 简化跳转
@cfg.fillrpo(fn_)
@cfg.fillpreds(fn_)
```

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- `rega` 的输出已经不再是"虚拟" SSA：每个 `Tmp` 都有了具体的物理寄存器（或 `RSlot` 表示已溢出）。
- 实际寄存器编号遵循 `types` 包中的 `RAX=1`...`RSP=16`, `XMM0=17`...`XMM15=32`。
- 如果 `rega` 仍无法分配（spill 不够激进），会抛 `Ice` 提示内部错误。
