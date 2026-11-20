///|
// QBE SSA IR Parser
// Parses a token stream from the lexer into QBE IR data structures.

///|
// Parser state - holds tokens and current position
pub struct Parser {
  tokens : Array[@lexer.Token]
  source_file : String
  mut pos : Int32
  mut line : Int32
  // Collected output
  funcs : Array[@types.Fn]
  datas : Array[@types.Dat]
  typs : Array[@types.Typ]
  // Top-level section order: "f" for function, "d" for data (the C emits in
  // input order)
  order : Array[String]
  // String interner for symbol labels
  interner : @util.Interner
  // Current function being parsed (None outside function)
  mut curfn : @types.Fn?
  // Current block id being parsed (-1 if none)
  mut curblk : Int32
  // Return class index (0=Jretw, 1=Jretl, 2=Jrets, 3=Jretd, 4=Jretc, 5=Jret0)
  mut rcls : Int32
  // Parameter instructions (Par/Parc/Pare), to be prepended to start block
  par_ins : Array[@types.Ins]
  // Instructions currently in the open block, counted the way the reference's
  // shared insb[] buffer is (C parse.c `curi - insb`). Used for the NIns
  // "too many instructions" limit. The start block begins with the staged
  // parameter instructions.
  mut blk_nins : Int32
}

///|
// C struct Lnk: linkage information collected by parselnk.
priv struct Linkage {
  mut is_export : Bool
  mut thread : Bool
  mut common : Bool
  mut align : Int32
  mut sec : String
  mut secf : String
}

///|
fn Linkage::new() -> Linkage {
  Linkage::{
    is_export: false,
    thread: false,
    common: false,
    align: 0,
    sec: "",
    secf: "",
  }
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
    funcs: [],
    datas: [],
    typs: [],
    order: [],
    interner: @util.Interner::new(),
    curfn: None,
    curblk: -1,
    rcls: 0,
    par_ins: [],
    blk_nins: 0,
  }
}

///|
// Get current token (without advancing). The C parser's lex() returns Teof for
// every read past the end of the input, so reads are clamped to the trailing
// TEof token instead of running off the token array.
fn Parser::peek(self : Self) -> @lexer.Token {
  if self.pos >= self.tokens.length() {
    self.tokens[self.tokens.length() - 1]
  } else {
    self.tokens[self.pos]
  }
}

///|
// Get current token kind
fn Parser::peek_kind(self : Self) -> @lexer.TokenKind {
  self.peek().kind
}

///|
// Get current token and advance (C parse.c next). The lexer appends one TEof
// token, and the C lexer keeps returning Teof forever at end of input, so the
// position stops on the trailing TEof rather than advancing past the array.
fn Parser::next(self : Self) -> @lexer.Token {
  let t = self.peek()
  if self.pos < self.tokens.length() {
    self.pos = self.pos + 1
  }
  if t.kind == TNl {
    self.line = self.line + 1
  }
  t
}

///|
// Get current token kind and advance
fn Parser::next_kind(self : Self) -> @lexer.TokenKind {
  let t = self.next()
  t.kind
}

///|
// Advance past newlines, return the first non-newline token kind
fn Parser::next_nl(self : Self) -> @lexer.TokenKind {
  let mut k = self.next_kind()
  while k == TNl {
    k = self.next_kind()
  }
  k
}

///|
// Expect a specific token kind, error if not
fn Parser::expect(self : Self, expected : @lexer.TokenKind) -> Unit raise {
  let t = self.next()
  if t.kind != expected {
    raise @util.QbeError::ParseError(
      self.source_file,
      t.line,
      "\{tok_display(expected)} expected, got \{tok_display(t.kind)} instead",
    )
  }
}

///|
// Token display name used by expect(), mirroring vendor/qbe parse.c ttoa[]:
// only these tokens have names, every other token renders as "??".
fn tok_display(k : @lexer.TokenKind) -> String {
  match k {
    TLoc => "label"
    TCom => ","
    TEq => "="
    TNl => "newline"
    TLpa => "("
    TRpa => ")"
    TLbr => "{"
    TRbr => "}"
    _ => "??"
  }
}

///|
// Report a parse error
fn Parser::error(self : Self, msg : String) -> @util.QbeError {
  @util.QbeError::ParseError(self.source_file, self.line, msg)
}

///|
// Get the current function (must be inside function parsing)
fn Parser::curfn(self : Self) -> @types.Fn raise {
  match self.curfn {
    Some(fn_) => fn_
    None => raise @util.QbeError::Ice("no current function")
  }
}

///|
// Get the interner (for symbol name resolution in printfn)
pub fn Parser::interner_ref(self : Self) -> @util.Interner {
  self.interner
}
