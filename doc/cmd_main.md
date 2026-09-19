# `cmd/main` Package API Reference

Package path: `azhzx/qbe/cmd/main`

CLI entry point. Reads command-line arguments, orchestrates pipeline stages, outputs assembly or debug dumps. Corresponds to `main.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/cmd_main.md)

The CLI supports `amd64_sysv` (default), `wasm`, `rv64`, `la64`, and `arm64`,
selected via `-t`. Compilation is dispatched through the shared
`@qbe.compile_target` and `@qbe.compile_target_debug` APIs.

## Command-Line Interface

```
Usage: qbe [OPTIONS] {file.ssa, -}
    -h          prints this help
    -o file     output to file
    -t <target> generate for a target among:
                amd64_sysv (default), wasm, rv64, la64, arm64
    -G {e,m}    generate gas (e) or osx (m) asm (amd64_sysv only)
    -d <flags>  dump debug information
```

### `-t` Target Selection

| Target | Output | Description |
| --- | --- | --- |
| `amd64_sysv` | x86-64 GAS assembly | Default; `-G e` (Linux `.L` labels) / `-G m` (macOS `L` + `_` prefix) selects GAS style |
| `wasm` | WAT text | WebAssembly text format; skips register allocation |
| `rv64` | RISC-V 64 GAS assembly | `-G` has no effect |
| `la64` | LoongArch64 GAS assembly | LP64D ABI; supports `-G e`/`-G m` labels |
| `arm64` | AArch64 GAS assembly | AAPCS64 ELF; supports `-G e`/`-G m` labels |

Examples:

```
moon run cmd/main -- -t rv64 demo/01_arith.ssa
moon run cmd/main -- -t wasm demo/05_float.ssa
moon run cmd/main -- -t la64 demo/01_arith.ssa
moon run cmd/main -- -t arm64 demo/01_arith.ssa
moon run cmd/main -- -t amd64_sysv -G m -o out.s demo/01_arith.ssa
moon run cmd/main -- --run main,42 demo/01_arith.ssa
```

### `-d` Debug Flags

| Flag | Phase | Output Content |
| --- | --- | --- |
| `-dP` | parse | Parsed function IL |
| `-dM` | memopt + loadopt | State after memory optimization |
| `-dN` | SSA construction | Dominator chain + SSA form |
| `-dC` | copy | Copy propagation result |
| `-dF` | fold | Constant folding result |
| `-dA` | abi | State after ABI processing |
| `-dI` | isel | Instruction selection result |
| `-dL` | live | Liveness variable sets |
| `-dS` | spill | Spilling cost + actual spilling |
| `-dR` | rega | Register allocation result |

Combinable, e.g., `-dMN` dumps both memopt and SSA simultaneously.

## Compilation Pipeline

The shared frontend is implemented by `run_frontend_passes` in
`pipeline.mbt`; each target then applies its ABI, instruction selection, and
machine-specific output stages:

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

Each `-d*` flag triggers a dump for the corresponding phase (output to stderr). When any debug flag is enabled, **no assembly is output** (only debug dumps); otherwise assembly is output to stdout or the `-o` specified file.

## Main Functions

- `process_file(file, flags, gas, target) -> String` - Process a single input file
  - `file == "-"` reads from stdin
  - Dispatches to `@qbe.compile_target` / `@qbe.compile_target_debug`
  - Returns generated assembly string (debug mode returns `""`, dump output goes to stderr)

## Dependencies

- `azhzx/qbe/lexer`
- `azhzx/qbe/parser`
- `azhzx/qbe/types`
- `azhzx/qbe/util`
- `azhzx/qbe/cfg`
- `azhzx/qbe/ssa`
- `azhzx/qbe/abi_amd64`
- `azhzx/qbe/isel`
- `azhzx/qbe/fold`
- `azhzx/qbe/live`
- `azhzx/qbe/spill`
- `azhzx/qbe/rega`
- `azhzx/qbe/emit_amd64`
- `azhzx/qbe/abi_wasm` / `azhzx/qbe/isel_wasm` / `azhzx/qbe/emit_wasm`
- `azhzx/qbe/abi_rv64` / `azhzx/qbe/isel_rv64` / `azhzx/qbe/emit_rv64`
- `moonbitlang/x` (`@fs`), `moonbitlang/async` (`@stdio`), `moonbitlang/core/argparse`
