///|
// QBE compiler backend - MoonBit implementation
// Entry point for the CLI. A thin wrapper over the `@qbe` library API: it
// handles argument parsing and file I/O, and delegates the pipeline to
// `@qbe.compile` / `@qbe.compile_debug`.

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
// Format a compile error the way the reference CLI does.
fn format_qbe_error(e : @qbe.QbeError) -> String {
  match e {
    @qbe.QbeError::ParseError(f, line, msg) => "\{f}:\{line}: error: \{msg}"
    @qbe.QbeError::CompileError(msg) => "error: \{msg}"
    @qbe.QbeError::Ice(msg) => "ICE: \{msg}"
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
async fn process_file(file : String, flags : String, gas : String) -> String {
  let source = read_source(file) catch {
    e => {
      @util.eprint("error: \{e}\n")
      return ""
    }
  }
  if flags != "" {
    match @qbe.compile_debug(source, flags) {
      Ok(dump) => {
        @util.eprint(dump)
        ""
      }
      Err(e) => {
        @util.eprint(format_qbe_error(e) + "\n")
        ""
      }
    }
  } else {
    match @qbe.compile(source, gas~) {
      Ok(asm) => asm
      Err(e) => {
        @util.eprint(format_qbe_error(e) + "\n")
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
    let s = process_file(file, flags, gas)
    out.write_string(s)
  }
  if flags == "" {
    if out_file != "" && out_file != "-" {
      @fs.write_string_to_file(out_file, out.to_string()) catch {
        e => @util.eprint("error: \{e}\n")
      }
    } else {
      @util.iprint(out.to_string())
    }
  }
}
