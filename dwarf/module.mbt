///|
// DWARF4 compilation-unit writer for debug info declared through the
// programmatic builder (and the C ABI / Rust crate).
//
// The line table itself comes from the assembler (.file/.loc); this module
// adds the .debug_info tree (compile unit, subprograms, variables, base types)
// and a .debug_loc list with the location of each variable, so `frame
// variable` works. Locations are resolved after register allocation: a value
// in a register uses DW_OP_regx, one in a stack slot uses DW_OP_fbreg.

///|
// A resolved variable location.
pub(all) struct DbgLoc {
  name : String
  ty : @types.DbgType
  kind : Int // 0 = register, 1 = frame-base relative (fbreg)
  value : Int // DWARF register number, or frame-base offset
} derive(Debug)

///|
// Entry
struct DbgFn {
  name : String
  start_label : String
  end_label : String
  locs : Array[DbgLoc]
}

///|
let dbg_fns : Array[Array[DbgFn]] = [[]]

///|
pub fn reset() -> Unit {
  dbg_fns[0] = []
}

///|
pub fn has_info() -> Bool {
  dbg_fns[0].length() > 0
}

///|
pub fn record_fn(
  name : String,
  start_label : String,
  end_label : String,
  locs : Array[DbgLoc],
) -> Unit {
  dbg_fns[0].push(DbgFn::{ name, start_label, end_label, locs, })
}

///|
fn uleb(v : Int) -> Array[Int] {
  let out : Array[Int] = []
  let mut x = v
  while true {
    let b = x & 0x7F
    x = x >> 7
    if x == 0 {
      out.push(b)
      break
    } else {
      out.push(b | 0x80)
    }
  }
  out
}

///|
fn sleb(v : Int) -> Array[Int] {
  let out : Array[Int] = []
  let mut x = v
  let mut more = true
  while more {
    let b = x & 0x7F
    x = x >> 7
    if (x == 0 && (b & 0x40) == 0) || (x == -1 && (b & 0x40) != 0) {
      out.push(b)
      more = false
    } else {
      out.push(b | 0x80)
    }
  }
  out
}

///|
fn loc_expr(loc : DbgLoc) -> Array[Int] {
  let out : Array[Int] = []
  if loc.kind == 0 {
    out.push(0x90) // DW_OP_regx
    for b in uleb(loc.value) {
      out.push(b)
    }
  } else {
    out.push(0x91) // DW_OP_fbreg
    for b in sleb(loc.value) {
      out.push(b)
    }
  }
  out
}

///|
fn emit_bytes(sb : StringBuilder, bs : Array[Int]) -> Unit {
  for b in bs {
    sb.write_string("\t.byte ")
    sb.write_string(b.to_string())
    sb.write_char('\n')
  }
}

///|
fn type_off_for(m : Map[String, Int], ty : @types.DbgType) -> Int {
  match ty {
    @types.DbgW => m["w"]
    @types.DbgL => m["l"]
    @types.DbgS => m["s"]
    @types.DbgD => m["d"]
    @types.DbgPtr => m["ptr"]
    @types.DbgAgg(n, _) => m["agg:" + n]
  }
}

