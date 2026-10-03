# azhzx/qbe

> QBE 的 MoonBit 重写版

# 项目文档
> **[Qbe.mbt API 文档](README.md)**

# 项目概览
qbe.mbt 旨在将 Quick Backend (QBE) 的核心后端能力移植到 MoonBit 生态。

提供轻量级编译器后端。

提供 SSA 中间表示、IL 文本解析与输出、指令选择、寄存器分配、ABI 处理。

# 核心功能范围
提供 QBE 风格的 SSA 中间表示模型，支持函数、基本块、临时变量、指令、跳转、phi 节点、数据段以及类型系统；

支持 QBE IL 文本格式的解析、输出与美化打印（pretty printing），用于与上游 QBE 工具链或自定义前端交换中间表示；

提供统一的编译入口

支持 amd64（System V，GAS 输出，Linux/macOS 两种风格）

支持 WebAssembly（wasm32，WAT 文本输出）

支持 RISC-V 64（rv64）与 LoongArch 64（la64，LP64D）GAS 输出，以及直接的 SSA 解释执行

支持基础后端流水线

支持常见 IL 指令

提供调试辅助模块

提供统一的编译入口 `@qbe.compile` / `@qbe.compile_debug`，涵盖 IL 解析、SSA 构造、寄存器分配与汇编输出；

提供 WebAssembly 编译入口 `@qbe.compile_wasm` / `@qbe.compile_wasm_debug`，涵盖 IL 解析、SSA 构造与 WAT 文本输出；

提供 RISC-V 编译入口 `@qbe.compile_rv64` / `@qbe.compile_rv64_debug`，涵盖 IL 解析、SSA 构造、RISC-V 寄存器分配与汇编输出；
提供 LoongArch64 编译入口 `@qbe.compile_la64` / `@qbe.compile_la64_debug`（LP64D ABI，输出数据段与浮点常量池）；
提供 SSA 解释器入口 `@qbe.interpret`（async）—— 直接执行 pre-isel IR，内置可移植运行时（`putchar`/`puts`/`printf`/`malloc`/`free`/`exit`）以及可注入的外部符号钩子；

提供 MoonBit 单元/黑盒/白盒测试，维护核心回归测试（`.ssa` 差分回归 + `moon test`）；

提供 README 示例，覆盖 IL 解析、SSA 构造、寄存器分配、汇编输出与目标架构选择。

提供程序化 IR 构造器（`ir_builder`，Cranelift/LLVM 风格），构造与解析器产出的相同 `Fn`/`Blk`/`Ins`/`Phi` IR，并提供 `@qbe.compile_ir_object` / `@qbe.compile_ir_asm` / `@qbe.compile_ir_bin_module` 入口，外加 C ABI（`ir_builder_capi`，`include/qbe_builder.h`）；参见 [ir_builder.md](ir_builder.md)。

# 快速开始

`@qbe.compile` 将 IL 文本编译为 amd64 GAS 汇编；`@qbe.compile_debug` 返回各阶段的 dump：

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

`@qbe.compile_wasm` 将 IL 文本编译为 WAT（WebAssembly Text）格式：

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
  match @qbe.compile_wasm(src) {
    Ok(wat) => {
      assert_true(wat.contains("(func $add"))
      assert_true(wat.contains("i32.add"))
    }
    Err(_) => fail("wasm compile failed")
  }
}
```

`@qbe.compile_rv64` 将 IL 文本编译为 RISC-V 64 GAS 汇编：

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
  match @qbe.compile_rv64(src) {
    Ok(assembly) => {
      assert_true(assembly.contains("add:"))
      assert_true(assembly.contains("addw a0, a0, a1"))
    }
    Err(_) => fail("rv64 compile failed")
  }
}
```

`@qbe.compile_la64` 将 IL 文本编译为 LoongArch64 GAS 汇编：

```mbt check
///|
test {
  let src =
    #|export function w $add(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|
    #|}
  match @qbe.compile_la64(src) {
    Ok(assembly) => {
      assert_true(assembly.contains("add:"))
      assert_true(assembly.contains("add.w"))
    }
    Err(_) => fail("la64 compile failed")
  }
}
```

`@qbe.interpret` 直接执行 SSA（异步，类似 LLVM IR 的 `lli`）：

