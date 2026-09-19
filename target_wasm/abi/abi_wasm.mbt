///|
// Wasm ABI lowering — lowers Par/Arg/Call/Ret for wasm32 target.

///|
priv struct WasmAbiState {
  fn_ : @types.Fn
  buf : Array[@types.Ins]
}

///|
fn wasm_abi_new(fn_ : @types.Fn) -> WasmAbiState {
  WasmAbiState::{ fn_, buf: Array::new(), }
}

///|
// Process a single block: convert Par/Arg to Nop, simplify Call.
fn wasm_process_block(_st : WasmAbiState, blk : @types.Blk) -> Unit {
  for i in 0..<blk.ins.length() {
    let ins = blk.ins[i]
    match ins.op {
      @types.Par | @types.Parc | @types.Pare =>
        blk.ins[i] = @types.Ins::new_void(
          @types.Nop,
          ins.cls,
          @types.Ref::none(),
          @types.Ref::none(),
        )
      @types.Arg | @types.Argc | @types.Arge =>
        blk.ins[i] = @types.Ins::new_void(
          @types.Nop,
          ins.cls,
          @types.Ref::none(),
          @types.Ref::none(),
        )
      @types.Call | @types.Vacall =>
        blk.ins[i] = @types.Ins::new(
          ins.op,
          ins.cls,
          ins.to,
          ins.arg1,
          @types.Ref::none(),
        )
      _ => ()
    }
  }
}

///|
// Main ABI lowering entry point for wasm.
pub fn abi_wasm(
  fn_ : @types.Fn,
  _typs : Array[@types.Typ],
  print_dbg : Bool,
  _interner : @util.Interner,
  _all_typs : Array[@types.Typ],
) -> String {
  let st = wasm_abi_new(fn_)

  for b in fn_.def_order {
    wasm_process_block(st, fn_.blks[b])
  }

  if print_dbg {
    let out = StringBuilder::new()
    out.write_string("> After wasm ABI lowering:\n")
    out.to_string()
  } else {
    ""
  }
}
