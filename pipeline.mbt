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
  mut g : Bool
  mut k : Bool
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
    g: false,
    k: false,
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
    'G' | 'g' => dbg.g = true
    'K' | 'k' => dbg.k = true
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
// Run the target-independent frontend and SSA pipeline shared by every
// backend. Target-specific ABI lowering and instruction selection follow this
// helper in each backend driver.
fn run_frontend_passes(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
  dbg : DbFlags,
  cansel : Bool,
  from_c : Bool,
  out : StringBuilder,
  apple_abi0~ : Bool = false,
) -> Unit raise {
  if dbg.p {
    out.write_string("\n> After parsing:\n")
    dbg_function(fn_, interner, typs, out)
  }
  // C main.c: T.abi0(fn). All upstream targets use elimsb except the Apple
  // arm64 flavour, whose T.abi0 is apple_extsb.
  if apple_abi0 {
    @abi_arm64.apple_extsb(fn_)
    if dbg.a {
      out.write_string("\n> After Apple pre-ABI:\n")
      dbg_function(fn_, interner, typs, out)
    }
  } else {
    @ssa.elimsb(fn_)
  }
  // C main.c: fillcfg = fillrpo + fillpreds + fixphis.
  @cfg.fillcfg(fn_)
  @ssa.filluse(fn_)
  // promote (mem.c): -dM "After slot promotion".
  out.write_string(
    @mem.promote(fn_, dbg.m, interner, typs, skip_read_before_write=from_c),
  )
  @ssa.filluse(fn_)
  // ssa construction (ssa.c): filldom/fillfron/filllive/phiins/renblk.
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
  @cfg.fillalias(fn_)
  // loadopt (load.c): -dM "After load elimination".
  out.write_string(@ssa.loadopt(fn_, dbg.m, interner, typs))
  @ssa.filluse(fn_)
  @cfg.fillalias(fn_)
  // coalesce (mem.c): -dM "Slot coalescing".
  out.write_string(@mem.coalesce(fn_, dbg.m, interner, typs))
  @ssa.filluse(fn_)
  @cfg.filldom(fn_)
  @ssa.ssacheck(fn_)
  // gvn/gcm (gvn.c/gcm.c): -dG.
  out.write_string(@gvn.gvn(fn_, dbg.g, interner, typs))
  @cfg.fillcfg(fn_)
  // simplcfg (cfg.c): -dC.
  out.write_string(@cfg.simplcfg(fn_, dbg.c, interner, typs))
  @ssa.filluse(fn_)
  @cfg.filldom(fn_)
  out.write_string(@gvn.gcm(fn_, dbg.g, interner, typs))
  @ssa.filluse(fn_)
  @ssa.ssacheck(fn_)
  if cansel {
    // ifconvert (ifopt.c): -dK, amd64 only.
    out.write_string(@ifopt.ifconvert(fn_, dbg.k, interner, typs))
    @cfg.fillcfg(fn_)
    @ssa.filluse(fn_)
    @cfg.filldom(fn_)
    @ssa.ssacheck(fn_)
  }
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
  apple~ : Bool = false,
) -> Unit raise {
  @types.init_amd64_target()
  run_frontend_passes(fn_, interner, typs, dbg, true, false, out)
  // T.abi (sysv.c): -dA.
  out.write_string(@abi_amd64.abi(fn_, typs, dbg.a, interner, typs))
  // simpl (simpl.c), then refill cfg/use.
  out.write_string(@ifopt.simpl(fn_, false, interner, typs))
  @cfg.fillcfg(fn_)
  @ssa.filluse(fn_)
  // T.isel (amd64/isel.c): -dI.
  @util.set_asm_loc(if apple { "L" } else { ".L" })
  out.write_string(@isel.isel(fn_, interner, dbg.i, typs, apple~))
  // Post-isel pipeline (main.c): fillcfg, filllive, fillcost, spill, rega.
  @types.init_amd64_target()
  @cfg.fillcfg(fn_)
  out.write_string(@live.filllive(fn_, dbg.l))
  @cfg.fillloop(fn_)
  out.write_string(@spill.fillcost(fn_, dbg.s))
  out.write_string(@spill.spill(fn_, dbg.s, interner, typs))
  out.write_string(@rega.rega(fn_, dbg.r, interner, typs))
  @cfg.fillcfg(fn_)
  @cfg.simpljmp(fn_)
  @cfg.fillcfg(fn_)
  // Bookkeeping only: keep loop depths describing the final CFG for external
  // consumers (C main.c does not need this because nothing reads them again).
  @cfg.fillloop(fn_)
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
// The (name, directory) a debugger should use for the module: the first
// `dbgfile` path, split at the last slash.
fn dbg_cu_info(order : Array[String]) -> (String, String) {
  for item in order {
    if item.has_prefix("dbgfile:") {
      let path = item[8:].to_owned()
      let mut i = path.length() - 1
      while i >= 0 {
        if path[i] == '/' {
          let dir = if i == 0 { "/" } else { path[:i].to_owned() }
          return (path[i + 1:].to_owned(), dir)
        }
        i = i - 1
      }
      return (path, ".")
    }
  }
  ("<input>", ".")
}

///|
// Translate the GAS flavor string into (gasloc, gassym, apple), matching
// QBE's -G. "m" is the Mach-O flavor.
fn gas_setting(gas : String) -> (String, String, Bool) raise {
  match gas {
    "e" => (".L", "", false)
    "m" => ("L", "_", true)
    g => raise @util.QbeError::CompileError("unknown gas flavor '\{g}'")
  }
}

///|
let debug_fn_id : Array[Int32] = [0]

///|
// Reset once per output stream, not once per independently parsed input.
fn reset_output_state() -> Unit {
  @types.fp_stash_reset()
  @util.dbg_reset()
  @dwarf.reset()
  debug_fn_id[0] = 0
  @emit_amd64.amd64_emit_reset()
  @emit_arm64.arm64_emit_reset()
  @emit_rv64.rv64_emit_reset()
  @emit_la64.la64_emit_reset()
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
  apple : Bool,
  sb : StringBuilder,
  reset~ : Bool = true,
  finish~ : Bool = true,
  windows~ : Bool = false,
) -> Unit raise {
  if reset {
    reset_output_state()
  }
  let mut fi = 0
  let mut di = 0
  for item in order {
    if item.has_prefix("dbgfile:") {
      // Debug file marker: `.file <n> "<path>"` at this input position.
      @util.emit_dbgfile(item[8:].to_owned(), sb)
      continue
    }
    if item == "f" {
      let fn_ = funcs[fi]
      fi = fi + 1
      if windows {
        run_passes_win(fn_, interner, typs, DbFlags::new(), sb)
      } else {
        run_passes(fn_, interner, typs, DbFlags::new(), sb, apple~)
      }
      @emit_amd64.emitfn(fn_, interner, gasloc, gassym, apple, sb, windows~)
      sb.write_string("/* end function \{fn_.name} */\n\n")
      if @util.debug_info() {
        let dbg_lbl = gasloc + "dbgfn" + debug_fn_id[0].to_string()
        debug_fn_id[0] += 1
        sb.write_string(dbg_lbl + ":\n")
        @dwarf.record_fn(
          fn_.name,
          gassym + fn_.name,
          dbg_lbl,
          @emit_amd64.debug_locs(fn_, apple),
        )
      }
    } else {
      while di < datas.length() {
        let d = datas[di]
        di = di + 1
        @gasdata.emit(d, gassym, apple, sb)
        if d.kind == @types.DEnd {
          sb.write_string("/* end data */\n\n")
          break
        }
      }
    }
  }
  if finish && @util.debug_info() && @dwarf.has_info() {
    let (dbg_cu_name, dbg_cu_dir) = dbg_cu_info(order)
    let cu_name = if funcs[0].dbg_name != "" {
      funcs[0].dbg_name
    } else {
      dbg_cu_name
    }
    let cu_dir = if funcs[0].dbg_dir != "" {
      funcs[0].dbg_dir
    } else {
      dbg_cu_dir
    }
    @dwarf.emit_debug_info(gasloc, cu_name, cu_dir, apple, sb)
  }
  if finish {
    @emit_amd64.gasemitfin(gasloc, apple, sb, windows~)
  }
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
  run_frontend_passes(fn_, interner, typs, dbg, false, false, out)
  // Wasm ABI lowering
  out.write_string(@abi_wasm.abi_wasm(fn_, typs, dbg.a, interner, typs))
  // simpl (simpl.c), exactly as every native backend does after its ABI pass:
  // it expands the blit0/blit1 pseudo pair into load/store/add chunks and
  // lowers udiv/urem by a power of two.  Without it a `blit` in the input
  // reached the wasm selector and was silently dropped.
  out.write_string(@ifopt.simpl(fn_, false, interner, typs))
  @cfg.fillcfg(fn_)
  @ssa.filluse(fn_)
  // Wasm instruction selection
  @util.set_asm_loc(".L")
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
  validate_wasm_module(funcs, datas, interner)
  @types.fp_stash_reset()
  @util.dbg_reset()
  for fn_ in funcs {
    run_passes_wasm(fn_, interner, typs, DbFlags::new(), sb)
  }
  @emit_wasm.emit_wat_module(funcs, datas, order, interner, sb)
}

///|
// Run RISC-V compilation pipeline on a function.
// Reuses SSA passes (target-agnostic), skips spill/rega (RISC-V uses a
// different register allocation strategy), and runs RISC-V-specific ABI + isel.
fn run_passes_rv64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
  dbg : DbFlags,
  out : StringBuilder,
) -> Unit raise {
  @types.init_rv64_target()
  run_frontend_passes(fn_, interner, typs, dbg, false, false, out)
  // RISC-V ABI lowering
  out.write_string(@abi_rv64.abi_rv64(fn_, typs, dbg.a, interner, typs))
  out.write_string(@ifopt.simpl(fn_, false, interner, typs))
  @cfg.fillcfg(fn_)
  @ssa.filluse(fn_)
  // RISC-V instruction selection
  @util.set_asm_loc(".L")
  out.write_string(@isel_rv64.isel_rv64(fn_, interner, dbg.i, typs))
  // Post-isel: fillrpo, filllive, fillcost, spill, rega.
  @types.init_rv64_target()
  @cfg.fillcfg(fn_)
  out.write_string(@live.filllive(fn_, dbg.l))
  @cfg.fillloop(fn_)
  out.write_string(@spill.fillcost(fn_, dbg.s))
  out.write_string(@spill.spill(fn_, dbg.s, interner, typs))
  out.write_string(@rega.rega(fn_, dbg.r, interner, typs))
  @cfg.fillcfg(fn_)
  @cfg.simpljmp(fn_)
  @cfg.fillcfg(fn_)
  // Bookkeeping only: keep loop depths describing the final CFG for external
  // consumers (C main.c does not need this because nothing reads them again).
  @cfg.fillloop(fn_)
}

