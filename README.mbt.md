# Qbe.mbt

> rewrite qbe in moonbit but add more feature

# We Impl What Qbe has
- IR optimizer
- RISC-V 64 backend
- amd64(x86-64) backend
- arm64(AArch64) backend — byte-exact vs `tools/qbe-ref -t arm64`
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