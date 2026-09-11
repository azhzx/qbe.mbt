# `abi` 包接口介绍

包路径: `azhzx/qbe/abi`

ABI (Application Binary Interface) 处理。在指令选择前把抽象的函数参数/返回值引用替换为具体平台的寄存器/栈槽引用。当前实现针对 **amd64_sysv** ABI（System V AMD64 调用约定）。对应 QBE 原项目的 `abi.c` + 目标特定 `amd64/sysv.c`。

## 入口

```moonbit
pub fn abi(
  @types.Fn,
  Array[@types.Typ],     // 全局类型表
  Bool,                  // -dA 调试开关
  @util.Interner,        // 字符串驻留器（生成符号标签）
  Array[@types.Typ],     // typs 副本（兼容 main.c 调用约定）
) -> String
```

`abi()` 完成以下工作：

1. **参数传递**：把 `Arg`/`Par`/`Argc`/`Arge`/`Parc`/`Pare` 指令替换为 `copy` 到/自具体寄存器；超出寄存器数的参数溢出到栈槽。
2. **返回值**：根据返回类型 (`ret_ty`) 决定通过寄存器 (RAX/RDX/XMM0) 还是内存返回，替换 `Ret*` 跳转的 `arg` 为具体引用。
3. **可变参数 (`is_vararg`)**：为 `vastart`/`vaarg` 准备寄存器保存区。
4. **聚合类型**：按 System V 规则对超过 16 字节的结构参数走内存传递。

返回值约定同 `ssa.copy`/`ssa.loadopt`：调试模式返回 dump 文本，非调试模式返回空串。

## 寄存器掩码辅助

```moonbit
pub fn argregs(@types.Ref) -> (UInt64, Int, Int)   // 参数寄存器掩码
pub fn retregs(@types.Ref) -> (UInt64, Int, Int)   // 返回寄存器掩码
```

返回三元组 `(mask, n_int_regs, n_fp_regs)`，用于寄存器分配阶段计算活跃约束。

## 寄存器列表

```moonbit
pub let rsave : Array[Int]    // callee-saved 寄存器列表
pub let rclob : Array[Int]    // caller-saved (被调用方可能破坏的) 寄存器
```

这些列表与 `types` 包中的同名字段共享同一份数据（amd64_sysv 的具体配置）。

## 典型调用

```moonbit
@util.eprint(@abi.abi(fn_, typs, dbg.a, interner, typs))
@cfg.fillpreds(fn_)      // ABI 改写了 CFG，需重算
@ssa.filluse(fn_)        // 也需重算使用链
```

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- `abi` 是从抽象 SSA 到平台相关 SSA 的**关键转换点**。在该函数返回前，所有引用都是抽象的 `RTmp`/`RCon`；返回后，参数/返回值相关指令变成对 `RSlot`/具体 `RTmp` 的 `copy`。
- 目前仅支持 `amd64_sysv`。未来 wasm/arm64 等目标需在 `abi/` 下新增对应实现，并保留同一入口签名。
