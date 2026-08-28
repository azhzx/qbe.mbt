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
| Wasm ABI | `abi_wasm` | [abi_wasm.md](abi_wasm.md) | wasm 调用约定：Par/Arg→Nop，Call 简化 |
| Wasm 指令选择 | `isel_wasm` | [isel_wasm.md](isel_wasm.md) | wasm op 映射、地址模式分解、CFG→结构化控制流 |
| Wasm 汇编输出 | `emit_wasm` | [emit_wasm.md](emit_wasm.md) | WAT 文本格式输出 |
| ABI 处理 | `abi` | [abi.md](abi.md) | 参数/返回值的平台 ABI |
| 指令选择 | `isel` | [isel.md](isel.md) | amd64 指令模式选择 |
| 活跃分析 | `live` | [live.md](live.md) | in/out 活跃集合 |
| 寄存器溢出 | `spill` | [spill.md](spill.md) | 寄存器压力下的栈溢出 |
| 寄存器分配 | `rega` | [rega.md](rega.md) | 虚拟 → 物理寄存器 |
| 汇编输出 | `emit` | [emit.md](emit.md) | 渲染 GAS 汇编 |
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

## 项目相关

- 总体介绍：[README.mbt.md](../README.mbt.md)
- 演示样例：[demo/](../demo/README.md)
- 回归测试：[test/](../test/)
- 编码规范：[AGENTS.md](../AGENTS.md)
