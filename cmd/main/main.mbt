///|
// QBE compiler backend - MoonBit implementation
// Entry point for the CLI.

///|
// CLI command specification. @argparse auto-generates -h/--help from this.
let cmd : @argparse.Command = @argparse.Command(
  "qbe",
  about="QBE compiler backend (MoonBit port)",
  options=[
    @argparse.OptionArg("output", short='o'),
    @argparse.OptionArg("target", short='t'),
    @argparse.OptionArg("gas", short='G'),
    @argparse.OptionArg("debug", short='d'),
  ],
  positionals=[
    @argparse.PositionArg("file", num_args=@argparse.ValueRange(lower=0)),
  ],
  arg_required_else_help=true,
)

///|
// Debug flags (P/A/I/L/M/N/C/F/S/R as in QBE main.c)
struct DbFlags {
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
// Dump a function block and its dominator chain (-dN output), mirroring
// ssa.c: for each block in definition order print "%10s:" then its
// dominator-tree children.
async fn dbg_dominators(fn_ : @types.Fn) -> Unit {
  for id in fn_.def_order {
    let b1 = fn_.blks[id]
    if b1.dom_link < 0 {
      continue
    }
    let sb = StringBuilder::new()
    let name = b1.name
    let pad = " ".repeat(
      if 10 > name.length() {
        10 - name.length()
      } else {
        0
      },
    )
    sb.write_string(pad)
    sb.write_string(name)
    sb.write_string(":")
    let mut c = b1.dom_link
    while c >= 0 {
      sb.write_string(" ")
      sb.write_string(fn_.blks[c].name)
      c = fn_.blks[c].dom_next
    }
    @util.eprint(sb.to_string())
    @util.eprint("\n")
  }
}

///|
// Print the current function in IL format to stderr, as C's printfn + "\n".
async fn dbg_function(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
) -> Unit {
  @util.eprint(@parser.printfn(fn_, interner, typs))
  @util.eprint("\n")
}

///|
// Whether any debug flag is set.
fn any_dbg(dbg : DbFlags) -> Bool {
  dbg.p ||
  dbg.a ||
  dbg.i ||
  dbg.l ||
  dbg.m ||
  dbg.n ||
  dbg.c ||
  dbg.f ||
  dbg.s ||
  dbg.r
}

///|
// Run the full compilation pipeline on a function (C func() in main.c).
// Debug output is emitted to stderr according to the flags; in non-debug mode
// all debug strings are empty so this is silent.
async fn run_passes(
  fn_ : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
  dbg : DbFlags,
) -> Unit {
  if dbg.p {
    @util.eprint("\n> After parsing:\n")
    dbg_function(fn_, interner, typs)
  }
  @cfg.fillrpo(fn_)
  @cfg.fillpreds(fn_)
  @ssa.filluse(fn_)
  @ssa.memopt(fn_)
  // mem.c: -dM section.
  if dbg.m {
    @util.eprint("\n> After memory optimization:\n")
    dbg_function(fn_, interner, typs)
  }
  // ssa(): filldom + -dN dominators.
  @cfg.filldom(fn_)
  if dbg.n {
    @util.eprint("\n> Dominators:\n")
    dbg_dominators(fn_)
  }
  @cfg.fillfron(fn_)
  // C ssa() sets debug['L'] = 0 during ssa, so the pre-abi liveness
  // analysis is never dumped.
  @util.eprint(@live.filllive(fn_, false))
  @ssa.phiins(fn_)
  @ssa.renblk(fn_)
  @ssa.filluse(fn_)
  @ssa.ssacheck(fn_)
  // ssa.c: -dN After SSA construction.
  if dbg.n {
    @util.eprint("\n> After SSA construction:\n")
    dbg_function(fn_, interner, typs)
  }
  @cfg.fillloop(fn_)
  @cfg.fillalias(fn_)
  // load.c: -dM After load elimination.
  @util.eprint(@ssa.loadopt(fn_, dbg.m, interner, typs))
  @ssa.filluse(fn_)
  @ssa.ssacheck(fn_)
  // copy.c: -dC.
  @util.eprint(@ssa.copy(fn_, dbg.c, interner, typs))
  @ssa.filluse(fn_)
  // fold.c: -dF.
  @util.eprint(@fold.fold(fn_, dbg.f, interner, typs))
  // T.abi (sysv.c): -dA.
  @util.eprint(@abi.abi(fn_, typs, dbg.a, interner, typs))
  @cfg.fillpreds(fn_)
  @ssa.filluse(fn_)
  // T.isel (amd64/isel.c): -dI.
  @util.eprint(@isel.isel(fn_, interner, dbg.i, typs))
  // Post-isel pipeline (main.c): fillrpo, filllive, fillcost, spill, rega.
  @cfg.fillrpo(fn_)
  @util.eprint(@live.filllive(fn_, dbg.l))
  @util.eprint(@spill.fillcost(fn_, dbg.s))
  @util.eprint(@spill.spill(fn_, dbg.s, interner, typs))
  @util.eprint(@rega.rega(fn_, dbg.r, interner, typs))
  @cfg.fillrpo(fn_)
  @cfg.simpljmp(fn_)
  @cfg.fillrpo(fn_)
  @cfg.fillpreds(fn_)
}

///|
// Process one input file. In non-debug mode returns the generated assembly;
// in debug mode returns "" (all debug output goes to stderr).
async fn process_file(
  file : String,
  dbg : DbFlags,
  gasloc : String,
  gassym : String,
) -> String {
  let source = if file == "-" {
    @stdio.stdin.read_all().text()
  } else {
    @fs.read_file_to_string(file)
  }
  let lexer = @lexer.Lexer::new(source, file)
  let tokens = lexer.tokenize()
  let parser = @parser.Parser::new(tokens, file)
  parser.parse()
  let funcs = parser.get_funcs()
  let datas = parser.get_datas()
  let order = parser.get_order()
  let typs = parser.get_typs()
  let interner = parser.interner_ref()
  let is_dbg = any_dbg(dbg)
  if is_dbg {
    for fn_ in funcs {
      // C main.c: fprintf(stderr, "**** Function %s ****", fn->name);
      @util.eprint("**** Function \{fn_.name} ****")
      run_passes(fn_, interner, typs, dbg)
      // C main.c: fprintf(stderr, "\n"); at end of debug mode.
      @util.eprint("\n")
    }
    return ""
  } else {
    let sb = StringBuilder::new()
    // data sections and functions in input order
    let mut fi = 0
    let mut di = 0
    for item in order {
      if item == "f" {
        let fn_ = funcs[fi]
        fi = fi + 1
        run_passes(fn_, interner, typs, dbg)
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
    return sb.to_string()
  }
}

///|
async fn main {
  let parsed = cmd.parse() catch {
    e => {
      @util.eprint("\{e}\n")
      return
    }
  }
  let dbg = DbFlags::new()
  match parsed.values.get("debug") {
    Some(flags) =>
      for f in flags {
        for j in 0..<f.length() {
          set_dbg(dbg, f[j])
        }
      }
    None => ()
  }
  let out_file = match parsed.values.get("output") {
    Some(arr) if arr.length() > 0 => arr[0]
    _ => ""
  }
  let mut gasloc = ".L"
  let mut gassym = ""
  match parsed.values.get("gas") {
    Some(arr) if arr.length() > 0 =>
      match arr[0] {
        "e" => ()
        "m" => {
          gasloc = "L"
          gassym = "_"
        }
        g => {
          @util.eprint("unknown gas flavor '\{g}'\n")
          return
        }
      }
    _ => ()
  }
  match parsed.values.get("target") {
    Some(arr) if arr.length() > 0 =>
      if arr[0] != "amd64_sysv" {
        @util.eprint("unknown target '\{arr[0]}'\n")
        return
      }
    _ => ()
  }
  let files = match parsed.values.get("file") {
    Some(arr) => arr
    None => Array::new()
  }
  if files.length() == 0 {
    @util.eprint("qbe: no input files\n")
    return
  }
  // Process each file, accumulating the output.
  let out = StringBuilder::new()
  for file in files {
    let s = process_file(file, dbg, gasloc, gassym) catch {
      @util.QbeError::ParseError(f, line, msg) => {
        @util.eprint("\{f}:\{line}: error: \{msg}\n")
        ""
      }
      @util.QbeError::CompileError(msg) => {
        @util.eprint("error: \{msg}\n")
        ""
      }
      @util.QbeError::Ice(msg) => {
        @util.eprint("ICE: \{msg}\n")
        ""
      }
      e => {
        @util.eprint("error: \{e}\n")
        ""
      }
    }
    out.write_string(s)
  }
  if !any_dbg(dbg) {
    if out_file != "" && out_file != "-" {
      @fs.write_string_to_file(out_file, out.to_string()) catch {
        e => @util.eprint("error: \{e}\n")
      }
    } else {
      @util.iprint(out.to_string())
    }
  }
}