```mbt check
///|
async test {
  let src =
    #|export function l $square(l %x) {
    #|@start
    #|  %r =l mul %x, %x
    #|  ret %r
    #|
    #|}
  match @qbe.interpret(src, entry="square", args=[@interp.VInt(7)]) {
    Ok((@interp.VInt(v), _out)) => assert_eq(v, 49L)
    Ok(_) => fail("unexpected result kind")
    Err(@util.QbeError::CompileError(m)) => fail("ce: \{m}")
    Err(@util.QbeError::Ice(m)) => fail("ice: \{m}")
    Err(@util.QbeError::ParseError(_, _, m)) => fail("parse: \{m}")
  }
}
```

# 技术细节

## 包结构与编译流水线

MoonBit 包按编译流水线阶段组织（参见 [doc/](README.md)）：

| 阶段 | 包 | 说明 |
| --- | --- | --- |
| 数据结构 | `types` | SSA 中间表示：`Fn`/`Blk`/`Ins`/`Phi`/`Jump`/`Con`/`Tmp`/`Dat` 等，由所有后端包共享 |
| 通用工具 | `util` | 错误类型、字符串驻留（Interner）、输出、排序 |
| 词法分析 | `lexer` | IL 文本 → token 序列，错误收集到 `err_msgs` 而非抛出异常 |
| 语法分析 | `parser` | token 序列 → `Fn`/`Dat`/`Typ`，支持 `type`/`data`/`function` 三种顶层定义 |
| 程序化前端 | `ir_builder` | 基于 builder 构造 IL（函数、基本块、块参数/phi、指令、数据）；通过 `@qbe.compile_ir_object`/`compile_ir_asm`/`compile_ir_bin_module` 产出 |
| C ABI | `ir_builder_capi` | `foreign_library` 导出面向 C 的 `qbe_*` 构造器符号（`include/qbe_builder.h`） |
| CFG 分析 | `cfg` | 逆后序、前驱、支配者树、支配边界、循环深度、别名分析、跳转简化 |
| SSA 构造 | `ssa` | 使用链、memopt、phi 插入、块重命名、loadopt、copy 传播、合法性检查 |
| 常量折叠 | `fold` | 直接求值所有操作数均为常量的指令，并将其替换为引用 |
| Wasm ABI | `target_wasm/abi` | Wasm 调用约定：保留 Par/Arg，Call 简化 |
| Wasm 指令选择 | `target_wasm/isel` | wasm op 映射、地址模式分解、CFG→结构化控制流 |
| Wasm 汇编输出 | `target_wasm/emit` | WAT 文本格式输出 |
| ABI 处理 | `abi` | System V AMD64 调用约定：参数/返回寄存器、栈溢出、可变参数 |
| 指令选择 | `isel` | amd64 指令模式：立即数、地址模式、除法魔数、条件跳转 |
| 活跃分析 | `live` | 逆向数据流计算 in/out，基本块边界统计 `nlive_w`/`nlive_d` |
| 寄存器溢出 | `spill` | 基于代价与循环加权的溢出点选择，迭代至收敛 |
| 寄存器分配 | `rega` | 由活跃集合构建干涉图，贪心着色 |
| 汇编输出 | `emit` | 渲染 GAS 汇编（Linux `.L`/macOS `L`，`_` 前缀） |
| RISC-V ABI | `target_rv64/abi` | rv64 调用约定：A0–A7 / FA0–FA7 参数与返回，聚合类型拆分 |
| RISC-V 指令选择 | `target_rv64/isel` | rv64 指令映射、比较+分支合并 |
| RISC-V 汇编输出 | `target_rv64/emit` | RISC-V GAS 文本输出 |
| LoongArch ABI | `target_la64/abi` | la64（LP64D）调用约定：A0-A7 / FA0-FA7 参数与返回 |
| LoongArch 指令选择 | `target_la64/isel` | la64 指令映射、比较指令降低为 slt/sltu |
| LoongArch 汇编输出 | `target_la64/emit` | LoongArch GAS 文本输出（数据段 + 浮点常量池） |
| ARM64 ABI | `target_arm64/abi` | AAPCS64 调用约定：x0-x7 / v0-v7 参数、x8 隐藏结果指针、HFA、栈参数 |
| ARM64 指令选择 | `target_arm64/isel` | arm64 指令映射、立即数折叠、比较+分支合并 |
| ARM64 汇编输出 | `target_arm64/emit` | AArch64 GAS 文本输出（参考快照语法） |
| SSA 解释器 | `interp` | 直接执行 pre-isel IR，内置运行时 |
| CLI 入口 | `cmd/main` | 参数解析与文件 I/O（薄壳，调用 `@qbe` façade，`-t` 选择目标） |
| 库入口 | `.` | 统一编译 API `compile` / `compile_debug` 与 IR 类型重导出 |

