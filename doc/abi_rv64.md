# `abi_rv64` 包接口介绍

包路径: `azhzx/qbe/abi_rv64`

RISC-V 64 (rv64) ABI 处理。在指令选择前把抽象的函数参数/返回值引用替换为
RISC-V 调用约定的具体寄存器引用。与 `abi`（amd64 System V）平级，对应上游
QBE 的 `rv64/abi.c`。

## 入口

```moonbit
pub fn abi_rv64(
  @types.Fn,             // 待处理的函数（就地修改）
  Array[@types.Typ],     // 函数局部类型表
  Bool,                  // 调试开关（-dA dump）
  @util.Interner,        // 字符串驻留器
  Array[@types.Typ],     // 全局类型表
) -> String
```

返回 `-dA` 调试文本（`print_dbg == false` 时为空字符串）。

## 调用约定

| 类别 | 寄存器 |
| --- | --- |
| 整数参数 | `A0`–`A7`（`t` 类传参借用 `T0`–`T5`，见下） |
| 浮点参数 | `FA0`–`FA7` |
| 整数返回值 | `A0`、`A1` |
| 浮点返回值 | `FA0`、`FA1` |
| 调用者保存 | `T0`–`T5`、`A0`–`A7`、`FA0`–`FA7`、`FT0`–`FT10` |
| 被调用者保存 | `S1`–`S11`、`FS0`–`FS11` |

寄存器以 tmp id 编号（见 `types/target_rv64.mbt`）：`T0=1..A7=14`，
`S1..S11=15..25`，`FP=26 SP=27 GP=28 TP=29 RA=30`，
`FT0..FA7=31..49`，`FS0..FS11=50..61`，首个非寄存器临时 `Rv64Tmp0=64`。

## 完成的工作

1. **参数降低 (`selpar`)**：把入口块的 `Par` 指令替换为从 `A0..`/`FA0..`
   （超出寄存器的走栈槽 `Salloc`）的 copy；聚合类型经 `rv64_typclass` 判定
   走寄存器还是内存，逐字段搬运（`rv64_ldregs`/`rv64_sttmps`）。
2. **调用降低 (`selcall`)**：把 `Arg` 替换为到参数寄存器/栈槽的 copy；
   超出寄存器数量的参数在栈上预留空间；聚合参数经 `rv64_blit`/
   `rv64_fpstruct` 拆分。
3. **返回值降低**：`Ret` 跳转前把结果 copy 到 `A0`/`A1`/`FA0`/`FA1`；
   大聚合通过隐藏指针返回。
4. **vararg**：`vastart`/`vaarg` 按 RISC-V `va_list` 布局处理寄存器保存区。

## 与其它后端 ABI 的区别

| 特性 | amd64_sysv (`abi`) | wasm (`abi_wasm`) | rv64 (`abi_rv64`) |
|------|--------------------|--------------------|-------------------|
| 整数参数 | RDI,RSI,RDX,RCX,R8,R9 | 函数签名参数 | A0–A7 |
| 浮点参数 | XMM0–XMM7 | 函数签名参数 | FA0–FA7 |
| 返回值 | RAX,RDX / XMM0,XMM1 | 函数签名返回值 | A0,A1 / FA0,FA1 |
| 聚合类型 | 8 字节内拆分进寄存器 | 通过内存指针 | 按字段分类，走寄存器或内存 |
| 可变参数 | 寄存器保存区 | 不支持 | 寄存器保存区 + 栈 |

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- rv64 后端目前没有差分参考验证（上游 C QBE 的 rv64 目标尚未纳入
  `compare.py` 基线），行为以 IL 语义与 RISC-V 调用约定为准。
- `spill`/`rega` 是目标无关的：`abi_rv64` 降级完成后，`pipeline.mbt` 调用
  `@types.init_rv64_target()` 切换全局 `TargetCfg`，后续 `spill`/`rega`
  按 RISC-V 寄存器编号分配。
