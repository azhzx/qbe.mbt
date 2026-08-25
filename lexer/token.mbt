///|
// Token kinds for QBE SSA IR
pub(all) enum TokenKind {
  TEof // End of file
  TNl // Newline

  // Identifiers
  TTemp // %name - temporary variable
  TGlo // $name - global symbol
  TLoc // @name - block label
  TTyp // :name - type reference

  // Keywords
  TFunc // function
  TData // data
  TType // type
  TExport // export
  TPhi // phi

  // Jump keywords
  TJmp // jmp
  TJnz // jnz
  TRet // ret (ret0, retw, etc. handled by parser)
  THlt // hlt

  // Opcodes are read as identifiers and matched by the parser
  // using op_from_string

  // Literals
  TInt // Integer literal
  TFlt // Float literal (s_ or d_ prefix)
  TStr // String literal (for data sections)

  // Punctuation
  TEq // =
  TCom // ,
  TLpa // (
  TRpa // )
  TLbr // {
  TRbr // }
  TDot3 // ... (variadic)
  TArrow // -> (for exported data)

  // Raw identifier (opcode or type class, parser decides)
  TId // identifier

  // Error
  TErr // Error token
} derive(Eq, Debug)

///|
// Token struct with position info
pub(all) struct Token {
  kind : TokenKind
  line : Int
  col : Int
  raw : String // Raw text of the token
} derive(Debug)

///|
pub fn Token::new(
  kind : TokenKind,
  line : Int,
  col : Int,
  raw : String,
) -> Token {
  Token::{ kind, line, col, raw }
}

///|
// Get token kind name for error messages
pub fn Token::kind_str(self : Token) -> String {
  match self.kind {
    TEof => "eof"
    TNl => "newline"
    TTemp => "temp"
    TGlo => "global"
    TLoc => "label"
    TTyp => "type"
    TFunc => "function"
    TData => "data"
    TType => "type"
    TExport => "export"
    TPhi => "phi"
    TJmp => "jmp"
    TJnz => "jnz"
    TRet => "ret"
    THlt => "hlt"
    TInt => "int"
    TFlt => "float"
    TStr => "string"
    TEq => "="
    TCom => ","
    TLpa => "("
    TRpa => ")"
    TLbr => "{"
    TRbr => "}"
    TDot3 => "..."
    TArrow => "->"
    TId => "id"
    TErr => "error"
  }
}

///|
// Show implementation for TokenKind (for error messages)
pub impl Show for TokenKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
// Convert TokenKind to string
pub fn TokenKind::to_string(self : TokenKind) -> String {
  match self {
    TEof => "eof"
    TNl => "newline"
    TTemp => "temp"
    TGlo => "global"
    TLoc => "label"
    TTyp => "type"
    TFunc => "function"
    TData => "data"
    TType => "type"
    TExport => "export"
    TPhi => "phi"
    TJmp => "jmp"
    TJnz => "jnz"
    TRet => "ret"
    THlt => "hlt"
    TInt => "int"
    TFlt => "float"
    TStr => "string"
    TEq => "="
    TCom => ","
    TLpa => "("
    TRpa => ")"
    TLbr => "{"
    TRbr => "}"
    TDot3 => "..."
    TArrow => "->"
    TId => "id"
    TErr => "error"
  }
}
