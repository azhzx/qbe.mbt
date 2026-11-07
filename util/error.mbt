///|
/// QbeError - corresponds to die_() in util.c
#derive(Debug)
pub(all) suberror QbeError {
  ParseError(String, Int32, String) // file, line, msg
  CompileError(String)
  Ice(String)
}
