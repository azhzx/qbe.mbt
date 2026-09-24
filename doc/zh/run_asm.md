# JIT 与目标文件生成

qbe.mbt 可以把 .ssa 变成机器码，目前支持 **macOS / aarch64**，有两条路径：

    qbe --emit obj -o fib.o demo/10_fibonacci.ssa    # 生成 Mach-O .o
    qbe --run-asm fib,10 demo/10_fibonacci.ssa           # 输出 55

两者都走同一条流水线（前端 -> arm64 ABI -> isel -> rega）和逐字节对齐的
arm64 文本发射器。

## 路线 A - 借道系统工具链（默认）

`run_asm/`（仅 native）调用系统工具链：

- `--emit obj`：把 Mach-O 汇编写到临时 `.s`，再 `clang -c` 得到 `.o`。
- `--run-asm FUNC[,ARG]`：把 Mach-O 汇编写到临时 `.s`，`clang -dynamiclib` 生成
  dylib，`dlopen` 后用 `dlsym` 解析 `FUNC` 并调用。

MoonBit 自身无法表达的部分放在 `run_asm/run_asm_stub.c`，通过类型化 FFI
（`run_asm/ffi.mbt`）暴露：`mmap`/`mprotect` 可执行内存、临时文件、进程启动、
`dlopen`/`dlsym`、调用裸代码地址。

优点：今天即可用、代码少、复用已验证的发射器。缺点：运行期依赖 Xcode/clang。

## 路线 B - 自包含（进行中）

目标（对齐 Cranelift）：不依赖工具链，进程内直接产出目标文件并执行。

已完成并验证：

- `object/macho.mbt` - Mach-O（`MH_OBJECT`，arm64）写入器：header、带 section
  的 `LC_SEGMENT_64`、`LC_BUILD_VERSION`、`LC_SYMTAB`、`nlist_64` 与外部
  重定位。手工构造的目标文件可被 `ld` 链接并运行。
- `object/arm64_enc.mbt` - 编码器切片（`add` 立即数、`movz`、`movk`、`ret`），
  与 `clang` 逐字节对拍通过。
- `run_asm/module.mbt` - `ExecBlock`：`mmap` + 拷贝 + `mprotect` + 调用，内存中的
  arm64 代码可直接执行。

路线 B 进度：`target_arm64/emit/emit_arm64_bin.mbt` 已能从同一份 post-`rega`
IR 直接产出 arm64 机器字（函数序言/尾声、整数与双精度运算、加载/存储、用
`cset` 的比较、常量物化、函数内跳转回填）。对 `add` 与带分支/循环的用例，与
clang 汇编文本发射器的结果逐字节一致；native 测试已在 `ExecBlock` 中真正执行
产出的代码（`sum_to`）。

待完成：调用与全局地址（`BRANCH26`/`PAGE21`/`PAGEOFF12` 重定位）、浮点常量与
单精度、多 section 的 `.o` 输出，以及把 `--emit obj` / `--run-asm` 接到这条
路径。

## 运行 wasm（`--run-wasm`）

`qbe --run-wasm FUNC[,ARG]...` 编译到 wasm（`-t wasm` 后端），用
`moon-wasm-opt`（MoonBit 自带的 binaryen）把 WAT 转成模块，再在 `node` 下运行
导出函数。例如：

    qbe --run-wasm add,2,3 demo/01_arith.ssa   # 5

wasm 后端把 QBE 的 CFG 下沉为带 `br_table` 的分发循环，因此循环与 phi 节点可用；
同时支持内部调用/递归、浮点比较与 `data` 数据段。外部导入（`printf` 等）与可变
参数调用尚未发射。

## 测试

    moon test --target native -p run_asm      # FFI、路线 A、路线 B 切片
    moon test --target native -p object   # 编码器对拍、目标文件布局