///|
// Emit .debug_info and .debug_loc for the recorded functions. `text_label`
// marks the end of .text (the compilation unit range).
pub fn emit_debug_info(
  gasloc : String,
  cu_name : String,
  comp_dir : String,
  apple : Bool,
  sb : StringBuilder,
) -> Unit {
  let fns = dbg_fns[0]
  if fns.length() == 0 {
    return
  }
  let producer = "qbe.mbt"
  let text_label = gasloc + "dbgend"
  let cu_low = fns[0].start_label
  // Distinct aggregate names, and whether any pointer type is needed.
  let aggs : Array[String] = []
  let mut uses_ptr = false
  for f in fns {
    for l in f.locs {
      match l.ty {
        @types.DbgPtr => uses_ptr = true
        @types.DbgAgg(n, _) => if !aggs.contains(n) { aggs.push(n) }
        _ => ()
      }
    }
  }
  // DIE offsets (relative to the start of .debug_info).
  let tmap : Map[String, Int] = Map([], capacity=8)
  let mut off = 11 // unit header without its length field
  off = off +
    (
      1 +
      producer.length() +
      1 +
      2 +
      cu_name.length() +
      1 +
      comp_dir.length() +
      1 +
      8 +
      8 +
      4
    )
  let base_names = ["int", "long int", "float", "double"]
  let base_keys = ["w", "l", "s", "d"]
  let base_sizes = [4, 8, 4, 8]
  let base_enc = [5, 5, 4, 4]
  for i in 0..<4 {
    tmap[base_keys[i]] = off
    off = off + 1 + base_names[i].length() + 1 + 1 + 1
  }
  if uses_ptr {
    tmap["ptr"] = off
    off = off + 1
  }
  for n in aggs {
    tmap["agg:" + n] = off
    off = off + 1 + n.length() + 1 + 1
  }
  let sub_off : Array[Int] = []
  for f in fns {
    sub_off.push(off)
    off = off + 1 + (f.name.length() + 1) + 8 + 8 + 2
    for l in f.locs {
      off = off + 1 + (l.name.length() + 1) + 4 + 4
    }
    off = off + 1
  }
  off = off + 1
  let unit_len = off - 4
  // .debug_loc offsets (one range per variable, in emission order).
  let loc_offs : Array[Int] = []
  let mut lo = 0
  for f in fns {
    for l in f.locs {
      loc_offs.push(lo)
      let e = loc_expr(l)
      // DWARF4 .debug_loc entries use a 2-byte expression length.
      lo = lo + 8 + 8 + 2 + e.length()
    }
  }
  // ---- .text end label ----
  sb.write_string(".text\n")
  sb.write_string(text_label)
  sb.write_string(":\n")
  // ---- .debug_abbrev ----
  if apple {
    sb.write_string(".section __DWARF,__debug_abbrev,regular,debug\n")
  } else {
    sb.write_string(".section .debug_abbrev,\"\",@progbits\n")
  }
  emit_bytes(sb, [
    1, 0x11, 1, 0x25, 0x08, 0x13, 0x05, 0x03, 0x08, 0x1b, 0x08, 0x11, 0x01, 0x12,
    0x01, 0x10, 0x17, 0, 0,
  ])
  emit_bytes(sb, [
    2, 0x2e, 1, 0x03, 0x08, 0x11, 0x01, 0x12, 0x01, 0x40, 0x18, 0, 0,
  ])
  emit_bytes(sb, [3, 0x34, 0, 0x03, 0x08, 0x49, 0x13, 0x02, 0x17, 0, 0])
  emit_bytes(sb, [4, 0x24, 0, 0x03, 0x08, 0x0b, 0x0b, 0x3e, 0x0b, 0, 0])
  emit_bytes(sb, [5, 0x0f, 0, 0, 0])
  emit_bytes(sb, [6, 0x13, 0, 0x03, 0x08, 0x0b, 0x0b, 0, 0])
  emit_bytes(sb, [0])
  // ---- .debug_info ----
  if apple {
    sb.write_string(".section __DWARF,__debug_info,regular,debug\n")
  } else {
    sb.write_string(".section .debug_info,\"\",@progbits\n")
  }
  sb.write_string("\t.long " + unit_len.to_string() + "\n")
  sb.write_string("\t.short 4\n\t.long 0\n\t.byte 8\n")
  sb.write_string("\t.byte 0x01\n")
  sb.write_string("\t.asciz \"" + producer + "\"\n")
  sb.write_string("\t.short 12\n")
  sb.write_string("\t.asciz \"" + cu_name + "\"\n")
  sb.write_string("\t.asciz \"" + comp_dir + "\"\n")
  sb.write_string("\t.quad " + cu_low + "\n")
  sb.write_string("\t.quad " + text_label + "\n")
  sb.write_string("\t.long 0\n")
  // base types
  for i in 0..<4 {
    sb.write_string("\t.byte 4\n")
    sb.write_string("\t.asciz \"" + base_names[i] + "\"\n")
    sb.write_string("\t.byte " + base_sizes[i].to_string() + "\n")
    sb.write_string("\t.byte " + base_enc[i].to_string() + "\n")
  }
  if uses_ptr {
    sb.write_string("\t.byte 5\n")
  }
  for n in aggs {
    let mut size = 0
    for f in fns {
      for l in f.locs {
        match l.ty {
          @types.DbgAgg(nn, sz) => if nn == n { size = sz }
          _ => ()
        }
      }
    }
    sb.write_string("\t.byte 6\n")
    sb.write_string("\t.asciz \"" + n + "\"\n")
    sb.write_string("\t.byte " + size.to_string() + "\n")
  }
  // subprograms + variables
  let mut loc_i = 0
  for f in fns {
    sb.write_string("\t.byte 2\n")
    sb.write_string("\t.asciz \"" + f.name + "\"\n")
    sb.write_string("\t.quad " + f.start_label + "\n")
    sb.write_string("\t.quad " + f.end_label + "\n")
    sb.write_string("\t.byte 1\n\t.byte 0x9c\n") // DW_OP_call_frame_cfa
    for l in f.locs {
      sb.write_string("\t.byte 3\n")
      sb.write_string("\t.asciz \"" + l.name + "\"\n")
      sb.write_string("\t.long " + type_off_for(tmap, l.ty).to_string() + "\n")
      sb.write_string("\t.long " + loc_offs[loc_i].to_string() + "\n")
      loc_i = loc_i + 1
    }
    sb.write_string("\t.byte 0\n")
  }
  sb.write_string("\t.byte 0\n")
  // ---- .debug_loc ----
  if apple {
    sb.write_string(".section __DWARF,__debug_loc,regular,debug\n")
  } else {
    sb.write_string(".section .debug_loc,\"\",@progbits\n")
  }
  for f in fns {
    for l in f.locs {
      sb.write_string("\t.quad " + f.start_label + "\n")
      sb.write_string("\t.quad " + f.end_label + "\n")
      let e = loc_expr(l)
      sb.write_string("\t.short " + e.length().to_string() + "\n")
      emit_bytes(sb, e)
    }
  }
  sb.write_string("\t.quad 0\n\t.quad 0\n")
}
