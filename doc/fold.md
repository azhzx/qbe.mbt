# `fold` 包接口介绍

包路径: `azhzx/qbe/fold`

常量折叠。识别操作数均为常量的指令，直接计算出结果并替换为对该常量的引用。对应 QBE 原项目的 `fold.c`。

## 入口

```moonbit
pub fn fold(
  @types.Fn,
  Bool,                  // -dF 调试开关
  @util.Interner,        // 用于生成浮点常数标签
  Array[@types.Typ],
) -> String
```

`fold()` 在 SSA 构造之后、ABI 之前调用：

```moonbit
@ssa.copy(fn_, dbg.c, interner, typs)
@ssa.filluse(fn_)
@util.eprint(@fold.fold(fn_, dbg.f, interner, typs))   // <- 折叠
@util.eprint(@abi.abi(fn_, typs, dbg.a, interner, typs))
```

## 折叠范围

支持的折叠规则（部分列举）：

| 操作 | 折叠规则 |
| --- | --- |
| `Add`/`Sub`/`Mul`/`Div`/`Rem`/`Udiv`/`Urem` | 整数算术，结果取 `Int64` 后包装为 `Con::int` |
| `And`/`Or`/`Xor` | 位运算，按 64 位宽度计算 |
| `Sar`/`Shr`/`Shl` | 移位 |
| `Ceq*`/`Cslt*`/`Cugt*`/... | 比较折叠为 `0`/`1` |
| `Cast` | 整数 ↔ 浮点位重新解释 |
| `Copy` | 直接传播常量 |
| `Extsb`/`Extub`/`Extsh`/... | 符号/零扩展 |

`OpInfo` 中带 `canfold = true` 的操作均会进入折叠路径。

## 调试输出

`Bool = true` 时返回 `-dF` 调试 dump 文本，列出每条被折叠的指令及其替换结果；非调试模式返回空串。

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- 折叠是**保守**的：只要任一操作数不是 `Ref::RCon`，指令保持不变。
- 折叠产生的浮点常量通过 `Interner` 驻留符号名，最终在 emit 阶段以 `.rodata` 段输出。