完整流水线（`pipeline.mbt` 中的 `run_passes`，为库使用者封装在 `@qbe.compile` 中）：

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

Wasm 流水线（`run_passes_wasm`，为库使用者封装在 `@qbe.compile_wasm` 中）：

```
parse → fillrpo → fillpreds → filluse → memopt
      → filldom → fillfron → filllive(false) → phiins → renblk → filluse → ssacheck
      → fillloop → fillalias → loadopt → filluse → ssacheck
      → copy → filluse → fold
      → abi_wasm → fillpreds → filluse
      → isel_wasm
      → [skip spill/rega — wasm has no physical registers]
      → emit_wasm
```

RISC-V 流水线（`run_passes_rv64`，为库使用者封装在 `@qbe.compile_rv64` 中）：

```
parse → fillrpo → fillpreds → filluse → memopt
      → filldom → fillfron → filllive(false) → phiins → renblk → filluse → ssacheck
      → fillloop → fillalias → loadopt → filluse → ssacheck
      → copy → filluse → fold
      → abi_rv64 → fillpreds → filluse
      → isel_rv64
      → init_rv64_target()   ← switch TargetCfg (register layout)
      → fillrpo → filllive → fillcost → spill → rega
      → fillrpo → simpljmp → fillrpo → fillpreds
      → emit_rv64

LoongArch 流水线（`run_passes_la64`，为库使用者封装在 `@qbe.compile_la64` 中）：

```
  parse → cfg/ssa/live/fold passes
      → abi_la64 → fillpreds → filluse
      → isel_la64
      → init_la64_target()   ← switch TargetCfg (register layout)
      → fillrpo → filllive → fillcost → spill → rega
      → simpljmp
      → emit_la64 (+ data sections + float constant pool)
```

ARM64 流水线（`run_passes_arm64`，为库使用者封装在 `@qbe.compile_arm64` 中）：

```
  parse → cfg/ssa/live/fold passes
      → abi_arm64 → fillpreds → filluse
      → isel_arm64
      → init_arm64_target()  ← switch TargetCfg (register layout)
      → fillrpo → filllive → fillcost → spill → rega
      → simpljmp
      → emit_arm64 (+ data sections + float constant pool)
```

解释器路径（`@qbe.interpret`）：

```
  parse → lay out data segment → bind args
      → interpret pre-isel IR (phi, calls, memory, builtins)
      → Result[InterpValue, QbeError]
```
```

## 中间表示设计

- **SSA IR**：函数（`Fn`）、基本块（`Blk`）、临时变量（`Tmp`）、指令（`Ins`）均为可变结构体，就地修改而不产生副本；支持 phi 节点与多种跳转形式（无条件跳转、条件跳转、整数/浮点条件跳转、5 种返回类型）。
- **操作码**：`Op` 枚举覆盖全部 100 多条 QBE 指令（算术、位运算、移位、比较、load/store、扩展/转换、alloc、vararg、call 以及内部指令 `Nop`/`Addr`/`Swap`/`Xcmp` 等），`OpInfo` 携带操作数属性与可折叠标记。
- **引用类型**：`Ref` 是操作数引用，统一了临时变量（`RTmp`）、常量（`RCon`）、类型（`RType`）、栈槽（`RSlot`）、调用点（`RCall`）、内存（`RMem`）。
- **位集合** `BSet`：用 `Array[UInt64]` 实现的紧凑位集合，用于活跃变量集合与寄存器掩码。
- **寄存器编号**：`RAX=1..RSP=16, XMM0=17..XMM15=32`，`RXX=0` 表示“无寄存器”。

## 关键算法

- **SSA 构造**：基于支配边界（`fillfron`）插入 phi 节点，通过块与变量重命名建立 SSA 形式，`ssacheck` 执行合法性检查。
- **活跃分析**：逆向数据流迭代至不动点；`gen_set` 只构建一次并复用，仅重新计算 in/out。
- **寄存器分配**：先按代价溢出（使用/定义点计数 + `10^loop_depth` 循环加权，字/双字通道分别评估），随后在 `rega` 中由活跃集合构建干涉图并进行贪心着色；基本块边界处不一致的寄存器会插入 `copy` 进行同步。调用者保存计数与全局活跃掩码来自 `types.target_cfg`（例如 amd64 `post_call_gpr`/`fpr` = 9/15，arm64 = 19/23，rglob = FP|SP|R18），因此 `spill`/`rega` 在 amd64/rv64/la64/arm64 之间共享。
- **指令选择**：进行保持语义的强度削减 —— 将立即数折叠进指令、把 `add` 链合并为 `[base + index*scale + offset]` 寻址、把常量除数除法转换为魔数乘加移位、把比较 + `jnz` 模式转换为 amd64 条件跳转。
- **内存优化**：memopt 消除冗余的 alloc/load/store；loadopt 消除同一基本块内无介入 store 的同址重复 load；copy 传播合并等价的临时变量。

