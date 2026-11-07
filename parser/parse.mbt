///|
// Top-level parse entry point
// Parses the entire token stream into functions, data, and types
pub fn Parser::parse(self : Self) -> Unit raise {
  while true {
    let lnk = Linkage::new()
    let t = self.parselnk(lnk)
    match t {
      TFunc => {
        lnk.align = 16
        self.order.push("f")
        self.parsefn(lnk)
      }
      TData => {
        self.order.push("d")
        self.parsedat(lnk)
      }
      TType => self.parsetyp()
      Tdbgfile => {
        // Debug file marker. The path is recorded in top-level order so the
        // emitter can emit .file <n> <path> at this point in the output.
        self.expect(TStr)
        self.order.push("dbgfile:" + self.tokens[self.pos - 1].raw)
      }
      TEof => break
      _ => raise self.error("top-level definition expected")
    }
  }
}

///|
// C parse.c parselnk: collect linkage keywords before a top-level definition.
fn Parser::parselnk(self : Self, lnk : Linkage) -> @lexer.TokenKind raise {
  let mut haslnk = false
  let mut result = @lexer.TEof
  let mut go = true
  while go {
    let t = self.next_nl()
    match t {
      TExport => lnk.is_export = true
      TThread => lnk.thread = true
      TCommon => lnk.common = true
      TSection => {
        if lnk.sec != "" {
          raise self.error("only one section allowed")
        }
        if self.next().kind != @lexer.TStr {
          raise self.error("section name expected")
        }
        lnk.sec = self.tokens[self.pos - 1].raw
        if self.peek_kind() == @lexer.TStr {
          let _ = self.next()
          lnk.secf = self.tokens[self.pos - 1].raw
        }
      }
      _ => {
        if t == TFunc && lnk.thread {
          raise self.error("only data may have thread linkage")
        }
        if haslnk && t != TData && t != TFunc {
          raise self.error("only data and function have linkage")
        }
        result = t
        go = false
      }
    }
    haslnk = true
  }
  result
}

///|
// The top-level section order: "f" for a function, "d" for a data section.
pub fn Parser::get_order(self : Self) -> Array[String] {
  self.order
}

///|
// Parse result: get all parsed functions
pub fn Parser::get_funcs(self : Self) -> Array[@types.Fn] {
  self.funcs
}

///|
// Parse result: get all parsed data items
pub fn Parser::get_datas(self : Self) -> Array[@types.Dat] {
  self.datas
}

///|
// Parse result: get all parsed types
pub fn Parser::get_typs(self : Self) -> Array[@types.Typ] {
  self.typs
}
