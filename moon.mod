// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "azhzx/qbe"

version = "0.23.1"

readme = "README.mbt.md"

repository = "https://github.com/azhzx/qbe.mbt"

license = "Apache-2.0"

keywords = [ "qbe", "compiler", "jit", "ssa" ]

preferred_target = "wasm"

description = "QBE reimplemented in MoonBit: the optimizer pipeline plus a programmatic IR builder, an in-memory aarch64 JIT, and LoongArch64/WASM backends"

import {
  "moonbitlang/x@0.5.5",
  "moonbitlang/async@0.21.0",
}
