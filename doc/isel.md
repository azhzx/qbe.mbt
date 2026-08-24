# `isel` 包接口介绍

包路径: `azhzx/qbe/isel`

指令选择 (Instruction Selection)。在 ABI 处理之后，把抽象的 SSA 指令模式替换为 amd64 上更高效的具体指令。对应 QBE 原项目的 `amd64/isel.c`、`amd64/addr.c`、`amd64/cmp.c`、`amd64/sel.c`。

## 入口

```moonbit
pub fn isel(
  @types.Fn,
  @util.Interner,
  Bool,                  // -dI 调试开关
  Array[@types.Typ],     // 全局类型表
) -> String
```

`isel()` 完成以下工作（仅列举主要项）：

1. **立即数优化**：把形如 `%r = add %x, c`（c 为常量）的指令转为 amd64 的立即数形式（避免占用一个寄存器）。对应 `_test/isel/001_imm_add_*.ssa` 等回归测试。
2. **地址模式**：把 `add` 链组合为 `[base + index*scale + offset]` 寻址，直接喂给 load/store。对应 `addr.mbt`。
3. **除法常量魔法数**：把 `div`/`rem`（特别是常量除数）转换为乘以魔法数 + 移位的形式，避免除法指令。对应 `001_div_c_w_7` 等用例。
4. **比较模式**：把 `ceq`/`cslt` 等比较 + `jnz` 模式转为 amd64 条件跳转（`je`/`jl`/...）。对应 `cmp.mbt`。
5. **比较结果归一**：把比较指令的输出宽度规整为 1 字节。
6. **`alloc*` 处理**：栈分配转换为对 `slot` 的引用。

返回值约定同 `ssa.copy`/`abi.abi`：调试模式 (`Bool = true`) 返回 dump 文本，非调试模式返回空串。

## 内部模块

文件 [isel/addr.mbt](../isel/addr.mbt) 实现地址模式识别；
文件 [isel/cmp.mbt](../isel/cmp.mbt) 实现比较 + 跳转模式识别；
文件 [isel/sel.mbt](../isel/sel.mbt) 实现主要选择逻辑；
文件 [isel/isel.mbt](../isel/isel.mbt) 为入口。

## 典型调用

```moonbit
@util.eprint(@isel.isel(fn_, interner, dbg.i, typs))
@cfg.fillrpo(fn_)       // 指令选择后基本块结构可能变化
```

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- `isel` 只做"语义保持的强度提升"，不改变指令的控制流结构。控制流的进一步简化由后续 `cfg.simpljmp` 完成。
- 目前仅支持 amd64_sysv。其它目标的 isel 应放在 `isel/<target>/` 下。
