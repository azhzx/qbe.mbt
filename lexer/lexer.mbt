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
  Lexer::{ source, source_file, tokens: Array::new(), err_msgs: Array::new() }
}

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c == '.'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
// Read an identifier from a StringView, return (identifier, remaining)
fn read_ident(s : StringView) -> (String, StringView) {
  let builder = StringBuilder::new()
  let mut rest : StringView = s
  // Check if this is a float literal prefix (s_ or d_)
  // Float literals can contain '-' for negative numbers
  let mut is_float_prefix = false
  for cur = s {
    match cur {
      [c, .. r] => {
        if is_ident_char(c) {
          builder.write_char(c)
          rest = r
          // After reading 2 chars, check if it's a float prefix
          if builder.to_string().length() == 2 {
            let s = builder.to_string()
            if s == "s_" || s == "d_" {
              is_float_prefix = true
            }
          }
          continue r
        }
        // For float literals, allow '-' as part of the number
        if is_float_prefix && c == '-' {
          builder.write_char(c)
          rest = r
          continue r
        }
        break
      }
      [] => break
    }
  }
  (builder.to_string(), rest)
}

///|
// Read a number from a StringView, return (raw, is_float, remaining)
fn read_number(s : StringView) -> (String, Bool, StringView) {
  let builder = StringBuilder::new()
  let mut is_float = false
  let mut rest : StringView = s
  for cur = s {
    match cur {
      [c, .. r] => {
        if is_digit(c) {
          builder.write_char(c)
          rest = r
          continue r
        }
        if c == '.' && !is_float {
          is_float = true
          builder.write_char(c)
          rest = r
          continue r
        }
        break
      }
      [] => break
    }
  }
  (builder.to_string(), is_float, rest)
}

///|
// Read a string literal (between double quotes)
// Input s starts after the opening quote
fn read_string(s : StringView) -> (String, StringView) {
  let builder = StringBuilder::new()
  let mut rest : StringView = s
  for cur = s {
    match cur {
      ['"', .. r] => {
        rest = r
        break
      }
      [.. "\\n", .. r] => {
        builder.write_char('\n')
        rest = r
        continue r
      }
      [.. "\\t", .. r] => {
        builder.write_char('\t')
        rest = r
        continue r
      }
      [.. "\\r", .. r] => {
        builder.write_char('\r')
        rest = r
        continue r
      }
      [.. "\\0", .. r] => {
        builder.write_char('\u0000')
        rest = r
        continue r
      }
      [.. "\\\"", .. r] => {
        builder.write_char('"')
        rest = r
        continue r
      }
      [.. "\\\\", .. r] => {
        builder.write_char('\\')
        rest = r
        continue r
      }
      ['\n', .. r] => {
        // Unterminated string literal
        rest = r
        break
      }
      [c, .. r] => {
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
// Check if an identifier is a float literal (starts with s_ or d_)
fn is_float_literal(id : StringView) -> Bool {
  match id {
    [.. "s_", ..] => true
    [.. "d_", ..] => true
    _ => false
  }
}

///|
// Keyword lookup: returns TokenKind if id is a keyword, else None
fn keyword_of(id : StringView) -> TokenKind? {
  match id {
    "function" => Some(TFunc)
    "data" => Some(TData)
    "type" => Some(TType)
    "export" => Some(TExport)
    "phi" => Some(TPhi)
    "jmp" => Some(TJmp)
    "jnz" => Some(TJnz)
    "ret" | "ret0" | "retw" | "retl" | "rets" | "retd" | "retc" => Some(TRet)
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
      [' ' | '\t' | '\r', .. rest] => {
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

      // Global: $name
      ['$', .. rest] => {
        let (name, r) = read_ident(rest)
        tokens.push(Token::new(TGlo, line, col, name))
        col = col + 1 + name.length()
        idx = idx + 1 + name.length()
        continue r
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
        let (str, r) = read_string(c[1:])
        tokens.push(Token::new(TStr, line, col, str))
        // raw length = 1 (open quote) + str length + 1 (close quote)
        let len = 1 + str.length() + 1
        col = col + len
        idx = idx + len
        continue r
      }

      // Negative number literal
      ['-', '0'..='9', ..] as c => {
        let (num, is_flt, r) = read_number(c[1:])
        let raw = "-" + num
        let kind = if is_flt { TFlt } else { TInt }
        tokens.push(Token::new(kind, line, col, raw))
        col = col + raw.length()
        idx = idx + raw.length()
        continue r
      }

      // Number literal
      ['0'..='9', ..] as c => {
        let (num, is_flt, r) = read_number(c)
        let kind = if is_flt { TFlt } else { TInt }
        tokens.push(Token::new(kind, line, col, num))
        col = col + num.length()
        idx = idx + num.length()
        continue r
      }

      // Identifier / keyword / float literal
      ['a'..='z' | 'A'..='Z' | '_', ..] as c => {
        let (id, r) = read_ident(c)
        let id_view : StringView = id[:]
        // Check for float literal prefix (s_ or d_)
        if is_float_literal(id_view) {
          tokens.push(Token::new(TFlt, line, col, id))
        } else {
          // Check for keyword
          match keyword_of(id_view) {
            Some(kw) => tokens.push(Token::new(kw, line, col, id))
            None => tokens.push(Token::new(TId, line, col, id))
          }
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
