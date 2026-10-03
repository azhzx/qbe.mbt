# QPCC —— C 语言支持

QPCC（`qpcc/`）是把 C 降低到 qbe.mbt IR builder、再从那里降低到 Mach-O arm64
的 C 前端与代码生成器。本页是特性矩阵：它接受并降低哪些内容、哪些是部分支持、
哪些尚缺。

## 证据

- `sh qpcc/test.sh` —— 覆盖 `qpcc/tests/*.c`（134 个 fixture）的 clang oracle：
  每个文件分别用 clang 和 QPCC 编译，链接两个目标文件，运行两个二进制，
  并比较退出码与 stdout。全部 134 个通过。
- `moon test --target native qpcc/front qpcc/sema` —— 词法/语法分析器与语义
  分析器的白盒测试。
- `examples/qpcc-selfhost/` —— QPCC 编译整个 vendored QBE，生成的二进制通过
  58/58 个语义 fixture。
- `qpcc/chibicc-tests/` —— vendored 的 chibicc 子集，作为参考语料保留
  （`test.sh` 不运行）。

下表中的 fixture 列给出覆盖某特性的 oracle 用例；"sweep" 表示手工运行的
端到端检查。

## 模式

| 模式 | 标志 | 说明 |
| --- | --- | --- |
| C11 | 默认，`-std=c11` | 基线 |
| C23 | `-std=c23` | 在同一前端之上启用 C23 语法；部分支持（见下） |
| C2y | `-std=c2y` | 在同一前端之上启用 C2y 语法；见 C2y 小节 |

C 预处理器是**外部的**：当输入使用 `#include`/`#define` 时，在 QPCC 之前运行
`clang -E -P`。驱动只剥离剩余以 `#` 开头的行，因此仅由 `#define` 定义的名字
*不会*被展开。

## 图例

- **是** —— 编译、链接并正确运行。
- **部分** —— 被接受，但缺少某个语义或布局细节。
- **否** —— 被拒绝或不支持。

## 类型

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| `void`、`_Bool` | 是 | `bool` |
| `char`、`signed`/`unsigned char` | 是 | `char`, `uchar` |
| `short`、`int`、`long`、`long long` | 是 | `short`, `longlong`, `arith` |
| 有符号/无符号算术、转换、通常算术转换 | 是 | `unsigned`, `ushr`, `uint_widen`, `shift_signedness`, `op_size` |
| `float`、`double` | 是 | `float`, `float2` |
| `long double`（arm64 上 8 字节） | 是 | sweep |
| `_Complex`（算术、字面量、`__real__`/`__imag__`、混合） | 是 | `complex_add`, `complex_addmix`, `complex_cmp`, `complex_compound`, `complex_div`, `complex_float`, `complex_lit`, `complex_mixed`, `complex_mul`, `complex_real_imag`, `complex_sub`, `complex_unary` |
| `__int128` | 是 | sweep |
| 指针 | 是 | `ptr`, `ptr2`, `ptr_index_diff`, `alias_shape` |
| 数组，包括多维 | 是 | `arr`, `arr_member`, `arr_member_loop`, `static_ptr2d`, `static_ptr2d_b`, `static_ptr2d_c` |
| 变长数组 | 部分 | `sizeof_vec`；索引可用，但 `sizeof` 返回指针/元素大小，而不是运行时长度 |
| 函数与函数指针 | 是 | `fnptr`, `fnptr2`, `fnptr_param` |
| `_BitInt(N)` | 是（C23） | sweep |
| `char8_t` | 是（C23） | `char8_t`；`unsigned char` 的内建名字 |
| `_Decimal*`、`_Fract`、`_Accum` | 否 | — |

