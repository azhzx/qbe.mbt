///|
// String interner - intern strings to integer labels
// Corresponds to the string interning in QBE for symbol names
pub struct Interner {
  table : Map[String, Int]
  values : Array[String]
}

///|
pub fn Interner::new() -> Interner {
  Interner::{ table: Map([], capacity=16), values: Array::new() }
}

///|
// Intern a string, returns its unique id
pub fn Interner::intern(self : Self, s : String) -> Int {
  match self.table.get(s) {
    Some(id) => id
    None => {
      let id = self.values.length()
      self.values.push(s)
      self.table[s] = id
      id
    }
  }
}

///|
// Get a string by its interned id
pub fn Interner::get(self : Self, id : Int) -> String {
  self.values[id]
}
