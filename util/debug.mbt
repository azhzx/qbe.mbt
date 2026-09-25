///|
// DWARF line-table file/location directives (C emit.c emitdbgfile/emitdbgloc).
//
// `.file` and `.loc` are assembler directives: the assembler turns them into a
// DWARF .debug_line section, which is what a debugger uses for source-level
// breakpoints and stepping. The state mirrors emit.c's static nfile/curfile/
// file[] and is reset for every module compile.

///|
let dbg_nfile : Array[Int] = Array::make(1, 0)

///|
let dbg_curfile : Array[Int] = Array::make(1, 0)

///|
let dbg_paths : Array[String] = []

///|
// Whether the DWARF extensions (CFI, .debug_info) are enabled. Off by
// default so plain output stays byte-identical to the reference; the CLI's
// -g/--debug-info sets it.
let dbg_info_on : Array[Bool] = Array::make(1, false)

///|
// Enable or disable the DWARF debug-info extensions.
pub fn set_debug_info(on : Bool) -> Unit {
  dbg_info_on[0] = on
}

///|
// True when DWARF debug-info extensions are enabled.
pub fn debug_info() -> Bool {
  dbg_info_on[0]
}

///|
// Reset the file table (called once per module compile).
pub fn dbg_reset() -> Unit {
  dbg_nfile[0] = 0
  dbg_curfile[0] = 0
}

///|
// C emit.c emitdbgfile: for a path not seen before emit `.file <n> \"<path>\"`
// and set the current file number; existing paths only update curfile.
pub fn emit_dbgfile(path : String, sb : StringBuilder) -> Unit {
  let n = dbg_nfile[0]
  for i in 0..<n {
    if dbg_paths[i] == path {
      // gas requires positive file numbers.
      dbg_curfile[0] = i + 1
      return
    }
  }
  if dbg_paths.length() > n {
    dbg_paths[n] = path
  } else {
    dbg_paths.push(path)
  }
  dbg_nfile[0] = n + 1
  dbg_curfile[0] = n + 1
  sb.write_string(".file ")
  sb.write_string(dbg_curfile[0].to_string())
  sb.write_string(" \"")
  sb.write_string(path)
  sb.write_string("\"\n")
}

///|
// C emit.c emitdbgloc: emit `\t.loc <curfile> <line>[ <col>]`.
pub fn emit_dbgloc(line : Int, col : Int, sb : StringBuilder) -> Unit {
  sb.write_string("\t.loc ")
  sb.write_string(dbg_curfile[0].to_string())
  sb.write_char(' ')
  sb.write_string(line.to_string())
  if col != 0 {
    sb.write_char(' ')
    sb.write_string(col.to_string())
  }
  sb.write_char('\n')
}
