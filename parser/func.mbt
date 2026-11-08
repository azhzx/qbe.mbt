///|
// Parser state for block/instruction parsing (internal)
#derive(Eq)
enum PState {
  PLbl // Expecting a label
  PPhi // Parsing phi nodes
  PIns // Parsing instructions
  PEnd // End of function body
}

///|
// Parse a function definition
// export: whether the function is exported
fn Parser::parsefn(self : Self, lnk : Linkage) -> Unit raise {
  self.curblk = -1
  // Parse return class and function name
  // If next token is not TGlo, parse the return class first
  let mut ret_ty = -1
  self.rcls = 9 // K0: void return
  if self.peek_kind() != TGlo {
    let (cls, ty, bh) = self.parsecls()
    ret_ty = ty
    // C parse.c keeps the class code: Kw..Kd = 0..3, Ksb..Kuh = 4..7,
    // Kc = 8 (aggregate), K0 = 9 (void).  Jretw + rcls then selects the
    // matching sub-word return jump.
    self.rcls = if bh >= 0 {
      4 + bh
    } else {
      match cls {
        @types.Kw => 0
        @types.Kl => 1
        @types.Ks => 2
        @types.Kd => 3
        @types.Kx => 8
      }
    }
  }
  // Expect function name ($name)
  let name_tok = self.next()
  if name_tok.kind != TGlo {
    raise self.error("function name expected")
  }
  // Create the function
  let fn_ = @types.Fn::new(name_tok.raw)
  fn_.is_export = lnk.is_export
  fn_.align = lnk.align
  fn_.sec = lnk.sec
  fn_.secf = lnk.secf
  fn_.ret_ty = ret_ty
  // Pre-populate register temporaries (indices 0..Tmp0-1)
  fn_.init_regs()
  // Initialize first constant to 0 (C: curf->con[0].type = CBits)
  let _ = fn_.get_con(0)
  self.curfn = Some(fn_)
  // Parse parameter list
  self.par_ins.clear()
  fn_.is_vararg = self.parserefl(false)
  // Expect { to start function body
  if self.next_nl() != TLbr {
    raise self.error("function body must start with {")
  }
  // Parse blocks
  let mut ps = PLbl
  while true {
    ps = self.parseline(ps)
    if ps == PEnd {
      break
    }
  }
  // Verify last block has a jump
  let fn_final = self.curfn()
  if self.curblk < 0 {
    raise self.error("empty function")
  }
  let last_blk = fn_final.blk(self.curblk)
  if last_blk.jmp.kind == @types.Jxxx {
    raise self.error("last block misses jump")
  }
  // Prepend parameter instructions to the start block
  let start_id = fn_final.def_order[0]
  fn_final.start_id = start_id
  if self.par_ins.length() > 0 {
    let start = fn_final.blks[start_id]
    for i in (self.par_ins.length() - 1)>=..0 {
      start.ins.insert(0, self.par_ins[i])
    }
  }
  // Validate the function (C parse.c typecheck, phi subset)
  self.typecheck(fn_final)
  // Add the function to the result
  self.funcs.push(self.curfn.unwrap())
  self.curfn = None
  self.curblk = -1
}

