# `parser` 包接口介绍

包路径: `azhzx/qbe/parser`

将 `lexer` 产出的 token 序列解析为 `types` 包中的 `Fn` / `Dat` / `Typ` 结构。对应 QBE 原项目的 `parse.c`。是编译前端的最后一站，解析后即可交给后端阶段处理。

## `Parser`

```moonbit
pub struct Parser {
  tokens : Array[@lexer.Token]
  source_file : String
  mut pos : Int
  mut line : Int
  funcs : Array[@types.Fn]
  datas : Array[@types.Dat]
  typs : Array[@types.Typ]
  order : Array[String]      // 顶层定义顺序 ("f" 函数 / "d" 数据)
  interner : @util.Interner
  mut curfn : @types.Fn?
  mut curblk : Int
  mut rcls : Int
  par_ins : Array[@types.Ins]
}
```

构造与入口：

```moonbit
pub fn Parser::new(Array[@lexer.Token], String) -> Self
pub fn Parser::from_lexer(@lexer.Lexer) -> Self   // 一步到位
pub fn Parser::parse(Self) -> Unit raise          // 解析整个文件
```

解析结果取出：

```moonbit
pub fn Parser::get_funcs(Self) -> Array[@types.Fn]
pub fn Parser::get_datas(Self) -> Array[@types.Dat]
pub fn Parser::get_typs(Self) -> Array[@types.Typ]
pub fn Parser::get_order(Self) -> Array[String]
pub fn Parser::interner_ref(Self) -> @util.Interner
```

典型用法（参考 [cmd/main/main.mbt](../cmd/main/main.mbt)）：

```moonbit
let lexer = @lexer.Lexer::new(source, file)
let tokens = lexer.tokenize()
let parser = @parser.Parser::new(tokens, file)
parser.parse()
let funcs = parser.get_funcs()
let datas = parser.get_datas()
let order = parser.get_order()
let typs = parser.get_typs()
let interner = parser.interner_ref()
```

## token 游标

| 方法 | 用途 |
| --- | --- |
| `peek(Self) -> @lexer.Token` | 看下一个但不消费 |
| `peek_kind(Self) -> @lexer.TokenKind` | 仅看类型 |
| `next(Self) -> @lexer.Token` | 消费并返回下一个 |
| `next_kind(Self) -> @lexer.TokenKind` | 消费并返回类型 |
| `next_nl(Self) -> @lexer.TokenKind` | 跨过换行消费 |
| `next_nl_tok(Self) -> @lexer.Token` | 同上但返回 token |
| `cur_raw(Self) -> String` | 当前 token 原始文本 |
| `expect(Self, @lexer.TokenKind) -> Unit raise` | 期望某类型，否则报错 |
| `expect_nl(Self, @lexer.TokenKind) -> Unit raise` | 期望并允许换行 |

## 上下文访问

```moonbit
pub fn Parser::curfn(Self) -> @types.Fn            // 当前正在解析的函数（不可变）
pub fn Parser::curfn_mut(Self) -> @types.Fn       // 当前函数（可变）
pub fn Parser::findblk(Self, String) -> Int       // 当前函数中按名查块
pub fn Parser::findtyp(Self, String) -> Int raise  // 按名查类型，未找到则 raise
pub fn Parser::tmpref(Self, String) -> @types.Ref  // 取/创建临时变量引用
pub fn Parser::error(Self, String) -> @util.QbeError
```

## 子解析器

```moonbit
pub fn Parser::parse(Self) -> Unit raise                              // 顶层
pub fn Parser::parsefn(Self, Bool) -> Unit raise                     // 函数
pub fn Parser::parsedat(Self, Bool) -> Unit raise                    // 数据段
pub fn Parser::parsetyp(Self) -> Unit raise                          // 类型定义
pub fn Parser::parseline(Self, PState) -> PState raise                // 函数体一行
pub fn Parser::parsecls(Self) -> (@types.Class, Int) raise           // 类型类
pub fn Parser::parsefields(Self, @types.Typ, @lexer.TokenKind) -> Unit raise
pub fn Parser::parseref(Self) -> @types.Ref raise                    // 操作数引用
pub fn Parser::parserefl(Self, Bool) -> Bool raise                   // 带括号的引用列表
```

`PState` 是包私有枚举，用于在 `parseline` 间传递状态（在指令行与 phi 行之间切换）。

## IL 打印（回写）

```moonbit
pub fn printfn(@types.Fn, @util.Interner, Array[@types.Typ]) -> String
pub fn printref(@types.Ref, @types.Fn, @util.Interner, StringBuilder, Array[@types.Typ]) -> Unit
pub fn jtoa(@types.JumpKind) -> String
```

`printfn` 把 `Fn` 重新渲染为 QBE IL 文本，用于 `-dP`/`-dM`/`-dN`/`-dC` 等调试 dump。

## 依赖

- `azhzx/qbe/lexer`
- `azhzx/qbe/types`
- `azhzx/qbe/util`
