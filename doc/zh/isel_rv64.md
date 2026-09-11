# `isel_rv64` 包接口介绍

包路径: `azhzx/qbe/isel_rv64`

RISC-V 64 指令选择。在 `abi_rv64` 降级之后运行，把通用 SSA 指令映射为
RISC-V 指令形态，对应上游 QBE 的 `rv64/isel.c`。

## 入口

```moonbit
pub fn isel_rv64(
  @types.Fn,          // 待处理的函数（就地修改）
  @util.Interner,     // 字符串驻留器
  Bool,               // 调试开关（-dI dump）
  Array[@types.Typ],  // 全局类型表
) -> String raise
```

返回 `-dI` 调试文本（`print_dbg == false` 时为空字符串）。

## 指令映射概要

| QBE IL | RISC-V |
| --- | --- |
| `add`/`sub`/`mul` | `add`/`sub`/`mul`（按类别 `w`/`l` 选 `addw` 等） |
| `div`/`rem`/`udiv`/`urem` | `div`/`rem`/`divu`/`remu` |
| `and`/`or`/`xor` | `and`/`or`/`xor` |
| `shl`/`sar`/`shr` | `sll`/`sra`/`srl`（word 变体 `*w`） |
| `loadsb/ub/sh/uh/sw/uw/l` | `lb/lbu/lh/lhu/lw/lwu/ld` |
| `storeb/h/w/l` | `sb/sh/sw/sd` |
| `loads`/`stores` | `flw`/`fsw` |
| `loadd`/`stored` | `fld`/`fsd` |
| `extsb`/`extsh`/`extsw` | `sext.b`/`sext.h`/`sext.w`（或合并进 load） |
| 浮点运算 | `fadd.s`/`fsub.s`/`fmul.s`/`fdiv.s` 及 `d` 变体 |
| 比较 | 先 `slt`/浮点比较，再经 `beq`/`bne` 等分支 |

比较 + 分支的组合在指令选择层被改写为 RISC-V 分支指令直接消费比较结果的
形态（RISC-V 没有独立的 flags 状态）。

## 与 amd64 isel 的区别

- **无 flags 寄存器**：amd64 用 `xcmp` + flag-op + `jX...`，rv64 直接生成
  比较 + 分支序列。
- **无复杂寻址**：amd64 可把 `add` 链折叠成 `[base + index*scale + offset]`
  寻址操作数；RISC-V 只支持 `[rs1 + imm]`，`isel_rv64` 仅做
  `base + offset` 形式识别（`decompose_addr`/`is_simple_addr` 语义），
  复杂地址保留显式 `add` 指令。
- **无魔法数除法**：amd64 把常量除法降为乘加移位序列；rv64 直接用
  `div`/`rem` 指令。
- **立即数**：RISC-V 指令立即数位宽有限，大常量先 `li` 装载到寄存器。

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- 指令选择在 ABI 降级之后运行，此时参数/返回值已是具体寄存器引用。
- rv64 复用 amd64 的 `spill`/`rega`（通过 `types.target_cfg` 切换目标），
  因此 isel_rv64 输出的指令引用的寄存器编号遵循
  `types/target_rv64.mbt` 的编号方案。
