# azhzx/qbe

> 用Moonbit重写qbe

# 项目文档
> **[Qbe.mbt文档](doc/)**

# 项目简介
qbe.mbt 计划将 Quick Backend (qbe) 的核心后端能力移植到 MoonBit 生态

提供轻量级的编译器后端

提供 SSA 中间表示、IL 文本解析与输出、指令选择、寄存器分配、ABI 处理

# 核心功能范围
提供 qbe 风格的 SSA 中间表示模型，支持函数、基本块、临时变量、指令、跳转、phi 节点、数据段和类型系统；

支持 qbe IL 文本格式的解析、输出和 pretty print，便于与上游 qbe 工具链或自研前端交换中间表示；

提供统一编译入口

支持 amd64

支持基础后端流程

支持常用 IL 指令

提供调试辅助模块

提供统一编译入口 `@qbe.compile` / `@qbe.compile_debug`，覆盖 IL 解析、SSA 构建、寄存器分配、汇编输出；

提供 MoonBit 单元 / 黑盒 / 白盒测试，并持续保持核心回归测试通过（`.ssa` 差分回归 + `moon test`）；

提供 README 示例，覆盖 IL 解析、SSA 构建、寄存器分配、汇编输出和目标架构选择。

# 快速上手

`@qbe.compile` 把一段 IL 文本编译成 amd64 GAS 汇编；`@qbe.compile_debug` 返回各阶段 dump：

```mbt check
///|
test {
  let src =
    #|export function w $add(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  match @qbe.compile(src) {
    Ok(assembly) => {
      assert_true(assembly.contains("addl"))
      assert_true(assembly.contains("add:"))
    }
    Err(_) => fail("compile failed")
  }
  match @qbe.compile_debug(src, "P") {
    Ok(dump) => assert_true(dump.contains("After parsing"))
    Err(_) => fail("compile failed")
  }
}
```

# 技术细节

## 包结构与编译流水线

按编译流水线阶段顺序组织的 MoonBit 包（详见 [doc/](doc/README.md)）：

| 阶段 | 包 | 说明 |
| --- | --- | --- |
| 数据结构 | `types` | SSA 中间表示：`Fn`/`Blk`/`Ins`/`Phi`/`Jump`/`Con`/`Tmp`/`Dat` 等，全部后端包共享 |
| 通用工具 | `util` | 错误类型、字符串驻留 (Interner)、输出、排序 |
| 词法分析 | `lexer` | IL 文本 → token 序列，错误收集到 `err_msgs` 而非抛异常 |
| 语法分析 | `parser` | token 序列 → `Fn`/`Dat`/`Typ`，含 `type`/`data`/`function` 三种顶层定义 |
| CFG 分析 | `cfg` | 反向后序、前驱、支配者树、支配边界、循环深度、别名分析、跳转简化 |
| SSA 构造 | `ssa` | 使用链、memopt、phi 插入、块重命名、loadopt、copy 传播、合法性检查 |
| 常量折叠 | `fold` | 操作数均为常量的指令直接求值并替换 |
| ABI 处理 | `abi` | System V AMD64 调用约定：参数/返回寄存器、栈溢出、vararg |
| 指令选择 | `isel` | amd64 指令模式：立即数、地址模式、除法魔法数、条件跳转 |
| 活跃分析 | `live` | 反向数据流求 in/out，块边界统计 `nlive_w`/`nlive_d` |
| 寄存器溢出 | `spill` | 基于代价与循环加权选择溢出点，迭代到收敛 |
| 寄存器分配 | `rega` | 基于活跃集合构建干涉图，贪心染色 |
| 汇编输出 | `emit` | 渲染 GAS 汇编（Linux `.L`/macOS `L`、`_` 前缀） |
| CLI 入口 | `cmd/main` | 参数解析与文件 I/O（薄壳，调用 `@qbe` facade） |
| 库入口 | `.` | 统一编译 API `compile` / `compile_debug` 与 IR 类型再导出 |

完整流水线（`pipeline.mbt` 中 `run_passes`，对库用户封装在 `@qbe.compile`）：

```
parse → fillrpo → fillpreds → filluse → memopt
      → filldom → fillfron → filllive(false) → phiins → renblk → filluse → ssacheck
      → fillloop → fillalias → loadopt → filluse → ssacheck
      → copy → filluse → fold
      → abi → fillpreds → filluse
      → isel
      → fillrpo → filllive → fillcost → spill → rega
      → fillrpo → simpljmp → fillrpo → fillpreds
      → emitfn
```

## 中间表示设计

