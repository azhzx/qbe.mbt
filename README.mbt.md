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
- (FIX) rv64 backend: `data` segment and floating-point constant rodata output, reference differential verification

## Contributors
<a href="https://github.com/azhzx/qbe.mbt/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=azhzx/qbe.mbt" />
</a>
Made with [contrib.rocks](https://contrib.rocks).
