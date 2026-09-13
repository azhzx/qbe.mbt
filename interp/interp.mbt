///|
// SSA interpreter for QBE IL - directly executes the pre-isel IR produced by
// the parser (like `lli` for LLVM IR). Values are carried as raw 64-bit
// words (word temporaries are sign-extended, floats bitcast), matching the
// semantics of the constant folder in `fold/opfold.mbt`.

///|
// A public argument/return value. Word and long arguments take `VInt` (the
// low 32 bits are used for `w` parameters), singles take `VFloat` and
// doubles take `VDouble`. Functions returning nothing produce `VVoid`.
pub(all) enum InterpValue {
  VVoid
  VInt(Int64)
  VFloat(Float)
  VDouble(Double)
} derive(Debug, Eq)

///|
// Extract the raw 64-bit word of an argument value (bitcast for floats).
fn InterpValue::bits(self : InterpValue) -> Int64 {
  match self {
    VInt(v) => v
    VFloat(f) => f.reinterpret_as_uint().to_int64()
    VDouble(d) => d.reinterpret_as_int64()
    VVoid => 0L
  }
}

///|
// Package a raw word produced by a return jump of the given class.
fn InterpValue::from_bits(k : @types.Class, bits : Int64) -> InterpValue {
  match k {
    @types.Ks =>
      VFloat(Float::reinterpret_from_uint(bits.to_int().reinterpret_as_uint()))
    @types.Kd => VDouble(bits.reinterpret_as_double())
    _ => VInt(bits)
  }
}

///|
// One active call frame.
priv struct Frame {
  fn_ : @types.Fn
  // value of every temporary (indexed by tmp id); registers included
  locals : FixedArray[Int64]
  // bump pointer for alloc4/8/16 inside this frame (grows down)
  mut frame_sp : UInt64
  // pending call arguments collected from Arg/Argc/Arge instructions
  mut call_args : Array[InterpValue]
}

///|
// Interpreter state: functions, data memory, function pointers, limits.
priv struct Interp {
  funcs : Map[String, @types.Fn]
  interner : @util.Interner
  mem : Memory
  // code region: function name -> address, and the reverse map
  code_addr : Map[String, UInt64]
  code_name : Map[UInt64, String]
  mut steps : Int
  max_steps : Int
  max_depth : Int
  // current stack bump pointer (frames allocate downward)
  mut sp : UInt64
  // heap bump pointer for malloc
  mut heap : UInt64
  extern_hook : ((String, Array[InterpValue]) -> InterpValue?)?
  // collected text output of the builtin runtime (putchar/puts/printf)
  out : StringBuilder
}

///|
// Address-space layout of the interpreter.
const DATA_BASE : UInt64 = 0x100000UL

///|
const CODE_BASE : UInt64 = 0x400000UL

///|
const HEAP_BASE : UInt64 = 0x800000UL

///|
const STACK_TOP : UInt64 = 0x100000000000UL

///|
fn Interp::code_of(self : Interp, name : String) -> UInt64 {
  match self.code_addr.get(name) {
    Some(a) => a
    None => {
      let a = CODE_BASE + self.code_addr.size().to_uint64() * 16UL
      self.code_addr[name] = a
      self.code_name[a] = name
      a
    }
  }
}

