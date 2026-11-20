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
// C parse.c: the operand array and the phi block array of one instruction hold
// at most NPred entries; the 64th operand is an error.
const NPRED : Int32 = 63

///|
// C all.h NIns: the parser emits into a shared Ins insb[NIns] buffer and
// rejects the instruction that would not fit.
const NINS : Int32 = 1048576

///|
// Number of instructions currently in the open block's buffer (C parse.c
// `curi - insb`). Before the first block label the staged parameter
// instructions occupy the buffer.
fn Parser::ins_count(self : Self) -> Int32 {
  if self.curblk >= 0 {
    self.blk_nins
  } else {
    self.par_ins.length()
  }
}

///|
// Emit one parsed instruction into the open block (or the staged parameter
// list before the body starts), enforcing the reference's shared-buffer limit.
fn Parser::emit_ins(self : Self, ins : @types.Ins) -> Unit raise {
  if self.ins_count() >= NINS {
    raise self.error("too many instructions")
  }
  if self.curblk >= 0 {
    self.curfn().blks[self.curblk].ins.push(ins)
    self.blk_nins = self.blk_nins + 1
  } else {
    self.par_ins.push(ins)
  }
}

///|
// C parse.c parseline initializes `Ref arg[NPred] = {R}`: an operand slot
// that was not written holds R.
fn operand(args : Array[@types.Ref], i : Int32) -> @types.Ref {
  if i < args.length() {
    args[i]
  } else {
    @types.Ref::none()
  }
}

