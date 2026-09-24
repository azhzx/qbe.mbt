///|
// QBE compiler backend - MoonBit implementation
// Entry point for the CLI. A thin wrapper over the `@qbe` library API: it
// handles argument parsing and file I/O, and delegates the pipeline to the
// selected target backend (amd64_sysv, wasm, rv64, la64, or arm64).

///|
// CLI command specification. @argparse auto-generates -h/--help from this.
let cmd : @argparse.Command = @argparse.Command(
  "qbe",
  about="QBE compiler backend (MoonBit port) — targets: amd64_sysv (default), wasm, rv64, la64, arm64; --run FUNC[,ARG]... interprets the SSA directly",
  options=[
    @argparse.OptionArg("output", short='o'),
    @argparse.OptionArg("target", short='t'),
    @argparse.OptionArg("gas", short='G'),
    @argparse.OptionArg("debug", short='d'),
    @argparse.OptionArg("run"),
    @argparse.OptionArg("emit"),
    @argparse.OptionArg("run-asm"),
  ],
  positionals=[
    @argparse.PositionArg("file", num_args=@argparse.ValueRange(lower=0)),
  ],
  arg_required_else_help=true,
)

///|
// Parse one `--run` value: "func" or "func,arg1,arg2..." where each arg is
// an integer (a1, -2) or a float literal (1.5, d_2.5, s_0.5).
fn parse_run_spec(
  spec : String,
) -> Result[(String, Array[@interp.InterpValue]), String] {
  let parts : Array[String] = []
  for piece in spec.split(",") {
    parts.push(piece.to_owned())
  }
  if parts.length() == 0 || parts[0] == "" {
    return Err("--run requires a function name")
  }
  let name = parts[0]
  let args : Array[@interp.InterpValue] = []
  for i in 1..<parts.length() {
    let raw = parts[i]
    if raw == "" {
      return Err("--run contains an empty argument")
    }
    if raw.has_prefix("s_") {
      // QBE single literal
      let d = @string.parse_double(raw[2:]) catch {
        _ => return Err("invalid single argument '\{raw}'")
      }
      args.push(@interp.VFloat(Float::from_double(d)))
    } else if raw.has_prefix("d_") {
      // QBE double literal
      let d = @string.parse_double(raw[2:]) catch {
        _ => return Err("invalid double argument '\{raw}'")
      }
      args.push(@interp.VDouble(d))
    } else if raw.contains(".") || raw.contains("e") || raw.contains("E") {
      let d = @string.parse_double(raw) catch {
        _ => return Err("invalid floating-point argument '\{raw}'")
      }
      args.push(@interp.VDouble(d))
    } else {
      let v = @string.parse_int64(raw) catch {
        _ => return Err("invalid integer argument '\{raw}'")
      }
      args.push(@interp.VInt(v))
    }
  }
  Ok((name, args))
}

///|
// Format a compile error the way the reference CLI does.
fn format_qbe_error(e : @util.QbeError, src_file? : String = "") -> String {
  match e {
    @util.QbeError::ParseError(f, line, msg) => {
      // vendor/qbe parse.c: fprintf(stderr, "qbe:%s:%d: ", inpath, lnum)
      let src = if src_file == "" { f } else { src_file }
      "qbe:\{src}:\{line}: \{msg}"
    }
    @util.QbeError::CompileError(msg) => "error: \{msg}"
    @util.QbeError::Ice(msg) => "ICE: \{msg}"
  }
}

///|
// Read one input file ("-" means stdin).
async fn read_source(file : String) -> String {
  if file == "-" {
    @stdio.stdin.read_all().text()
  } else {
    @fs.read_file_to_string(file)
  }
}