///|
// Layout the data segment and register all functions.
fn Interp::setup(
  self : Interp,
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
) -> Unit raise {
  for f in funcs {
    self.funcs[f.name] = f
    let _ = self.code_of(f.name)
  }
  let mut cur_label = ""
  let mut cur_addr = DATA_BASE
  let mut i = 0
  while i < datas.length() {
    let d = datas[i]
    i = i + 1
    match d.kind {
      @types.DStart => ()
      @types.DEnd => cur_label = ""
      @types.DName => {
        // reserve an aligned slot for the upcoming label
        let align = 8UL
        let pad = (align - cur_addr % align) % align
        let _ = self.mem.zero(cur_addr, pad.to_int64())
        cur_addr = cur_addr + pad
        self.mem.symbols[d.str] = cur_addr
        cur_label = d.str
        cur_addr = cur_addr
      }
      @types.DAlign => {
        let a = d.num.reinterpret_as_uint64()
        if a > 1UL {
          let pad = (a - cur_addr % a) % a
          let _ = self.mem.zero(cur_addr, pad.to_int64())
          cur_addr = cur_addr + pad
        }
      }
      _ =>
        // data payload: strings, scalar values or symbol references
        if d.kind == @types.DZ {
          let _ = self.mem.zero(cur_addr, d.num)
          cur_addr = cur_addr + d.num.reinterpret_as_uint64()
        } else if d.is_str {
          for c in d.str {
            let _ = self.mem.store8(cur_addr, c.to_int())
            cur_addr = cur_addr + 1UL
          }
          // NUL terminator (already present in the IL string? the IL keeps
          // the raw string without terminator)
          let _ = self.mem.store8(cur_addr, 0)
          cur_addr = cur_addr + 1UL
        } else if d.is_ref {
          // symbol reference patched to its address (data or code)
          let target = match self.mem.symbols.get(d.ref_name) {
            Some(a) => a
            None =>
              // maybe a function
              self.code_of(d.ref_name)
          }
          let v = target + d.ref_offset.reinterpret_as_uint64()
          let n = match d.kind {
            @types.DB => 1
            @types.DH => 2
            @types.DW => 4
            _ => 8
          }
          let _ = self.mem.store_int(cur_addr, v.reinterpret_as_int64(), n)
          cur_addr = cur_addr + n.to_uint64()
        } else {
          let n = match d.kind {
            @types.DB => 1
            @types.DH => 2
            @types.DW => 4
            _ => 8
          }
          let v = match d.kind {
            @types.DB => d.num & 0xFFL
            @types.DH => d.num & 0xFFFFL
            @types.DW => d.num & 0xFFFFFFFFL
            _ => d.num
          }
          let _ = self.mem.store_int(cur_addr, v, n)
          cur_addr = cur_addr + n.to_uint64()
        }
    }
  }
  ignore(cur_label)
}

///|
// Run one function to completion with the given arguments.
fn Interp::call_function(
  self : Interp,
  name : String,
  args : Array[InterpValue],
  depth : Int,
) -> InterpValue raise {
  if depth > self.max_depth {
    raise @util.QbeError::CompileError(
      "interpreter: call depth exceeded \{self.max_depth}",
    )
  }
  let f = match self.funcs.get(name) {
    Some(f) => f
    None =>
      raise @util.QbeError::CompileError(
        "interpreter: unknown function '\{name}'",
      )
  }
  // bind parameters: consecutive Par/Parc/Pare instructions in the start block
  let locals : FixedArray[Int64] = FixedArray::make(f.ntmp(), 0L)
  let start = f.blks[f.start_id]
  let mut argi = 0
  for ins in start.ins {
    if !ins.op.is_par() {
      break
    }
    if ins.to.is_tmp() {
      if argi >= args.length() {
        raise @util.QbeError::CompileError(
          "interpreter: too few arguments for '\{name}'",
        )
      }
      locals[ins.to.tmp_val()] = args[argi].bits()
      argi = argi + 1
    }
  }
  if argi < args.length() {
    raise @util.QbeError::CompileError(
      "interpreter: too many arguments for '\{name}'",
    )
  }
  let frame : Frame = {
    fn_: f,
    locals,
    frame_sp: self.sp,
    call_args: Array::new(),
  }
  self.enter_block(frame, f.start_id, -1, depth)
}

