///|
// C emitters skip T.assym for quoted symbols: the quotes are part of the name.
pub fn sym_prefix(gassym : String, name : String) -> String {
  if name.length() > 0 && name[0] == '"' {
    ""
  } else {
    gassym
  }
}
