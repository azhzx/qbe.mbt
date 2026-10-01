///|
// Route B object emission: turn the binary emitter's output into a Mach-O
// object with real relocations (BRANCH26 for calls, PAGE21/PAGEOFF12 for
// global addresses, UNSIGNED for data pointers). This is what lets --emit obj
// stop depending on clang.

///|
fn arm64_obj_bytes(a : Array[Int]) -> Bytes {
  let out : Array[Byte] = []
  for b in a {
    out.push(b.to_byte())
  }
  Bytes::from_array(out[:])
}

///|
// Every relocation target must have a symbol table entry; defined targets point
// at their section, undefined ones (libc calls) are N_UNDF/N_EXT.
fn arm64_obj_sym(
  syms : Array[@object.MachoSym],
  index : Map[String, Int],
  name : String,
  sect : Int,
  value : Int,
  is_ext : Bool,
) -> Int {
  match index.get(name) {
    Some(i) => i
    None => {
      let i = syms.length()
      index[name] = i
      syms.push(@object.MachoSym::{ name: "_" + name, sect, value, is_ext, })
      i
    }
  }
}

///|
pub fn emit_arm64_object(
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
  interner : @util.Interner,
  apple : Bool,
) -> Bytes raise {
  arm64_emit_reset()
  let text_words : Array[Int] = []
  let fns : Array[(String, Int)] = []
  let calls : Array[(Int, String)] = []
  let addrs : Array[(Int, Int, Int, String, Int)] = []
  let defined : Array[String] = []
  for fn_ in funcs {
    defined.push(fn_.name)
  }
  for d in datas {
    defined.push(d.str)
  }
  for fn_ in funcs {
    let (w, c, a) = emit_arm64_bin_fn_ex(fn_, interner, apple, defined)
    let off = text_words.length()
    fns.push((fn_.name, off))
    for x in w {
      text_words.push(x)
    }
    for x in c {
      calls.push((off + x.0, x.1))
    }
    for x in a {
      addrs.push((off + x.0, off + x.1, x.2, x.3, x.4))
    }
  }
  let (datas_map, data_bytes0, data_refs) = arm64_bin_layout_data(datas)
  // Pointer entries are relocatable in an object file: zero the addend and let
  // the linker fill in the address via an UNSIGNED relocation.
  let data_bytes = data_bytes0.copy()

  let syms : Array[@object.MachoSym] = []
  let index : Map[String, Int] = Map([])
  for f in fns {
    let mut is_ext = false
    for fn_ in funcs {
      if fn_.name == f.0 && fn_.is_export {
        is_ext = true
      }
    }
    ignore(arm64_obj_sym(syms, index, f.0, 1, f.1 * 4, is_ext))
  }
  for d in datas_map {
    let mut is_ext = false
    for dt in datas {
      if dt.is_export && dt.str == d.0 {
        is_ext = true
      }
    }
    ignore(arm64_obj_sym(syms, index, d.0, 2, d.1, is_ext))
  }
  // Floating-point constants live in __TEXT,__const as local LfpN symbols.
  let (fp_map, fp_bytes) = arm64_fp_layout()
  for p in fp_map {
    index[p.0] = syms.length()
    syms.push(@object.MachoSym::{
      name: "L" + p.0,
      sect: 3,
      value: p.1,
      is_ext: false,
    })
  }

  let data_relocs : Array[@object.MachoReloc] = []
  for r in data_refs {
    let w = r.2
    // A non-pcrel ARM64_RELOC_UNSIGNED takes its addend from the bytes at the
    // relocation site, so store the symbol-relative offset there.
    let mut v = r.3
    if v < 0 {
      v = v + (1 << (w * 8))
    }
    for i in 0..<w {
      data_bytes[r.0 + i] = (v >> (i * 8)) & 0xFF
    }
    let i = arm64_obj_sym(syms, index, r.1, 0, 0, true)
    data_relocs.push(@object.MachoReloc::{
      offset: r.0,
      sym: i,
      pcrel: false,
      length: if w == 8 {
        3
      } else {
        2
      },
      rtype: @object.ARM64_RELOC_UNSIGNED,
      is_extern: true,
    })
  }

  let text_relocs : Array[@object.MachoReloc] = []
  for c in calls {
    // Calls always go through a relocation so the linker can resolve them,
    // whether the callee is in this object or external.
    let i = arm64_obj_sym(syms, index, c.1, 0, 0, true)
    text_relocs.push(@object.MachoReloc::{
      offset: c.0 * 4,
      sym: i,
      pcrel: true,
      length: 2,
      rtype: @object.ARM64_RELOC_BRANCH26,
      is_extern: true,
    })
  }
  for a in addrs {
    // A directly referenced symbol that is defined in this object can use a
    // plain adrp/add; an external one must go through the GOT.
    let is_def = defined.contains(a.3)
    let i = arm64_obj_sym(syms, index, a.3, 0, 0, true)
    text_relocs.push(@object.MachoReloc::{
      offset: a.0 * 4,
      sym: i,
      pcrel: true,
      length: 2,
      rtype: if is_def {
        @object.ARM64_RELOC_PAGE21
      } else {
        @object.ARM64_RELOC_GOT_LOAD_PAGE21
      },
      is_extern: true,
    })
    if a.4 != 0 {
      text_relocs.push(@object.MachoReloc::{
        offset: a.1 * 4,
        sym: a.4,
        pcrel: false,
        length: 2,
        rtype: @object.ARM64_RELOC_ADDEND,
        is_extern: false,
      })
    }
    text_relocs.push(@object.MachoReloc::{
      offset: a.1 * 4,
      sym: i,
      pcrel: false,
      length: 2,
      rtype: if is_def {
        @object.ARM64_RELOC_PAGEOFF12
      } else {
        @object.ARM64_RELOC_GOT_LOAD_PAGEOFF12
      },
      is_extern: true,
    })
  }

  let sections : Array[@object.MachoSection] = [
    @object.MachoSection::{
      name: "__text",
      seg: "__TEXT",
      data: @object.words_to_bytes(text_words),
      align: 2,
      flags: @object.section_flags_text(),
      relocs: text_relocs,
    },
    @object.MachoSection::{
      name: "__data",
      seg: "__DATA",
      data: arm64_obj_bytes(data_bytes),
      align: 3,
      flags: @object.section_flags_data(),
      relocs: data_relocs,
    },
    @object.MachoSection::{
      name: "__const",
      seg: "__TEXT",
      data: arm64_obj_bytes(fp_bytes),
      align: 4,
      flags: @object.section_flags_data(),
      relocs: [],
    },
  ]
  @object.write_object(sections, syms)
}