///|
// Parse parameter/argument reference list
// arg: true if parsing call arguments, false if parsing function parameters
// Returns true if the list is variadic (contains ...)
fn Parser::parserefl(self : Self, arg : Bool) -> Bool raise {
  self.expect(TLpa) // (
  let mut hasenv = false
  let mut vararg = false
  while true {
    let pk = self.peek_kind()
    if pk == TRpa {
      break
    }
    // C parse.c rejects a signature parameter after `...`; calls intentionally
    // continue after the Argv marker.
    if !arg && vararg {
      raise self.error("no parameters allowed after '...'")
    }
    // The ellipsis marks where the variadic arguments start. In a signature
    // it sets is_vararg; in a call it emits an Argv marker. Arguments may
    // follow it, so keep parsing after consuming the marker (C parserefl).
    if pk == TDot3 {
      if vararg {
        raise self.error("only one '...' allowed")
      }
      let _ = self.next() // consume ...
      vararg = true
      if arg {
        let fn_ = self.curfn()
        let ins = @types.Ins::new(
          @types.Argv,
          @types.Kw,
          @types.Ref::none(),
          @types.Ref::none(),
          @types.Ref::none(),
        )
        if self.curblk >= 0 {
          fn_.blks[self.curblk].ins.push(ins)
        } else {
          self.par_ins.push(ins)
        }
      }
      if self.peek_kind() == TRpa {
        break
      }
      self.expect(TCom) // ,
      continue
    }
    // Parse environment or class
    let env = pk == TId && self.peek().raw == "env"
    let (k, ty, bh) : (@types.Class, Int32, Int32) = if env {
      let _ = self.next() // consume 'env'
      (@types.Kl, -1, -1)
    } else {
      self.parsecls()
    }
    let r = self.parseref()
    if r.is_none() {
      raise self.error("invalid argument")
    }
    if hasenv && env {
      raise self.error("only one environment allowed")
    }
    if !arg && !r.is_tmp() {
      raise self.error("invalid function parameter")
    }
    // Build the instruction based on class/env/arg
    let fn_ = self.curfn()
    let ins : @types.Ins = if k == @types.Kx {
      // Type class
      if arg {
        @types.Ins::new(
          @types.Argc,
          @types.Kl,
          @types.Ref::none(),
          @types.Ref::typ(ty),
          r,
        )
      } else {
        @types.Ins::new(
          @types.Parc,
          @types.Kl,
          r,
          @types.Ref::typ(ty),
          @types.Ref::none(),
        )
      }
    } else if env {
      if arg {
        @types.Ins::new(
          @types.Arge,
          k,
          @types.Ref::none(),
          r,
          @types.Ref::none(),
        )
      } else {
        @types.Ins::new(
          @types.Pare,
          k,
          r,
          @types.Ref::none(),
          @types.Ref::none(),
        )
      }
    } else if bh >= 0 {
      // Sub-word ABI operand (C parse.c Oargsb/Oparsb + (k - Ksb)).
      let op = if arg {
        @types.Op::from_index(@types.Argsb.index() + bh)
      } else {
        @types.Op::from_index(@types.Parsb.index() + bh)
      }
      if arg {
        @types.Ins::new(
          op,
          @types.Kw,
          @types.Ref::none(),
          r,
          @types.Ref::none(),
        )
      } else {
        @types.Ins::new(
          op,
          @types.Kw,
          r,
          @types.Ref::none(),
          @types.Ref::none(),
        )
      }
    } else if arg {
      @types.Ins::new(@types.Arg, k, @types.Ref::none(), r, @types.Ref::none())
    } else {
      @types.Ins::new(@types.Par, k, r, @types.Ref::none(), @types.Ref::none())
    }
    // Add instruction to current block (or pending list during signature)
    if self.curblk >= 0 {
      fn_.blks[self.curblk].ins.push(ins)
    } else {
      self.par_ins.push(ins)
    }
    hasenv = env || hasenv
    if self.peek_kind() == TRpa {
      break
    }
    self.expect(TCom) // ,
  }
  self.expect(TRpa) // )
  vararg
}

///|
// Find or create a block by name
fn Parser::findblk(self : Self, name : String) -> Int32 raise {
  let fn_ = self.curfn()
  let existing = fn_.find_blk(name)
  if existing >= 0 {
    return existing
  }
  fn_.add_blk(name)
}

