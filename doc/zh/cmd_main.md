# `cmd/main` 包接口介绍

包路径: `azhzx/qbe/cmd/main`

CLI 入口。读取命令行参数，调度各阶段，输出汇编或调试 dump。对应 QBE 原项目的 `main.c`。

CLI 支持 `amd64_sysv`（默认）、`wasm`、`rv64`、`la64` 和 `arm64`，通过 `-t` 选择；
编译统一通过 `@qbe.compile_target` 和 `@qbe.compile_target_debug` 分发。
分别调用库入口 `@qbe.compile` / `@qbe.compile_wasm` / `@qbe.compile_rv64`。

## 命令行接口

```
Usage: qbe [OPTIONS] {file.ssa, -}
    -h          prints this help
    -o file     output to file
    -t <target> generate for a target among:
                amd64_sysv (default), wasm, rv64, la64, arm64
    -G {e,m}    generate gas (e) or osx (m) asm (amd64_sysv only)
    -d <flags>  dump debug information
    --emit obj  写出 Mach-O arm64 目标文件（arm64 目标）
    --jit FUNC[,ARG]...
                编译到 arm64，用 mmap 装载并调用 FUNC（macOS/aarch64，路线 B）
    --run-asm FUNC[,ARG]
                发 arm64 汇编，用 clang 汇编/链接后调用 FUNC（路线 A）
    --run-wasm FUNC[,ARG]
                编译到 wasm，在 node 下运行 FUNC
    --clang     用借道 clang 的 arm64 后端跑 --emit obj（默认：自包含）
    --out-dir DIR
                --emit obj 的输出目录（默认 .qbe_build）
```

### `-t` 目标选择

| 目标 | 输出 | 说明 |
| --- | --- | --- |
| `amd64_sysv` | x86-64 GAS 汇编 | 默认；`-G e`（Linux `.L` 标签）/ `-G m`（macOS `L` + `_` 前缀）选择 GAS 风格；两种风格均与参考逐字节一致（`-t amd64_sysv` / `-t amd64_apple`） |
| `wasm` | WAT 文本 | WebAssembly 文本格式；跳过寄存器分配 |
| `rv64` | RISC-V 64 GAS 汇编 | ELF；支持 `-G e`（`.L` 标签），输出数据段与浮点池 |

示例：

```
moon run cmd/main -- -t rv64 demo/01_arith.ssa
moon run cmd/main -- -t wasm demo/05_float.ssa
moon run cmd/main -- -t amd64_sysv -G m -o out.s demo/01_arith.ssa
```

### arm64 JIT / 目标文件（`--jit`、`--emit obj`、`--run-asm`）

在 macOS/aarch64 上，arm64 后端可以不依赖工具链直接产出并运行机器码
（路线 B，默认）：

```
moon run --target native cmd/main -- --jit fib,10 demo/10_fibonacci.ssa        # 55
moon run --target native cmd/main -- --jit add,2,3 demo/01_arith.ssa           # 5
moon run --target native cmd/main -- --jit main demo/11_main.ssa               # Hello from qbe.mbt!
moon run --target native cmd/main -- --emit obj demo/10_fibonacci.ssa          # .qbe_build/10_fibonacci.o
moon run --target native cmd/main -- --emit obj --out-dir build demo/10_fibonacci.ssa
moon run --target native cmd/main -- --emit obj -o fib.o demo/10_fibonacci.ssa
moon run --target native cmd/main -- --run-asm fib,10 demo/10_fibonacci.ssa     # 借道 clang 的路线 A
```

`--jit FUNC[,ARG]...` 在内存里编译并调用函数，按签名分派：0..8 个全整数或
0..8 个全浮点实参，结果按类型打印。libc `putchar`/`sqrt` 等外部符号通过
`dlsym` 解析（远距离调用经镜像内 veneer），因此带 libc 调用的程序可直接运行。

`--run-asm FUNC[,ARG]` 走工具链路线：发 arm64 汇编，用 clang 汇编/链接后调用
（路线 A）。

`--emit obj` 是纯 MoonBit，任何平台都能用。细节与限制见
[run_asm.md](run_asm.md)。

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
- `azhzx/qbe/target_amd64/abi`
- `azhzx/qbe/target_amd64/isel`
- `azhzx/qbe/fold`
- `azhzx/qbe/live`
- `azhzx/qbe/spill`
- `azhzx/qbe/rega`
- `azhzx/qbe/target_amd64/emit`
- `azhzx/qbe/target_wasm/abi` / `azhzx/qbe/target_wasm/isel` / `azhzx/qbe/target_wasm/emit`
- `azhzx/qbe/target_rv64/abi` / `azhzx/qbe/target_rv64/isel` / `azhzx/qbe/target_rv64/emit`
- `moonbitlang/x` (`@fs`)、`moonbitlang/async` (`@stdio`)、`moonbitlang/core/argparse`
