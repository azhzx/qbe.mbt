///|
// Internal compilation pipeline.
// The full pass sequence (mirroring cmd/main in upstream qbe) lives here so it
// is reusable as a library. Debug dumps are written into a caller-provided
// buffer instead of stderr, which keeps the pipeline synchronous and makes the
// staged output testable.

///|
// Debug flags (P/A/I/L/M/N/C/F/S/R as in QBE main.c).
priv struct DbFlags {
  mut p : Bool
  mut a : Bool
  mut i : Bool
  mut l : Bool
  mut m : Bool
  mut n : Bool
  mut c : Bool
  mut f : Bool
  mut s : Bool
  mut r : Bool
}

///|
fn DbFlags::new() -> DbFlags {
  DbFlags::{
    p: false,
    a: false,
    i: false,
    l: false,
    m: false,
    n: false,
    c: false,
    f: false,
    s: false,
    r: false,
  }
}

///|
fn set_dbg(dbg : DbFlags, c : UInt16) -> Unit {
  match c {
    'P' | 'p' => dbg.p = true
    'A' | 'a' => dbg.a = true
    'I' | 'i' => dbg.i = true
    'L' | 'l' => dbg.l = true
    'M' | 'm' => dbg.m = true
    'N' | 'n' => dbg.n = true
    'C' | 'c' => dbg.c = true
    'F' | 'f' => dbg.f = true
    'S' | 's' => dbg.s = true
    'R' | 'r' => dbg.r = true
    _ => ()
  }
}

///|
fn dbg_from_flags(flags : String) -> DbFlags {
  let dbg = DbFlags::new()
  for j in 0..<flags.length() {
    set_dbg(dbg, flags[j])
  }
  dbg
}

///|
// Dump a function block and its dominator chain (-dN output), mirroring
// ssa.c: for each block in definition order print "%10s:" then its
// dominator-tree children.
fn dbg_dominators(fn_ : @types.Fn, out : StringBuilder) -> Unit {
  for id in fn_.def_order {
    let b1 = fn_.blks[id]
    if b1.dom_link < 0 {
      continue
    }
    let name = b1.name
    let pad = " ".repeat(
      if 10 > name.length() {
        10 - name.length()
      } else {
        0
      },
    )
    out.write_string(pad)
    out.write_string(name)
    out.write_string(":")
    let mut c = b1.dom_link
    while c >= 0 {
      out.write_string(" ")
      out.write_string(fn_.blks[c].name)
      c = fn_.blks[c].dom_next
    }
    out.write_string("\n")
  }
}

///|
// Print the current function in IL format, mirroring C's printfn + "\n".
fn dbg_function(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
  out : StringBuilder,
) -> Unit {
  out.write_string(@parser.printfn(fn_, interner, typs))
  out.write_string("\n")
}

///|
// Run the full compilation pipeline on a function (C func() in main.c).
// Debug output is appended to `out` according to the flags; in non-debug mode
// all debug strings are empty so this is silent.
fn run_passes(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
  dbg : DbFlags,
  out : StringBuilder,
) -> Unit raise {
  if dbg.p {
    out.write_string("\n> After parsing:\n")
    dbg_function(fn_, interner, typs, out)
  }
  @cfg.fillrpo(fn_)
  @cfg.fillpreds(fn_)
  @ssa.filluse(fn_)
  @ssa.memopt(fn_)
  // mem.c: -dM section.
  if dbg.m {
    out.write_string("\n> After memory optimization:\n")
    dbg_function(fn_, interner, typs, out)
  }
  // ssa(): filldom + -dN dominators.
  @cfg.filldom(fn_)
  if dbg.n {
    out.write_string("\n> Dominators:\n")
    dbg_dominators(fn_, out)
  }
  @cfg.fillfron(fn_)
  // C ssa() sets debug['L'] = 0 during ssa, so the pre-abi liveness
  // analysis is never dumped.
  out.write_string(@live.filllive(fn_, false))
  @ssa.phiins(fn_)
  @ssa.renblk(fn_)
  @ssa.filluse(fn_)
  @ssa.ssacheck(fn_)
  // ssa.c: -dN After SSA construction.
  if dbg.n {
    out.write_string("\n> After SSA construction:\n")
    dbg_function(fn_, interner, typs, out)
  }
  @cfg.fillloop(fn_)
  @cfg.fillalias(fn_)
  // load.c: -dM After load elimination.
  out.write_string(@ssa.loadopt(fn_, dbg.m, interner, typs))
  @ssa.filluse(fn_)
  @ssa.ssacheck(fn_)
  // copy.c: -dC.
  out.write_string(@ssa.copy(fn_, dbg.c, interner, typs))
  @ssa.filluse(fn_)
  // fold.c: -dF.
  out.write_string(@fold.fold(fn_, dbg.f, interner, typs))
  // T.abi (sysv.c): -dA.
  out.write_string(@abi.abi(fn_, typs, dbg.a, interner, typs))
  @cfg.fillpreds(fn_)
  @ssa.filluse(fn_)
  // T.isel (amd64/isel.c): -dI.
  out.write_string(@isel.isel(fn_, interner, dbg.i, typs))
  // Post-isel pipeline (main.c): fillrpo, filllive, fillcost, spill, rega.
  @cfg.fillrpo(fn_)
  out.write_string(@live.filllive(fn_, dbg.l))
  out.write_string(@spill.fillcost(fn_, dbg.s))
  out.write_string(@spill.spill(fn_, dbg.s, interner, typs))
  out.write_string(@rega.rega(fn_, dbg.r, interner, typs))
  @cfg.fillrpo(fn_)
  @cfg.simpljmp(fn_)
  @cfg.fillrpo(fn_)
  @cfg.fillpreds(fn_)
}