///|
// Process one input file. Returns the generated assembly (empty in debug mode,
// where the debug dump is printed to stderr instead).
async fn process_file(
  file : String,
  flags : String,
  gas : String,
  target : String,
) -> String {
  let source = read_source(file) catch {
    e => {
      @util.eprint("error: \{e}\n")
      return ""
    }
  }
  let backend = match target {
    "wasm" => @qbe.Target::Wasm32
    "rv64" => @qbe.Target::Rv64
    "la64" => @qbe.Target::La64
    "arm64" => @qbe.Target::Arm64
    _ => @qbe.Target::Amd64Sysv
  }
  if flags != "" {
    match @qbe.compile_target_debug(source, backend, flags) {
      Ok(dump) => {
        @util.eprint(dump)
        ""
      }
      Err(e) => {
        @util.eprint(format_qbe_error(e, src_file=file) + "\n")
        ""
      }
    }
  } else {
    match @qbe.compile_target(source, backend, gas~) {
      Ok(assembly) => assembly
      Err(e) => {
        @util.eprint(format_qbe_error(e, src_file=file) + "\n")
        ""
      }
    }
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
  let mut flags = ""
  match parsed.values.get("debug") {
    Some(debugs) =>
      for d in debugs {
        flags = flags + d
      }
    None => ()
  }
  let out_file = match parsed.values.get("output") {
    Some(arr) if arr.length() > 0 => arr[0]
    _ => ""
  }
  let mut gas = "e"
  match parsed.values.get("gas") {
    Some(arr) if arr.length() > 0 => gas = arr[0]
    _ => ()
  }
  let mut target = "amd64_sysv"
  match parsed.values.get("target") {
    Some(arr) if arr.length() > 0 =>
      match arr[0] {
        "amd64_sysv" | "wasm" | "rv64" | "la64" | "arm64" => target = arr[0]
        t => {
          @util.eprint("unknown target '\{t}'\n")
          return
        }
      }
    _ => ()
  }
  let files = match parsed.values.get("file") {
    Some(arr) => arr
    None => []
  }
  if files.length() == 0 {
    @util.eprint("qbe: no input files\n")
    return
  }
  // --run mode: interpret the SSA directly instead of emitting assembly
  match parsed.values.get("run") {
    Some(runs) if runs.length() > 0 => {
      let (entry, run_args) = match parse_run_spec(runs[0]) {
        Ok(spec) => spec
        Err(msg) => {
          @util.eprint("error: \{msg}\n")
          return
        }
      }
      for file in files {
        let source = read_source(file) catch {
          e => {
            @util.eprint("error: \{e}\n")
            continue
          }
        }
        match @qbe.interpret(source, entry~, args=run_args) {
          Ok((value, output)) => {
            if output != "" {
              @util.iprint(output)
            }
            match value {
              @interp.VVoid => ()
              @interp.VInt(v) => @util.iprint("\{v}\n")
              @interp.VFloat(f) => @util.iprint("\{f}\n")
              @interp.VDouble(d) => @util.iprint("\{d}\n")
            }
          }
          Err(e) => @util.eprint(format_qbe_error(e) + "\n")
        }
      }
      return
    }
    _ => ()
  }
  // --run-asm mode: compile to arm64 Mach-O assembly, load it and call `func`.
  match parsed.values.get("run-asm") {
    Some(specs) if specs.length() > 0 => {
      let (entry, asm_args) = match parse_run_spec(specs[0]) {
        Ok(spec) => spec
        Err(msg) => {
          @util.eprint("error: \{msg}\n")
          return
        }
      }
      let a0 = if asm_args.length() == 0 {
        0L
      } else if asm_args.length() == 1 {
        match asm_args[0] {
          @interp.VInt(v) => v
          _ => {
            @util.eprint("error: --run-asm takes a single integer argument\n")
            return
          }
        }
      } else {
        @util.eprint("error: --run-asm takes at most one argument\n")
        return
      }
      for file in files {
        let source = read_source(file) catch {
          e => {
            @util.eprint("error: \{e}\n")
            continue
          }
        }
        match @qbe.compile_target(source, @qbe.Target::Arm64, gas="m") {
          Ok(asm) => {
            let m = @run_asm.RunAsmModule::load_shared(asm) catch {
              e => {
                @util.eprint("run-asm error: \{Repr(e)}\n")
                continue
              }
            }
            let r = m.call1(entry, a0) catch {
              e => {
                @util.eprint("run-asm error: \{Repr(e)}\n")
                continue
              }
            }
            @util.iprint("\{r}\n")
          }
          Err(e) => @util.eprint(format_qbe_error(e, src_file=file) + "\n")
        }
      }
      return
    }
    _ => ()
  }
  // --emit obj: assemble the Mach-O output text into a .o file.
  match parsed.values.get("emit") {
    Some(arr) if arr.length() > 0 && arr[0] == "obj" => {
      for file in files {
        let asm = process_file(file, flags, "m", "arm64")
        if asm == "" {
          continue
        }
        let obj = @run_asm.assemble_object(asm) catch {
          e => {
            @util.eprint("run-asm error: \{Repr(e)}\n")
            continue
          }
        }
        let path = if out_file != "" && out_file != "-" {
          out_file
        } else {
          file + ".o"
        }
        @run_asm.write_file(path, obj) catch {
          e => {
            @util.eprint("run-asm error: \{Repr(e)}\n")
            continue
          }
        }
        @util.eprint("qbe: wrote \{path}\n")
      }
      return
    }
    _ => ()
  }
  // Process each file, accumulating the output.
  let out = StringBuilder::StringBuilder()
  for file in files {
    let s = process_file(file, flags, gas, target)
    out.write_string(s)
  }
  if flags == "" {
    if out_file != "" && out_file != "-" {
      @fs.write_string_to_file(out_file, out.to_string()) catch {
        e => @util.eprint("error: \{Repr(e)}\n")
      }
    } else {
      @util.iprint(out.to_string())
    }
  }
}
