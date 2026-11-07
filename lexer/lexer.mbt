///|
// Lexer for QBE SSA IR
pub struct Lexer {
  source : String
  source_file : String
  tokens : Array[Token]
  err_msgs : Array[String]
}

///|
pub fn Lexer::new(source : String, source_file : String) -> Lexer {
  Lexer::{ source, source_file, tokens: [], err_msgs: [], }
}

///|
fn is_ident_char(c : Char) -> Bool {
  // C parse.c lex(): isalpha(c) || c == '$' || c == '.' || c == '_' || isdigit(c)
  c.is_ascii_alphabetic() ||
  c.is_ascii_digit() ||
  c == '_' ||
  c == '.' ||
  c == '$'
}

///|
// Read an identifier (C parse.c lex, Alpha label): the first character must be
// alphabetic, '.' or '_'; continuation adds digits, '$' and '_'.
fn read_ident(s : StringView) -> (String, StringView) {
  let builder = StringBuilder::StringBuilder()
  let mut rest : StringView = s
  let mut first = true
  for cur = s {
    match cur {
      [c, .. r] => {
        if first {
          if !(c.is_ascii_alphabetic() || c == '.' || c == '_') {
            break
          }
          first = false
        } else if !is_ident_char(c) {
          break
        }
        builder.write_char(c)
        rest = r
        continue r
      }
      [] => break
    }
  }
  (builder.to_string(), rest)
}

