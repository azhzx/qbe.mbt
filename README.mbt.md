# Qbe.mbt
> Rewrite Qbe in MoonBit with additional features

## What we implement (same as upstream Qbe)
- IR optimizer
- RISC-V 64 backend
- amd64 (x86-64) backend
- arm64 (AArch64) backend — byte-exact output compared against `vendor/qbe/qbe -t arm64`
  (IR: 5684/5684, assembly: 406/406)

## Extended features
- LoongArch64 backend
- WASM backend
- IR Interpreter

## Plan
- (TODO) Add JIT interface (copy-and-patch approach)
- (TODO) Add IR Debugger
- (WIP) align with the frozen `vendor/qbe` reference (661ceb2):
  `data` segment and floating-point constant rodata output are byte-identical to
  `vendor/qbe` on amd64/arm64/rv64; the debug-dump differential suite
  (`python compare.py`) passes 12096/12096 cases (12 debug flags x 3 targets) and
  the emitted assembly is byte-identical on every compilable test
  (336/336 per target, 1008/1008 total)

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
- [Developer guide](doc/guide.mbt.md)
- [Command-line reference](doc/cmd_main.md)
- [Demos](demo/README.md)
- [Tests](test/README.md)
