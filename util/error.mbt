///|
/// QbeError - corresponds to die_() in util.c
pub(all) suberror QbeError {
  ParseError(String, Int32, String) // file, line, msg
  CompileError(String)
  Ice(String)
} derive(Debug)