///|
// Emit RISC-V assembly for the whole module in input order.
fn emit_rv64_module(
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
  order : Array[String],
  typs : Array[@types.Typ],
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  sb : StringBuilder,
  reset~ : Bool = true,
  finish~ : Bool = true,
) -> Unit raise {
  if reset {
    reset_output_state()
  }
  let mut fi = 0
  let mut di = 0
  for item in order {
    if item.has_prefix("dbgfile:") {
      // Debug file marker: `.file <n> "<path>"` at this input position.
      @util.emit_dbgfile(item[8:].to_owned(), sb)
      continue
    }
    if item == "f" {
      let fn_ = funcs[fi]
      fi = fi + 1
      run_passes_rv64(fn_, interner, typs, DbFlags::new(), sb)
      sb.write_string(
        @emit_rv64.emit_rv64(fn_, interner, gasloc, gassym, false, typs),
      )
      sb.write_string("/* end function \{fn_.name} */\n\n")
      if @util.debug_info() {
        let dbg_lbl = gasloc + "dbgfn" + debug_fn_id[0].to_string()
        debug_fn_id[0] += 1
        sb.write_string(dbg_lbl + ":\n")
        @dwarf.record_fn(
          fn_.name,
          gassym + fn_.name,
          dbg_lbl,
          @emit_rv64.debug_locs(fn_, false),
        )
      }
    } else {
      while di < datas.length() {
        let d = datas[di]
        di = di + 1
        @gasdata.emit(d, gassym, false, sb)
        if d.kind == @types.DEnd {
          sb.write_string("/* end data */\n\n")
          break
        }
      }
    }
  }
  if finish && @util.debug_info() && @dwarf.has_info() {
    let (dbg_cu_name, dbg_cu_dir) = dbg_cu_info(order)
    let cu_name = if funcs[0].dbg_name != "" {
      funcs[0].dbg_name
    } else {
      dbg_cu_name
    }
    let cu_dir = if funcs[0].dbg_dir != "" {
      funcs[0].dbg_dir
    } else {
      dbg_cu_dir
    }
    @dwarf.emit_debug_info(gasloc, cu_name, cu_dir, false, sb)
  }
  if finish {
    @emit_rv64.gasemitfin_rv64(gasloc, sb)
  }
}

