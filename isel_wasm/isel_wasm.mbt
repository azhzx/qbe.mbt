///|
// Wasm instruction selection — maps QBE IL ops to wasm instructions.

///|
// Wasm instruction selection state
priv struct WasmIselState {
  fn_ : @types.Fn
  buf : Array[@types.Ins]
  interner : @util.Interner
}

///|
fn wasm_isel_new(fn_ : @types.Fn, interner : @util.Interner) -> WasmIselState {
  WasmIselState::{ fn_, buf: Array::new(), interner }
}

///|
fn wasm_isel_emit(st : WasmIselState, i : @types.Ins) -> Unit {
  st.buf.push(i)
}

///|
// Select a single instruction: map QBE op to wasm equivalent.
fn wasm_sel(st : WasmIselState, i : @types.Ins) -> Unit {
  match i.op {
    // Arithmetic — direct passthrough
    @types.Add
    | @types.Sub
    | @types.Mul
    | @types.And
    | @types.Or
    | @types.Xor
    | @types.Sar
    | @types.Shr
    | @types.Shl
    | @types.Div
    | @types.Udiv
    | @types.Rem
    | @types.Urem => wasm_isel_emit(st, i)

    // Comparisons — all comparison ops passthrough
    @types.Ceqw
    | @types.Cnew
    | @types.Csgew
    | @types.Csgtw
    | @types.Cslew
    | @types.Csltw
    | @types.Cugew
    | @types.Cugtw
    | @types.Culew
    | @types.Cultw
    | @types.Ceql
    | @types.Cnel
    | @types.Csgel
    | @types.Csgtl
    | @types.Cslel
    | @types.Csltl
    | @types.Cugel
    | @types.Cugtl
    | @types.Culel
    | @types.Cultl
    | @types.Ceqs
    | @types.Cges
    | @types.Cgts
    | @types.Cles
    | @types.Clts
    | @types.Cnes
    | @types.Cos
    | @types.Cuos
    | @types.Ceqd
    | @types.Cged
    | @types.Cgtd
    | @types.Cled
    | @types.Cltd
    | @types.Cned
    | @types.Cod
    | @types.Cuod => wasm_isel_emit(st, i)

    // Memory operations
    @types.Load
    | @types.Loadsb
    | @types.Loadub
    | @types.Loadsh
    | @types.Loaduh
    | @types.Loadsw
    | @types.Loaduw => wasm_isel_emit(st, i)
    @types.Storeb
    | @types.Storeh
    | @types.Storew
    | @types.Storel
    | @types.Stores
    | @types.Stored => wasm_isel_emit(st, i)

    // Extensions/truncations
    @types.Extsb
    | @types.Extub
    | @types.Extsh
    | @types.Extuh
    | @types.Exts
    | @types.Truncd
    | @types.Stosi
    | @types.Dtosi
    | @types.Swtof
    | @types.Sltof
    | @types.Cast
    | @types.Extsw
    | @types.Extuw => wasm_isel_emit(st, i)

    // Stack allocation
    @types.Alloc4 | @types.Alloc8 | @types.Alloc16 => {
      st.fn_.has_dynalloc = true
      wasm_isel_emit(st, i)
    }

    // Copy — direct passthrough
    @types.Copy => wasm_isel_emit(st, i)

    // Nop — skip
    @types.Nop => ()

    // Call/Vacall — passthrough
    @types.Call | @types.Vacall => wasm_isel_emit(st, i)

    // Internal ops — skip (amd64-specific)
    @types.Swap
    | @types.Sign
    | @types.Salloc
    | @types.Xidiv
    | @types.Xdiv
    | @types.Xcmp
    | @types.Xtest
    | @types.Acmp
    | @types.Acmn
    | @types.Afcmp
    | @types.Addr => ()

    // Flag-setting ops — skip (wasm doesn't use flags)
    @types.Flagieq
    | @types.Flagine
    | @types.Flagisge
    | @types.Flagisgt
    | @types.Flagisle
    | @types.Flagislt
    | @types.Flagiuge
    | @types.Flagiugt
    | @types.Flagiule
    | @types.Flagiult
    | @types.Flagfeq
    | @types.Flagfne
    | @types.Flagfge
    | @types.Flagfgt
    | @types.Flagfle
    | @types.Flagflt
    | @types.Flagfo
    | @types.Flagfuo => ()

    // Vararg ops — not supported in wasm
    @types.Vaarg | @types.Vastart => ()

    // Parameter/argument ops — handled by abi_wasm
    @types.Par
    | @types.Parc
    | @types.Pare
    | @types.Arg
    | @types.Argc
    | @types.Arge => ()

    // Error/placeholder
    @types.Oxxx => ()
  }
}

///|
// Main wasm instruction selection entry point.
pub fn isel_wasm(
  fn_ : @types.Fn,
  interner : @util.Interner,
  print_dbg : Bool,
  all_typs : Array[@types.Typ],
) -> String raise {
  let st = wasm_isel_new(fn_, interner)

  for bid in fn_.def_order {
    let blk = fn_.blks[bid]
    for i in 0..<blk.ins.length() {
      wasm_sel(st, blk.ins[i])
    }
  }

  if print_dbg {
    let out = StringBuilder::new()
    out.write_string("> After wasm instruction selection:\n")
    out.write_string(@parser.printfn(fn_, interner, all_typs))
    out.write_string("\n")
    out.to_string()
  } else {
    ""
  }
}
