///|
/// QbeError - corresponds to die_() in util.c
pub(all) suberror QbeError {
  ParseError(String, Int, String) // file, line, msg
  CompileError(String)
  Ice(String)
} derive(Debug)
