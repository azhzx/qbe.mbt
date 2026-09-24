# qbe.mbt 接口文档 (doc)

本目录提供 qbe.mbt 编译后端各 MoonBit 包的接口说明，依据各包的 `pkg.generated.mbti`（`moon info` 生成）以及源码注释。

## 包一览

按编译流水线阶段顺序排列：

| 阶段 | 包 | 接口文档 | 说明 |
| --- | --- | --- | --- |
| 数据结构 | `types` | [types.md](types.md) | SSA 中间表示：`Fn`/`Blk`/`Ins`/`Phi`/`Jump`/`Con`/`Tmp` 等 |
| 通用工具 | `util` | [util.md](util.md) | 错误类型、字符串驻留、输出、排序 |
| 词法分析 | `lexer` | [lexer.md](lexer.md) | IL 文本 → token 序列 |
| 语法分析 | `parser` | [parser.md](parser.md) | token 序列 → `Fn`/`Dat`/`Typ` |
| CFG 分析 | `cfg` | [cfg.md](cfg.md) | 前驱、支配者、支配边界、循环、别名 |
| SSA 构造 | `ssa` | [ssa.md](ssa.md) | 使用链、phi 插入、memopt/loadopt/copy |
| 常量折叠 | `fold` | [fold.md](fold.md) | 常量指令求值 |
| Wasm ABI | `target_wasm/abi` | [abi_wasm.md](abi_wasm.md) | wasm 调用约定：Par/Arg→Nop，Call 简化 |
| Wasm 指令选择 | `target_wasm/isel` | [isel_wasm.md](isel_wasm.md) | wasm op 映射、地址模式分解、CFG→结构化控制流 |
| Wasm 汇编输出 | `target_wasm/emit` | [emit_wasm.md](emit_wasm.md) | WAT 文本格式输出 |
| ABI 处理 | `target_amd64/abi` | [abi.md](abi.md) | 参数/返回值的平台 ABI |
| 指令选择 | `target_amd64/isel` | [isel.md](isel.md) | amd64 指令模式选择 |
| 活跃分析 | `live` | [live.md](live.md) | in/out 活跃集合 |
| 寄存器溢出 | `spill` | [spill.md](spill.md) | 寄存器压力下的栈溢出 |
| 寄存器分配 | `rega` | [rega.md](rega.md) | 虚拟 → 物理寄存器 |
| 汇编输出 | `target_amd64/emit` | [emit.md](emit.md) | 渲染 GAS 汇编 |
| RISC-V ABI | `target_rv64/abi` | [abi_rv64.md](abi_rv64.md) | rv64 调用约定：A0-A7/FA0-FA7 参数与返回 |
| RISC-V 指令选择 | `target_rv64/isel` | [isel_rv64.md](isel_rv64.md) | rv64 指令映射、比较+分支合并 |
| RISC-V 汇编输出 | `target_rv64/emit` | [emit_rv64.md](emit_rv64.md) | RISC-V GAS 文本输出 |
| LoongArch ABI | `target_la64/abi` | [abi_la64.md](abi_la64.md) | la64（LP64D）调用约定：A0-A7/FA0-FA7 参数与返回 |
| LoongArch 指令选择 | `target_la64/isel` | [isel_la64.md](isel_la64.md) | la64 指令映射、比较指令降低为 slt/sltu |
| LoongArch 汇编输出 | `target_la64/emit` | [emit_la64.md](emit_la64.md) | LoongArch GAS 文本输出（含数据段与浮点常量池） |
| ARM64 ABI | `target_arm64/abi` | [abi_arm64.md](abi_arm64.md) | AAPCS64：x0-x7/v0-v7 参数、x8 隐藏结果指针、HFA、栈参数 |
| ARM64 指令选择 | `target_arm64/isel` | [isel_arm64.md](isel_arm64.md) | arm64 指令映射、立即数折叠、比较+分支合并 |
| ARM64 汇编输出 | `target_arm64/emit` | [emit_arm64.md](emit_arm64.md) | AArch64 GAS 文本输出（参考快照语法） |
| SSA 解释器 | `interp` | [interp.md](interp.md) | 直接执行 pre-isel IR，内置可移植运行时 |
| CLI 入口 | `cmd/main` | [cmd_main.md](cmd_main.md) | 命令行参数与流水线调度 |

## 流水线一览

```
            ┌──────┐  ┌───────┐
   src.ssa ─►│lexer │─►│parser │─┐
            └──────┘  └───────┘ │
                                  ▼
                              ┌─────┐
                              │types│  Fn/Dat/Typ
                              └─────┘
                                  │
   ┌──────────────────────────────┼──────────────────────────────┐
   │                                ▼                              │
   │  cfg.fillrpo/preds/dom/fron/loop/alias                        │
   │                                │                              │
   │                                ▼                              │
   │           ssa.filluse → ssa.memopt → ssa.phiins → renblk     │
   │                                │                              │
   │                                ▼                              │
   │           ssa.loadopt → ssa.copy → fold.fold                  │
   │                                │                              │
   │                                ▼                              │
   │                          abi.abi                              │
   │                                │                              │
   │                                ▼                              │
   │                          isel.isel                           │
   │                                │                              │
   │                                ▼                              │
   │           live.filllive → spill.fillcost → spill.spill        │
   │                                │                              │
   │                                ▼                              │
   │           rega.rega → cfg.simpljmp                           │
   │                                │                              │
   └────────────────────────────────┼─────────────────────────────┘
                                    ▼
                              emit.emitfn
                                    │
                                    ▼
                               out.s (GAS 汇编)
```

