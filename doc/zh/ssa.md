# `ssa` 包接口介绍

包路径: `azhzx/qbe/ssa`

SSA (静态单赋值) 构造与优化。包含使用链维护、内存优化（memopt）、load 消除（loadopt）、copy 传播（copy）、phi 插入与块重命名、SSA 合法性检查。对应 QBE 原项目的 `ssa.c` / `mem.c` / `load.c` / `copy.c`。

## 使用链 - `filluse`

```moonbit
pub fn filluse(@types.Fn) -> Unit
```

扫描所有 phi/ins/jmp，为每个 `Tmp` 维护 `uses` 列表、`ndef`/`nuse` 计数。CFG 或指令发生任何变化后都需重新调用。对应 C 的 `filluse()`。

## 内存优化 - `memopt`

```moonbit
pub fn memopt(@types.Fn) -> Unit
```

`mem.c` 的对应物。消除冗余的 alloc/load/store（例如把 `load` 一条 alloc 出来的内存替换为对应的 SSA 临时变量）。在 SSA 构造之前调用一次。`-dM` 调试输出会打印 memopt 之后的状态。

## SSA 构造

```moonbit
pub fn phiins(@types.Fn) -> Unit     // 在支配边界处插入 phi 节点
pub fn renblk(@types.Fn) -> Unit      // 块与变量重命名，建立 SSA 形式
pub fn ssacheck(@types.Fn) -> Unit    // 合法性检查（调试断言，发现问题抛 Ice）
```

典型序列：

```moonbit
@cfg.filldom(fn_)
@cfg.fillfron(fn_)
@util.eprint(@live.filllive(fn_, false))   // 预 ABI 活跃分析（不 dump）
@ssa.phiins(fn_)                            // 插 phi
@ssa.renblk(fn_)                            // 重命名
@ssa.filluse(fn_)                           // 重建使用链
@ssa.ssacheck(fn_)                          // 校验
```

## Load 消除 - `loadopt`

```moonbit
pub fn loadopt(@types.Fn, Bool, @util.Interner, Array[@types.Typ]) -> String
```

`load.c` 的对应物。识别可消除的 load（同一基础块内、无介入 store 的同址 load），用前一个 load 的结果替代。`Bool` 参数是 `-dM` 调试开关；当为 `true` 时把 dump 文本作为返回字符串（与 `copy`/`fold` 一致的模式）。

## Copy 传播 - `copy`

```moonbit
pub fn copy(@types.Fn, Bool, @util.Interner, Array[@types.Typ]) -> String
```

`copy.c` 的对应物。识别 `copy` 指令的传递闭包，合并等价临时变量。对应 `-dC` 调试输出。

## 长度查询

```moonbit
pub fn loadsz(@types.Ins) -> Int    // 该 load 指令读取的字节数
pub fn storesz(@types.Ins) -> Int   // 该 store 指令写入的字节数
```

## 辅助

```moonbit
pub fn kcode(@types.Class) -> Int   // 类 -> 硬件编码
pub fn kx() -> Int                  // Kx 类编码
pub fn phicls(Int, Array[@types.Tmp]) -> Int   // 决定 phi 的类
pub fn clsmerge(@ref.Ref[Int], Int) -> Bool     // 类合并辅助
```

## 调试输出约定

`loadopt`、`copy` 都返回 `String`：
- 调试模式 (`Bool = true`)：返回要输出到 stderr 的文本；
- 非调试模式：返回空字符串。

调用方在 [cmd/main/main.mbt](../cmd/main/main.mbt) 中用 `@util.eprint(...)` 输出，所以非调试模式下相当于无操作。

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`
- `moonbitlang/core/ref`（用于 `clsmerge` 的可变引用）