## 声明与存储

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| `typedef`、typedef 链 | 是 | `typedef`, `typedefptr`, `typedefstruct`, `bf_typedef` |
| 全局变量、暂定定义、BSS | 是 | `global`, `global2`, `globals`, `bss_zero`, `global_struct`, `global_ptr`, `global_stride`, `global_bitfield` |
| `static` 局部变量与文件作用域 `static` | 是 | `static_ptr`, `static_ptr2d`, `static_desig` |
| `extern` | 是 | `chibicc-tests/tests/extern.c` |
| `const`、`volatile` | 是 | sweep |
| `restrict`（以及 `__restrict`） | 是 | sweep |
| `inline`（以及 `__inline`） | 是 | sweep |
| `register`、`auto` | 是 | sweep |
| `_Thread_local` / `__thread` | 是 | sweep |
| `_Alignas`（局部变量与全局变量） | 是 | `alignas`, `alignas_global` |
| `_Alignof` | 是 | `alignof` |
| `_Noreturn` | 是 | sweep |
| `__attribute__((unused))`、`((noreturn))` | 是 | sweep |
| `__attribute__((packed))` | 部分 | 已解析但被忽略 —— 它不改变 `sizeof` |
| `__attribute__((aligned(N)))` | 部分 | 已解析但被忽略 —— 它不改变对齐 |
| C23 `auto` 推导与 `__auto_type` | 是 | `auto_infer`；单个裸声明符且有初始化器 |
| K&R（旧式）函数定义 | 否 | — |
| 嵌套函数 | 否 | 解析错误 |

## 聚合与布局

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| `struct` | 是 | `struct`, `structarr`, `structptr`, `structsz`, `struct_ptr_index`, `global_struct` |
| `union` | 是 | `union` |
| 匿名的 `struct`/`union` 成员 | 是 | sweep |
| 空的 `struct`/`union`（GNU 扩展，无成员） | 是 | 零大小类型：`sizeof` 为 0、`_Alignof` 为 1 |
| `enum`（显式值、缺口、重复） | 是 | `enum`, `enum_gap`, `shift_enum` |
| C23 `enum E : T` 固定底层类型 | 是 | `enum_fixed`；枚举即其底层整型 |
| 按值传递的结构体参数与返回值、嵌套聚合 | 是 | `ins_byval`, `ref_byval`, `nested`, `aggregate_double` |
| 位域 —— 无符号字段、全局变量、参数 | 是 | `bitfield`, `bitfield_2929`, `bitfield_top`, `bf_arg`, `bf_global`, `bf_pos`, `global_bitfield` |
| 位域 —— 某些有符号组合 | 部分 | `struct { int a:3; int b:2; }` 会误读字段值 |
| 柔性数组成员 | 部分 | `sizeof` 正确，存储由调用方负责 |
| `#pragma pack` | 否 | 预处理器是外部的 |

## 初始化器

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| 标量与聚合初始化器 | 是 | `initarr`, `initstruct`, `compound_char`, `compound_zero` |
| 指定初始化器（数组、结构体、顺序、缺口） | 是 | `designated_dec`, `designated_gap`, `designated_inc`, `designated_int`, `designated_order`, `designated_ptr` |
| 复合字面量，包括文件作用域 | 是 | `file_compound_ptr` |
| 字符串初始化器 | 是 | `str`, `string` |
| 地址常量初始化器与重定位 | 是 | `static_desig`, `global_ptr` |
| 字符串字面量或由字符串初始化的 `char[]` 的 `sizeof` | 部分 | `sizeof("ab")` 是 8，`sizeof(char s[] = "ab")` 是 0，而不是 3 |

## 表达式与运算符

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| 算术、位、比较、逻辑运算符 | 是 | `arith`, `logic`, `op_tab`, `optab_shape` |
| 短路 `&&` / `\|\|` 与 `\|\|` 链 | 是 | `shortcircuit`, `or_short` |
| 条件 `?:`，包括 GNU 的 `a ?: b` | 是 | `cond`, `cond_arm_width` |
| 赋值与复合赋值、`++`/`--` | 是 | sweep |
| 强制转换、整型提升、word/wide 转换 | 是 | `cast`, `widen_word_const`, `store_wide_const`, `uint_widen` |
| 类型、表达式与数组的 `sizeof` | 是 | `sizeof`, `sizeof_ins`, `sizeof_vec`, `op_size` |
| `_Generic` | 是 | `generic`, `generic2` |
| `_Static_assert` | 是 | `staticassert` |
| C2y `_Countof(expr)` / `_Countof(type-name)` | 是 | `countof` |
| C2y `_Maxof(type-name)` / `_Minof(type-name)` | 是 | `maxminof` |
| `__builtin_offsetof`、`__builtin_types_compatible_p`、`__builtin_constant_p`、`__builtin_expect`、`__builtin_unreachable` | 是 | sweep |
| `typeof`/`__typeof__`/`typeof_unqual`、`__alignof__` | 是 | sweep |
| 语句表达式 `({ ... })`，包括在宏内部 | 是 | sweep |
| `__extension__` | 是 | sweep |
| `__real__`、`__imag__` | 是 | `complex_real_imag` |
| `__builtin_va_arg`、`<stdarg.h>` | 是 | `clang -E` 之后；sweep |
| `__builtin_va_list` 作为可赋值的值 | 否 | `aq = ap` 触发内部错误 |
| C23 `auto` 推导与 `__auto_type` | 是 | `auto_infer` |

