# `cmd/main` 包接口介绍

包路径: `azhzx/qbe/cmd/main`

CLI 入口。读取命令行参数，调度各阶段，输出汇编或调试 dump。对应 QBE 原项目的 `main.c`。

CLI 支持三个目标：`amd64_sysv`（默认）、`wasm`、`rv64`，通过 `-t` 选择；
分别调用库入口 `@qbe.compile` / `@qbe.compile_wasm` / `@qbe.compile_rv64`。

## 命令行接口

```
Usage: qbe [OPTIONS] {file.ssa, -}
    -h          prints this help
    -o file     output to file
    -t <target> generate for a target among:
                amd64_sysv (default), wasm, rv64
    -G {e,m}    generate gas (e) or osx (m) asm (amd64_sysv only)
    -d <flags>  dump debug information
```

### `-t` 目标选择

| 目标 | 输出 | 说明 |
| --- | --- | --- |
| `amd64_sysv` | x86-64 GAS 汇编 | 默认；`-G e`（Linux `.L` 标签）/ `-G m`（macOS `L` + `_` 前缀）选择 GAS 风格 |
| `wasm` | WAT 文本 | WebAssembly 文本格式；跳过寄存器分配 |
| `rv64` | RISC-V 64 GAS 汇编 | `-G` 不生效 |

示例：

```
moon run cmd/main -- -t rv64 demo/01_arith.ssa
moon run cmd/main -- -t wasm demo/05_float.ssa
moon run cmd/main -- -t amd64_sysv -G m -o out.s demo/01_arith.ssa
```

### `-d` 调试标志

| 标志 | 阶段 | 输出内容 |
| --- | --- | --- |
| `-dP` | parse | 解析后的函数 IL |
| `-dM` | memopt + loadopt | 内存优化后状态 |
| `-dN` | SSA 构造 | 支配者链 + SSA 形式 |
| `-dC` | copy | copy 传播结果 |
| `-dF` | fold | 常量折叠结果 |
| `-dA` | abi | ABI 处理后状态 |
| `-dI` | isel | 指令选择结果 |
| `-dL` | live | 活跃变量集合 |
| `-dS` | spill | 溢出代价 + 实际溢出 |
| `-dR` | rega | 寄存器分配结果 |

可组合，如 `-dMN` 同时 dump memopt 和 SSA。

## 编译流水线

参考 [cmd/main/main.mbt](../cmd/main/main.mbt) 中的 `run_passes`：

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

每个 `-d*` 标志触发对应阶段的 dump（输出到 stderr）。当任一调试标志开启时，**不输出汇编**（仅 dump 调试信息）；否则输出汇编到 stdout 或 `-o` 指定文件。

## 主要函数

- `process_file(file, flags, gas, target) -> String` - 处理单个输入文件
  - `file == "-"` 表示从 stdin 读取
  - 按 `target` 分发到 `@qbe.compile*` / `@qbe.compile_*_debug`
  - 返回生成的汇编字符串（调试模式返回 `""`，dump 输出到 stderr）

## 依赖

- `azhzx/qbe/lexer`
- `azhzx/qbe/parser`
- `azhzx/qbe/types`
- `azhzx/qbe/util`
- `azhzx/qbe/cfg`
- `azhzx/qbe/ssa`
- `azhzx/qbe/abi`
- `azhzx/qbe/isel`
- `azhzx/qbe/fold`
- `azhzx/qbe/live`
- `azhzx/qbe/spill`
- `azhzx/qbe/rega`
- `azhzx/qbe/emit`
- `azhzx/qbe/abi_wasm` / `azhzx/qbe/isel_wasm` / `azhzx/qbe/emit_wasm`
- `azhzx/qbe/abi_rv64` / `azhzx/qbe/isel_rv64` / `azhzx/qbe/emit_rv64`
- `moonbitlang/x` (`@fs`)、`moonbitlang/async` (`@stdio`)、`moonbitlang/core/argparse`
