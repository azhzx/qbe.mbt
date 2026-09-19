# `abi_la64` 包接口介绍

包路径: `azhzx/qbe/abi_la64`

LoongArch 64 (la64) LP64D ABI 处理。在指令选择前把抽象的函数参数/返回值引
用替换为 LoongArch 调用约定的具体寄存器引用。与 `abi_rv64` 平级，结构完全
镜像（LP64D 的参数分类规则与 RISC-V lp64d 在寄存器层面一致）。

## 入口

```moonbit
pub fn abi_la64(
  @types.Fn,             // 待处理的函数（就地修改）
  Array[@types.Typ],     // 函数局部类型表
  Bool,                  // 调试开关（-dA dump）
  @util.Interner,        // 字符串驻留器
  Array[@types.Typ],     // 全局类型表
) -> String
```

## 调用约定（LP64D）

| 类别 | 寄存器 |
| --- | --- |
| 整数参数 | `LA_A0`–`LA_A7` |
| 浮点参数 | `LA_FA0`–`LA_FA7` |
| 整数返回值 | `LA_A0`、`LA_A1` |
| 浮点返回值 | `LA_FA0`、`LA_FA1` |
| 调用者保存 | `LA_T0`–`LA_T7`、`LA_A0`–`LA_A7`、`LA_FA0`–`LA_FA7`、`LA_FT0`–`LA_FT15` |
| 被调用者保存 | `LA_S0`–`LA_S8`、`LA_FS0`–`LA_FS7` |
| 全局活跃 | `LA_FP`、`LA_SP`、`LA_TP`、`LA_RA` |

寄存器以 tmp id 编号（见 `types/target_la64.mbt`，QBE 风格重编号）：
`LA_T0=1..LA_A7=16`，`LA_S0..S8=17..25`，`LA_FP=26 SP=27 TP=28 RA=29`，
`LA_T8=30`（发射器 scratch / env），`LA_FT0..FT15=32..47`，
`LA_FA0..FA7=48..55`，`LA_FS0..FS7=56..63`，首个非寄存器临时 `La64Tmp0=64`。

聚合体：≤16 字节按成员分类（全整 → GPR、全浮 → FPR、混合 → 各一），
与 rv64 移植的约定一致；对齐 >16 字节的聚合体按引用（`Cptr`）。

## Notes

- LoongArch64 无上游 C QBE 参考实现（`vendor/qbe` 只有 amd64/arm64），
  无差分基线；正确性由单测 + e2e 快照（`qbe_la64_snapshot_test.mbt`）保证，
  快照逐条对照 LoongArch ELF psABI 与 GNU as 语法手工核验。
- `selcall` 在发射 `Call` 时把返回值寄存器计数编码进 cty 的低 4 位——
  spill/rega 据此判定调用定义的寄存器，避免把返回值驱逐到被调用者保存
  寄存器（修复自 rv64 移植的同源缺陷，见 `doc/abi_rv64.md`）。
