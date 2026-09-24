# JIT 与目标文件生成

qbe.mbt 可以把 `.ssa` 变成 **macOS / aarch64** 的机器码：默认走**完全自包含**的
路线 B（不需要工具链），也可以用 `--clang` 回到借道 clang 的路线 A：

    qbe --emit obj -o fib.o demo/10_fibonacci.ssa    # 生成 Mach-O .o
    qbe --run-asm fib,10 demo/10_fibonacci.ssa       # 输出 55

## 怎么体验

先构建一次（`moon build --target native`），然后：

    M=./_build/native/debug/build/cmd/main/main.exe

    # 进程内执行：mmap + mprotect + 直接调用，无 clang、无链接器
    $M --run-asm fib,10 demo/10_fibonacci.ssa        # 55
    $M --run-asm sum_to,100 demo/03_loop_phi.ssa     # 5050
    $M --run-asm fact,10 demo/04_recursion.ssa       # 3628800
    $M --run-asm global_demo demo/06_memory.ssa      # 1
    $M --run-asm sign,-5 demo/08_compare.ssa         # 4294967295（-1 的 u32）

    # 产出 Mach-O 目标文件；不加 -o 时默认写到 .qbe_build/<名字>.o
    $M --emit obj demo/10_fibonacci.ssa                     # .qbe_build/10_fibonacci.o
    $M --emit obj --out-dir build demo/10_fibonacci.ssa     # build/10_fibonacci.o
    $M --emit obj -o fib.o demo/10_fibonacci.ssa            # 指定精确路径
    printf 'long fib(long);\nint main(void){ return fib(10)==55?0:1; }\n' > drv.c
    clang -o fib .qbe_build/10_fibonacci.o drv.c && ./fib; echo $?   # 0

    # demo/11_main.ssa 自带 export main，产出的 .o 可直接链接
    $M --emit obj demo/11_main.ssa
    gcc -o hello .qbe_build/11_main.o && ./hello    # Hello from qbe.mbt!

`--run-asm` 需要 macOS/aarch64（要真正执行代码）；`--emit obj` 是纯 MoonBit，
任何平台都能跑。`--clang` 可把两者切回 clang 路线。

## 路线 B - 自包含（默认）

`target_arm64/emit/emit_arm64_bin.mbt` 直接消费同一份 post-`rega` IR，产出
arm64 机器字：函数序言/尾声、整数与双精度运算、加载/存储、用 `cset` 的比较、
常量物化（`MOVZ`/`MOVN`/`ORR` 逻辑立即数）、单精度运算、浮点转换与浮点常量池
（`Lfp0`、`Lfp1`…）、并行复制 `swap`，以及函数内跳转回填。

模块发射器（`emit_arm64_bin_module`）把所有函数拼成一段 text，回填模块内 `bl`，
把 `data` 段布局进同一镜像并回填全局 `adrp`/`add` 地址。`ExecBlock::load_module`
负责映射镜像，并且只把代码段设为可执行（RX），数据段保持可写（RW）。

`target_arm64/emit/emit_arm64_obj.mbt` 构造多 section 的 Mach-O
（`__text` / `__data` / `__TEXT,__const`），生成四类重定位：`PAGE21`/`PAGEOFF12`
（全局地址）、`BRANCH26`（调用）、`UNSIGNED`（数据指针）。

`object/macho.mbt` 写目标文件；`object/arm64_enc.mbt` 是逐条与 `clang` 对拍过的
编码器；`run_asm/run_asm_stub.c` 提供 MoonBit 自身无法表达的部分
（`mmap`/`mprotect`、临时文件、进程启动、`dlopen`/`dlsym`、调用裸代码地址），
通过类型化 FFI（`run_asm/ffi.mbt`）暴露。

## 路线 A - 借道工具链（回退，`--clang`）

`run_asm/`（仅 native）把 Mach-O 汇编写到临时 `.s`：`--emit obj` 调 `clang -c`；
`--run-asm` 调 `clang -dynamiclib` 再 `dlopen`/`dlsym` 调用。运行期依赖
Xcode/clang，主要作为参照与回退路径保留。

## 验证

    moon test --target native          # 315 个单元/白盒测试
    python tools/check_route_b.py      # 336/336 个可编译 arm64 用例与 clang 逐字节一致

`tools/check_route_b.py` 对 `test/` 下所有非 `_` 开头的用例，把路线 B 的 Mach-O
`__text` 与「clang 汇编路线 A 文本」的结果逐字节比较。其余 70 个用例被冻结版参考
QBE 同样拒绝，没有汇编可比。native 测试还会链接并运行一个路线 B 的目标文件，并
解引用 `$r -> $t` 数据指针以覆盖 `UNSIGNED`。

## 已知限制

- JIT：尚未解析外部符号（libc `printf` 等），`--run-asm` 目前适用于自包含函数。
- 未实现 QBE 可变参数 ABI（vararg 序言会被跳过）。
- `--emit obj` 只写 `__text`/`__data`/`__TEXT,__const`；`__bss` 与
  `__cstring` 合并进 `__data`。

## 运行 wasm（`--run-wasm`）

`qbe --run-wasm FUNC[,ARG]...` 编译到 wasm（`-t wasm` 后端），用
`moon-wasm-opt`（MoonBit 自带的 binaryen）把 WAT 转成模块，再在 `node` 下运行
导出函数。例如：

    qbe --run-wasm add,2,3 demo/01_arith.ssa   # 5

wasm 后端把 QBE 的 CFG 下沉为带 `br_table` 的分发循环，因此循环与 phi 节点可用；
同时支持内部调用/递归、浮点比较与 `data` 数据段。外部导入（`printf` 等）与可变
参数调用尚未发射。

## 测试

    moon test --target native -p run_asm      # FFI、路线 A、路线 B、目标文件链接
    moon test --target native -p object       # 编码器对拍、目标文件布局
    qbe --run-wasm add,2,3 demo/01_arith.ssa  # wasm via node