///|
// Parse a single line of the function body (block label, instruction, or jump)
fn Parser::parseline(self : Self, ps : PState) -> PState raise {
  let t = self.next_nl()
  let fn_ = self.curfn()
  if ps == PLbl && t != TLoc && t != TRbr {
    raise self.error("label or } expected")
  }
  match t {
    TRbr => return PEnd
    TLoc => {
      // Block label
      let blk_id = self.findblk(self.tokens[self.pos - 1].raw)
      // If current block has no jump, add an implicit jmp
      if self.curblk >= 0 {
        let curb = fn_.blks[self.curblk]
        if curb.jmp.kind == @types.Jxxx {
          curb.jmp.kind = @types.Jjmp
          curb.jmp.s1 = blk_id
        }
      }
      // Check for duplicate block definition
      let new_blk = fn_.blks[blk_id]
      if new_blk.jmp.kind != @types.Jxxx {
        raise self.error("multiple definitions of block @\{new_blk.name}")
      }
      // Record definition order
      fn_.def_order.push(blk_id)
      self.curblk = blk_id
      self.expect(TNl)
      return PPhi
    }
    TRet => {
      // Return instruction (C parse.c): the jump class comes from the
      // function's declared return class; a missing value means ret0.
      let curb = fn_.blks[self.curblk]
      // rcls codes: Kw..Kd = 0..3, Ksb..Kuh = 4..7, Kc = 8, K0 = 9.
      let mut kind = match self.rcls {
        0 => @types.Jretw
        1 => @types.Jretl
        2 => @types.Jrets
        3 => @types.Jretd
        4 => @types.Jretsb
        5 => @types.Jretub
        6 => @types.Jretsh
        7 => @types.Jretuh
        8 => @types.Jretc
        _ => @types.Jret0
      }
      if self.peek_kind() == TNl {
        kind = @types.Jret0
      } else if self.rcls != 9 {
        let r = self.parseref()
        if r.is_none() {
          raise self.error("invalid return value")
        }
        curb.jmp.arg = r
      }
      curb.jmp.kind = kind
      self.expect(TNl)
      return PLbl
    }
    TJmp => {
      // Unconditional jump
      let curb = fn_.blks[self.curblk]
      curb.jmp.kind = @types.Jjmp
      self.expect(TLoc)
      curb.jmp.s1 = self.findblk(self.tokens[self.pos - 1].raw)
      self.check_not_start(curb.jmp.s1)
      self.expect(TNl)
      return PLbl
    }
    TJnz => {
      // Conditional jump
      let curb = fn_.blks[self.curblk]
      curb.jmp.kind = @types.Jjnz
      let r = self.parseref()
      if r.is_none() {
        raise self.error("invalid argument for jnz jump")
      }
      curb.jmp.arg = r
      self.expect(TCom) // ,
      self.expect(TLoc)
      curb.jmp.s1 = self.findblk(self.tokens[self.pos - 1].raw)
      self.check_not_start(curb.jmp.s1)
      self.expect(TCom) // ,
      self.expect(TLoc)
      curb.jmp.s2 = self.findblk(self.tokens[self.pos - 1].raw)
      self.check_not_start(curb.jmp.s2)
      self.expect(TNl)
      return PLbl
    }
    THlt => {
      // Halt instruction (treated as a jump)
      let curb = fn_.blks[self.curblk]
      curb.jmp.kind = @types.Jhlt
      self.expect(TNl)
      return PLbl
    }
    TTemp => {
      // Instruction with result: %tmp = class op args...
      let to = self.tmpref(self.tokens[self.pos - 1].raw)
      self.expect(TEq) // =
      let (cls, ty, bh) = self.parsecls()
      let op_tok = self.next()
      // C permits subword/aggregate classes for calls only.
      if (bh >= 0 || cls == @types.Kx) &&
        !(op_tok.kind == TId && op_tok.raw == "call") {
        raise self.error("size class must be w, l, s, or d")
      }
      // Check for phi
      if op_tok.kind == TPhi {
        if ps != PPhi || self.curblk == fn_.def_order[0] {
          raise self.error("unexpected phi instruction")
        }
        self.parse_phi(to, cls)
        return PPhi
      }
      // Check for call
      if op_tok.kind == TId && op_tok.raw == "call" {
        self.parse_call(to, cls, ty)
        self.expect(TNl)
        return PIns
      }
      // Regular instruction
      let op = if op_tok.kind == TId {
        @types.Op::from_string(op_tok.raw)
      } else {
        @types.Oxxx
      }
      if op == @types.Oxxx {
        raise self.error("unknown keyword \{op_tok.raw}")
      }
      // Inline assembly: %r =l asm "text" (%in1, %in2)
      if op == @types.InlineAsm {
        let ins = self.parse_asm_ins(cls, to)
        fn_.blks[self.curblk].ins.push(ins)
        self.expect(TNl)
        return PIns
      }
      // Parse arguments
      let (arg1, arg2) = self.parse_ins_args()
      let ins = @types.Ins::new(op, cls, to, arg1, arg2)
      fn_.blks[self.curblk].ins.push(ins)
      self.expect(TNl)
      return PIns
    }
    TId => {
      // Instruction without result (store, call, vastart)
      let name = self.tokens[self.pos - 1].raw
      if name == "dbgloc" {
        // Debug location: dbgloc LINE[, COL] (C parse.c case Odbgloc).
        self.expect(TInt)
        let line = parse_int64(self.tokens[self.pos - 1].raw)
        if line < 0L || line > 536870911L {
          raise self.error("line number too big")
        }
        let mut col : Int64 = 0L
        if self.peek_kind() == TCom {
          let _ = self.next()
          self.expect(TInt)
          col = parse_int64(self.tokens[self.pos - 1].raw)
          if col < 0L || col > 536870911L {
            raise self.error("column number too big")
          }
        }
        let ins = @types.Ins::new_void(
          @types.Dbgloc,
          @types.Kw,
          @types.Ref::rint(line.to_int()),
          @types.Ref::rint(col.to_int()),
        )
        fn_.blks[self.curblk].ins.push(ins)
        self.expect(TNl)
        return PIns
      }
      if name == "asm" {
        // Inline assembly with no output: asm "text" (%in1, %in2)
        let ins = self.parse_asm_ins(@types.Kw, @types.Ref::none())
        fn_.blks[self.curblk].ins.push(ins)
        self.expect(TNl)
        return PIns
      }
      if @types.Op::from_string(name).is_store() {
        // Store instruction: storew value, addr
        let op = @types.Op::from_string(name)
        let (arg1, arg2) = self.parse_ins_args()
        let ins = @types.Ins::new_void(op, @types.Kw, arg1, arg2)
        fn_.blks[self.curblk].ins.push(ins)
        self.expect(TNl)
        return PIns
      }
      if name == "blit" {
        // blit %dst, %src, size (C parse.c Tblit). The parser splits it into
        // two pseudo instructions: blit0 with the two addresses and blit1 with
        // the constant size, which ifopt.simpl later expands into load/store
        // chunks. The class letter is not part of the syntax.
        let dst = self.parseref()
        self.expect(TCom) // ,
        let src = self.parseref()
        self.expect(TCom) // ,
        let sz = self.parseref()
        if dst.is_none() || src.is_none() || sz.is_none() {
          raise self.error("invalid instruction argument")
        }
        if !sz.is_con() {
          raise self.error("blit size must be constant")
        }
        let c = fn_.cons[sz.con_val()]
        if c.kind != @types.CBits || c.bits.i < 0L || c.bits.i > 268435455L {
          raise self.error("invalid blit size")
        }
        let b = fn_.blks[self.curblk]
        b.ins.push(@types.Ins::new_void(@types.Blit0, @types.Kw, dst, src))
        b.ins.push(
          @types.Ins::new_void(
            @types.Blit1,
            @types.Kw,
            @types.Ref::rint(c.bits.i.to_int()),
            @types.Ref::none(),
          ),
        )
        self.expect(TNl)
        return PIns
      }
      if name == "vastart" {
        let r = self.parseref()
        if r.is_none() {
          raise self.error("invalid argument for vastart")
        }
        if !fn_.is_vararg {
          raise self.error("cannot use vastart in non-variadic function")
        }
        let ins = @types.Ins::new_void(
          @types.Vastart,
          @types.Kw,
          r,
          @types.Ref::none(),
        )
        fn_.blks[self.curblk].ins.push(ins)
        self.expect(TNl)
        return PIns
      }
      if name == "call" {
        // Call without result
        self.parse_call(@types.Ref::none(), @types.Kw, -1)
        self.expect(TNl)
        return PIns
      }
      raise self.error("label, instruction or jump expected")
    }
    _ => raise self.error("label, instruction or jump expected")
  }
}