## ABI 与目标支持

提供五个目标，通过命令行 `-t` 选择（默认 `amd64_sysv`），各自具有独立的库 API 入口（另有 `--run` 用于直接解释执行）：

- **amd64_sysv**：`abi` 阶段把抽象的 `Arg`/`Par`/`Ret*` 替换为具体的寄存器/栈槽引用；聚合类型遵循 System V 规则决定走寄存器还是内存；输出两种 GAS 风格（Linux `.L` / macOS `L` + `_` 前缀，通过 `-G` 选择）。具备完整的 408 用例差分回归。
- **wasm**：`target_wasm/abi` 阶段保留 `Par`（签名参数）与 `Arg`（调用实参）的真实类别，并简化 `Call` 引用；`target_wasm/isel` 进行指令映射后跳过寄存器分配（wasm 是栈式机，没有物理寄存器），`target_wasm/emit` 输出 WAT 文本格式。wasm32 指针宽度为 32 位（`Km = Kw`），没有 `Kl` 类型。
- **rv64**：`target_rv64/abi` 按 RISC-V 调用约定把参数降低到 `A0–A7` / `FA0–FA7`，通过 `A0`/`A1` / `FA0`/`FA1` 返回；`target_rv64/isel` 把 IL 指令映射为 RISC-V 指令（比较 + 分支直接合并，无标志位、无魔数除法、无复杂寻址）；随后与 amd64 一样运行 `spill`/`rega` —— 目标差异通过 `types.TargetCfg` 在运行时切换（`init_amd64_target()` / `init_rv64_target()`），`target_rv64/emit` 输出 RISC-V GAS 汇编（`fp`/`ra` 栈帧链，16 字节栈对齐）。
- **la64**：`target_la64/abi` 按 LoongArch LP64D psABI 把参数降低到 `A0-A7` / `FA0-FA7`；`target_la64/isel` 把比较降低为 `slt`/`sltu` 序列（无标志位）并物化常量；`target_la64/emit` 输出带数据段与浮点常量池的 LoongArch GAS 汇编。通过 `init_la64_target()` 复用 `spill`/`rega`。
- **arm64**：`target_arm64/abi` 按 AAPCS64（ELF）把参数降低到 `x0-x7` / `v0-v7`，通过 `x0`/`x1` / `v0-v3` 返回，并经由 HFA、GP 块或 `x8` 隐藏指针传递聚合类型；`target_arm64/isel` 折叠立即数并把比较合并为标志位分支；`target_arm64/emit` 输出 AArch64 GAS（参考快照语法：间接 `blr`、`.L` 标签、`mov`/`movk` 常量）。通过 `init_arm64_target()` 复用 `spill`/`rega`。已与 `vendor/qbe/qbe -t arm64` 逐字节验证（每个 debug dump，408/408 汇编）。
- **interp**：`@qbe.interpret` 直接执行 pre-isel IR —— 扁平的小端内存、带符号引用的数据段布局、函数指针、递归、纯 MoonBit 的内置运行时，以及可注入的外部钩子（相当于 LLVM ORC 的符号解析）。

目标对比：

| | amd64_sysv | wasm | rv64 | la64 | arm64 | interp |
| --- | --- | --- | --- | --- | --- | --- |
| 库入口 | `compile` / `compile_debug` | `compile_wasm` / `compile_wasm_debug` | `compile_rv64` / `compile_rv64_debug` | `compile_la64` / `compile_la64_debug` | `compile_arm64` / `compile_arm64_debug` | `interpret`（async） |
| CLI | `-t amd64_sysv`（默认） | `-t wasm` | `-t rv64` | `-t la64` | `-t arm64` | `--run FUNC[,ARG]...` |
| 输出 | x86-64 GAS | WAT | RISC-V GAS | LoongArch GAS | AArch64 GAS | 解释执行结果 |
| 寄存器分配 | spill + rega | 跳过（栈式机） | spill + rega（`TargetCfg` 切换） | spill + rega（`TargetCfg` 切换） | spill + rega（`TargetCfg` 切换） | 无（直接执行） |
| 验证强度 | 逐字节差分回归 | 单元测试 + 快照 | 单元测试 + e2e 快照（无参考基线） | 单元测试 + e2e 快照（psABI 核验） | 逐字节差分回归（`vendor/qbe/qbe -t arm64`）+ clang 汇编门禁 | 单元测试 + e2e 测试 |