///|
// Run LoongArch64 (la64, LP64D) compilation pipeline on a function.
// Reuses the target-agnostic SSA passes, runs the LoongArch ABI + isel, then
// the shared spill/rega passes with the la64 machine configuration.
fn run_passes_la64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
  dbg : DbFlags,
  out : StringBuilder,
) -> Unit raise {
  @types.init_la64_target()
  run_frontend_passes(fn_, interner, typs, dbg, false, false, out)
  // LoongArch ABI lowering
  out.write_string(@abi_la64.abi_la64(fn_, typs, dbg.a, interner, typs))
  out.write_string(@ifopt.simpl(fn_, false, interner, typs))
  @cfg.fillcfg(fn_)
  @ssa.filluse(fn_)
  // la64 has no scalar unsigned conversion instructions accepted by the
  // assembler, so lower them with portable bit tricks before selection.
  lower_unsigned_la64(fn_)
  @ssa.filluse(fn_)
  // LoongArch instruction selection
  @util.set_asm_loc(".L")
  out.write_string(@isel_la64.isel_la64(fn_, interner, dbg.i, typs))
  // Post-isel: fillrpo, filllive, fillcost, spill, rega.
  @types.init_la64_target()
  @cfg.fillcfg(fn_)
  out.write_string(@live.filllive(fn_, dbg.l))
  @cfg.fillloop(fn_)
  out.write_string(@spill.fillcost(fn_, dbg.s))
  out.write_string(@spill.spill(fn_, dbg.s, interner, typs))
  out.write_string(@rega.rega(fn_, dbg.r, interner, typs))
  @cfg.fillcfg(fn_)
  @cfg.simpljmp(fn_)
  @cfg.fillcfg(fn_)
  // Bookkeeping only: keep loop depths describing the final CFG for external
  // consumers (C main.c does not need this because nothing reads them again).
  @cfg.fillloop(fn_)
}