### Wasm 流水线

```
            ┌──────┐  ┌───────┐
   src.ssa ─►│lexer │─►│parser │─┐
            └──────┘  └───────┘ │
                                  ▼
                              ┌─────┐
                              │types│  Fn/Dat/Typ
                              └─────┘
                                  │
   ┌──────────────────────────────┼──────────────────────────────┐
   │                                ▼                              │
   │  cfg.fillrpo/preds/dom/fron/loop/alias                        │
   │                                │                              │
   │                                ▼                              │
   │           ssa.filluse → ssa.memopt → ssa.phiins → renblk     │
   │                                │                              │
   │                                ▼                              │
   │           ssa.loadopt → ssa.copy → fold.fold                  │
   │                                │                              │
   │                                ▼                              │
   │                       abi_wasm.abi_wasm                       │
   │                                │                              │
   │                                ▼                              │
   │                      isel_wasm.isel_wasm                      │
   │                                │                              │
   │                                ▼                              │
   │              [跳过 spill/rega — wasm 无物理寄存器]              │
   │                                │                              │
   └────────────────────────────────┼─────────────────────────────┘
                                    ▼
                              emit_wasm.emit_fn
                                    │
                                    ▼
                              out.wat (WAT 文本)
```

每个带 `-d*` 标志的阶段在调试模式下会输出 IL 形式的快照到 stderr，参考 [cmd_main.md](cmd_main.md) 的标志表。

三个差分目标（`amd64_sysv`、`arm64`、`rv64`）的每个调试标志输出与
生成的汇编，均与冻结参考 `vendor/qbe`（661ceb2）逐字节一致。

## 项目相关

- 总体介绍：[README.mbt.md](../README.mbt.md)
- 演示样例：[demo/](../demo/README.md)
- 回归测试：[test/](../test/)
- 编码规范：[AGENTS.md](../AGENTS.md)

### RISC-V 64 流水线

```
parse → fillrpo → fillpreds → filluse → memopt
      → filldom → fillfron → filllive(false) → phiins → renblk → filluse → ssacheck
      → fillloop → fillalias → loadopt → filluse → ssacheck
      → copy → filluse → fold
      → abi_rv64 → fillpreds → filluse
      → isel_rv64
      → init_rv64_target()   ← 切换 TargetCfg（寄存器布局）
      → fillrpo → filllive → fillcost → spill → rega
      → fillrpo → simpljmp → fillrpo → fillpreds
      → emit_rv64
```

rv64 与 amd64 共享同一套 `spill`/`rega`：目标差异通过 `types.target_cfg`
（见 [types.md](types.md) 的 TargetCfg 章节）在运行时切换。
rv64 的 `data` 段与浮点常量池与 `vendor/qbe -t rv64` 逐字节一致；差分验证通过
`python compare.py --target rv64` 与独立的 `tools/check_rv64_asm.py` 汇编门禁进行。

```
la64（LoongArch64，LP64D）：
  parse → cfg/ssa/live/fold 各 pass
      → abi_la64 → fillpreds → filluse
      → isel_la64
      → init_la64_target()   ← 切换 TargetCfg（寄存器布局）
      → fillrpo → filllive → fillcost → spill → rega
      → simpljmp
      → emit_la64（含数据段与浮点常量池）
```

la64 通过 `types.target_cfg` 与 amd64/rv64 共享同一套 `spill`/`rega`。
没有上游差分参考基线，快照逐条对照 LoongArch ELF psABI 手工核验；
数据段与浮点常量池为完整输出，与 rv64 相同。

```
arm64（AArch64，AAPCS64 ELF）：
  parse → cfg/ssa/live/fold 各 pass
      → abi_arm64 → fillpreds → filluse
      → isel_arm64
      → init_arm64_target()  ← 切换 TargetCfg（寄存器布局）
      → fillrpo → filllive → fillcost → spill → rega
      → simpljmp
      → emit_arm64（含数据段与浮点常量池）
```

arm64 通过 `types.target_cfg` 与其它目标共享 `spill`/`rega`，并对照
`vendor/qbe/qbe -t arm64` 逐字节验证：IR dump 5684/5684、ELF 汇编 406/406
（`-G e`）与 Mach-O（`-G m`）两种风格（各 406/406）。参考快照未实现的
功能（动态 `alloc`、`truncd` 等）在两端同样失败。

```
interp（SSA 直接解释执行）：
  parse → 布局数据段 → 绑定实参
      → 解释 pre-isel IR（phi、调用、内存、内置运行时）
      → Result[InterpValue, QbeError]
```

解释器完全绕开 ABI/指令选择/寄存器分配，直接执行源语义层 IR；
详见 [interp.md](interp.md)。
