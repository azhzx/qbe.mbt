# Qbe.mbt
> A QBE reimplementation in MoonBit — the upstream compiler plus a programmatic
> IR builder, an in-memory JIT, and LoongArch64/WASM backends

## Features
- **Byte-faithful QBE core**: the optimizer pipeline and the amd64 / arm64 /
  rv64 backends, checked byte-for-byte against the pinned `vendor/qbe`
  reference (661ceb2) — every debug stage and the emitted assembly (406/406
  per target)
- **Extra backends**: LoongArch64 and WASM
- **Programmatic IR builder** (`ir_builder`, C ABI `ir_builder_capi`,
  `include/qbe_builder.h`): construct QBE IL from MoonBit or C with no `.ssa`
  round-trip, print it back, or emit assembly text, a Mach-O arm64 object, or a
  JIT-ready code image
- **In-memory JIT** for macOS/aarch64 (`jit/`): map and call arm64 machine code
  with no toolchain in the path, resolving libc via `dlsym` and host callbacks;
  usable from the C ABI or Rust
- **Rust glue layer** (`rust/`, crate `qbe-builder`): Cranelift/inkwell-style
  `Context` / `Module` / `FunctionBuilder` / `ins()`, including `Module::jit`
- **Layered runtime**: `native/` (executable memory, symbol lookup, temp files,
  process spawn, dynamic linking) shared by `jit/` and `run_asm/`
- **Debug info**: the IL `dbgfile`/`dbgloc` statements emit `.file`/`.loc` DWARF
  line tables (byte-identical to the reference); `-g` adds a DWARF4 compilation
  unit, variables/types from the builder, and CFI/`.eh_frame`, giving
  source-level `lldb` debugging with `frame variable`
  ([doc/debug_info.md](doc/debug_info.md))

## Status
- amd64 / arm64 / rv64 debug dumps and assembly are byte-identical to
  `vendor/qbe`; the self-contained arm64 object matches clang on all 336
  compilable cases (`python tools/check_route_b.py`)
- `--jit FUNC[,ARG]...` runs code in-process; `--run-asm FUNC[,ARG]` does the
  same through clang; `--run-wasm FUNC[,ARG]` runs the WASM backend under node;
  `--emit obj` writes a self-contained Mach-O arm64 `.o`
- `dbgfile`/`dbgloc` line info is emitted for amd64/arm64/rv64/la64 and matches
  `vendor/qbe` on every debug flag; `-g` adds a DWARF4 CU (subprograms, variables,
  types, `.debug_loc`) + CFI (`.eh_frame`), verified end to end under `lldb`

## Roadmap
- Debug info: per-scope variable ranges, rv64/la64 CFI, and DWARF in the
  self-contained object / JIT path ([doc/debug_info.md](doc/debug_info.md))
- (TODO) IR debugger

## Contributors
<a href="https://github.com/azhzx/qbe.mbt/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=azhzx/qbe.mbt" />
</a>
Made with [contrib.rocks](https://contrib.rocks).

## Quick start

`./scripts/bootstrap.sh` is an interactive installer (rustup-style): it asks
how to get the MoonBit compiler, builds the native `qbe` binary and offers to
put it on your `PATH`.

```sh
git clone https://github.com/azhzx/qbe.mbt.git
cd qbe.mbt
./scripts/bootstrap.sh
```

```text
  +--------------------------------------------+
  |  qbe.mbt - QBE reimplemented in MoonBit    |
  +--------------------------------------------+

[1/3] MoonBit compiler
How should we get the MoonBit compiler?
  1)  Use the moon on PATH      (/Users/you/.moon/bin/moon)
  2)  Install MoonBit           (Homebrew / install.sh)
  3)  Use a custom moon path
  Choose [1]:

[2/3] Building qbe
    /Users/you/.moon/bin/moon build --target native
ok  built _build/native/debug/build/cmd/main/main.exe

[3/3] Shell integration
Add qbe to your PATH (install to /Users/you/.local/bin) [Y/n]
ok  installed /Users/you/.local/bin/qbe
ok  added /Users/you/.local/bin to /Users/you/.zshrc

qbe.mbt is ready.
```

Non-interactive options:

```sh
./scripts/bootstrap.sh --skip-install        # use the moon on PATH, never install
./scripts/bootstrap.sh --install-moon        # install MoonBit, then build
./scripts/bootstrap.sh --moon /opt/moon/bin/moon
./scripts/bootstrap.sh --yes --no-path       # scripted build, leave PATH alone
./scripts/bootstrap.sh --with-reference      # also build vendor/qbe (diff tests)
```

Colors are used only on a TTY; set `NO_COLOR=1` to disable them.

Documentation:

- [API documentation](doc/README.md)
- [Programmatic IR builder and C ABI](doc/ir_builder.md)
- [Rust bindings (`rust/`)](doc/rust_bindings.md)
- [Developer guide](doc/guide.mbt.md)
- [Command-line reference](doc/cmd_main.md)
- [Demos](demo/README.md)
- [Tests](test/README.md)