///|
// Emit LoongArch assembly for the whole module in input order (data and
// functions interleaved as parsed, followed by the float constant pool).
fn emit_la64_module(
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
  order : Array[String],
  typs : Array[@types.Typ],
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  sb : StringBuilder,
  reset~ : Bool = true,
  finish~ : Bool = true,
) -> Unit raise {
  if reset {
    reset_output_state()
  }
  let mut fi = 0
  let mut di = 0
  for item in order {
    if item.has_prefix("dbgfile:") {
      // Debug file marker: `.file <n> "<path>"` at this input position.
      @util.emit_dbgfile(item[8:].to_owned(), sb)
      continue
    }
    if item == "f" {
      let fn_ = funcs[fi]
      fi = fi + 1
      run_passes_la64(fn_, interner, typs, DbFlags::new(), sb)
      sb.write_string(@emit_la64.emit_la64(fn_, interner, gasloc, gassym, typs))
      sb.write_string("/* end function \{fn_.name} */\n\n")
      if @util.debug_info() {
        let dbg_lbl = gasloc + "dbgfn" + debug_fn_id[0].to_string()
        debug_fn_id[0] += 1
        sb.write_string(dbg_lbl + ":\n")
        @dwarf.record_fn(
          fn_.name,
          gassym + fn_.name,
          dbg_lbl,
          @emit_la64.debug_locs(fn_, false),
        )
      }
    } else {
      while di < datas.length() {
        let d = datas[di]
        di = di + 1
        @gasdata.emit(d, gassym, false, sb)
        if d.kind == @types.DEnd {
          sb.write_string("/* end data */\n\n")
          break
        }
      }
    }
  }
  if finish && @util.debug_info() && @dwarf.has_info() {
    let (dbg_cu_name, dbg_cu_dir) = dbg_cu_info(order)
    let cu_name = if funcs[0].dbg_name != "" {
      funcs[0].dbg_name
    } else {
      dbg_cu_name
    }
    let cu_dir = if funcs[0].dbg_dir != "" {
      funcs[0].dbg_dir
    } else {
      dbg_cu_dir
    }
    @dwarf.emit_debug_info(gasloc, cu_name, cu_dir, false, sb)
  }
  if finish {
    @emit_la64.gasemitfin_la64(gasloc, sb)
  }
}