///|
// Execute block `bid`, entered from `from_id` (for phi selection).
fn Interp::enter_block(
  self : Interp,
  frame : Frame,
  bid : Int,
  from_id : Int,
  depth : Int,
) -> InterpValue raise {
  // block dispatch is a loop (not tail recursion): wasm has no guaranteed
  // TCO, so an interpreted `jmp @self` loop must not grow the host stack
  let mut bid = bid
  let mut from_id = from_id
  for ;; {
    self.steps = self.steps + 1
    if self.steps > self.max_steps {
      raise @util.QbeError::CompileError(
        "interpreter: step limit \{self.max_steps} exceeded",
      )
    }
    let f = frame.fn_
    let b = f.blks[bid]
    // phi nodes
    for phi in b.phi {
      if phi.to.is_tmp() {
        let mut v : Int64 = 0L
        let mut found = false
        for pa in phi.args {
          if pa.blk_id == from_id {
            v = self.eval_ref(frame, pa.value)
            found = true
            break
          }
        }
        if !found {
          raise @util.QbeError::CompileError(
            "interpreter: phi in \{b.name} has no value for predecessor \{from_id}",
          )
        }
        frame.locals[phi.to.tmp_val()] = v
      }
    }
    // instructions
    for idx in 0..<b.ins.length() {
      let ins = b.ins[idx]
      self.steps = self.steps + 1
      if self.steps > self.max_steps {
        raise @util.QbeError::CompileError(
          "interpreter: step limit \{self.max_steps} exceeded",
        )
      }
      match ins.op {
        @types.Par | @types.Parc | @types.Pare => ()
        @types.Arg | @types.Argc | @types.Arge =>
          // pending call argument (consumed by the following call)
          frame.call_args.push(self.eval_arg(frame, ins))
        @types.Call | @types.Vacall => self.exec_call(frame, ins, depth)
        @types.Alloc4 | @types.Alloc8 | @types.Alloc16 => {
          let align : UInt64 = match ins.op {
            @types.Alloc4 => 4UL
            @types.Alloc8 => 8UL
            _ => 16UL
          }
          let sz = self.eval_ref(frame, ins.arg1).reinterpret_as_uint64()
          let sp = frame.frame_sp - sz
          let sp = sp - sp % align
          frame.frame_sp = sp
          self.sp = sp
          if ins.to.is_tmp() {
            frame.locals[ins.to.tmp_val()] = sp.reinterpret_as_int64()
          }
        }
        @types.Vastart =>
          raise @util.QbeError::CompileError(
            "interpreter: vastart is not supported",
          )
        @types.Vaarg =>
          raise @util.QbeError::CompileError(
            "interpreter: vaarg is not supported",
          )
        @types.Nop => ()
        _ => {
          // compute and store the result
          let v = self.eval_ins(frame, ins)
          if ins.to.is_tmp() {
            frame.locals[ins.to.tmp_val()] = v
          }
        }
      }
    }
    // jump
    let jmp = b.jmp
    let result : InterpValue = match jmp.kind {
      @types.Jret0 => VVoid
      @types.Jretw | @types.Jretl => {
        let k = if jmp.kind == @types.Jretw { @types.Kw } else { @types.Kl }
        let v = self.eval_ref(frame, jmp.arg)
        if k == @types.Kw {
          VInt(sext32(v))
        } else {
          VInt(v)
        }
      }
      @types.Jrets =>
        VFloat(
          Float::reinterpret_from_uint(
            self.eval_ref(frame, jmp.arg).to_int().reinterpret_as_uint(),
          ),
        )
      @types.Jretd =>
        VDouble(self.eval_ref(frame, jmp.arg).reinterpret_as_double())
      @types.Jretc => VInt(self.eval_ref(frame, jmp.arg))
      @types.Jjmp => {
        self.sp = frame.frame_sp
        from_id = bid
        bid = jmp.s1
        continue
      }
      @types.Jjnz => {
        let cond = self.eval_ref(frame, jmp.arg) != 0L
        self.sp = frame.frame_sp
        from_id = bid
        bid = if cond { jmp.s1 } else { jmp.s2 }
        continue
      }
      _ =>
        raise @util.QbeError::CompileError("interpreter: unsupported jump kind")
    }
    return result
  }
}

