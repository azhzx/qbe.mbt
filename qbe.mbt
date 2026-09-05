///|
// azhzx/qbe — a lightweight QBE-style compiler backend in MoonBit.
//
// This package exposes a unified compilation entry point on top of the
// per-stage packages (`lexer`, `parser`, `cfg`, `ssa`, `fold`, `abi`, `isel`,
// `live`, `spill`, `rega`, `emit`).
//
// # Example
// ```mbt check
// test {
//   let src =
//     #|export function w $add(w %a, w %b) {
//     #|@start
//     #|  %s =w add %a, %b
//     #|  ret %s
//     #|}
//     #|
//   match compile(src) {
//     Ok(assembly) =>
//       assert_true(
//         assembly.contains("addl") &&
//         assembly.contains("add:") &&
//         assembly.contains("ret"),
//       )
//     Err(_) => fail("compile failed")
//   }
// }
// ```

///|
// Compile IL source text to GAS assembly (target: amd64_sysv).
//
// `gas` selects the GAS flavor: "e" for ELF (Linux, `.L` labels) and "m" for
// Mach-O (macOS, `L` labels and `_` symbol prefix).
//
// Returns the generated assembly, or a `@util.QbeError` describing a lexing,
// parsing, or internal compiler error.
//
// # Example
// ```mbt check
// test {
//   let src = "export function w $one() { @start ret 1 }\n"
//   let assembly = match compile(src) {
//     Ok(assembly) => assembly
//     Err(_) => fail("compile failed")
//   }
//   assert_true(assembly.contains("one:"))
// }
// ```
pub fn compile(
  text : String,
  gas? : String = "e",
) -> Result[String, @util.QbeError] {
  try compile_raise(text, gas) catch {
    @util.QbeError::ParseError(f, l, m) =>
      Err(@util.QbeError::ParseError(f, l, m))
    @util.QbeError::CompileError(m) => Err(@util.QbeError::CompileError(m))
    @util.QbeError::Ice(m) => Err(@util.QbeError::Ice(m))
    e => Err(@util.QbeError::Ice("\{e}"))
  } noraise {
    r => Ok(r)
  }
}

///|
// Compile IL source text and return the staged debug dumps selected by `flags`.
//
// `flags` is a string of QBE debug flag characters (combinable): `P` parse,
// `M` memory optimization, `N` SSA construction, `C` copy elimination, `F`
// constant folding, `A` ABI lowering, `I` instruction selection, `L` liveness,
// `S` spill, `R` register allocation. Assembly output is suppressed in debug
// mode, matching the reference CLI.
//
// # Example
// ```mbt check
// test {
//   let src = "export function w $one() { @start ret 1 }\n"
//   let dump = match compile_debug(src, "PN") {
//     Ok(dump) => dump
//     Err(_) => fail("compile failed")
//   }
//   assert_true(dump.contains("> After parsing:"))
// }
// ```
pub fn compile_debug(
  text : String,
  flags : String,
) -> Result[String, @util.QbeError] {
  try compile_debug_raise(text, flags) catch {
    @util.QbeError::ParseError(f, l, m) =>
      Err(@util.QbeError::ParseError(f, l, m))
    @util.QbeError::CompileError(m) => Err(@util.QbeError::CompileError(m))
    @util.QbeError::Ice(m) => Err(@util.QbeError::Ice(m))
    e => Err(@util.QbeError::Ice("\{e}"))
  } noraise {
    r => Ok(r)
  }
}

///|
// Assembly-producing compile, raising `@util.QbeError` on failure.
fn compile_raise(text : String, gas : String) -> String raise {
  let (gasloc, gassym) = gas_setting(gas)
  let (funcs, datas, order, typs, interner) = parse_module(text, "<input>")
  let sb = StringBuilder::new()
  emit_module(funcs, datas, order, typs, interner, gasloc, gassym, sb)
  sb.to_string()
}

///|
// Debug-dump compile, raising `@util.QbeError` on failure.
fn compile_debug_raise(text : String, flags : String) -> String raise {
  let (funcs, _, _, typs, interner) = parse_module(text, "<input>")
  let dbg = dbg_from_flags(flags)
  let out = StringBuilder::new()
  for fn_ in funcs {
    out.write_string("**** Function \{fn_.name} ****")
    run_passes(fn_, interner, typs, dbg, out)
    out.write_string("\n")
  }
  out.to_string()
}

///|
// Compile IL source text to WAT (WebAssembly Text format).
//
// Returns the generated WAT module, or a `@util.QbeError` describing
// a lexing, parsing, or internal compiler error.
//
// # Example
// ```mbt check
// test {
//   let src = "export function w $one() { @start ret 1 }\n"
//   let wat = match compile_wasm(src) {
//     Ok(wat) => wat
//     Err(_) => fail("wasm compile failed")
//   }
//   assert_true(wat.contains("(func $one"))
//   assert_true(wat.contains("i32.const 1"))
// }
// ```
pub fn compile_wasm(text : String) -> Result[String, @util.QbeError] {
  try compile_wasm_raise(text) catch {
    @util.QbeError::ParseError(f, l, m) =>
      Err(@util.QbeError::ParseError(f, l, m))
    @util.QbeError::CompileError(m) => Err(@util.QbeError::CompileError(m))
    @util.QbeError::Ice(m) => Err(@util.QbeError::Ice(m))
    e => Err(@util.QbeError::Ice("\{e}"))
  } noraise {
    r => Ok(r)
  }
}

