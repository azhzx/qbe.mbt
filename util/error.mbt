///|
/// QbeError - corresponds to die_() in util.c
pub(all) suberror QbeError {
  ParseError(String, Int, String) // file, line, msg
  CompileError(String)
  Ice(String)
} derive(Debug)

///|
/// ParseError constructor with named args
pub fn QbeError::parse_error(
  file~ : String,
  line~ : Int,
  msg~ : String,
) -> QbeError {
  ParseError(file, line, msg)
}
