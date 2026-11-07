///|
// Data and linkage emission - a transcription of the reference emit.c
// (emitdat/emitlnk, SecData/SecBss). All GAS text targets share it, as the
// reference does.

///|
// C static int64_t zero in emitdat, plus the current Lnk fields.
let zero : Array[Int64] = [0L]

///|
let name : Array[String] = [""]

///|
let is_export : Array[Bool] = [false]

///|
let is_thread : Array[Bool] = [false]

///|
let is_common : Array[Bool] = [false]

///|
let align : Array[Int32] = [8]

///|
let sec : Array[String] = [""]

///|
let secf : Array[String] = [""]

///|
// Section ids (C enum in emit.c).
const SEC_TEXT : Int32 = 0

///|
const SEC_DATA : Int32 = 1

///|
const SEC_BSS : Int32 = 2

///|
fn sec_of(thread : Bool, s : Int32) -> String {
  if thread {
    match s {
      SEC_DATA => ".section .tdata,\"awT\""
      SEC_BSS => ".section .tbss,\"awT\""
      _ => ".abort \"unreachable\""
    }
  } else {
    match s {
      SEC_TEXT => ".text"
      SEC_DATA => ".data"
      _ => ".bss"
    }
  }
}

///|
fn s64_plus(v : Int64) -> String {
  if v >= 0L {
    "+" + v.to_string()
  } else {
    v.to_string()
  }
}

///|
fn dtoa_of(kind : @types.DatKind) -> String {
  match kind {
    @types.DB => "\t.byte"
    @types.DH => "\t.short"
    @types.DW => "\t.int"
    @types.DL => "\t.quad"
    _ => ""
  }
}

///|
fn dmask(kind : @types.DatKind) -> Int64 {
  match kind {
    @types.DB => 0xffL
    @types.DH => 0xffffL
    @types.DW => 0xffffffffL
    _ => -1L
  }
}

///|
// C emitlnk(n, lnk, s, f).
fn emitlnk(
  n : String,
  gassym : String,
  apple : Bool,
  s : Int32,
  sb : StringBuilder,
) -> Unit {
  let pfx = @util.sym_prefix(gassym, n)
  let mut sfx = ""
  if apple && is_thread[0] {
    sec[0] = "__DATA"
    secf[0] = "__thread_data,thread_local_regular"
    sfx = "$tlv$init"
    sb.write_string(".section __DATA,__thread_vars,thread_local_variables\n")
    sb.write_string("\{pfx}\{n}:\n")
    sb.write_string("\t.quad __tlv_bootstrap\n\t.quad 0\n\t.quad ")
    sb.write_string(pfx + n + sfx + "\n\n")
  }
  if sec[0] != "" {
    // C parse.c stores the Tstr token (including quotes) in Lnk.sec/secf.
    sb.write_string(".section \"\{sec[0]}\"")
    if secf[0] != "" {
      sb.write_string(",\"\{secf[0]}\"")
    }
  } else {
    sb.write_string(sec_of(is_thread[0], s))
  }
  sb.write_string("\n")
  if align[0] != 0 {
    sb.write_string(".balign \{align[0]}\n")
  }
  if is_export[0] {
    sb.write_string(".globl \{pfx}\{n}\n")
  }
  sb.write_string("\{pfx}\{n}\{sfx}:\n")
}

///|
// C emitfnlnk: function labels always use SecText; a function cannot be
// thread, and common is ignored for text.
pub fn emitfnlnk(fn_ : @types.Fn, gassym : String, sb : StringBuilder) -> Unit {
  name[0] = fn_.name
  is_export[0] = fn_.is_export
  is_thread[0] = false
  is_common[0] = false
  align[0] = fn_.align
  sec[0] = fn_.sec
  secf[0] = fn_.secf
  emitlnk(fn_.name, gassym, false, SEC_TEXT, sb)
}

///|
// C emitdat: apply one Dat item to the current data definition.
pub fn emit(
  d : @types.Dat,
  gassym : String,
  apple : Bool,
  sb : StringBuilder,
) -> Unit {
  match d.kind {
    @types.DStart => {
      zero[0] = 0L
      name[0] = ""
      is_export[0] = false
      is_thread[0] = false
      is_common[0] = false
      align[0] = 8
      sec[0] = ""
      secf[0] = ""
    }
    @types.DEnd =>
      if is_common[0] {
        // C: die("invalid common data definition") if data was already emitted.
        if zero[0] == -1L {
          abort("invalid common data definition")
        }
        let p = @util.sym_prefix(gassym, name[0])
        sb.write_string(".comm \{p}\{name[0]},\{zero[0]}")
        if align[0] != 0 {
          sb.write_string(",\{align[0]}")
        }
        sb.write_string("\n")
      } else if zero[0] != -1L {
        emitlnk(name[0], gassym, apple, SEC_BSS, sb)
        sb.write_string("\t.fill \{zero[0]},1,0\n")
      }
    @types.DName => {
      name[0] = d.str
      is_export[0] = d.is_export
      is_thread[0] = d.is_thread
      is_common[0] = d.is_common
      align[0] = d.align
      sec[0] = d.sec
      secf[0] = d.secf
    }
    @types.DAlign => align[0] = d.num.to_int()
    @types.DZ =>
      if zero[0] != -1L {
        zero[0] = zero[0] + d.num
      } else {
        sb.write_string("\t.fill \{d.num},1,0\n")
      }
    _ => {
      if zero[0] != -1L {
        emitlnk(name[0], gassym, apple, SEC_DATA, sb)
        if zero[0] > 0L {
          sb.write_string("\t.fill \{zero[0]},1,0\n")
        }
        zero[0] = -1L
      }
      let dtoa = dtoa_of(d.kind)
      if d.is_str {
        // C: strings are only supported for 'b'.
        if d.kind != @types.DB {
          abort("strings only supported for 'b' currently")
        }
        sb.write_string("\t.ascii \"\{d.str}\"\n")
      } else if d.is_ref {
        let p = @util.sym_prefix(gassym, d.ref_name)
        sb.write_string("\{dtoa} \{p}\{d.ref_name}\{s64_plus(d.ref_offset)}\n")
      } else {
        sb.write_string("\{dtoa} \{(d.num & dmask(d.kind)).to_string()}\n")
      }
    }
  }
}