///|
// A jump may not target the entry block (C parse.c: "invalid jump to the
// start block"); dominator and phi construction assume the entry has no
// predecessors.
fn Parser::check_not_start(self : Self, b : Int32) -> Unit raise {
  let d = self.curfn().def_order
  if d.length() > 0 && b == d[0] {
    raise self.error("invalid jump to the start block")
  }
}

///|
// Parse phi node arguments: @blk val, @blk val, ...
fn Parser::parse_phi(
  self : Self,
  to : @types.Ref,
  cls : @types.Class,
) -> Unit raise {
  let phi = @types.Phi::new(to, cls)
  // Parse arguments: @blk val, @blk val, ...
  if self.peek_kind() != TNl {
    while true {
      // Expect block label
      self.expect(TLoc)
      let blk_id = self.findblk(self.tokens[self.pos - 1].raw)
      let val = self.parseref()
      if val.is_none() {
        raise self.error("invalid phi argument")
      }
      phi.args.push(@types.PhiArg::{ value: val, blk_id, })
      if self.peek_kind() == TNl {
        break
      }
      self.expect(TCom) // ,
    }
  }
  self.expect(TNl)
  let fn_ = self.curfn()
  fn_.blks[self.curblk].phi.push(phi)
}

///|
// Parse a call instruction: call $name(arg_list)
fn Parser::parse_call(
  self : Self,
  to : @types.Ref,
  cls : @types.Class,
  ty : Int32,
) -> Unit raise {
  // Any call makes the function non-leaf (C parse.c: curf->leaf = 0).
  self.curfn().leaf = false
  // Parse function reference
  let callee = self.parseref()
  if callee.is_none() {
    raise self.error("invalid callee in call")
  }
  // Parse argument list; a variadic call is marked by an Argv instruction.
  let _is_vararg = self.parserefl(true)
  let op = @types.Call
  let (call_cls, arg2) = if cls == @types.Kx {
    (@types.Kl, @types.Ref::typ(ty))
  } else {
    (cls, @types.Ref::none())
  }
  let ins = @types.Ins::new(op, call_cls, to, callee, arg2)
  self.curfn().blks[self.curblk].ins.push(ins)
}

