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
    --emit obj  write a Mach-O arm64 object file (arm64 target)
    --jit FUNC[,ARG]...
                compile to arm64, mmap and call FUNC (macOS/aarch64, route B)
    --run-asm FUNC[,ARG]
                emit arm64 asm, assemble/link with clang and call FUNC (route A)
    --run-wasm FUNC[,ARG]
                compile to wasm and run FUNC under node
    --clang     use the clang-backed arm64 backend for --emit obj
                (default: self-contained)
    --out-dir DIR
                directory for --emit obj output (default: .qbe_build)
```

### `-t` Target Selection

| Target | Output | Description |
| --- | --- | --- |
| `amd64_sysv` | x86-64 GAS assembly | Default; `-G e` (Linux `.L` labels) / `-G m` (macOS `L` + `_` prefix) selects GAS style; both flavors are byte-identical to the reference (`-t amd64_sysv` / `-t amd64_apple`) |
| `wasm` | WAT text | WebAssembly text format; skips register allocation |
| `rv64` | RISC-V 64 GAS assembly | ELF; supports `-G e` (`.L` labels), emits data + float pool |
| `la64` | LoongArch64 GAS assembly | LP64D ABI; supports `-G e`/`-G m` labels |
| `arm64` | AArch64 GAS assembly | AAPCS64; `-G e` (ELF) / `-G m` (Mach-O) both byte-identical to the reference |

Examples:

```
moon run cmd/main -- -t rv64 demo/01_arith.ssa
moon run cmd/main -- -t wasm demo/05_float.ssa
moon run cmd/main -- -t la64 demo/01_arith.ssa
moon run cmd/main -- -t arm64 demo/01_arith.ssa
moon run cmd/main -- -t amd64_sysv -G m -o out.s demo/01_arith.ssa
moon run cmd/main -- --run main,42 demo/01_arith.ssa
```

### arm64 JIT / object (`--jit`, `--emit obj`, `--run-asm`)

On macOS/aarch64 the arm64 backend emits and runs machine code without a
toolchain (route B):

```
moon run --target native cmd/main -- --jit fib,10 demo/10_fibonacci.ssa        # 55
moon run --target native cmd/main -- --jit add,2,3 demo/01_arith.ssa           # 5
moon run --target native cmd/main -- --jit main demo/11_main.ssa               # Hello from qbe.mbt!
moon run --target native cmd/main -- --emit obj demo/10_fibonacci.ssa          # .qbe_build/10_fibonacci.o
moon run --target native cmd/main -- --emit obj --out-dir build demo/10_fibonacci.ssa
moon run --target native cmd/main -- --emit obj -o fib.o demo/10_fibonacci.ssa
moon run --target native cmd/main -- --run-asm fib,10 demo/10_fibonacci.ssa     # clang route A
```

`--jit FUNC[,ARG]...` compiles to in-process machine code and calls the
function. It dispatches on the function signature: 0..8 all-integer or 0..8
all-float arguments, with the result printed accordingly. External symbols
such as libc `putchar`/`sqrt` are resolved with `dlsym` (far calls go through
in-image veneers), so programs with libc calls run directly.

`--run-asm FUNC[,ARG]` takes the toolchain route instead: emit arm64 assembly,
assemble/link it with clang and call the function (route A).

`--emit obj` is pure MoonBit and works on any host. See
[run_asm.md](run_asm.md) for details and limitations.

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
- `azhzx/qbe/target_amd64/abi`
- `azhzx/qbe/target_amd64/isel`
- `azhzx/qbe/fold`
- `azhzx/qbe/live`
- `azhzx/qbe/spill`
- `azhzx/qbe/rega`
- `azhzx/qbe/target_amd64/emit`
- `azhzx/qbe/target_wasm/abi` / `azhzx/qbe/target_wasm/isel` / `azhzx/qbe/target_wasm/emit`
- `azhzx/qbe/target_rv64/abi` / `azhzx/qbe/target_rv64/isel` / `azhzx/qbe/target_rv64/emit`
- `moonbitlang/x` (`@fs`), `moonbitlang/async` (`@stdio`), `moonbitlang/core/argparse`
