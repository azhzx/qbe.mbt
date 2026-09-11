# `lexer` 包接口介绍

包路径: `azhzx/qbe/lexer`

将 QBE IL 文本切分为 token 序列，供 `parser` 包使用。对应 QBE 原项目的 `lex.c`。

## `Lexer`

```moonbit
pub struct Lexer {
  source : String
  source_file : String
  tokens : Array[Token]
  err_msgs : Array[String]
}

pub fn Lexer::new(source : String, source_file : String) -> Self
pub fn Lexer::tokenize(Self) -> Array[Token]
```

典型用法：

```moonbit
let lexer = @lexer.Lexer::new(source_text, "file.ssa")
let tokens = lexer.tokenize()
```

错误会写入 `err_msgs` 而非抛出异常，便于一次扫描多个错误。

## `Token`

```moonbit
pub(all) struct Token {
  kind : TokenKind
  line : Int
  col : Int
  raw : String
}

pub fn Token::new(TokenKind, Int, Int, String) -> Token
pub fn Token::is_id(Self) -> Bool       // 是否为标识符类 token
pub fn Token::kind_str(Self) -> String  // 文本表示
```

每个 token 记录其在源文件中的位置（line/col），便于 parser 报错定位。

## `TokenKind`

```moonbit
pub(all) enum TokenKind {
  TEof          // 文件结束
  TNl           // 换行
  TTemp         // %tmp   临时变量
  TGlo          // $glo   全局符号
  TLoc          // :loc   类型/标签
  TTyp          // :typ   聚合类型引用
  TFunc         // $func  函数名
  TData         // $data  数据段名
  TType         // type   关键字
  TExport       // export 关键字
  TPhi          // phi   关键字
  TJmp          // jmp   关键字
  TJnz          // jnz   关键字
  TRet          // ret   关键字
  THlt          // hlt   关键字
  TInt          // 整数字面量
  TFlt          // 浮点字面量 (1.5, d_2.0, s_0.5)
  TStr          // 字符串字面量 "..."
  TEq           // =
  TCom          // ,
  TLpa          // (
  TRpa          // )
  TLbr          // {
  TRbr          // }
  TDot3         // ...
  TArrow        // ->
  TId           // 一般标识符 (操作码、类型名)
  TErr          // 非法字符
}
```

枚举 `TokenKind::to_string(Self) -> String` 返回文本形式，并实现了 `Show`。

## 与其他包的关系

`lexer` 仅依赖 `moonbitlang/core/debug`（用于 `Debug`），输出 `Array[Token]` 给 `parser` 包消费。
