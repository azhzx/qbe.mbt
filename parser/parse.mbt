///|
// Top-level parse entry point
// Parses the entire token stream into functions, data, and types
pub fn Parser::parse(self : Self) -> Unit raise {
  while true {
    let t = self.next_nl()
    match t {
      TEof => break
      TExport => {
        // export function or data
        let t2 = self.next_nl()
        match t2 {
          TFunc => {
            self.order.push("f")
            self.parsefn(true)
          }
          TData => {
            self.order.push("d")
            self.parsedat(true)
          }
          _ => raise self.error("export can only qualify data and function")
        }
      }
      TFunc => {
        self.order.push("f")
        self.parsefn(false)
      }
      TData => {
        self.order.push("d")
        self.parsedat(false)
      }
      TType => self.parsetyp()
      _ => raise self.error("top-level definition expected")
    }
  }
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