///|
// Execute a call instruction using the pending Arg cluster.
fn Interp::exec_call(
  self : Interp,
  frame : Frame,
  ins : @types.Ins,
  depth : Int,
) -> Unit raise {
  let args = frame.call_args
  frame.call_args = Array::new()
  // resolve the callee
  let name : String = if ins.arg1.is_con() {
    let con = frame.fn_.cons[ins.arg1.con_val()]
    if con.kind == @types.CAddr {
      self.interner.get(con.label)
    } else {
      raise @util.QbeError::CompileError(
        "interpreter: invalid direct call target",
      )
    }
  } else if ins.arg1.is_tmp() {
    // indirect call through a function pointer
    let addr = frame.locals[ins.arg1.tmp_val()].reinterpret_as_uint64()
    match self.code_name.get(addr) {
      Some(n) => n
      None =>
        raise @util.QbeError::CompileError(
          "interpreter: indirect call to non-function address \{addr}",
        )
    }
  } else {
    raise @util.QbeError::CompileError("interpreter: invalid call target")
  }
  let result : InterpValue = if self.funcs.contains(name) {
    self.call_function(name, args, depth + 1)
  } else {
    // external symbol: user hook first, then builtins
    let hooked = match self.extern_hook {
      Some(h) => h(name, args)
      None => None
    }
    match hooked {
      Some(v) => v
      None => self.call_builtin(name, args)
    }
  }
  if ins.to.is_tmp() {
    frame.locals[ins.to.tmp_val()] = result.bits()
  }
}

///|
// Evaluate an Arg/Argc/Arge instruction into a call-argument value.
fn Interp::eval_arg(
  self : Interp,
  frame : Frame,
  ins : @types.Ins,
) -> InterpValue raise {
  let v : InterpValue = match ins.op {
    @types.Arge => VInt(self.eval_ref(frame, ins.arg1))
    @types.Argc =>
      // aggregate: the operand is a pointer to the value
      VInt(self.eval_ref(frame, ins.arg2))
    _ =>
      match ins.cls {
        @types.Ks =>
          VFloat(
            Float::reinterpret_from_uint(
              self.eval_ref(frame, ins.arg1).to_int().reinterpret_as_uint(),
            ),
          )
        @types.Kd =>
          VDouble(self.eval_ref(frame, ins.arg1).reinterpret_as_double())
        _ => {
          let w = self.eval_ref(frame, ins.arg1)
          if ins.cls == @types.Kw {
            VInt(sext32(w))
          } else {
            VInt(w)
          }
        }
      }
  }
  v
}

///|
// The module entry point: lay out data, bind arguments, run `entry`.
pub fn run_module(
  funcs : Array[@types.Fn],
  datas : Array[@types.Dat],
  interner : @util.Interner,
  entry : String,
  args : Array[InterpValue],
  max_steps? : Int = 10000000,
  max_depth? : Int = 10000,
  hook? : ((String, Array[InterpValue]) -> InterpValue?)? = None,
) -> Result[(InterpValue, String), @util.QbeError] {
  let it = Interp::{
    funcs: Map::new(),
    interner,
    mem: Memory::new(),
    code_addr: Map::new(),
    code_name: Map::new(),
    steps: 0,
    max_steps,
    max_depth,
    sp: STACK_TOP,
    heap: HEAP_BASE,
    extern_hook: hook,
    out: StringBuilder::new(),
  }
  try {
    it.setup(funcs, datas)
    let v = it.call_function(entry, args, 0)
    Ok((v, it.out.to_string()))
  } catch {
    ExitSignal(code) => Ok((VInt(code), it.out.to_string()))
    @util.QbeError::ParseError(f, l, m) =>
      Err(@util.QbeError::ParseError(f, l, m))
    @util.QbeError::CompileError(m) => Err(@util.QbeError::CompileError(m))
    @util.QbeError::Ice(m) => Err(@util.QbeError::Ice(m))
    e => Err(@util.QbeError::Ice("\{e}"))
  }
}