///|
// Parse a function definition
// export: whether the function is exported
fn Parser::parsefn(self : Self, lnk : Linkage) -> Unit raise {
  self.curblk = -1
  self.blk_nins = 0
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
        self.emit_ins(ins)
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
      if hasenv {
        raise self.error("only one environment allowed")
      }
      let _ = self.next() // consume 'env'
      (@types.Kl, -1, -1)
    } else {
      self.parsecls()
    }
    let r = self.parseref()
    if r.is_none() {
      raise self.error("invalid argument")
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
    self.emit_ins(ins)
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
      let is_first = fn_.def_order.length() == 0
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
      // C parse.c: the parameter instructions staged in insb[] are the first
      // instructions of the start block, so they count against its NIns limit.
      self.blk_nins = if is_first { self.par_ins.length() } else { 0 }
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
      // C parse.c case Ttmp: %tmp = class op operands...
      // The op token decides the path. Calls carry their own argument list and
      // bypass the class check; phi and blit are Tblit/Tphi tokens in the
      // reference, and everything else must be a public op keyword (the
      // reference lexer only knows those: any other keyword was an error when
      // the token was read).
      let to = self.tmpref(self.tokens[self.pos - 1].raw)
      self.expect(TEq) // =
      let (cls, ty, bh) = self.parsecls()
      let op_tok = self.next()
      let op_name = op_tok.raw
      if op_tok.kind == TId && op_name == "call" {
        self.parse_call(to, cls, ty)
        self.expect(TNl)
        return PIns
      }
      let mut is_phi = false
      let mut is_blit = false
      let mut op = @types.Oxxx
      if op_tok.kind == TPhi {
        is_phi = true
      } else if op_tok.kind == TId && op_name == "blit" {
        is_blit = true
      } else if op_tok.kind == TId {
        op = @types.Op::from_string(op_name)
        // "argv" is an internal op that the reference lexer does not know
        // (lexinit only maps optab[0..NPubOp) plus the explicit kwmap aliases).
        if op == @types.Oxxx || op == @types.Argv {
          raise self.error("unknown keyword \{op_name}")
        }
      } else {
        raise self.error("invalid instruction")
      }
      // C parse.c: if (k >= Ksb) err("size class must be w, l, s, or d").
      // parsecls reports the sub-word classes through bh and the aggregate
      // class as Kx; a call was handled above.
      if bh >= 0 || cls == @types.Kx {
        raise self.error("size class must be w, l, s, or d")
      }
      if is_phi {
        let (args, blks) = self.parse_operands(true)
        // C parse.c case Tphi: the state checks happen after the arguments.
        if ps != PPhi || self.curblk == fn_.def_order[0] {
          raise self.error("unexpected phi instruction")
        }
        let phi = @types.Phi::new(to, cls)
        for i in 0..<args.length() {
          phi.args.push(@types.PhiArg::{ value: args[i], blk_id: blks[i], })
        }
        fn_.blks[self.curblk].phi.push(phi)
        return PPhi
      }
      if is_blit {
        // C parse.c case Tblit: a blit written with a result is accepted too
        // (the result is dropped).
        let (args, _) = self.parse_operands(false)
        self.build_blit(args)
        return PIns
      }
      // C parse.c: vastart may only appear in a variadic function, with or
      // without a result.
      if op == @types.Vastart && !fn_.is_vararg {
        raise self.error("cannot use vastart in non-variadic function")
      }
      // Inline assembly: %r =l asm "text" (%in1, %in2) (port extension).
      if op == @types.InlineAsm {
        let ins = self.parse_asm_ins(cls, to)
        self.emit_ins(ins)
        return PIns
      }
      let (args, _) = self.parse_operands(false)
      let ins = @types.Ins::new(op, cls, to, operand(args, 0), operand(args, 1))
      self.emit_ins(ins)
      return PIns
    }
    TId => {
      // Instruction without result. C parse.c only reaches the shared
      // instruction path for stores, blit, call and vastart (plus the Odbgloc
      // token); any other op keyword fails with "label, instruction or jump
      // expected".
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
        self.emit_ins(ins)
        self.expect(TNl)
        return PIns
      }
      if name == "asm" {
        // Inline assembly with no output: asm "text" (%in1, %in2)
        let ins = self.parse_asm_ins(@types.Kw, @types.Ref::none())
        self.emit_ins(ins)
        self.expect(TNl)
        return PIns
      }
      if name == "blit" {
        // blit %dst, %src, size (C parse.c Tblit). The parser splits it into
        // two pseudo instructions: blit0 with the two addresses and blit1 with
        // the constant size, which ifopt.simpl later expands into load/store
        // chunks. The class letter is not part of the syntax.
        let (args, _) = self.parse_operands(false)
        self.build_blit(args)
        return PIns
      }
      if name == "call" {
        // Call without result
        self.parse_call(@types.Ref::none(), @types.Kw, -1)
        self.expect(TNl)
        return PIns
      }
      let op = @types.Op::from_string(name)
      if op == @types.Vastart {
        // C parse.c: the variadic guard precedes the operand loop and applies
        // to the statement form too.
        if !fn_.is_vararg {
          raise self.error("cannot use vastart in non-variadic function")
        }
        let (args, _) = self.parse_operands(false)
        self.emit_ins(
          @types.Ins::new_void(
            @types.Vastart,
            @types.Kw,
            operand(args, 0),
            operand(args, 1),
          ),
        )
        return PIns
      }
      if op.is_store() {
        // Store instruction: storew value, addr
        let (args, _) = self.parse_operands(false)
        self.emit_ins(
          @types.Ins::new_void(
            op,
            @types.Kw,
            operand(args, 0),
            operand(args, 1),
          ),
        )
        return PIns
      }
      if op == @types.Oxxx {
        // The reference lexer does not know this keyword at all.
        raise self.error("unknown keyword \{name}")
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
// C parse.c parseline operand loop, shared by every instruction shape:
//
//   i = 0;
//   if (peek() != Tnl)
//       for (;;) {
//           if (i == NPred) err("too many arguments");
//           if (op == Tphi) { expect(Tlbl); blk[i] = findblk(); }
//           arg[i] = parseref();
//           if (req(arg[i], R)) err("invalid instruction argument");
//           i++;
//           t = peek();
//           if (t == Tnl) break;
//           if (t != Tcomma) err(", or end of line expected");
//           next();
//       }
//   next();
//
// The trailing newline is consumed here; the caller applies the instruction's
// own checks afterwards.
fn Parser::parse_operands(
  self : Self,
  is_phi : Bool,
) -> (Array[@types.Ref], Array[Int32]) raise {
  let args : Array[@types.Ref] = []
  let blks : Array[Int32] = []
  if self.peek_kind() != TNl {
    while true {
      if args.length() == NPRED {
        raise self.error("too many arguments")
      }
      if is_phi {
        self.expect(TLoc)
        blks.push(self.findblk(self.tokens[self.pos - 1].raw))
      }
      let r = self.parseref()
      if r.is_none() {
        raise self.error("invalid instruction argument")
      }
      args.push(r)
      let t = self.peek_kind()
      if t == TNl {
        break
      }
      if t != TCom {
        raise self.error(", or end of line expected")
      }
      let _ = self.next()
    }
  }
  let _ = self.next()
  (args, blks)
}

///|
// C parse.c parseline `case Tblit:`: split blit dst, src, size into blit0
// (the two addresses) and blit1 (the constant byte count), which simpl later
// expands into load/store chunks. The reference parses operands through the
// shared loop, so a class letter or additional operands are ignored; the two
// instructions occupy two slots of the NIns buffer.
fn Parser::build_blit(self : Self, args : Array[@types.Ref]) -> Unit raise {
  if self.ins_count() >= NINS - 1 {
    raise self.error("too many instructions")
  }
  let fn_ = self.curfn()
  let dst = operand(args, 0)
  let src = operand(args, 1)
  let sz = operand(args, 2)
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
  self.blk_nins = self.blk_nins + 2
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
  // Parse the callee reference. C parse.c does not validate it here: a missing
  // callee leaves R in arg[0] and typecheck reports "missing first operand in
  // call".
  let callee = self.parseref()
  // Parse argument list; a variadic call is marked by an Argv instruction.
  let _is_vararg = self.parserefl(true)
  // C parse.c: aggregate result classes become Kl with the type payload, and
  // any sub-word class is narrowed to Kw.
  let (call_cls, arg2) = if cls == @types.Kx {
    (@types.Kl, @types.Ref::typ(ty))
  } else {
    (cls, @types.Ref::none())
  }
  let ins = @types.Ins::new(@types.Call, call_cls, to, callee, arg2)
  self.emit_ins(ins)
}

///|
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
  let args : Array[@types.Ref] = []
  if self.peek_kind() == TLpa {
    let _ = self.next()
    let first = self.parseref()
    if first.is_none() {
      raise self.error("invalid asm operand")
    }
    args.push(first)
    while self.peek_kind() == TCom {
      let _ = self.next()
      let r = self.parseref()
      if r.is_none() {
        raise self.error("invalid asm operand")
      }
      args.push(r)
    }
    self.expect(TRpa)
  }
  @types.Ins::new_asm_n(cls, to, args, text)
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
