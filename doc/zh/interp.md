# `interp` 包接口介绍

包路径: `azhzx/qbe/interp`

QBE IL 的 SSA 解释器：直接解释执行解析器输出的 pre-isel IR，作用类似 LLVM
的 `lli` 之于 LLVM IR。值以 64 位原始字承载（`w` 临时按符号扩展、浮点位转
换），语义与 `fold/opfold.mbt` 的常量折叠完全一致。

## 入口

```moonbit
pub fn run_module(
  funcs : Array[@types.Fn],          // 模块内全部函数
  datas : Array[@types.Dat],         // 数据段（布局到内存）
  interner : @util.Interner,         // 符号名驻留器
  entry : String,                    // 入口函数名
  args : Array[InterpValue],         // 位置实参
  max_steps~ : Int = 10_000_000,     // 指令/块步数上限（防死循环）
  max_depth~ : Int = 10_000,         // 调用深度上限
  hook~ : ((String, Array[InterpValue]) -> InterpValue?)? = None,
) -> Result[(InterpValue, String), @util.QbeError]
```

顶层门面 `@qbe.interpret(src, ...)`（async）内部调用 `parse_module` 后委托给
本包。`hook~` 是 LLVM ORC `SymbolResolver` 的对应物：外部调用先询问 hook，
未命中再回落内置运行时，仍未命中报
`QbeError::CompileError("unknown external function ...")`。

**输出缓冲**：内置运行时的文本输出收集到缓冲区，随结果一并返回
（元组第二分量），库保持可移植与无副作用；CLI 将缓冲写到 stdout。

## 值类型

```moonbit
pub(all) enum InterpValue {
  VVoid
  VInt(Int64)
  VFloat(Float)
  VDouble(Double)
} derive(Debug, Eq)
```

`w`/`l` 参数用 `VInt`（`w` 取低 32 位）、`s` 用 `VFloat`、`d` 用 `VDouble`。

## 语义

- **求值**：整数算术按 C QBE 语义——`w` 运算 32 位截断后符号扩展；`udiv`/
  `urem` 的 `w` 形式对零扩展的 32 位操作数做无符号运算；除零报
  `CompileError`。浮点运算为 IEEE 语义，除零得无穷大。
- **内存**：扁平小端稀疏字节内存。数据段基址 `0x10_0000`，堆（malloc）
  基址 `0x80_0000`，栈（`alloc4/8/16`）自 `0x1000_0000_0000` 向下按帧分配，
  帧退出即回收。
- **控制流**：块分发为迭代循环（宿主栈不随解释循环增长）；`phi` 按
  `PhiArg.blk_id` 匹配前驱块。调用是真正的宿主递归，深度受 `max_depth`
  限制。
- **调用**：`Call` 前的连续 `Arg/Argc/Arge` 指令簇构成实参列表；`Argc`
  （聚合体）按地址传递。函数指针为代码区地址（基址 `0x40_0000`），经数据
  段符号引用或指针运算后间接调用。

## 内置运行时

纯 MoonBit 实现（全部后端目标可用），输出经 `@util.iprint`（async）：

| 符号 | 语义 |
| --- | --- |
| `putchar(c)` | 输出字符，返回 `c` |
| `puts(s)` | 输出 NUL 结尾字符串加换行，返回长度+1 |
| `printf(fmt, ...)` | 子集格式化：`%d %i %u %x %c %s %ld %li %lu %lx %f %lf %e %g %%` |
| `malloc(sz)` | 16 字节对齐 bump 分配，零初始化 |
| `free(p)` | no-op（bump 分配器，测试程序安全） |
| `exit(n)` | 终止解释，`run_module` 返回 `Ok(VInt(n))` |

## 限制

- 不支持 `vastart`/`vaarg`（显式报错）。
- 不运行 ABI/指令选择后端——解释的是源语义层 IR。
- `free` 为 no-op；依赖 malloc 复用的程序不适用。
