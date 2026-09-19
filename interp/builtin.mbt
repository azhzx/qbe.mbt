///|
// Built-in runtime for the SSA interpreter - the portable analogue of the
// symbol resolution layer an LLVM JIT wires up (LLVM ORC resolves external
// symbols against the host process; the interpreter resolves them against
// this table plus an optional user-provided hook). Everything is implemented
// in pure MoonBit. Text output is collected into a buffer that `run_module`
// returns alongside the result, so the library stays portable and side
// effect free.

///|
// Raised by the `exit` builtin to unwind interpretation.
priv suberror ExitSignal {
  ExitSignal(Int64)
}

///|
// Heap allocation granularity (C malloc guarantees max_align_t).
const HEAP_ALIGN : UInt64 = 16UL

///|
// Resolve and execute a builtin. Raises QbeError for unknown symbols.
fn Interp::call_builtin(
  self : Interp,
  name : String,
  args : Array[InterpValue],
) -> InterpValue raise {
  match name {
    "putchar" => {
      let c = self.arg_of(args, 0)
      self.out.write_string(c.to_int().unsafe_to_char().to_string())
      VInt(c)
    }
    "puts" => {
      let s = self.mem.load_cstr(self.arg_of(args, 0).reinterpret_as_uint64())
      self.out.write_string(s)
      self.out.write_string("\n")
      VInt((s.length() + 1).to_int64())
    }
    "printf" => VInt(self.exec_printf(args))
    "malloc" => {
      let sz = self.arg_of(args, 0).reinterpret_as_uint64()
      let base = (self.heap + HEAP_ALIGN - 1UL) / HEAP_ALIGN * HEAP_ALIGN
      self.heap = base + (if sz > 0UL { sz } else { 1UL })
      // the sparse memory is zero-initialized
      VInt(base.reinterpret_as_int64())
    }
    "free" =>
      // no-op: the interpreter heap is a bump allocator. This mirrors the
      // common interpreter simplification and is safe for test programs.
      VInt(0L)
    "exit" => raise ExitSignal(self.arg_of(args, 0))
    _ =>
      raise @util.QbeError::CompileError(
        "interpreter: unknown external function '\{name}'",
      )
  }
}

///|
// The raw word of argument `i`, or 0 when absent.
fn Interp::arg_of(self : Interp, args : Array[InterpValue], i : Int) -> Int64 {
  ignore(self)
  if i < args.length() {
    args[i].bits()
  } else {
    0L
  }
}

///|
// A minimal printf: %d %i %u %x %c %s %ld %li %lu %lx %f %lf %e %g and %%.
// Arguments are consumed from the pending call-argument list.
fn Interp::exec_printf(self : Interp, args : Array[InterpValue]) -> Int64 raise {
  if args.length() == 0 {
    raise @util.QbeError::CompileError("interpreter: printf without format")
  }
  let fmt_addr = self.arg_of(args, 0).reinterpret_as_uint64()
  let fmt = self.mem.load_cstr(fmt_addr)
  let sb = StringBuilder::StringBuilder()
  let mut ai = 1
  let mut i = 0
  while i < fmt.length() {
    let c = fmt[i]
    if c != '%' {
      sb.write_char(c.unsafe_to_char())
      i = i + 1
      continue
    }
    i = i + 1
    if i >= fmt.length() {
      break
    }
    let esc = fmt[i]
    i = i + 1
    // accept an optional length modifier (l / ll) before the conversion
    let mut conv = esc
    if esc == 'l' {
      if i < fmt.length() {
        conv = fmt[i]
        i = i + 1
        if conv == 'l' && i < fmt.length() {
          conv = fmt[i]
          i = i + 1
        }
      } else {
        break
      }
    }
    match conv {
      '%' => sb.write_char('%')
      'd' | 'i' => {
        sb.write_string(self.arg_of(args, ai).to_string())
        ai = ai + 1
      }
      'u' => {
        sb.write_string(
          self.arg_of(args, ai).reinterpret_as_uint64().to_string(),
        )
        ai = ai + 1
      }
      'x' => {
        sb.write_string(
          hex_string(self.arg_of(args, ai).reinterpret_as_uint64()),
        )
        ai = ai + 1
      }
      'c' => {
        sb.write_char(self.arg_of(args, ai).to_int().unsafe_to_char())
        ai = ai + 1
      }
      's' => {
        sb.write_string(
          self.mem.load_cstr(self.arg_of(args, ai).reinterpret_as_uint64()),
        )
        ai = ai + 1
      }
      'f' | 'e' | 'g' => {
        // doubles are passed as VDouble arguments; bit patterns carried in
        // VInt are also accepted
        let d = match args.get(ai) {
          Some(VDouble(d)) => d
          Some(VFloat(f)) => f.to_double()
          Some(v) => v.bits().reinterpret_as_double()
          None => 0.0
        }
        sb.write_string(d.to_string())
        ai = ai + 1
      }
      _ => {
        // unknown conversion: emit it verbatim
        sb.write_char('%')
        sb.write_char(conv.unsafe_to_char())
      }
    }
  }
  self.out.write_string(sb.to_string())
  sb.to_string().length().to_int64()
}

///|
// Lowercase hex without a prefix (C printf %x).
fn hex_string(v : UInt64) -> String {
  if v == 0UL {
    return "0"
  }
  let digits = "0123456789abcdef"
  let sb = StringBuilder::StringBuilder()
  let mut x = v
  let buf : Array[Char] = []
  while x > 0UL {
    buf.push(char_code_at(digits, (x & 0xFUL).to_int()).unsafe_to_char())
    x = x >> 4
  }
  for i in (buf.length() - 1)>=..0 {
    sb.write_char(buf[i])
  }
  sb.to_string()
}

///|
fn char_code_at(s : String, i : Int) -> Int {
  s[i].to_int()
}
