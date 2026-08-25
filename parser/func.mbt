///|
// Parser state for block/instruction parsing (internal)
enum PState {
  PLbl // Expecting a label
  PPhi // Parsing phi nodes
  PIns // Parsing instructions
  PEnd // End of function body
} derive(Eq)

///|
// Parse a function definition
// export: whether the function is exported
fn Parser::parsefn(self : Self, is_export : Bool) -> Unit raise {
  self.curblk = -1
  // Parse return class and function name
  // If next token is not TGlo, parse the return class first
  let mut ret_ty = -1
  self.rcls = 5 // default: void return
  if self.peek_kind() != TGlo {
    let (cls, ty) = self.parsecls()
    ret_ty = ty
    // Map class to return class index
    self.rcls = match cls {
      @types.Kw => 0
      @types.Kl => 1
      @types.Ks => 2
      @types.Kd => 3
      @types.Kx => 4
    }
  }
  // Expect function name ($name)
  let name_tok = self.next()
  if name_tok.kind != TGlo {
    raise self.error("function name expected")
  }
  // Create the function
  let fn_ = @types.Fn::new(name_tok.raw)
  fn_.is_export = is_export
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
    for i = self.par_ins.length() - 1; i >= 0; i = i - 1 {
      start.ins.insert(0, self.par_ins[i])
    }
  }
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
  while true {
    let pk = self.peek_kind()
    if pk == TRpa || pk == TDot3 {
      break
    }
    // Parse environment or class
    let env = pk == TId && self.peek().raw == "env"
    let (k, ty) : (@types.Class, Int) = if env {
      let _ = self.next() // consume 'env'
      (@types.Kl, -1)
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
          @types.ref_none(),
          @types.Ref::typ(ty),
          r,
        )
      } else {
        @types.Ins::new(
          @types.Parc,
          @types.Kl,
          r,
          @types.Ref::typ(ty),
          @types.ref_none(),
        )
      }
    } else if env {
      if arg {
        @types.Ins::new(@types.Arge, k, @types.ref_none(), r, @types.ref_none())
      } else {
        @types.Ins::new(@types.Pare, k, r, @types.ref_none(), @types.ref_none())
      }
    } else if arg {
      @types.Ins::new(@types.Arg, k, @types.ref_none(), r, @types.ref_none())
    } else {
      @types.Ins::new(@types.Par, k, r, @types.ref_none(), @types.ref_none())
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
  // Check for ... (variadic)
  if self.peek_kind() == TDot3 {
    let _ = self.next() // consume ...
    self.expect(TRpa) // )
    return true
  }
  self.expect(TRpa) // )
  false
}

///|
// Find or create a block by name
fn Parser::findblk(self : Self, name : String) -> Int raise {
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
      // Return instruction
      let curb = fn_.blks[self.curblk]
      curb.jmp.kind = match self.rcls {
        0 => @types.Jretw
        1 => @types.Jretl
        2 => @types.Jrets
        3 => @types.Jretd
        4 => @types.Jretc
        _ => @types.Jret0
      }
      // Check if there's a return value
      if self.peek_kind() == TNl {
        curb.jmp.kind = @types.Jret0
      } else if self.rcls < 5 {
        let r = self.parseref()
        if r.is_none() {
          raise self.error("invalid return value")
        }
        curb.jmp.arg = r
      }
      self.expect(TNl)
      return PLbl
    }
    TJmp => {
      // Unconditional jump
      let curb = fn_.blks[self.curblk]
      curb.jmp.kind = @types.Jjmp
      self.expect(TLoc)
      curb.jmp.s1 = self.findblk(self.tokens[self.pos - 1].raw)
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
      self.expect(TCom) // ,
      self.expect(TLoc)
      curb.jmp.s2 = self.findblk(self.tokens[self.pos - 1].raw)
      self.expect(TNl)
      return PLbl
    }
    THlt => {
      // Halt instruction (treated as a jump)
      let curb = fn_.blks[self.curblk]
      curb.jmp.kind = @types.Jxxx // TODO: handle hlt properly
      self.expect(TNl)
      return PLbl
    }
    TTemp => {
      // Instruction with result: %tmp = class op args...
      let to = self.tmpref(self.tokens[self.pos - 1].raw)
      self.expect(TEq) // =
      let (cls, ty) = self.parsecls()
      let op_tok = self.next()
      // Check for phi
      if op_tok.kind == TPhi {
        if ps != PPhi {
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
        @types.op_from_string(op_tok.raw)
      } else {
        @types.Oxxx
      }
      if op == @types.Oxxx {
        raise self.error("invalid instruction: \{op_tok.raw}")
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
      if @types.is_store(@types.op_from_string(name)) {
        // Store instruction: storew value, addr
        let op = @types.op_from_string(name)
        let (arg1, arg2) = self.parse_ins_args()
        let ins = @types.Ins::new_void(op, @types.Kw, arg1, arg2)
        fn_.blks[self.curblk].ins.push(ins)
        self.expect(TNl)
        return PIns
      }
      if name == "vastart" {
        let r = self.parseref()
        if r.is_none() {
          raise self.error("invalid argument for vastart")
        }
        let ins = @types.Ins::new_void(
          @types.Vastart,
          @types.Kw,
          r,
          @types.ref_none(),
        )
        fn_.blks[self.curblk].ins.push(ins)
        self.expect(TNl)
        return PIns
      }
      if name == "call" {
        // Call without result
        self.parse_call(@types.ref_none(), @types.Kw, -1)
        self.expect(TNl)
        return PIns
      }
      raise self.error("label, instruction or jump expected")
    }
    _ => raise self.error("label, instruction or jump expected")
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
      phi.args.push(@types.PhiArg::{ value: val, blk_id })
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
  ty : Int,
) -> Unit raise {
  // Parse function reference
  let callee = self.parseref()
  if callee.is_none() {
    raise self.error("invalid callee in call")
  }
  // Parse argument list
  let is_vararg = self.parserefl(true)
  let op = if is_vararg { @types.Vacall } else { @types.Call }
  let (call_cls, arg2) = if cls == @types.Kx {
    (@types.Kl, @types.Ref::typ(ty))
  } else {
    (cls, @types.ref_none())
  }
  let ins = @types.Ins::new(op, call_cls, to, callee, arg2)
  self.curfn().blks[self.curblk].ins.push(ins)
}

///|
// Parse instruction arguments (0, 1, or 2 refs)
// Returns (arg1, arg2) where unused args are ref_none()
fn Parser::parse_ins_args(self : Self) -> (@types.Ref, @types.Ref) raise {
  let mut arg1 = @types.ref_none()
  let mut arg2 = @types.ref_none()
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
  self.expect(TCom) // ,
  // Parse second argument
  let r2 = self.parseref()
  if r2.is_none() {
    raise self.error("invalid instruction argument")
  }
  arg2 = r2
  // Skip any additional arguments (shouldn't happen in QBE)
  while self.peek_kind() == TCom {
    let _ = self.next() // consume ,
    let _ = self.parseref() // skip extra arg
  }
  (arg1, arg2)
}