///|
// Compile IL source text to WAT and return staged debug dumps.
//
// # Example
// ```mbt check
// test {
//   let src = "export function w $one() { @start ret 1 }\n"
//   let dump = match compile_wasm_debug(src, "PN") {
//     Ok(dump) => dump
//     Err(_) => fail("wasm compile failed")
//   }
//   assert_true(dump.contains("> After parsing:"))
// }
// ```
pub fn compile_wasm_debug(
  text : String,
  flags : String,
) -> Result[String, @util.QbeError] {
  try compile_wasm_debug_raise(text, flags) catch {
    @util.QbeError::ParseError(f, l, m) =>
      Err(@util.QbeError::ParseError(f, l, m))
    @util.QbeError::CompileError(m) => Err(@util.QbeError::CompileError(m))
    @util.QbeError::Ice(m) => Err(@util.QbeError::Ice(m))
    e => Err(@util.QbeError::Ice("\{e}"))
  } noraise {
    r => Ok(r)
  }
}

///|
// Wasm compile, raising `@util.QbeError` on failure.
fn compile_wasm_raise(text : String) -> String raise {
  let (funcs, datas, order, typs, interner) = parse_module(text, "<input>")
  let sb = StringBuilder::new()
  emit_wasm_module(funcs, datas, order, typs, interner, sb)
  sb.to_string()
}

///|
// Wasm debug-dump compile, raising `@util.QbeError` on failure.
fn compile_wasm_debug_raise(text : String, flags : String) -> String raise {
  let (funcs, _, _, typs, interner) = parse_module(text, "<input>")
  let dbg = dbg_from_flags(flags)
  let out = StringBuilder::new()
  for fn_ in funcs {
    out.write_string("**** Function \{fn_.name} ****")
    run_passes_wasm(fn_, interner, typs, dbg, out)
    out.write_string("\n")
  }
  out.to_string()
}

///|
// Compile IL source text to RISC-V GAS assembly (target: rv64).
//
// Returns the generated assembly, or a `@util.QbeError` describing a lexing,
// parsing, or internal compiler error.
//
// # Example
// ```mbt check
// test {
//   let src = "export function w $one() { @start ret 1 }\n"
//   let assembly = match compile_rv64(src) {
//     Ok(assembly) => assembly
//     Err(_) => fail("rv64 compile failed")
//   }
//   assert_true(assembly.contains("one:"))
//   assert_true(assembly.contains("li"))
// }
// ```
pub fn compile_rv64(text : String) -> Result[String, @util.QbeError] {
  try compile_rv64_raise(text) catch {
    @util.QbeError::ParseError(f, l, m) =>
      Err(@util.QbeError::ParseError(f, l, m))
    @util.QbeError::CompileError(m) => Err(@util.QbeError::CompileError(m))
    @util.QbeError::Ice(m) => Err(@util.QbeError::Ice(m))
    e => Err(@util.QbeError::Ice("\{e}"))
  } noraise {
    r => Ok(r)
  }
}

///|
// Compile IL source text to RISC-V assembly and return staged debug dumps.
//
// # Example
// ```mbt check
// test {
//   let src = "export function w $one() { @start ret 1 }\n"
//   let dump = match compile_rv64_debug(src, "PN") {
//     Ok(dump) => dump
//     Err(_) => fail("rv64 compile failed")
//   }
//   assert_true(dump.contains("> After parsing:"))
// }
// ```
pub fn compile_rv64_debug(
  text : String,
  flags : String,
) -> Result[String, @util.QbeError] {
  try compile_rv64_debug_raise(text, flags) catch {
    @util.QbeError::ParseError(f, l, m) =>
      Err(@util.QbeError::ParseError(f, l, m))
    @util.QbeError::CompileError(m) => Err(@util.QbeError::CompileError(m))
    @util.QbeError::Ice(m) => Err(@util.QbeError::Ice(m))
    e => Err(@util.QbeError::Ice("\{e}"))
  } noraise {
    r => Ok(r)
  }
}

///|
// RISC-V compile, raising `@util.QbeError` on failure.
fn compile_rv64_raise(text : String) -> String raise {
  let (funcs, datas, order, typs, interner) = parse_module(text, "<input>")
  let sb = StringBuilder::new()
  emit_rv64_module(funcs, datas, order, typs, interner, sb)
  sb.to_string()
}

///|
// RISC-V debug-dump compile, raising `@util.QbeError` on failure.
fn compile_rv64_debug_raise(text : String, flags : String) -> String raise {
  let (funcs, _, _, typs, interner) = parse_module(text, "<input>")
  let dbg = dbg_from_flags(flags)
  let out = StringBuilder::new()
  for fn_ in funcs {
    out.write_string("**** Function \{fn_.name} ****")
    run_passes_rv64(fn_, interner, typs, dbg, out)
    out.write_string("\n")
  }
  out.to_string()
}

///|
// Convenience re-exports of the core IR types from `types`.
// Use `@qbe.Fn`, `@qbe.Ref`, ... instead of reaching into `@types` when the
// intent is "the module's public IR".

pub type Fn = @types.Fn

///|
pub type Blk = @types.Blk

///|
pub type Ins = @types.Ins

///|
pub type Tmp = @types.Tmp

///|
pub type Ref = @types.Ref

///|
pub type Con = @types.Con

///|
pub type Op = @types.Op

///|
pub type Jump = @types.Jump

///|
pub type Dat = @types.Dat

///|
pub type Typ = @types.Typ

///|
pub type BSet = @types.BSet

///|
pub type Class = @types.Class