///|
fn is_ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_hex_digit(c : Char) -> Bool {
  is_ascii_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn ascii_lower(c : Char) -> Char {
  let n = c.to_int()
  if n >= 65 && n <= 90 {
    (n + 32).unsafe_to_char()
  } else {
    c
  }
}

///|
fn take_while(s : StringView, pred : (Char) -> Bool) -> (String, StringView) {
  let b = StringBuilder::StringBuilder()
  let rest = for cur = s {
    match cur {
      [c, .. r] =>
        if pred(c) {
          b.write_char(c)
          continue r
        } else {
          break cur
        }
      [] => break cur
    }
  }
  (b.to_string(), rest)
}

///|
// Case-insensitive prefix match (for inf/infinity/nan).
fn match_ci(s : StringView, lit : String) -> StringView? {
  let ls = lit.to_array()
  let mut i = 0
  let mut rest : StringView = s
  for cur = s {
    if i >= ls.length() {
      break
    }
    match cur {
      [c, .. r] => {
        if ascii_lower(c) != ascii_lower(ls[i]) {
          return None
        }
        i = i + 1
        rest = r
        continue r
      }
      [] => break
    }
  }
  if i == ls.length() {
    Some(rest)
  } else {
    None
  }
}

///|
// Scan the tail of a C floating literal after the s_/d_ prefix (the text
// fscanf("%f") would accept): optional sign, decimal or hexadecimal mantissa,
// optional exponent, or inf/infinity/nan. Returns the matched text, the rest
// of the input and whether anything was matched.
fn scan_float_tail(s : StringView) -> (String, StringView, Bool) {
  let b = StringBuilder::StringBuilder()
  let mut rest : StringView = s
  match rest {
    ['-' | '+' as c, .. r] => {
      b.write_char(c)
      rest = r
    }
    _ => ()
  }
  // hexadecimal prefix (strtod accepts 0x only when a hex digit follows,
  // possibly after the point)
  let mut hex = false
  match rest {
    ['0', 'x' | 'X' as x, .. r] =>
      match r {
        [c, ..] if is_hex_digit(c) => {
          hex = true
          b.write_char('0')
          b.write_char(x)
          rest = r
        }
        ['.', c, ..] if is_hex_digit(c) => {
          hex = true
          b.write_char('0')
          b.write_char(x)
          rest = r
        }
        _ => ()
      }
    _ => ()
  }
  let mut any = false
  let pred : (Char) -> Bool = if hex { is_hex_digit } else { is_ascii_digit }
  let (d1, r1) = take_while(rest, pred)
  if d1.length() > 0 {
    b.write_string(d1)
    any = true
    rest = r1
  }
  // fraction
  match rest {
    ['.', .. r] => {
      let (d2, r2) = take_while(r, pred)
      if d2.length() > 0 || any {
        b.write_char('.')
        b.write_string(d2)
        rest = r2
        if d2.length() > 0 {
          any = true
        }
      }
    }
    _ => ()
  }
  // inf / infinity / nan (decimal only)
  if !any && !hex {
    let mut matched = false
    match match_ci(rest, "infinity") {
      Some(r) => {
        b.write_string("infinity")
        rest = r
        matched = true
      }
      None => ()
    }
    if !matched {
      match match_ci(rest, "inf") {
        Some(r) => {
          b.write_string("inf")
          rest = r
          matched = true
        }
        None => ()
      }
    }
    if !matched {
      match match_ci(rest, "nan") {
        Some(r) => {
          b.write_string("nan")
          rest = r
          matched = true
        }
        None => ()
      }
    }
    any = matched
  }
  // exponent: 'p' for hexadecimal, 'e' otherwise; only consumed when digits
  // (with an optional sign) follow.
  let exp_char = if hex { 'p' } else { 'e' }
  match rest {
    [c, .. r] if ascii_lower(c) == exp_char => {
      let eb = StringBuilder::StringBuilder()
      let mut rr = r
      match rr {
        ['-' | '+' as sc, .. r2] => {
          eb.write_char(sc)
          rr = r2
        }
        _ => ()
      }
      let (ed, r3) = take_while(rr, is_ascii_digit)
      if ed.length() > 0 {
        b.write_char(c)
        b.write_string(eb.to_string())
        b.write_string(ed)
        rest = r3
      }
    }
    _ => ()
  }
  (b.to_string(), rest, any)
}

///|
// Read an integer (C parse.c lex getint): digits only. Bare decimals are not
// floats in QBE IL; float constants are written s_.../d_....
fn read_number(s : StringView) -> (String, StringView) {
  take_while(s, is_ascii_digit)
}

///|
// Read a string literal (between double quotes).
// Escape sequences are kept raw, as the C lexer does (only an unescaped "
// terminates the string).
fn read_string(s : StringView) -> (String, StringView, Bool) {
  let builder = StringBuilder::StringBuilder()
  let mut esc = false
  let mut closed = false
  let mut rest : StringView = s
  for cur = s {
    match cur {
      ['"', .. r] if !esc => {
        rest = r
        closed = true
        break
      }
      [c, .. r] => {
        builder.write_char(c)
        esc = c == '\\' && !esc
        rest = r
        continue r
      }
      [] => break
    }
  }
  (builder.to_string(), rest, closed)
}

///|
// Keyword lookup: returns TokenKind if id is a keyword, else None
fn keyword_of(id : StringView) -> TokenKind? {
  match id {
    "function" => Some(TFunc)
    "data" => Some(TData)
    "type" => Some(TType)
    "export" => Some(TExport)
    "extern" => Some(TExtern)
    "thread" => Some(TThread)
    "common" => Some(TCommon)
    "section" => Some(TSection)
    "dbgfile" => Some(Tdbgfile)
    "phi" => Some(TPhi)
    "jmp" => Some(TJmp)
    "jnz" => Some(TJnz)
    "ret" => Some(TRet)
    "hlt" => Some(THlt)
    _ => None
  }
}

///|
// Main tokenize function
pub fn Lexer::tokenize(self : Self) -> Array[Token] {
  let code : StringView = self.source[:]
  let source_file = self.source_file
  let tokens = self.tokens
  let err_msgs = self.err_msgs
  let mut line = 1
  let mut col = 1
  let mut idx = 0
  for cur = code {
    match cur {
      [] => {
        tokens.push(Token::new(TEof, line, col, ""))
        break
      }

      // Newline
      ['\n', .. rest] => {
        tokens.push(Token::new(TNl, line, col, "\n"))
        line = line + 1
        col = 1
        idx = idx + 1
        continue rest
      }

      // Whitespace
      [' ' | '\t', .. rest] => {
        col = col + 1
        idx = idx + 1
        continue rest
      }

      // Comment (# to end of line)
      ['#', .. rest] => {
        let rest = for c = rest {
          match c {
            ['\n', ..] as r => break r
            [_, .. r2] => {
              col = col + 1
              idx = idx + 1
              continue r2
            }
            [] as r => break r
          }
        }
        continue rest
      }

      // Temporary: %name
      ['%', .. rest] => {
        let (name, r) = read_ident(rest)
        tokens.push(Token::new(TTemp, line, col, name))
        col = col + 1 + name.length()
        idx = idx + 1 + name.length()
        continue r
      }

      // Global: $name or a quoted symbol $"name" (C parse.c lex keeps the
      // quotes as part of the symbol name).
      ['$', .. rest] =>
        match rest {
          ['"', .. inner] => {
            let (text, r, closed) = read_string(inner)
            if !closed {
              tokens.push(Token::new(TErr, line, col, "\""))
              err_msgs.push(
                "unterminated string at \{source_file}:\{line}:\{col}",
              )
              col = col + 1
              idx = idx + 1
              continue inner
            }
            let name = "\"" + text + "\""
            tokens.push(Token::new(TGlo, line, col, name))
            col = col + 3 + text.length()
            idx = idx + 3 + text.length()
            continue r
          }
          _ => {
            let (name, r) = read_ident(rest)
            tokens.push(Token::new(TGlo, line, col, name))
            col = col + 1 + name.length()
            idx = idx + 1 + name.length()
            continue r
          }
        }

      // Block label: @name
      ['@', .. rest] => {
        let (name, r) = read_ident(rest)
        tokens.push(Token::new(TLoc, line, col, name))
        col = col + 1 + name.length()
        idx = idx + 1 + name.length()
        continue r
      }

      // Type reference: :name (only if followed by ident char)
      [':', .. rest] => {
        let (name, r) = read_ident(rest)
        if name.length() > 0 {
          tokens.push(Token::new(TTyp, line, col, name))
          col = col + 1 + name.length()
          idx = idx + 1 + name.length()
          continue r
        }
        // Lone ':' is not valid in QBE IR; emit as error
        tokens.push(Token::new(TErr, line, col, ":"))
        err_msgs.push("unexpected ':' at \{source_file}:\{line}:\{col}")
        col = col + 1
        idx = idx + 1
        continue rest
      }

      // Arrow -> (for exported data)
      [.. "->", .. rest] => {
        tokens.push(Token::new(TArrow, line, col, "->"))
        col = col + 2
        idx = idx + 2
        continue rest
      }

      // Triple dot ...
      [.. "...", .. rest] => {
        tokens.push(Token::new(TDot3, line, col, "..."))
        col = col + 3
        idx = idx + 3
        continue rest
      }

      // Punctuation
      ['+', .. rest] => {
        tokens.push(Token::new(TPlus, line, col, "+"))
        col = col + 1
        idx = idx + 1
        continue rest
      }
      ['=', .. rest] => {
        tokens.push(Token::new(TEq, line, col, "="))
        col = col + 1
        idx = idx + 1
        continue rest
      }
      [',', .. rest] => {
        tokens.push(Token::new(TCom, line, col, ","))
        col = col + 1
        idx = idx + 1
        continue rest
      }
      ['(', .. rest] => {
        tokens.push(Token::new(TLpa, line, col, "("))
        col = col + 1
        idx = idx + 1
        continue rest
      }
      [')', .. rest] => {
        tokens.push(Token::new(TRpa, line, col, ")"))
        col = col + 1
        idx = idx + 1
        continue rest
      }
      ['{', .. rest] => {
        tokens.push(Token::new(TLbr, line, col, "{"))
        col = col + 1
        idx = idx + 1
        continue rest
      }
      ['}', .. rest] => {
        tokens.push(Token::new(TRbr, line, col, "}"))
        col = col + 1
        idx = idx + 1
        continue rest
      }

      // String literal
      ['"', ..] as c => {
        let (str, r, closed) = read_string(c[1:])
        if closed {
          tokens.push(Token::new(TStr, line, col, str))
        } else {
          tokens.push(Token::new(TErr, line, col, str))
          err_msgs.push("unterminated string at \{source_file}:\{line}:\{col}")
        }
        // raw length = 1 (open quote) + str length + 1 (close quote)
        let len = 1 + str.length() + 1
        col = col + len
        idx = idx + len
        continue r
      }

      // Negative number literal
      ['-', '0'..<='9', ..] as c => {
        let (num, r) = read_number(c[1:])
        let raw = "-" + num
        tokens.push(Token::new(TInt, line, col, raw))
        col = col + raw.length()
        idx = idx + raw.length()
        continue r
      }

      // Number literal
      ['0'..<='9', ..] as c => {
        let (num, r) = read_number(c)
        tokens.push(Token::new(TInt, line, col, num))
        col = col + num.length()
        idx = idx + num.length()
        continue r
      }

      // Floating literal: s_... / d_... (C parse.c lex scans these with
      // fscanf("%f")/fscanf("%lf"), accepting signs, exponents and hex floats)
      ['s' | 'd', '_', ..] as c => {
        let prefix = match c {
          [ch, ..] => ch
          _ => 's'
        }
        let (num, r, ok) = scan_float_tail(c[2:])
        if ok {
          let raw = prefix.to_string() + "_" + num
          tokens.push(Token::new(TFlt, line, col, raw))
          col = col + raw.length()
          idx = idx + raw.length()
          continue r
        }
        let (id, r2) = read_ident(c)
        let id_view : StringView = id[:]
        match keyword_of(id_view) {
          Some(kw) => tokens.push(Token::new(kw, line, col, id))
          None => tokens.push(Token::new(TId, line, col, id))
        }
        col = col + id.length()
        idx = idx + id.length()
        continue r2
      }

      // Identifier starting with '.' (C lex allows '.', '_' or alpha there;
      // this is how a bare decimal such as 3.14 is rejected: '3' is an int
      // and '.14' becomes a keyword lookup).
      ['.', ..] as c => {
        let (id, r) = read_ident(c)
        let id_view : StringView = id[:]
        match keyword_of(id_view) {
          Some(kw) => tokens.push(Token::new(kw, line, col, id))
          None => tokens.push(Token::new(TId, line, col, id))
        }
        col = col + id.length()
        idx = idx + id.length()
        continue r
      }

      // Identifier / keyword
      ['a'..<='z' | 'A'..<='Z' | '_', ..] as c => {
        let (id, r) = read_ident(c)
        let id_view : StringView = id[:]
        match keyword_of(id_view) {
          Some(kw) => tokens.push(Token::new(kw, line, col, id))
          None => tokens.push(Token::new(TId, line, col, id))
        }
        col = col + id.length()
        idx = idx + id.length()
        continue r
      }

      // Unknown character
      [c, .. rest] => {
        err_msgs.push(
          "unexpected character '\{c}' at \{source_file}:\{line}:\{col}",
        )
        tokens.push(Token::new(TErr, line, col, c.to_string()))
        col = col + 1
        idx = idx + 1
        continue rest
      }
    }
  }
  tokens
}
