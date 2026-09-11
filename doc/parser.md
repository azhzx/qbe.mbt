# `parser` Package API Reference

Package path: `azhzx/qbe/parser`

Parses the token sequence produced by `lexer` into `Fn`/`Dat`/`Typ` structures from the `types` package. Corresponds to `parse.c` in the original QBE project. This is the last stage of the compilation frontend; after parsing, the result can be handed off to backend phases.

[中文版本 (Chinese Version)](zh/parser.md)

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
  order : Array[String]      // top-level definition order ("f" function / "d" data)
  interner : @util.Interner
  mut curfn : @types.Fn?
  mut curblk : Int
  mut rcls : Int
  par_ins : Array[@types.Ins]
}
```

Construction and entry:

```moonbit
pub fn Parser::new(Array[@lexer.Token], String) -> Self
pub fn Parser::from_lexer(@lexer.Lexer) -> Self   // one-step convenience
pub fn Parser::parse(Self) -> Unit raise          // parse entire file
```

Extracting parse results:

```moonbit
pub fn Parser::get_funcs(Self) -> Array[@types.Fn]
pub fn Parser::get_datas(Self) -> Array[@types.Dat]
pub fn Parser::get_typs(Self) -> Array[@types.Typ]
pub fn Parser::get_order(Self) -> Array[String]
pub fn Parser::interner_ref(Self) -> @util.Interner
```

Typical usage (see [cmd/main/main.mbt](../cmd/main/main.mbt)):

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

## Token Cursor

| Method | Purpose |
| --- | --- |
| `peek(Self) -> @lexer.Token` | Look at next without consuming |
| `peek_kind(Self) -> @lexer.TokenKind` | Look at kind only |
| `next(Self) -> @lexer.Token` | Consume and return next |
| `next_kind(Self) -> @lexer.TokenKind` | Consume and return kind |
| `next_nl(Self) -> @lexer.TokenKind` | Consume across newline |
| `next_nl_tok(Self) -> @lexer.Token` | Same but return token |
| `cur_raw(Self) -> String` | Current token raw text |
| `expect(Self, @lexer.TokenKind) -> Unit raise` | Expect kind, otherwise error |
| `expect_nl(Self, @lexer.TokenKind) -> Unit raise` | Expect with newline allowed |

## Context Access

```moonbit
pub fn Parser::curfn(Self) -> @types.Fn            // current function being parsed (immutable)
pub fn Parser::curfn_mut(Self) -> @types.Fn       // current function (mutable)
pub fn Parser::findblk(Self, String) -> Int       // find block by name in current function
pub fn Parser::findtyp(Self, String) -> Int raise  // find type by name, raise if not found
pub fn Parser::tmpref(Self, String) -> @types.Ref  // get/create temporary variable reference
pub fn Parser::error(Self, String) -> @util.QbeError
```

## Sub-parsers

```moonbit
pub fn Parser::parse(Self) -> Unit raise                              // top-level
pub fn Parser::parsefn(Self, Bool) -> Unit raise                     // function
pub fn Parser::parsedat(Self, Bool) -> Unit raise                    // data segment
pub fn Parser::parsetyp(Self) -> Unit raise                          // type definition
pub fn Parser::parseline(Self, PState) -> PState raise                // function body line
pub fn Parser::parsecls(Self) -> (@types.Class, Int) raise           // type class
pub fn Parser::parsefields(Self, @types.Typ, @lexer.TokenKind) -> Unit raise
pub fn Parser::parseref(Self) -> @types.Ref raise                    // operand reference
pub fn Parser::parserefl(Self, Bool) -> Bool raise                   // parenthesized reference list
```

`PState` is a package-private enum used to pass state between `parseline` calls (switching between instruction lines and phi lines).

## IL Printing (Re-serialization)

```moonbit
pub fn printfn(@types.Fn, @util.Interner, Array[@types.Typ]) -> String
pub fn printref(@types.Ref, @types.Fn, @util.Interner, StringBuilder, Array[@types.Typ]) -> Unit
pub fn jtoa(@types.JumpKind) -> String
```

`printfn` re-renders a `Fn` back to QBE IL text, used for `-dP`/`-dM`/`-dN`/`-dC` debug dumps.

## Dependencies

- `azhzx/qbe/lexer`
- `azhzx/qbe/types`
- `azhzx/qbe/util`
