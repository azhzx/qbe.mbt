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
  line tables, byte-identical to the reference ([doc/debug_info.md](doc/debug_info.md))

## Status
- amd64 / arm64 / rv64 debug dumps and assembly are byte-identical to
  `vendor/qbe`; the self-contained arm64 object matches clang on all 336
  compilable cases (`python tools/check_route_b.py`)
- `--jit FUNC[,ARG]...` runs code in-process; `--run-asm FUNC[,ARG]` does the
  same through clang; `--run-wasm FUNC[,ARG]` runs the WASM backend under node;
  `--emit obj` writes a self-contained Mach-O arm64 `.o`
- `dbgfile`/`dbgloc` line info is emitted for amd64/arm64/rv64/la64 and matches
  `vendor/qbe` on every debug flag

## Roadmap
- Debug info: CFI/`.eh_frame` and a DWARF `.debug_info` compilation unit
  ([doc/debug_info.md](doc/debug_info.md))
- (TODO) IR debugger

## Contributors
<a href="https://github.com/azhzx/qbe.mbt/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=azhzx/qbe.mbt" />
</a>
Made with [contrib.rocks](https://contrib.rocks).

## Quick start

Clone and bootstrap on macOS or Linux:

```sh
git clone https://github.com/azhzx/qbe.mbt.git
cd qbe.mbt
./scripts/bootstrap.sh
```

If MoonBit is already installed, use `--skip-install` to avoid installation attempts while still running smoke checks:

```sh
./scripts/bootstrap.sh --skip-install
```

To allow automatic MoonBit installation when `moon` is missing:

```sh
./scripts/bootstrap.sh --install-moon
```

Documentation:

- [API documentation](doc/README.md)
- [Programmatic IR builder and C ABI](doc/ir_builder.md)
- [Rust bindings (`rust/`)](doc/rust_bindings.md)
- [Developer guide](doc/guide.mbt.md)
- [Command-line reference](doc/cmd_main.md)
- [Demos](demo/README.md)
- [Tests](test/README.md)
