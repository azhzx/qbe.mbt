# `abi_arm64` 包接口介绍

包路径: `azhzx/qbe/target_arm64/abi`

ARM64 (AArch64) AAPCS64 ABI 降级（ELF 风格）。在指令选择之前，把抽象的
参数/返回值引用替换为具体的调用约定寄存器。逐行移植自
`vendor/qbe/arm64/abi.c`。

## 入口

```moonbit
pub fn abi_arm64(
  @types.Fn,             // 要降级的函数（原地修改）
  Array[@types.Typ],     // 函数局部类型表
  Bool,                  // 调试开关（-dA dump）
  @util.Interner,        // 符号名驻留器
  Array[@types.Typ],     // 全局类型表
) -> String
```

## 调用约定（AAPCS64）

| 类别 | 寄存器 |
| --- | --- |
| 整型参数 | `ARM64_R0`–`ARM64_R7`（x0-x7） |
| 浮点参数 | `ARM64_V0`–`ARM64_V7`（v0-v7） |
| 整型返回 | `ARM64_R0`、`ARM64_R1` |
| 浮点返回 | `ARM64_V0`–`ARM64_V3` |
| 隐藏结果指针 | `ARM64_R8`（x8） |
| 调用者保存 | x0-x18（`NGPS=19`）、v0-v7 与 v16-v30（`NFPS=23`） |
| 被调用者保存 | x19-x28、v8-v15（`NCLR=18`） |
| 全局活跃 | `ARM64_FP`(x29)、`ARM64_SP`、`ARM64_R18`（`NRGLOB=3`） |

寄存器编号为 tmp id（见 `types/target_arm64.mbt`，QBE 式重编号）：
`R0=1..IP1=18 R18=19..SP=32`、`V0=33..V30=63`，首个非寄存器临时量
`Arm64Tmp0=64`。

聚合分类（`typclass`）：最多 4 个 `s`/`d` 成员的齐次浮点聚合（HFA）依次进
浮点寄存器；其余不超过 16 字节的聚合按 8 字节块进通用寄存器；dark/超大/空
值以指针（`Cptr`）替代，并经栈 blob 拷贝（`blit`/`Oblit`）。

## 说明

- 字节级裁判为 `vendor/qbe/qbe -t arm64`；IR dump（5684/5684）与 ELF
  汇编（406/406，`-G e`）均逐字节一致；Mach-O（`-G m`，参考中为
  `-t arm64_apple`）同样逐字节一致：已实现非宽标量 4 字节栈槽与 Apple 变参
  处理（`apple_selvastart`/`apple_selvaarg`）；`apple_extsb` 在本移植中
  不需要，因为没有窄参数 `parsb..paruh`/`argsb..arguh` 形式。
- 本移植没有窄参数 `parsb..paruh`/`argsb..arguh` 形式。
- 聚合 `Cptr` 拷贝展开为显式的 `blt.` 前缀存取块（即参考快照的 `blit`），
  因为本移植早于 `Oblit0`/`Oblit1`。
