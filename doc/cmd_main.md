# `cmd/main` 包接口介绍

包路径: `azhzx/qbe/cmd/main`

CLI 入口。读取命令行参数，调度各阶段，输出汇编或调试 dump。对应 QBE 原项目的 `main.c`。

## 命令行接口

```
Usage: qbe [OPTIONS] {file.ssa, -}
    -h          prints this help
    -o file     output to file
    -t <target> generate for a target among:
                amd64_sysv
    -G {e,m}    generate gas (e) or osx (m) asm
    -d <flags>  dump debug information
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

- `process_file(file, dbg, gasloc, gassym) -> String` - 处理单个输入文件
  - `file == "-"` 表示从 stdin 读取
  - 返回生成的汇编字符串（调试模式返回 `""`）
- `run_passes(fn_, interner, typs, dbg) -> Unit` - 跑全部后端阶段
- `dbg_dominators(fn_) -> Unit` - `-dN` 输出支配者链
- `dbg_function(fn_, interner, typs) -> Unit` - 打印当前函数的 IL

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
- `moonbitlang/x` (`@stdio`、`@fs`、`@env`)
