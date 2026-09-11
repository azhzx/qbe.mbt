# `util` 包接口介绍

包路径: `azhzx/qbe/util`

通用工具包，提供错误类型、字符串驻留、格式化与终端输出原语。被几乎所有其他包依赖。

## 错误类型

```moonbit
pub(all) suberror QbeError {
  ParseError(String, Int, String)  // (file, line, msg)
  CompileError(String)              // (msg)
  Ice(String)                       // (msg) - 内部编译器错误
}
```

所有编译阶段通过 `raise` 抛出此错误。`ParseError::parse_error` 构造器使用命名参数 `file~`, `line~`, `msg~`。

## 字符串驻留 - `Interner`

把符号字符串映射为唯一整数 id，便于后续阶段快速比较：

```moonbit
pub struct Interner {
  table : Map[String, Int]
  values : Array[String]
}

pub fn Interner::new() -> Interner
pub fn Interner::intern(Self, String) -> Int   // 驻留字符串，返回 id
pub fn Interner::get(Self, Int) -> String      // 由 id 反查字符串
pub fn Interner::lookup(Self, String) -> Int   // 查询，未驻留返回 -1
```

另有一个**模块级**全局驻留器：

```moonbit
pub fn intern(s : String) -> Int
```

用于生成符号标签（例如浮点常数标签）。

## 输出原语

```moonbit
pub async fn iprint(String) -> Unit  // 输出到 stdout（最终汇编）
pub async fn eprint(String) -> Unit  // 输出到 stderr（调试 dump 与错误）
```

这两个函数是 `async` 的，对应 QBE 的 `printf`/`fprintf(stderr, ...)`。

## 格式化辅助

| 函数 | 用途 |
| --- | --- |
| `fmt_fixed(Double, Int) -> String` | 定点小数格式化（用于浮点常量输出） |
| `lpad(String, Int) -> String` | 左侧填充至指定宽度 |
| `rpad(Int, Int) -> String` | 数字右侧填充 |

## 排序

```moonbit
pub fn qsort_int(Array[Int], Int, Int, (Int, Int) -> Int) -> Unit
```

快速排序，用于按 id 排序临时变量等场景。

## 依赖

- `moonbitlang/core/debug`：用于 `QbeError` 的 `Debug` 实现。
