///|
// I/O helpers.
// QBE writes debug output to stderr and generated code to stdout.
// The MoonBit stdio package lives in the `moonbitlang/async` library and is
// async; these helpers wrap it so callers (an async main / driver) can emit
// text without trailing newlines, mirroring C's fprintf(outf/fp, ...).

///|
// Write to stderr (debug output channel).
pub async fn eprint(s : String) -> Unit {
  @stdio.stderr.write(s) catch {
    _ => ()
  }
}

///|
// Write to stdout (output channel).
pub async fn iprint(s : String) -> Unit {
  @stdio.stdout.write(s) catch {
    _ => ()
  }
}