///|
// Parse IL text into functions, data sections, top-level order and types.
fn parse_module(
  text : String,
  file_name : String,
) -> (
  Array[@types.Fn],
  Array[@types.Dat],
  Array[String],
  Array[@types.Typ],
  @util.Interner,
) raise {
  let lexer = @lexer.Lexer::new(text, file_name)
  let tokens = lexer.tokenize()
  let parser = @parser.Parser::new(tokens, file_name)
  parser.parse()
  (
    parser.get_funcs(),
    parser.get_datas(),
    parser.get_order(),
    parser.get_typs(),
    parser.interner_ref(),
  )
}

///|
// Translate the GAS flavor string into (gasloc, gassym), matching QBE's -G.
fn gas_setting(gas : String) -> (String, String) raise {
  match gas {
    "e" => (".L", "")
    "m" => ("L", "_")
    g => raise @util.QbeError::CompileError("unknown gas flavor '\{g}'")
  }
}

///|
// Emit assembly for the whole module in input order (data and functions
// interleaved as parsed).
fn emit_module(
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
  order : Array[String],
  typs : Array[@types.Typ],
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  sb : StringBuilder,
) -> Unit raise {
  @types.fp_stash_reset()
  let mut fi = 0
  let mut di = 0
  for item in order {
    if item == "f" {
      let fn_ = funcs[fi]
      fi = fi + 1
      run_passes(fn_, interner, typs, DbFlags::new(), sb)
      @emit.emitfn(fn_, interner, gasloc, gassym, sb)
      sb.write_string("/* end function \{fn_.name} */\n\n")
    } else {
      while di < datas.length() {
        let d = datas[di]
        di = di + 1
        @emit.gasemitdat(d, gasloc, gassym, sb)
        if d.kind == @types.DEnd {
          sb.write_string("/* end data */\n\n")
          break
        }
      }
    }
  }
  @emit.gasemitfin(gasloc, sb)
}

///|
// Run wasm compilation pipeline on a function.
// Reuses SSA passes (target-agnostic), skips spill/rega (wasm has no
// physical registers), and runs wasm-specific ABI + isel.
fn run_passes_wasm(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
  dbg : DbFlags,
  out : StringBuilder,
) -> Unit raise {
  if dbg.p {
    out.write_string("\n> After parsing:\n")
    dbg_function(fn_, interner, typs, out)
  }
  @cfg.fillrpo(fn_)
  @cfg.fillpreds(fn_)
  @ssa.filluse(fn_)
  @ssa.memopt(fn_)
  if dbg.m {
    out.write_string("\n> After memory optimization:\n")
    dbg_function(fn_, interner, typs, out)
  }
  @cfg.filldom(fn_)
  if dbg.n {
    out.write_string("\n> Dominators:\n")
    dbg_dominators(fn_, out)
  }
  @cfg.fillfron(fn_)
  out.write_string(@live.filllive(fn_, false))
  @ssa.phiins(fn_)
  @ssa.renblk(fn_)
  @ssa.filluse(fn_)
  @ssa.ssacheck(fn_)
  if dbg.n {
    out.write_string("\n> After SSA construction:\n")
    dbg_function(fn_, interner, typs, out)
  }
  @cfg.fillloop(fn_)
  @cfg.fillalias(fn_)
  out.write_string(@ssa.loadopt(fn_, dbg.m, interner, typs))
  @ssa.filluse(fn_)
  @ssa.ssacheck(fn_)
  out.write_string(@ssa.copy(fn_, dbg.c, interner, typs))
  @ssa.filluse(fn_)
  out.write_string(@fold.fold(fn_, dbg.f, interner, typs))
  // Wasm ABI lowering
  out.write_string(@abi_wasm.abi_wasm(fn_, typs, dbg.a, interner, typs))
  @cfg.fillpreds(fn_)
  @ssa.filluse(fn_)
  // Wasm instruction selection
  out.write_string(@isel_wasm.isel_wasm(fn_, interner, dbg.i, typs))
  // Skip spill/rega — wasm has no physical registers
}

///|
// Emit WAT module for the whole module in input order.
fn emit_wasm_module(
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
  order : Array[String],
  typs : Array[@types.Typ],
  interner : @util.Interner,
  sb : StringBuilder,
) -> Unit raise {
  @types.fp_stash_reset()
  for fn_ in funcs {
    run_passes_wasm(fn_, interner, typs, DbFlags::new(), sb)
  }
  @emit_wasm.emit_wat_module(funcs, datas, order, interner, sb)
}
