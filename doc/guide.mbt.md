# azhzx/qbe

> A MoonBit rewrite of QBE

[中文文档 (Chinese Documentation)](zh/README.md)

# Project Documentation
> **[Qbe.mbt API Documentation](README.md)**

# Project Overview
qbe.mbt aims to port the core backend capabilities of Quick Backend (QBE) to the MoonBit ecosystem.

Provides a lightweight compiler backend.

Provides SSA intermediate representation, IL text parsing and output, instruction selection, register allocation, ABI processing.

# Core Feature Scope
Provides QBE-style SSA intermediate representation model, supporting functions, basic blocks, temporary variables, instructions, jumps, phi nodes, data segments, and type systems;

Supports QBE IL text format parsing, output, and pretty printing for exchanging intermediate representations with upstream QBE toolchain or custom frontends;

Provides unified compilation entry point

Supports amd64 (System V, GAS output, Linux/macOS two styles)

Supports WebAssembly (wasm32, WAT text output)

Supports RISC-V 64 (rv64) and LoongArch 64 (la64, LP64D) GAS output, plus direct SSA interpretation

Supports basic backend pipeline

Supports common IL instructions

Provides debugging auxiliary modules

Provides unified compilation entry point `@qbe.compile` / `@qbe.compile_debug`, covering IL parsing, SSA construction, register allocation, and assembly output;

Provides WebAssembly compilation entry point `@qbe.compile_wasm` / `@qbe.compile_wasm_debug`, covering IL parsing, SSA construction, and WAT text output;

Provides RISC-V compilation entry point `@qbe.compile_rv64` / `@qbe.compile_rv64_debug`, covering IL parsing, SSA construction, RISC-V register allocation, and assembly output;
Provides LoongArch64 compilation entry point `@qbe.compile_la64` / `@qbe.compile_la64_debug` (LP64D ABI, data sections and float constant pool emitted);
Provides the SSA interpreter entry `@qbe.interpret` (async) - executes pre-isel IR directly with a built-in portable runtime (`putchar`/`puts`/`printf`/`malloc`/`free`/`exit`) and an injectable external-symbol hook;

Provides MoonBit unit/blackbox/whitebox tests, maintaining core regression tests (`.ssa` differential regression + `moon test`);

Provides README examples covering IL parsing, SSA construction, register allocation, assembly output, and target architecture selection.

Provides a programmatic IR builder (`ir_builder`, Cranelift/LLVM-style) that constructs the same `Fn`/`Blk`/`Ins`/`Phi` IR the parser produces, with `@qbe.compile_ir_object` / `@qbe.compile_ir_asm` / `@qbe.compile_ir_bin_module` entries, plus a C ABI (`ir_builder_capi`, `include/qbe_builder.h`); see [ir_builder.md](ir_builder.md).

# Quick Start

`@qbe.compile` compiles an IL text to amd64 GAS assembly; `@qbe.compile_debug` returns dumps from each stage:

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

`@qbe.compile_wasm` compiles an IL text to WAT (WebAssembly Text) format:

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

`@qbe.compile_rv64` compiles an IL text to RISC-V 64 GAS assembly:

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

`@qbe.compile_la64` compiles an IL text to LoongArch64 GAS assembly:

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

`@qbe.interpret` executes the SSA directly (async, like `lli` for LLVM IR):

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

# Technical Details

## Package Structure and Compilation Pipeline

MoonBit packages organized by compilation pipeline stages (see [doc/](README.md)):

