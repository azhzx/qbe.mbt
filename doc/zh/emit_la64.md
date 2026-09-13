# `emit_la64` 包接口介绍

包路径: `azhzx/qbe/emit_la64`

LoongArch 64 (la64) GAS 汇编发射。GNU as LoongArch 语法：目的操作数在前、
寄存器用 `$` 前缀的 ABI 名（`$a0`、`$ft15`…）、内存操作数为 `$base, si12`。

## 入口

```moonbit
pub fn emit_la64(
  @types.Fn,             // 已完成全部 pass 的函数
  @util.Interner,        // 符号名驻留器
  String,                // 本地标签前缀（gasloc：".L" / "L"）
  String,                // 符号前缀（gassym："" / "_"）
  Array[@types.Typ],
) -> String

pub fn gasemitdat_la64(@types.Dat, String, String, StringBuilder) -> Unit

pub fn gasemitfin_la64(String, StringBuilder) -> Unit
```

`emit_la64_module`（`pipeline.mbt`）按 `order` 交错发射函数与数据段，最后
调用 `gasemitfin_la64` 输出浮点常量池。

## 要点

- **序言/尾声**：`$fp/$ra` 栈帧链（与 rv64 移植相同的帧布局数学）；变参
  函数预留 64 字节寄存器保存区（`LA_A0`–`LA_A7`）。
- **分支**：`Jjnz` 三种 fall-through 形态——假目标为下一块时 `bnez` + 直落；
  真目标为下一块时 `beqz` + 直落；否则 `beqz` + `b`。语义在 la64/rv64 均
  经快照验证（修复了 rv64 移植的条件反转缺陷）。
- **地址**：符号地址统一 `la.local`（与 rv64 的 `lla` 同为本地 PC 相对，
  跨目标文件引用需链接器配合）；槽位偏移超出 12 位立即数时经 `$t8` 中转。
- **数据段**：便携 ELF 指令拼写——`.balign`（LoongArch gas 的 `.align`
  是 2 的幂语义）、`.byte/.half/.word/.quad`、`.fill`。
- **浮点常量池**：`fp_stash` 以 `.balign` + `.word` 序列输出，并附注释值
  （`/* 2.500000 */`）。rv64 尚未输出常量池，la64 为首个完整支持。
