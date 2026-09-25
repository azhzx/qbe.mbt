///|
// Wasm ABI lowering — lowers Par/Arg/Call/Ret for wasm32 target.

///|
priv struct WasmAbiState {
  fn_ : @types.Fn
  buf : Array[@types.Ins]
}

///|
fn wasm_abi_new(fn_ : @types.Fn) -> WasmAbiState {
  WasmAbiState::{ fn_, buf: [], }
}

///|
// Process a single block: convert Par/Arg to Nop, simplify Call.
fn wasm_process_block(_st : WasmAbiState, blk : @types.Blk) -> Unit {
  for i in 0..<blk.ins.length() {
    let ins = blk.ins[i]
    match ins.op {
      // Par/Parc/Pare are kept so the emitter can declare the wasm
      // parameters with their real classes. Arg/Arge are kept too: the
      // emitter pushes each argument value so the following call consumes
      // them from the wasm operand stack. Argc only carries a type payload,
      // which the wasm call does not need.
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
    let out = StringBuilder::StringBuilder()
    out.write_string("> After wasm ABI lowering:\n")
    out.to_string()
  } else {
    ""
  }
}