| Phase | Package | Description |
| --- | --- | --- |
| Data Structures | `types` | SSA IR: `Fn`/`Blk`/`Ins`/`Phi`/`Jump`/`Con`/`Tmp`/`Dat` etc., shared by all backend packages |
| Utilities | `util` | Error types, string interning (Interner), output, sorting |
| Lexing | `lexer` | IL text → token sequence, errors collected to `err_msgs` instead of exceptions |
| Parsing | `parser` | Token sequence → `Fn`/`Dat`/`Typ`, supports `type`/`data`/`function` three top-level definitions |
| Programmatic Front End | `ir_builder` | Builder-based IL construction (functions, blocks, block parameters/phi, instructions, data); emits via `@qbe.compile_ir_object`/`compile_ir_asm`/`compile_ir_bin_module` |
| C ABI | `ir_builder_capi` | `foreign_library` exporting the `qbe_*` builder symbols for C (`include/qbe_builder.h`) |
| CFG Analysis | `cfg` | Reverse postorder, predecessors, dominator tree, dominance frontiers, loop depth, alias analysis, jump simplification |
| SSA Construction | `ssa` | Use chains, memopt, phi insertion, block renaming, loadopt, copy propagation, validity checking |
| Constant Folding | `fold` | Directly evaluates instructions whose operands are all constants and replaces with references |
| Wasm ABI | `target_wasm/abi` | Wasm calling convention: keep Par/Arg, Call simplification |
| Wasm Instruction Selection | `target_wasm/isel` | Wasm op mapping, address mode decomposition, CFG→structured control flow |
| Wasm Assembly Output | `target_wasm/emit` | WAT text format output |
| ABI Processing | `abi` | System V AMD64 calling convention: parameter/return registers, stack spilling, vararg |
| Instruction Selection | `isel` | amd64 instruction patterns: immediates, address modes, division magic numbers, conditional jumps |
| Liveness Analysis | `live` | Backward data flow to compute in/out, block boundary statistics `nlive_w`/`nlive_d` |
| Register Spilling | `spill` | Cost-based and loop-weighted spilling point selection, iterates to convergence |
| Register Allocation | `rega` | Builds interference graph from live sets, greedy coloring |
| Assembly Output | `emit` | Renders GAS assembly (Linux `.L`/macOS `L`, `_` prefix) |
| RISC-V ABI | `target_rv64/abi` | rv64 calling convention: A0–A7 / FA0–FA7 parameters and returns, aggregate type splitting |
| RISC-V Instruction Selection | `target_rv64/isel` | rv64 instruction mapping, compare+branch merging |
| RISC-V Assembly Output | `target_rv64/emit` | RISC-V GAS text output |
| LoongArch ABI | `target_la64/abi` | la64 (LP64D) calling convention: A0-A7 / FA0-FA7 parameters and returns |
| LoongArch Instruction Selection | `target_la64/isel` | la64 instruction mapping, comparisons lowered to slt/sltu |
| LoongArch Assembly Output | `target_la64/emit` | LoongArch GAS text output (data + float pool) |
| ARM64 ABI | `target_arm64/abi` | AAPCS64 calling convention: x0-x7 / v0-v7 parameters, x8 hidden result pointer, HFA, stack args |
| ARM64 Instruction Selection | `target_arm64/isel` | arm64 instruction mapping, immediate folding, compare+branch merging |
| ARM64 Assembly Output | `target_arm64/emit` | AArch64 GAS text output (reference snapshot syntax) |
| SSA Interpreter | `interp` | direct pre-isel IR execution with built-in runtime |
| CLI Entry | `cmd/main` | Argument parsing and file I/O (thin shell, calls `@qbe` facade, `-t` selects target) |
| Library Entry | `.` | Unified compilation API `compile` / `compile_debug` and IR type re-exports |

Complete pipeline (`run_passes` in `pipeline.mbt`, encapsulated for library users in `@qbe.compile`):

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

Wasm pipeline (`run_passes_wasm`, encapsulated for library users in `@qbe.compile_wasm`):

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

RISC-V pipeline (`run_passes_rv64`, encapsulated for library users in `@qbe.compile_rv64`):

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

LoongArch pipeline (`run_passes_la64`, encapsulated for library users in `@qbe.compile_la64`):

```
  parse → cfg/ssa/live/fold passes
      → abi_la64 → fillpreds → filluse
      → isel_la64
      → init_la64_target()   ← switch TargetCfg (register layout)
      → fillrpo → filllive → fillcost → spill → rega
      → simpljmp
      → emit_la64 (+ data sections + float constant pool)
```

ARM64 pipeline (`run_passes_arm64`, encapsulated for library users in `@qbe.compile_arm64`):

```
  parse → cfg/ssa/live/fold passes
      → abi_arm64 → fillpreds → filluse
      → isel_arm64
      → init_arm64_target()  ← switch TargetCfg (register layout)
      → fillrpo → filllive → fillcost → spill → rega
      → simpljmp
      → emit_arm64 (+ data sections + float constant pool)
```

Interpreter path (`@qbe.interpret`):

