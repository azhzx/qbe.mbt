///|
fn audit_emit_state(apple : Bool) -> Arm64EmitState {
  let f = @types.Fn::new("f")
  f.init_regs()
  let bid = f.add_blk("start")
  f.def_order.push(bid)
  f.rpo.push(bid)
  f.blks[bid].jmp = @types.Jump::new(@types.Jret0)
  {
    fn_: f,
    interner: @util.Interner::new(),
    sb: StringBuilder(),
    gasloc: if apple {
      "L"
    } else {
      ".L"
    },
    gassym: if apple {
      "_"
    } else {
      ""
    },
    apple,
    frame: 0L,
    padding: 0L,
  }
}

///|
test "audit arm64: large address uses mov and movk" {
  let st = audit_emit_state(false)
  arm64_emitins(
    st,
    @types.Ins::new(
      @types.Addr,
      @types.Kl,
      @types.Ref::tmp(@types.ARM64_R0),
      @types.Ref::slot(17500),
      @types.Ref::none(),
    ),
  )
  assert_eq(
    st.sb.to_string(),
    "\tmov\tx0, #4480\n\tmovk\tx0, #1, lsl #16\n\tadd\tx0, x29, x0\n",
  )
}

///|
test "audit arm64: large load slot materializes IP1" {
  let st = audit_emit_state(false)
  arm64_emitins(
    st,
    @types.Ins::new(
      @types.Load,
      @types.Kl,
      @types.Ref::tmp(@types.ARM64_R0),
      @types.Ref::slot(17500),
      @types.Ref::none(),
    ),
  )
  assert_true(st.sb.to_string().contains("\tldr\tx0, [x17]\n"))
}

///|
test "audit arm64: Apple large word store preserves scratch through V31" {
  // C arm64/emit.c: "ds"[i->cls == Kw] and "xw"[i->cls == Kw] give
  // "fmov d31, x17" for a Kw store, then Ostores prints "str s31".
  let st = audit_emit_state(true)
  arm64_emitins(
    st,
    @types.Ins::new(
      @types.Storew,
      @types.Kw,
      @types.Ref::none(),
      @types.Ref::tmp(@types.ARM64_IP1),
      @types.Ref::slot(17500),
    ),
  )
  assert_true(st.sb.to_string().contains("\tfmov\td31, x17\n"))
  assert_true(st.sb.to_string().contains("\tstr\ts31, [x17]\n"))
}

///|
test "audit arm64: large frame materializes prologue and epilogue size" {
  let st = audit_emit_state(false)
  st.fn_.slot = 17500
  arm64_emitfn(st)
  assert_true(st.sb.to_string().contains("\tmovk\tx16, #1, lsl #16\n"))
  assert_true(st.sb.to_string().contains("\tsub\tsp, sp, x16\n"))
  assert_true(st.sb.to_string().contains("\tadd\tsp, sp, x16\n"))
}

///|
test "audit arm64: Apple function alignment forced to four" {
  let st = audit_emit_state(true)
  arm64_emitfn(st)
  assert_eq(st.fn_.align, 4)
}

///|
test "audit arm64: huge frame callee-save offsets go through fixarg" {
  // C prologue/epilogue saves are emitted through emitins, so with a frame
  // beyond the scaled immediate range the address is materialized in x18
  // (ELF) / x17 (Apple) instead of printing an unencodable [x29, off].
  let st = audit_emit_state(false)
  st.fn_.slot = 17500
  st.fn_.reg = st.fn_.reg | (1UL << @types.ARM64_R19)
  arm64_emitfn(st)
  let out = st.sb.to_string()
  assert_true(
    out.contains(
      "\tmov\tx18, #4488\n\tmovk\tx18, #1, lsl #16\n\tadd\tx18, x29, x18\n\tstr\tx19, [x18]\n",
    ),
  )
  assert_true(out.contains("\tldr\tx19, [x17]\n"))
}

///|
test "audit arm64: frame above 2^31 keeps the reference 64-bit size" {
  // C E.frame is uint64: a frame of 2.4e9 bytes is materialized with two movk
  // pieces (the old Int32 frame overflowed to a negative immediate).
  let st = audit_emit_state(false)
  st.fn_.slot = 600000000
  arm64_emitfn(st)
  let out = st.sb.to_string()
  assert_true(
    out.contains(
      "\tmov\tx16, #6144\n\tmovk\tx16, #36621, lsl #16\n\tsub\tsp, sp, x16\n",
    ),
  )
  assert_true(
    out.contains(
      "\tmov\tx16, #6144\n\tmovk\tx16, #36621, lsl #16\n\tadd\tsp, sp, x16\n",
    ),
  )
}

///|
test "audit arm64: direct call to a quoted symbol keeps the name quoted" {
  // C emit.c Ocall: p = l[0] == '"' ? "" : T.assym, then "bl <p><l>".
  let st = audit_emit_state(true)
  let ci = st.fn_.add_con(@types.Con::addr(st.interner.intern("\"foo\"")))
  arm64_emitins(
    st,
    @types.Ins::new_void(
      @types.Call,
      @types.Kw,
      @types.Ref::con(ci),
      @types.Ref::none(),
    ),
  )
  assert_eq(st.sb.to_string(), "\tbl\t\"foo\"\n")
}

///|
test "audit arm64: direct call to a thread symbol is rejected" {
  // C emit.c Ocall dies with "invalid call argument" when sym.type & SThr.
  let st = audit_emit_state(false)
  let ci = st.fn_.add_con(
    @types.Con::addr_sym(st.interner.intern("thr"), @types.SYM_THR),
  )
  let rejected = try {
    arm64_emitins(
      st,
      @types.Ins::new_void(
        @types.Call,
        @types.Kw,
        @types.Ref::con(ci),
        @types.Ref::none(),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