///|
// Run ARM64 (AArch64, AAPCS64 ELF) compilation pipeline on a function.
// Reuses the target-agnostic SSA passes, runs the ARM64 ABI + isel, then the
// shared spill/rega passes with the arm64 machine configuration.
fn run_passes_arm64(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
  dbg : DbFlags,
  apple : Bool,
  out : StringBuilder,
  from_c~ : Bool = false,
) -> Unit raise {
  @types.init_arm64_target()
  run_frontend_passes(
    fn_,
    interner,
    typs,
    dbg,
    false,
    from_c,
    out,
    apple_abi0=apple,
  )
  // ARM64 ABI lowering
  out.write_string(
    @abi_arm64.abi_arm64(fn_, typs, dbg.a, interner, apple, typs),
  )
  out.write_string(@ifopt.simpl(fn_, false, interner, typs))
  @cfg.fillcfg(fn_)
  @ssa.filluse(fn_)
  // ARM64 instruction selection
  @util.set_asm_loc(if apple { "L" } else { ".L" })
  out.write_string(@isel_arm64.isel_arm64(fn_, interner, dbg.i, typs, apple~))
  // Post-isel: fillrpo, filllive, fillcost, spill, rega.
  @types.init_arm64_target()
  @cfg.fillcfg(fn_)
  out.write_string(@live.filllive(fn_, dbg.l))
  @cfg.fillloop(fn_)
  out.write_string(@spill.fillcost(fn_, dbg.s))
  out.write_string(@spill.spill(fn_, dbg.s, interner, typs))
  out.write_string(@rega.rega(fn_, dbg.r, interner, typs))
  @cfg.fillcfg(fn_)
  @cfg.simpljmp(fn_)
  @cfg.fillcfg(fn_)
  // Bookkeeping only: keep loop depths describing the final CFG for external
  // consumers (C main.c does not need this because nothing reads them again).
  @cfg.fillloop(fn_)
}

///|
// Emit ARM64 assembly for the whole module in input order (data and functions
// interleaved as parsed, followed by the float constant pool).
fn emit_arm64_module(
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
  order : Array[String],
  typs : Array[@types.Typ],
  interner : @util.Interner,
  gasloc : String,
  gassym : String,
  apple : Bool,
  sb : StringBuilder,
  reset~ : Bool = true,
  finish~ : Bool = true,
) -> Unit raise {
  // The Windows PE flavour is amd64-only; keep the finalizer call uniform.
  let windows = false
  if reset {
    reset_output_state()
  }
  let mut fi = 0
  let mut di = 0
  for item in order {
    if item.has_prefix("dbgfile:") {
      // Debug file marker: `.file <n> "<path>"` at this input position.
      @util.emit_dbgfile(item[8:].to_owned(), sb)
      continue
    }
    if item == "f" {
      let fn_ = funcs[fi]
      fi = fi + 1
      run_passes_arm64(fn_, interner, typs, DbFlags::new(), apple, sb)
      sb.write_string(
        @emit_arm64.emit_arm64(fn_, interner, typs, gasloc, gassym, apple),
      )
      sb.write_string("/* end function \{fn_.name} */\n\n")
      if @util.debug_info() {
        let dbg_lbl = gasloc + "dbgfn" + debug_fn_id[0].to_string()
        debug_fn_id[0] += 1
        sb.write_string(dbg_lbl + ":\n")
        @dwarf.record_fn(
          fn_.name,
          gassym + fn_.name,
          dbg_lbl,
          @emit_arm64.debug_locs(fn_, apple),
        )
      }
    } else {
      while di < datas.length() {
        let d = datas[di]
        di = di + 1
        @gasdata.emit(d, gassym, apple, sb)
        if d.kind == @types.DEnd {
          sb.write_string("/* end data */\n\n")
          break
        }
      }
    }
  }
  if finish && @util.debug_info() && @dwarf.has_info() {
    let (dbg_cu_name, dbg_cu_dir) = dbg_cu_info(order)
    let cu_name = if funcs[0].dbg_name != "" {
      funcs[0].dbg_name
    } else {
      dbg_cu_name
    }
    let cu_dir = if funcs[0].dbg_dir != "" {
      funcs[0].dbg_dir
    } else {
      dbg_cu_dir
    }
    @dwarf.emit_debug_info(gasloc, cu_name, cu_dir, apple, sb)
  }
  if finish {
    @emit_amd64.gasemitfin(gasloc, apple, sb, windows~)
  }
}