## 语句与控制流

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| `if`/`else`、`for`、`while`、`do`/`while` | 是 | `if`, `for`, `while`, `dowhile` |
| `switch`/`case`/`default`、贯穿、跳入 `default` | 是 | `switch`, `switchfall`, `switch_into_default`, `switch_duff2` |
| `break`、`continue`、`goto`（向前跳转与循环） | 是 | `gotofwd`, `gotoloop` |
| 计算 goto `goto *p` 与 `&&label` | 是 | `computed_goto` |
| Duff 设备 | 是 | `duff`, `switch_duff2` |
| case 范围 `case 1 ... 5:` | 是 | sweep |
| C2y 命名循环：循环/switch 的 `label:`、`break label;`、`continue label;` | 是 | `named_loops` |
| C2y `_Defer` 语句 | 是 | `defer_basic`、`defer_header` |
| C23 语句位置的 `[[fallthrough]]` | 是 | `fallthrough_attr` |

## 函数

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| 定义、原型、无 K&R 的声明 | 是 | `fib`, `m0_return42`, `three_ref` |
| 变参定义（`va_start`/`va_arg`/`va_end`/`va_copy`） | 是 | `vararg`, `vararg_def` |
| 间接调用 | 是 | `fnptr`, `fnptr2`, `fnptr_param` |
| 内联汇编 / `asm` 标签 | 否 | `asm` 标签会 panic；内联 `asm` 不会被降低 |

## 字面量与字符串

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| 整数字面量（十进制、十六进制、八进制、二进制）、后缀 | 是 | `big_const`, `widen_word_const` |
| 浮点字面量 | 是 | `float`, `float2` |
| 字符字面量、`u8'x'` | 是 | sweep |
| 带转义的字符串字面量 | 部分 | 普通字符串可用；`"a\nb"` 可能解析失败 |
| 宽/UTF 字符串 `L`、`u`、`U` | 否 | 能解析，但运行时元素错误 |
| C23 数字分隔符（`1'000`） | 否 | 解析错误 |

## 原子操作

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| 顺序一致的加载/存储（`ldar`/`stlr`）与屏障（`dmb ish`） | 是 | `atomics` |
| 读-改-写形式（exchange、compare-exchange、fetch-add 等） | 否 | 需要 LL/SC 或 LSE 降低 |

## C23（`-std=c23`）

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| `bool`/`true`/`false`、`nullptr` | 是 | sweep |
| `constexpr` | 是 | `constexpr_assert`；可作为常量表达式中的对象 |
| `_BitInt(N)` | 是 | sweep |
| `typeof_unqual`、`alignas`/`alignof` | 是 | sweep |
| C23 属性 `[[...]]`（`[[maybe_unused]]`、`[[noreturn]]`） | 是 | sweep |
| 针对字面量常量的 `static_assert` | 是 | sweep |
| 二进制字面量 `0b1010`、`u8'x'` | 是 | sweep |
| `auto` 类型推导 | 是 | `auto_infer` |
| `char8_t` | 是 | `char8_t` |
| 数字分隔符（`1'000`） | 是 | `digit_sep` |
| 固定底层类型的 enum（`enum E : unsigned char`） | 是 | `enum_fixed` |
| 语句位置的 `[[fallthrough]]` | 是 | `fallthrough_attr` |

## C2y（`-std=c2y`）

C2y 语法需显式开启 `-std=c2y`；C11 与 C23 行为不变。

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| `_Maxof(type-name)` / `_Minof(type-name)`（N3628） | 是 | `maxminof`；要求整型，`_Bool` 被拒绝，结果是该类型自身的常量 |
| `_Countof(expr)` / `_Countof(type-name)`（N3369） | 是 | `countof`；操作数必须是数组类型 |
| 命名循环（N3355）：循环/switch 前的 `label:`、`break label;`、`continue label;` | 是 | `named_loops` |
| `_Defer` 语句（TS 25755 / N3590） | 是 | `defer_basic`、`defer_header` |