///|
// Parse instruction arguments (0, 1, or 2 refs)
// Returns (arg1, arg2) where unused args are ref_none()
// Parse the body of an inline-assembly instruction (port extension):
//
//   asm "dmb ish"
//   asm "msr daifset, #2" (%x)
//   %r =l asm "rbit %0, %1" (%x)
//
// %0 is the output, %1 and %2 the inputs, in that order. The text is a QBE
// string literal, so its escapes (\n) are decoded by the lexer.
fn Parser::parse_asm_ins(
  self : Self,
  cls : @types.Class,
  to : @types.Ref,
) -> @types.Ins raise {
  if self.peek_kind() != TStr {
    raise self.error("string literal expected after asm")
  }
  let tok = self.next()
  let text = decode_asm_escapes(tok.raw)
  if text.length() == 0 {
    raise self.error("DBG empty asm text, kind=\{tok.kind_str()}")
  }
  let mut arg1 = @types.Ref::none()
  let mut arg2 = @types.Ref::none()
  if self.peek_kind() == TLpa {
    let _ = self.next()
    arg1 = self.parseref()
    if arg1.is_none() {
      raise self.error("invalid asm operand")
    }
    if self.peek_kind() == TCom {
      let _ = self.next()
      arg2 = self.parseref()
      if arg2.is_none() {
        raise self.error("invalid asm operand")
      }
    }
    self.expect(TRpa)
  }
  @types.Ins::new_asm(cls, to, arg1, arg2, text)
}

///|
fn Parser::parse_ins_args(self : Self) -> (@types.Ref, @types.Ref) raise {
  let mut arg1 = @types.Ref::none()
  let mut arg2 = @types.Ref::none()
  if self.peek_kind() == TNl {
    return (arg1, arg2)
  }
  // Parse first argument
  let r1 = self.parseref()
  if r1.is_none() {
    raise self.error("invalid instruction argument")
  }
  arg1 = r1
  if self.peek_kind() == TNl {
    return (arg1, arg2)
  }
  // C parse.c parseins: after an operand, only a comma or end of line is
  // accepted.
  if self.peek_kind() != TCom {
    raise self.error(", or end of line expected")
  }
  let _ = self.next() // consume ,
  // Parse second argument
  let r2 = self.parseref()
  if r2.is_none() {
    raise self.error("invalid instruction argument")
  }
  arg2 = r2
  // Skip any additional arguments (shouldn't happen in QBE) and enforce the
  // C parse.c loop's trailing check after every operand.
  let mut nargs = 2
  while self.peek_kind() == TCom {
    let _ = self.next() // consume ,
    if nargs == 63 {
      raise self.error("too many arguments")
    }
    if self.parseref().is_none() {
      raise self.error("invalid instruction argument")
    }
    nargs += 1
  }
  if self.peek_kind() != TNl {
    raise self.error(", or end of line expected")
  }
  (arg1, arg2)
}

///|
// Decode the C-style escapes QBE string literals keep raw (the lexer preserves
// them so data strings can be emitted verbatim). Inline asm is port-only, so it
// decodes them itself; \`%%\`/operand substitution happens in the emitter.
fn decode_asm_escapes(s : String) -> String {
  let b = StringBuilder::new()
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '\\' && i + 1 < chars.length() {
      match chars[i + 1] {
        'n' => b.write_char('\n')
        't' => b.write_char('\t')
        'r' => b.write_char('\r')
        '\\' => b.write_char('\\')
        '"' => b.write_char('"')
        _ => {
          b.write_char('\\')
          b.write_char(chars[i + 1])
        }
      }
      i = i + 2
    } else {
      b.write_char(c)
      i = i + 1
    }
  }
  b.to_string()
}