- **SSA IR**：函数 (`Fn`)、基本块 (`Blk`)、临时变量 (`Tmp`)、指令 (`Ins`) 均为可变结构体，就地修改，不产生副本；支持 phi 节点与多种跳转形式（无条件跳转、条件跳转、整数/浮点条件跳转、5 种返回）。
- **操作码**：`Op` 枚举覆盖 qbe 全部 100+ 指令（算术、位运算、移位、比较、load/store、扩展/转换、alloc、vararg、call 与内部指令 `Nop`/`Addr`/`Swap`/`Xcmp` 等），通过 `OpInfo` 携带操作数属性与可折叠标记。
- **引用类型**：`Ref` 为操作数引用，统一表示临时变量 (`RTmp`)、常量 (`RCon`)、类型 (`RType`)、栈槽 (`RSlot`)、调用点 (`RCall`)、内存 (`RMem`)。
- **位集** `BSet`：以 `Array[UInt64]` 实现的紧凑位集，用于活跃变量集合与寄存器掩码。
- **寄存器编号**：`RAX=1..RSP=16, XMM0=17..XMM15=32`，`RXX=0` 表示"无寄存器"。

## 关键算法

- **SSA 构造**：基于支配边界 (`fillfron`) 插入 phi 节点，块与变量重命名建立 SSA 形式，`ssacheck` 做合法性校验。
- **活跃分析**：反向数据流迭代到不动点；`gen_set` 首建后复用，仅重算 in/out。
- **寄存器分配**：spill 先按代价（使用/定义点计数 + `10^loop_depth` 循环加权，word/double 通道分别按 `NGPS=9`/`NFPS=15` 评估）决定溢出到栈槽的临时变量，再在 `rega` 中按活跃集合构建干涉图并贪心染色；块边界寄存器不一致处插入 `copy` 同步。
- **指令选择**：做语义保持的强度提升——立即数折叠进指令、`add` 链组合为 `[base + index*scale + offset]` 寻址、常量除数除法转魔法数乘加移位、比较+`jnz` 模式转为 amd64 条件跳转。
- **内存优化**：memopt 消除冗余 alloc/load/store；loadopt 消除同块同址的无介入 store 的重复 load；copy 传播合并等价临时变量。

## ABI 与目标支持

- 当前仅支持 **amd64_sysv**（System V AMD64 调用约定）；`abi/` 与 `isel/` 为未来多目标（wasm、arm64 等）预留了同签名扩展位。
- `abi` 阶段把抽象 `Arg`/`Par`/`Ret*` 替换为具体寄存器/栈槽引用，聚合类型按 System V 规则决定走寄存器还是内存。
- 输出两种 GAS 风格：Linux（`-G e`，`.L` 标签、无符号前缀）与 macOS（`-G m`，`L` 标签、`_` 前缀），可直接 `gcc`/`clang` 汇编链接。

## 调试与测试

- 命令行 `-d <flags>` 提供分阶段 dump（`-dP` parse、`-dM` memopt、`-dN` SSA、`-dC` copy、`-dF` fold、`-dA` abi、`-dI` isel、`-dL` live、`-dS` spill、`-dR` rega），可组合；开启调试时不再输出汇编。库入口 `compile_debug(text, flags)` 返回同样的 dump 文本。
- 测试分三层：
  - **单元/白盒测试** `*_wbtest.mbt`：`types`（BSet/Con/Ref/Op/Class/Jump 等）、`util`（Interner/格式化）、`lexer`、`parser`、`fold`、`cfg`、`ssa`、`live` 的核心函数；
  - **黑盒测试** `qbe_test.mbt`：直接调用 `@qbe.compile` / `@qbe.compile_debug`，覆盖端到端编译（算术、浮点、内存、递归、循环 phi）与错误路径；
  - **差分回归**：`test/*.ssa`（406 个用例）与参考 qbe 二进制逐字节对比（`compare.py`）。
- 运行：`moon test`；更新快照：`moon test --update`；覆盖率：`moon coverage analyze`。

# 移植或参考说明
原项目信息
原项目名称：Quick Backend (qbe)

原项目链接：https://github.com/8l/qbe

本项目许可证：Apache 2.0

原项目许可证：MIT

原项目许可证原文
```
© 2015-2017 Quentin Carbonneaux quentin@c9x.me

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
```

与原项目相比，本项目会做以下简化和重新设计：

使用MoonBit现代ML系语言的写法重新编写代码，而不是复刻 C 的 suckless 结构；

优先实现可在MoonBit中独立运行的核心后端流程

改写原c代码的手动内存管理为MoonBit安全数据结构与枚举类型，降低内存风险；

# 未来计划
- 支持更多平台（包括wasm）的代码生成支持
- 添加方便JIT的相关接口
- 对接mbtcc，验证全流程的端到端的可行性