易读拼写来自 `qpcc/include/qbe/` 下的手写头文件：`stddefer.h`
（`defer` -> `_Defer`）、`stdcountof.h`（`countof` -> `_Countof`），以及
QPCC 扩展的 `stdmaxof.h`（`maxof` -> `_Maxof`）与 `stdminof.h`
（`minof` -> `_Minof`）。外部预处理器通过
`clang -E -P -I <qpcc>/qpcc/include/qbe` 找到它们；QPCC 自身只认下划线关键字。

已知限制：

- `_Defer` 在所在块退出时按逆序执行，退出路径包括自然结束、`return`、
  `break`、`continue`、向外 `goto`。会跳出 `_Defer` 语句自身的跳转、以及
  跳入它的 `goto`，都会被诊断；`longjmp` 跨过 defer 是未定义行为（按 TS）。
- clang 尚未实现 `_Maxof`/`_Minof`、命名循环与 `_Defer`，因此这些夹具是
  QPCC-only（`// expect-exit N`），按其预期退出码校验而非与 clang 对照。

## `_Tagged_union`（`-f_tagged_union`）

QPCC 私有扩展，没有 WG14 提案。需显式开启 `-f_tagged_union`；未开启时这三个
关键字只是普通标识符，C11/C23/C2y 行为不变。

```c
_Tagged_union Value {
  int as_int;
  float as_float;
};

_Tagged_union Value x = { .as_int = 100 };
x = (_Tagged_union Value){ .as_float = 1.5f };  /* 同时设置 tag */
switch (_Tag_of(x)) {
  case _Get_tag(_Tagged_union Value, as_int): break;
  case _Get_tag(_Tagged_union Value, as_float): break;
}
```

| 特性 | 状态 | 证据 |
| --- | --- | --- |
| `_Tagged_union Tag { members }` | 是 | `tagged_union` |
| 自然布局：偏移 0 是 `int` tag，成员在其后重叠 | 是 | `{ int; float }` 为 8 字节，`{ int; double }` 为 16 |
| 读 `x.m` | 是 | `tagged_union` |
| `_Tag_of(x)`，`int` 右值 | 是 | `tagged_union` |
| `_Get_tag(_Tagged_union T, m)`，整型常量表达式 | 是 | `tagged_union`（`_Static_assert` 与 `case`） |
| 设计化初始化：局部、复合字面量、全局、静态 | 是 | `tagged_union`、`tagged_union_static` |

语义与限制：

- tag 是偏移 0 的合成 `int`，成员在其后重叠，布局等价于
  `struct { int tag; union { members } payload; }`。
- 不能直接给成员赋值：`x.m = v`、`x.m += v`、`x.m++` 以及对嵌套成员的写入都会
  被诊断。请整体改值，例如 `x = (_Tagged_union T){ .m = v };`，它同时设置 tag。
  判别式按成员声明顺序，从 0 开始。
- 读取 tag 与当前不一致的成员是未定义行为，不做运行时检查。对成员取地址再经
  指针写入同样绕过 tag：`&x.m` 允许，但此时不变量由程序员负责。
- 初始化器必须写出成员名，如 `{ .as_int = 100 }`。位置元素（`{ 1 }`、`{ 0 }`）
  或空列表（`{}`）都会被诊断。多个 designator 时最后者生效（同 union）。
- tagged union 可以用 `_Tagged_union Tag` 命名，也可以用 typedef：tag 是
  可选的，所以 `typedef _Tagged_union { ... } Value;` 定义匿名形式，之后
  `Value` 就代表该类型（`_Get_tag` 同理）。写了 tag 时没有裸的别名。
- clang 完全不支持这些，因此夹具是 QPCC-only（`// expect-exit N`），按预期
  退出码校验。
## 已知缺口一览

- 预处理器是外部的（`clang -E`）；不处理 `#include`/`#define`。
- 字符串字面量或由字符串初始化的 `char[]` 的 `sizeof`。
- VLA 的 `sizeof`。
- 某些有符号位域宽度。
- `__attribute__((packed))` 与 `__attribute__((aligned(N)))` 被忽略。
- 宽/UTF 字符串字面量，某些情况下的字符串转义。
- 原子操作：没有读-改-写。
- `asm` 标签与嵌套函数。
- 诊断信息携带语句级位置。

## 另见

- `qpcc/README.md` —— 流水线、用法与限制。
- `examples/qpcc-selfhost/` —— 自举构建与语义检查。
