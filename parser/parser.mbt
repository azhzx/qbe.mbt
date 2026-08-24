///|
// QBE SSA IR Parser
// Parses a token stream from the lexer into QBE IR data structures.

///|
// Parser state - holds tokens and current position
pub struct Parser {
  tokens : Array[@lexer.Token]
  source_file : String
  mut pos : Int
  mut line : Int
  // Collected output
  funcs : Array[@types.Fn]
  datas : Array[@types.Dat]
  typs : Array[@types.Typ]
  // String interner for symbol labels
  interner : @util.Interner
  // Current function being parsed (None outside function)
  mut curfn : @types.Fn?
  // Current block id being parsed (-1 if none)
  mut curblk : Int
  // Return class index (0=Jretw, 1=Jretl, 2=Jrets, 3=Jretd, 4=Jretc, 5=Jret0)
  mut rcls : Int
  // Parameter instructions (Par/Parc/Pare), to be prepended to start block
  par_ins : Array[@types.Ins]
}

///|
pub fn Parser::new(
  tokens : Array[@lexer.Token],
  source_file : String,
) -> Parser {
  Parser::{
    tokens,
    source_file,
    pos: 0,
    line: 1,
    funcs: Array::new(),
    datas: Array::new(),
    typs: Array::new(),
    interner: @util.Interner::new(),
    curfn: None,
    curblk: -1,
    rcls: 0,
    par_ins: Array::new(),
  }
}

///|
// Construct parser from a lexer
pub fn Parser::from_lexer(lex : @lexer.Lexer) -> Parser {
  let tokens = lex.tokenize()
  Parser::new(tokens, lex.source_file)
}

///|
// Get current token (without advancing)
pub fn Parser::peek(self : Self) -> @lexer.Token {
  self.tokens[self.pos]
}

///|
// Get current token kind
pub fn Parser::peek_kind(self : Self) -> @lexer.TokenKind {
  self.tokens[self.pos].kind
}

///|
// Get current token and advance
pub fn Parser::next(self : Self) -> @lexer.Token {
  let t = self.tokens[self.pos]
  self.pos = self.pos + 1
  if t.kind == TNl {
    self.line = self.line + 1
  }
  t
}

///|
// Get current token kind and advance
pub fn Parser::next_kind(self : Self) -> @lexer.TokenKind {
  let t = self.next()
  t.kind
}

///|
// Advance past newlines, return the first non-newline token kind
pub fn Parser::next_nl(self : Self) -> @lexer.TokenKind {
  let mut k = self.next_kind()
  while k == TNl {
    k = self.next_kind()
  }
  k
}

///|
// Advance past newlines, return the first non-newline token
pub fn Parser::next_nl_tok(self : Self) -> @lexer.Token {
  let mut t = self.next()
  while t.kind == TNl {
    t = self.next()
  }
  t
}

///|
// Expect a specific token kind, error if not
pub fn Parser::expect(self : Self, expected : @lexer.TokenKind) -> Unit raise {
  let t = self.next()
  if t.kind != expected {
    raise @util.QbeError::ParseError(
      self.source_file,
      t.line,
      "\{expected} expected, got \{t.kind_str()} instead",
    )
  }
}

///|
// Expect a specific token kind (skip newlines first)
pub fn Parser::expect_nl(
  self : Self,
  expected : @lexer.TokenKind,
) -> Unit raise {
  let k = self.next_nl()
  if k != expected {
    raise @util.QbeError::ParseError(
      self.source_file,
      self.line,
      "\{expected} expected",
    )
  }
}

///|
// Get the raw string of the current token (without advancing)
pub fn Parser::cur_raw(self : Self) -> String {
  self.tokens[self.pos].raw
}

///|
// Report a parse error
pub fn Parser::error(self : Self, msg : String) -> @util.QbeError {
  @util.QbeError::ParseError(self.source_file, self.line, msg)
}

///|
// Get the current function (must be inside function parsing)
pub fn Parser::curfn(self : Self) -> @types.Fn {
  match self.curfn {
    Some(fn_) => fn_
    None => abort("no current function")
  }
}

///|
// Get mutable current function (must be inside function parsing)
pub fn Parser::curfn_mut(self : Self) -> @types.Fn {
  match self.curfn {
    Some(fn_) => fn_
    None => abort("no current function")
  }
}

///|
// Get the interner (for symbol name resolution in printfn)
pub fn Parser::interner_ref(self : Self) -> @util.Interner {
  self.interner
}
