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

///|
// Emit a DWARF4 compilation unit that ties the assembler-generated line table
// to the code, so a debugger can turn an address back into a file/line.
//
// DWARF4, not 5: Apple's lldb rejects version 5. The CU's low/high PC are
// plain DW_FORM_addr values in `.debug_info`, which the linker's debug map
// relocates. A single CU covers [first_fn, end-of-text].
pub fn emit_debug_info(
  gasloc : String,
  gassym : String,
  first_fn : String,
  cu_name : String,
  comp_dir : String,
  apple : Bool,
  sb : StringBuilder,
) -> Unit {
  let producer = "qbe.mbt"
  // .debug_info content length, excluding the leading unit_length: header
  // (version 2 + abbrev_offset 4 + address_size 1) + abbrev(1) + producer +
  // language(2) + name + comp_dir + low_pc(8) + high_pc(8) + stmt_list(4).
  let info_len = 7 +
    1 +
    (producer.length() + 1) +
    2 +
    (cu_name.length() + 1) +
    (comp_dir.length() + 1) +
    8 +
    8 +
    4
  let text_label = gasloc + "dbgend"
  // The end of the code range: the current end of .text.
  sb.write_string(".text\n")
  sb.write_string(text_label)
  sb.write_string(":\n")
  // .debug_abbrev
  if apple {
    sb.write_string(".section __DWARF,__debug_abbrev,regular,debug\n")
  } else {
    sb.write_string(".section .debug_abbrev,\"\",@progbits\n")
  }
  sb.write_string("\t.byte 0x01\n\t.byte 0x11\n\t.byte 0x00\n")
  sb.write_string("\t.byte 0x25\n\t.byte 0x08\n") // producer, string
  sb.write_string("\t.byte 0x13\n\t.byte 0x05\n") // language, data2
  sb.write_string("\t.byte 0x03\n\t.byte 0x08\n") // name, string
  sb.write_string("\t.byte 0x1b\n\t.byte 0x08\n") // comp_dir, string
  sb.write_string("\t.byte 0x11\n\t.byte 0x01\n") // low_pc, addr
  sb.write_string("\t.byte 0x12\n\t.byte 0x01\n") // high_pc, addr
  sb.write_string("\t.byte 0x10\n\t.byte 0x17\n") // stmt_list, sec_offset
  sb.write_string("\t.byte 0x00\n\t.byte 0x00\n\t.byte 0x00\n")
  // .debug_info
  if apple {
    sb.write_string(".section __DWARF,__debug_info,regular,debug\n")
  } else {
    sb.write_string(".section .debug_info,\"\",@progbits\n")
  }
  sb.write_string("\t.long ")
  sb.write_string(info_len.to_string())
  sb.write_char('\n')
  sb.write_string("\t.short 4\n\t.long 0\n\t.byte 8\n")
  sb.write_string("\t.byte 0x01\n")
  sb.write_string("\t.asciz \"")
  sb.write_string(producer)
  sb.write_string("\"\n")
  sb.write_string("\t.short 12\n")
  sb.write_string("\t.asciz \"")
  sb.write_string(cu_name)
  sb.write_string("\"\n")
  sb.write_string("\t.asciz \"")
  sb.write_string(comp_dir)
  sb.write_string("\"\n")
  sb.write_string("\t.quad ")
  sb.write_string(gassym)
  sb.write_string(first_fn)
  sb.write_char('\n')
  sb.write_string("\t.quad ")
  sb.write_string(text_label)
  sb.write_char('\n')
  sb.write_string("\t.long 0\n")
}