```
  parse → lay out data segment → bind args
      → interpret pre-isel IR (phi, calls, memory, builtins)
      → Result[InterpValue, QbeError]
```
```

## Intermediate Representation Design

- **SSA IR**: Functions (`Fn`), basic blocks (`Blk`), temporary variables (`Tmp`), instructions (`Ins`) are all mutable structs, modified in place without producing copies; supports phi nodes and multiple jump forms (unconditional jump, conditional jump, integer/float conditional jump, 5 return types).
- **Opcodes**: `Op` enum covers all 100+ QBE instructions (arithmetic, bitwise, shifts, comparisons, load/store, extensions/conversions, alloc, vararg, call and internal instructions `Nop`/`Addr`/`Swap`/`Xcmp` etc.), with `OpInfo` carrying operand properties and foldable markers.
- **Reference Types**: `Ref` is an operand reference, unifying temporary variables (`RTmp`), constants (`RCon`), types (`RType`), stack slots (`RSlot`), call points (`RCall`), memory (`RMem`).
- **Bit Sets** `BSet`: Compact bit sets implemented with `Array[UInt64]`, used for liveness variable sets and register masks.
- **Register Numbers**: `RAX=1..RSP=16, XMM0=17..XMM15=32`, `RXX=0` means "no register".

## Key Algorithms

- **SSA Construction**: Based on dominance frontiers (`fillfron`) inserts phi nodes, block and variable renaming establishes SSA form, `ssacheck` performs validity checking.
- **Liveness Analysis**: Backward data flow iterates to fixed point; `gen_set` built once and reused, only recomputing in/out.
- **Register Allocation**: Spill first by cost (use/definition point count + `10^loop_depth` loop weighting, word/double channels evaluated separately), then in `rega` builds interference graph from live sets and does greedy coloring; inconsistent registers at block boundaries get `copy` inserted for synchronization. Caller-save counts and globally-live masks come from `types.target_cfg` (e.g. amd64 `post_call_gpr`/`fpr` = 9/15, arm64 = 19/23, rglob = FP|SP|R18), so `spill`/`rega` are shared across amd64/rv64/la64/arm64.
- **Instruction Selection**: Does semantics-preserving strength reduction — folding immediates into instructions, combining `add` chains into `[base + index*scale + offset]` addressing, converting constant divisor division to magic number multiply-add-shift, converting comparison + `jnz` patterns to amd64 conditional jumps.
- **Memory Optimization**: memopt eliminates redundant alloc/load/store; loadopt eliminates repeated loads from same address with no intervening store in same block; copy propagation merges equivalent temporary variables.

## ABI and Target Support

Provides five targets, selected with `-t` on command line (`amd64_sysv` default), with independent library API entry points (plus `--run` for direct interpretation):

- **amd64_sysv**: `abi` phase replaces abstract `Arg`/`Par`/`Ret*` with concrete register/stack slot references; aggregate types follow System V rules for register vs memory; outputs two GAS styles (Linux `.L` / macOS `L` + `_` prefix, selected with `-G`). Has complete 406-case differential regression.
- **wasm**: `target_wasm/abi` phase keeps `Par` (signature parameters) and `Arg` (call arguments) with their real classes, and simplifies `Call` references; `target_wasm/isel` does instruction mapping then skips register allocation (wasm is stack machine, no physical registers), `target_wasm/emit` outputs WAT text format. wasm32 pointer width is 32 bits (`Km = Kw`), no `Kl` type.
- **rv64**: `target_rv64/abi` lowers parameters to `A0–A7` / `FA0–FA7` per RISC-V calling convention, returns via `A0`/`A1` / `FA0`/`FA1`; `target_rv64/isel` maps IL instructions to RISC-V instructions (compare + branch merged directly, no flags, no magic number division, no complex addressing); then runs `spill`/`rega` same as amd64 — target differences switched at runtime via `types.TargetCfg` (`init_amd64_target()` / `init_rv64_target()`), `target_rv64/emit` outputs RISC-V GAS assembly (`fp`/`ra` frame chain, 16-byte stack alignment).
- **la64**: `target_la64/abi` lowers parameters to `A0-A7` / `FA0-FA7` per the LoongArch LP64D psABI; `target_la64/isel` lowers comparisons to `slt`/`sltu` sequences (no flags) and materializes constants; `target_la64/emit` outputs LoongArch GAS assembly with data sections and the floating-point constant pool. Reuses `spill`/`rega` via `init_la64_target()`.
- **arm64**: `target_arm64/abi` lowers parameters to `x0-x7` / `v0-v7` per AAPCS64 (ELF), returns via `x0`/`x1` / `v0-v3`, and passes aggregates through HFAs, GP blocks or an `x8` hidden pointer; `target_arm64/isel` folds immediates and merges comparisons into flags branches; `target_arm64/emit` outputs AArch64 GAS (reference snapshot syntax: indirect `blr`, `.L` labels, `mov`/`movk` constants). Reuses `spill`/`rega` via `init_arm64_target()`. Validated byte-for-byte against `vendor/qbe/qbe -t arm64` (every debug dump, 406/406 assembly).
- **interp**: `@qbe.interpret` executes pre-isel IR directly - flat little-endian memory, data-segment layout with symbol refs, function pointers, recursion, a pure-MoonBit builtin runtime, and an injectable external hook (the analogue of LLVM ORC's symbol resolution).

Targets compared:

| | amd64_sysv | wasm | rv64 | la64 | arm64 | interp |
| --- | --- | --- | --- | --- | --- | --- |
| Library entry | `compile` / `compile_debug` | `compile_wasm` / `compile_wasm_debug` | `compile_rv64` / `compile_rv64_debug` | `compile_la64` / `compile_la64_debug` | `compile_arm64` / `compile_arm64_debug` | `interpret` (async) |
| CLI | `-t amd64_sysv` (default) | `-t wasm` | `-t rv64` | `-t la64` | `-t arm64` | `--run FUNC[,ARG]...` |
| Output | x86-64 GAS | WAT | RISC-V GAS | LoongArch GAS | AArch64 GAS | interpreted result |
| Register allocation | spill + rega | skipped (stack machine) | spill + rega (`TargetCfg` switch) | spill + rega (`TargetCfg` switch) | spill + rega (`TargetCfg` switch) | none (direct execution) |
| Validation strength | Differential regression byte-by-byte | Unit tests + snapshots | Unit tests + e2e snapshots (no reference baseline) | Unit tests + e2e snapshots (psABI-verified) | Differential regression byte-by-byte (`vendor/qbe/qbe -t arm64`) + clang assembler gate | Unit tests + e2e tests |

## Debugging and Testing

- Command-line `-d <flags>` provides per-stage dumps (`-dP` parse, `-dM` memopt, `-dN` SSA, `-dC` copy, `-dF` fold, `-dA` abi, `-dI` isel, `-dL` live, `-dS` spill, `-dR` rega), combinable; when debug is enabled, assembly is not output. Library entry `compile_debug(text, flags)` returns the same dump text.
- Tests in three layers:
  - **Unit/whitebox tests** `*_wbtest.mbt`: Cover all compilation pipeline packages — `types` (BSet/Con/Ref/Op/Class/Jump etc.), `util` (Interner/formatting), `lexer`, `parser`, `cfg` (dominator tree/loop/jump simplification), `ssa` (phi insertion/copy/memopt), `fold`, `live`, `abi`/`target_wasm/abi`/`target_rv64/abi`/`target_la64/abi`/`target_arm64/abi`, `isel`/`target_wasm/isel`/`target_rv64/isel`/`target_la64/isel`/`target_arm64/isel`, `spill`, `rega`, `emit`/`target_wasm/emit`/`target_rv64/emit`/`target_la64/emit`/`target_arm64/emit`, `interp`, `cmd/main`;
  - **Blackbox tests** `qbe_test.mbt` + `qbe_snapshot_test.mbt` (+ `qbe_rv64_snapshot_test.mbt` / `qbe_la64_snapshot_test.mbt` / `qbe_arm64_snapshot_test.mbt`): Directly call `@qbe.compile*` / `@qbe.compile*_debug`, covering end-to-end compilation (arithmetic, floating-point, memory, recursion, loop phi) and error paths; `qbe_snapshot_test.mbt` generated by `python tools/gen_snapshot_mbt.py` from `test/` categories, anchored with `inspect` snapshots;
  - **Differential regression**: `test/*.ssa` (406 cases) compared byte-by-byte with reference qbe binary (`vendor/qbe` pinned snapshot, built with `make -C vendor/qbe`) (`python compare.py`, can specify other binary with `QBE_REF`). arm64: `python compare.py --target arm64` (every debug flag on all 406 cases) and `--target arm64 --asm` (406/406), plus `python tools/check_arm64_asm.py` (clang aarch64 assemblability gate).
- Run: `moon test`; update snapshots: `moon test --update`; coverage: `moon coverage analyze`.

# Porting and Attribution Notes
Original project information
Original project name: Quick Backend (QBE)

Original project link: https://github.com/8l/qbe

This project license: Apache 2.0

Original project license: MIT

Original project license text
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

Compared to the original project, this project makes the following simplifications and redesigns:

Rewrites code using MoonBit's modern ML-family language style instead of replicating C's suckless structure;

Prioritizes implementing core backend capabilities that can run independently in MoonBit

Rewrites manual memory management from C code to MoonBit's safe data structures and enum types, reducing memory risks;

# Future Plans
- ✅ WebAssembly (wasm32) code generation support (WAT text output)
- ✅ RISC-V 64 (rv64) code generation (GAS output, reusing spill/rega)
- ✅ LoongArch 64 (la64) code generation (LP64D ABI, data + float pool, reusing spill/rega)
- ✅ SSA interpreter (`interp` package, `--run` CLI flag, builtin runtime + external symbol hook)
- ✅ rv64 `data` segment and floating-point constant rodata output (byte-identical to `vendor/qbe -t rv64`)
- ✅ Programmatic IR builder (`ir_builder`) and C ABI (`ir_builder_capi`, `include/qbe_builder.h`): construct QBE IL without rendering/re-parsing `.ssa`, then emit assembly / Mach-O object / JIT image
- rv64 full byte-parity under `python compare.py --target rv64`
- Interface with mbtcc to verify full end-to-end feasibility