///|
// Run the Windows x64 pipeline on a function (C func() with T_amd64_win).
fn run_passes_win(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
  dbg : DbFlags,
  out : StringBuilder,
) -> Unit raise {
  @types.init_amd64_win_target()
  run_frontend_passes(fn_, interner, typs, dbg, true, false, out)
  // T.abi1 (winabi.c): -dA.
  out.write_string(@abi_amd64.abi_win(fn_, typs, dbg.a, interner, typs))
  // simpl (simpl.c), then refill cfg/use.
  out.write_string(@ifopt.simpl(fn_, false, interner, typs))
  @cfg.fillcfg(fn_)
  @ssa.filluse(fn_)
  // T.isel (amd64/isel.c): -dI.
  @util.set_asm_loc("L")
  out.write_string(@isel.isel(fn_, interner, dbg.i, typs, apple=false))
  // Post-isel pipeline (main.c): fillcfg, filllive, fillcost, spill, rega.
  @types.init_amd64_win_target()
  @cfg.fillcfg(fn_)
  out.write_string(@live.filllive(fn_, dbg.l))
  @cfg.fillloop(fn_)
  out.write_string(@spill.fillcost(fn_, dbg.s))
  out.write_string(@spill.spill(fn_, dbg.s, interner, typs))
  out.write_string(@rega.rega(fn_, dbg.r, interner, typs))
  @cfg.fillcfg(fn_)
  @cfg.simpljmp(fn_)
  @cfg.fillcfg(fn_)
  @cfg.fillloop(fn_)
}

///|
fn validate_wasm_module(
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
  interner : @util.Interner,
) -> Unit raise {
  let data_names : Array[String] = []
  for d in datas {
    if d.kind == @types.DName {
      data_names.push(d.str)
    }
  }
  let fn_names : Array[String] = []
  for fn_ in funcs {
    fn_names.push(fn_.name)
  }
  for d in datas {
    if d.is_ref && !data_names.contains(d.ref_name) {
      raise @util.QbeError::CompileError(
        "wasm: data reference to undefined symbol '\{d.ref_name}' (wasm has no linker)",
      )
    }
  }
  if @types.WASM_DATA_BASE + @emit_wasm.wasm_data_end(datas) >
    @types.WASM_STACK_BASE {
    raise @util.QbeError::CompileError(
      "wasm: static data overlaps the stack region",
    )
  }
  // Address constants may only name static data; external addresses have no
  // representation in a standalone module. A direct call's callee is the one
  // allowed exception (it becomes an import).
  for fn_ in funcs {
    for bid in fn_.def_order {
      for ins in fn_.blks[bid].ins {
        let refs = [ins.arg1, ins.arg2]
        for r in refs {
          if r.is_con() {
            let c = fn_.cons[r.con_val()]
            if c.kind == @types.CAddr && !c.is_local {
              let nm = interner.get(c.label)
              if !data_names.contains(nm) &&
                !(r.eq(ins.arg1) && ins.op == @types.Call) {
                raise @util.QbeError::CompileError(
                  "wasm: address of external symbol '\{nm}' is not supported",
                )
              }
            }
          }
        }
      }
    }
  }
}