## 调试与测试

- 命令行 `-d <flags>` 提供各阶段 dump（`-dP` parse、`-dM` memopt、`-dN` SSA、`-dC` copy、`-dF` fold、`-dA` abi、`-dI` isel、`-dL` live、`-dS` spill、`-dR` rega），可组合使用；启用 debug 时不输出汇编。库入口 `compile_debug(text, flags)` 返回相同的 dump 文本。
- 测试分为三层：
  - **单元/白盒测试** `*_wbtest.mbt`：覆盖所有编译流水线包 —— `types`（BSet/Con/Ref/Op/Class/Jump 等）、`util`（Interner/格式化）、`lexer`、`parser`、`cfg`（支配树/循环/跳转简化）、`ssa`（phi 插入/copy/memopt）、`fold`、`live`、`abi`/`target_wasm/abi`/`target_rv64/abi`/`target_la64/abi`/`target_arm64/abi`、`isel`/`target_wasm/isel`/`target_rv64/isel`/`target_la64/isel`/`target_arm64/isel`、`spill`、`rega`、`emit`/`target_wasm/emit`/`target_rv64/emit`/`target_la64/emit`/`target_arm64/emit`、`interp`、`cmd/main`；
  - **黑盒测试** `qbe_test.mbt` + `qbe_snapshot_test.mbt`（+ `qbe_rv64_snapshot_test.mbt` / `qbe_la64_snapshot_test.mbt` / `qbe_arm64_snapshot_test.mbt`）：直接调用 `@qbe.compile*` / `@qbe.compile*_debug`，覆盖端到端编译（算术、浮点、内存、递归、循环 phi）与错误路径；`qbe_snapshot_test.mbt` 由 `python tools/gen_snapshot_mbt.py` 从 `test/` 分类生成，以 `inspect` 快照锚定；
  - **差分回归**：`test/*.ssa`（408 个用例）与参考 qbe 二进制逐字节比较（`vendor/qbe` 为固定快照，用 `make -C vendor/qbe` 构建）（`python compare.py`，可用 `QBE_REF` 指定其他二进制）。arm64：`python compare.py --target arm64`（对全部 408 个用例的每个 debug 标志）与 `--target arm64 --asm`（408/408），外加 `python tools/check_arm64_asm.py`（clang aarch64 可汇编性门禁）。
- 运行：`moon test`；更新快照：`moon test --update`；覆盖率：`moon coverage analyze`。

# 移植与归属说明
原始项目信息
原始项目名称：Quick Backend (QBE)

原始项目链接：https://github.com/8l/qbe

本项目许可证：Apache 2.0

原始项目许可证：MIT

原始项目许可证文本
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

与原项目相比，本项目做了以下简化和重新设计：

使用 MoonBit 的现代 ML 系语言风格重写代码，而不是照搬 C 的 suckless 结构；

优先实现可在 MoonBit 中独立运行的核心后端能力

将 C 代码中的手动内存管理改写为 MoonBit 的安全数据结构与枚举类型，降低内存风险；

# 未来计划
- ✅ WebAssembly（wasm32）代码生成支持（WAT 文本输出）
- ✅ RISC-V 64（rv64）代码生成（GAS 输出，复用 spill/rega）
- ✅ LoongArch 64（la64）代码生成（LP64D ABI，数据段 + 浮点常量池，复用 spill/rega）
- ✅ SSA 解释器（`interp` 包、`--run` CLI 标志、内置运行时 + 外部符号钩子）
- ✅ rv64 `data` 段与浮点常量 rodata 输出（与 `vendor/qbe -t rv64` 逐字节一致）
- ✅ 程序化 IR 构造器（`ir_builder`）与 C ABI（`ir_builder_capi`，`include/qbe_builder.h`）：无需渲染/重新解析 `.ssa` 即可构造 QBE IL，然后产出汇编 / Mach-O 目标文件 / JIT 镜像
- 在 `python compare.py --target rv64` 下实现 rv64 的完整逐字节一致
- 与 mbtcc 对接，验证完整的端到端可行性
