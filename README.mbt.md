# Qbe.mbt

> rewrite qbe in moonbit but add more feature

# We Impl What Qbe has
- IR optimizer
- RISC-V 64 backend
- amd64(x86-64) backend
- arm64(AArch64) backend — byte-exact vs `vendor/qbe/qbe -t arm64`
  (IR: 5684/5684, assembly: 406/406)


# We Extend More Feature
- loong-arch64 backend
- wasm backend
- IR Interpreter

# Plan
- (TODO) Add JIT Interface(maybe use copy-and patch)
- (TODO) Add IR Debuger
- (FIX) For rv64 backend: `data` segment and floating-point constant rodata output, differential reference verification
 
# Contributor

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

If MoonBit is already installed, `--skip-install` prevents any installation
attempt while still running all smoke checks:

```sh
./scripts/bootstrap.sh --skip-install
```

To allow the script to attempt a MoonBit installation when `moon` is missing:

```sh
./scripts/bootstrap.sh --install-moon
```

Documentation:

- [API documentation](doc/README.md)
- [Developer guide](doc/guide.mbt.md)
- [Command-line reference](doc/cmd_main.md)
- [Demos](demo/README.md)
- [Tests](test/README.md)
