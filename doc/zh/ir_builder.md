# 程序化 IR 构造器与 C ABI

`ir_builder` 以**程序化**方式构造 QBE IL：不再渲染 `.ssa` 文本再重新解析，
而是直接构造与解析器完全一致的内存 IR（`@types.Fn` / `Blk` / `Ins` / `Phi` /
`Jump` / `Con`），并直接交给后端（`@qbe.compile_ir_object` /
`compile_ir_asm` / `compile_ir_bin_module`）。

`ir_builder_capi`（`pkgtype(kind: "foreign_library")`）通过
[`include/qbe_builder.h`](../include/qbe_builder.h) 中声明的稳定 `qbe_*`
符号集，把该构造器暴露给 C。

## 同一份 IR，已校验

构造器只是一个*前端*，不是第二套编译器。由构造器生成的 IR 所产出的汇编，
与等价 `.ssa` 文本产出的汇编逐字节一致；三个 whitebox 测试分别覆盖算术、
控制流和块参数（phi），通过两条路径编译并比较输出来验证。

## MoonBit 接口

句柄就是普通 `Int`。值句柄 `-1` 表示 "none"。

```moonbit
let b = @ir_builder.Builder::new()

// export function w $add(w %a, w %b) { @start  %r =w add %a, %b  ret %r }
let f = b.add_func("add", @ir_builder.Ret::Word, [@types.Kw, @types.Kw], true)
let a = b.param(f, 0)
let c = b.param(f, 1)
let r = b.arith(f, @types.Add, @types.Kw, a, c)
b.ret(f, r)

// 自包含 Mach-O arm64 目标文件，或汇编文本：
let obj = b.emit_object()
// let asm = b.emit_asm()
```

主要方法：

| 方法 | 含义 |
| --- | --- |
| `add_func(name, ret, params, is_export)` | 定义函数；入口块 `start` 为 `params` 中每个 class 生成一条 `Par`。返回函数 id。 |
| `param(fid, i)` | 第 `i` 个参数的值句柄。 |
| `add_block(fid, label)` / `switch_to(fid, bid)` | 定义 / 选择基本块。 |
| `block_param(fid, bid, cls)` | 块参数（块首的 phi）。 |
| `iconst` / `fconst` / `sconst` / `global` | 整数 / double / single / 全局地址常量。 |
| `arith` / `cmp` / `unop` | 二元 ALU、比较（结果为 w）、扩展/截断。 |
| `load` / `store` | 内存访问。 |
| `call(fid, callee, args, ret)` | 直接调用；同时发出 `Arg` 指令。 |
| `jmp(fid, dest, args)` / `jnz(...)` | 分支；`args` 传给目标块参数。 |
| `ret(fid, v)` | 返回。 |
| `emit_ins` / `emit_void` | 通用逃生口：任意 `@types.Op` + 显式 class。 |
| `data_string` / `data_bytes` / `data_ref` | 数据段。 |
| `emit_asm` / `emit_object` / `emit_bin_module` | 编译。（`emit_bin_module` 交给 `run_asm.ExecBlock` 进程内执行。） |

分支实参采用惰性绑定，因此块参数既可以在分支之前、也可以在分支之后声明
（与文本中的 `phi` 行完全一致）。

## C ABI

该 foreign library 为每个操作导出一个符号。字符串以 MoonBit `Bytes`（UTF-8）
跨越边界；头文件基于 `moonbit_make_bytes` 提供 `qbe_cstr`、`qbe_bytes`、
`qbe_params` 辅助函数。class 就是普通整数（`QBE_W`/`QBE_L`/`QBE_S`/`QBE_D`，
`QBE_VOID = -1`）。

```c
#include "qbe_builder.h"

int32_t ps[2] = { QBE_W, QBE_W };
qbe_builder_t b = qbe_builder_new();
qbe_func_t f = qbe_add_func(b, qbe_cstr("add"), QBE_W, /*export=*/1,
                            qbe_params(ps, 2));
qbe_value_t a = qbe_func_param(b, f, 0);
qbe_value_t c = qbe_func_param(b, f, 1);
qbe_value_t r = qbe_emit(b, f, qbe_cstr("add"), QBE_W, QBE_W, a, c);
qbe_ret(b, f, r);
moonbit_bytes_t obj = qbe_emit_object(b);   /* Mach-O arm64，无运行时依赖 */
```

由于 `foreign_library` 不是可执行程序，包内附带一个极小的 `native_stub.c`
提供空 `main`；真正有价值的产物是目标文件
`_build/native/debug/build/ir_builder_capi/__moonbit_link_core__/ir_builder_capi.o`。
它需要链接 MoonBit 运行时：

```sh
cc -I include -I "$HOME/.moon/include" my_prog.c \
   ir_builder_capi.o "$HOME/.moon/lib/libmoonbitrun.o" \
   _build/native/debug/build/libruntime.a -lm "$HOME/.moon/lib/libbacktrace.a"
```

程序启动时、首次调用 `qbe_*` 之前，需调用一次
`moonbit_runtime_init(argc, argv)`，再调用 `moonbit_init()`。

## 冒烟测试

`scripts/build_capi.sh` 会构建该 foreign library，编译
`examples/capi/capi_smoke.c`（通过 C ABI 生成 `add.o` 与 `fib.o`），与
`examples/capi/capi_driver.c` 链接后运行，并校验 `add(20,22) == 42`、
`fib(10) == 55`：

```sh
bash scripts/build_capi.sh
```

`demo/12_builder_capi.c` 是更完整的示例：用 C 构造带两个块参数（phi）的 `$tri`
循环与 `$add`，打印 arm64 汇编，写出 `12_tri.o` / `12_add.o`，并与
`demo/12_builder_capi_driver.c` 链接运行：

```sh
bash scripts/run_builder_demo.sh
# tri(10)=55 add(20,22)=42
```

MoonBit 侧，`moon test --target native ir_builder` 还会在进程内 JIT 由构造器
生成的 `fib`，校验 `fib(10) == 55`、`fib(20) == 6765`。

## 限制

- 目标文件/JIT 仅在 arm64（macOS/aarch64）下可用，与 route B 一致。
- 聚合（`:type`）参数与返回值、可变参数调用、动态 `alloc` 尚未由 C ABI 封装；
  MoonBit 的 `emit_ins` 逃生口仍可表达。
- `finalize` 会就地绑定分支实参，因此一个 `Builder` 在首次 `emit_*` 后即被消耗。