# `lexer` Package API Reference

Package path: `azhzx/qbe/lexer`

Tokenizes QBE IL text into a token sequence for the `parser` package. Corresponds to `lex.c` in the original QBE project.

[中文版本 (Chinese Version)](zh/lexer.md)

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

Typical usage:

```moonbit
let lexer = @lexer.Lexer::new(source_text, "file.ssa")
let tokens = lexer.tokenize()
```

Errors are written to `err_msgs` rather than thrown as exceptions, allowing multiple errors to be collected in a single scan.

## `Token`

```moonbit
pub(all) struct Token {
  kind : TokenKind
  line : Int
  col : Int
  raw : String
}

pub fn Token::new(TokenKind, Int, Int, String) -> Token
pub fn Token::is_id(Self) -> Bool       // is this an identifier token
pub fn Token::kind_str(Self) -> String  // text representation
```

Each token records its position in the source file (line/col) for error reporting in the parser.

## `TokenKind`

```moonbit
pub(all) enum TokenKind {
  TEof          // end of file
  TNl           // newline
  TTemp         // %tmp   temporary variable
  TGlo          // $glo   global symbol
  TLoc          // :loc   type/label
  TTyp          // :typ   aggregate type reference
  TFunc         // $func  function name
  TData         // $data  data segment name
  TType         // type   keyword
  TExport       // export keyword
  TPhi          // phi   keyword
  TJmp          // jmp   keyword
  TJnz          // jnz   keyword
  TRet          // ret   keyword
  THlt          // hlt   keyword
  TInt          // integer literal
  TFlt          // floating-point literal (1.5, d_2.0, s_0.5)
  TStr          // string literal "..."
  TEq           // =
  TCom          // ,
  TLpa          // (
  TRpa          // )
  TLbr          // {
  TRbr          // }
  TDot3         // ...
  TArrow        // ->
  TId           // general identifier (opcode, type name)
  TErr          // illegal character
}
```

The enum `TokenKind::to_string(Self) -> String` returns the text form and implements `Show`.

## Relationship with Other Packages

`lexer` only depends on `moonbitlang/core/debug` (for `Debug`) and outputs `Array[Token]` for the `parser` package to consume.
