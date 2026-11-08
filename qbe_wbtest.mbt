// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
// Inline assembly (a port extension): the arm64 text emitter substitutes the
// registers the allocator picked into the %0/%1/%2 placeholders.
test "inline asm reaches the arm64 text emitter" {
  let src =
    #|export function l $rbits(l %a) {
    #|@start
    #|  %o =l asm "rbit %0, %1" (%a)
    #|  ret %o
    #|}
    #|
  let text = match compile_target(src, Target::Arm64) {
    Ok(t) => t
    Err(_e) => abort("compile failed")
  }
  assert_true(text.contains("rbit x0, x0"))
}

///|
// The self-contained object writer cannot encode raw assembly, so it has to say
// so instead of silently emitting an empty instruction.
test "inline asm is rejected by the binary object emitter" {
  let src =
    #|export function l $f(l %a) {
    #|@start
    #|  %o =l asm "nop" (%a)
    #|  ret %o
    #|}
    #|
  let tokens = @lexer.Lexer::new(src, "test").tokenize()
  let p = @parser.Parser::new(tokens, "test")
  p.parse()
  let msg = try {
    let _ = compile_ir_object(
      p.get_funcs(),
      p.get_datas(),
      p.get_typs(),
      p.interner_ref(),
    )
    "no error"
  } catch {
    e => {
      let r = Repr(e)
      r.to_string()
    }
  }
  assert_true(msg.contains("inline assembly"))
}

///|
// Module emission must be independent across library calls. In particular,
// DWARF records collected for one compilation must not leak into the next.
test "compile resets DWARF module state" {
  let first =
    #|export function w $first() {
    #|@start
    #|  ret 1
    #|}
    #|
  let second =
    #|export function w $second() {
    #|@start
    #|  ret 2
    #|}
    #|
  @util.set_debug_info(true)
  let _ = compile(first)
  let second_text = match compile(second) {
    Ok(text) => text
    Err(_e) => abort("compile failed")
  }
  @util.set_debug_info(false)
  assert_true(second_text.contains("\t.asciz \"second\"\n"))
  assert_true(!second_text.contains("\t.asciz \"first\"\n"))
}

///|
// A blit that reaches wasm instruction selection used to be dropped silently
// because the wasm pipeline skipped simpl(), which expands the blit0/blit1
// pseudo pair for every other target.
test "wasm: blit is expanded before instruction selection" {
  let src =
    #|export function w $f(l %p, w %x) {
    #|@start
    #|  %a =l alloc4 4
    #|  storew %x, %a
    #|  blit %a, %p, 4
    #|  %r =w loadw %p
    #|  ret %r
    #|}
    #|
  let (funcs, _, _, typs, interner) = parse_module(src, "test")
  let fn_ = funcs[0]
  let sb = StringBuilder::StringBuilder()
  run_passes_wasm(fn_, interner, typs, DbFlags::new(), sb)
  let mut blits = 0
  let mut chunks = 0
  for id in fn_.def_order {
    for ins in fn_.blks[id].ins {
      if ins.op == @types.Blit0 || ins.op == @types.Blit1 {
        blits = blits + 1
      }
      if ins.op == @types.Storew || ins.op == @types.Load {
        chunks = chunks + 1
      }
    }
  }
  assert_eq(blits, 0)
  assert_true(chunks > 0)
}

///|
// wasm has no inline-assembly lowering; it must be a hard error rather than a
// silently missing instruction.
test "wasm: inline assembly is rejected" {
  let src =
    #|export function l $g(l %p) {
    #|@start
    #|  %o =l asm "ldxr %0, [%1]" (%p)
    #|  ret %o
    #|}
    #|
  match compile_wasm(src) {
    Ok(_) => fail("expected wasm to reject inline assembly")
    Err(@util.QbeError::CompileError(m)) =>
      assert_true(m.contains("inline assembly"))
    Err(_) => fail("unexpected error kind")
  }
}

///|
test "inline asm decodes string escapes before emission" {
  let src = "export function l $f(l %a) {\n@start\n %o =l asm \"nop\\n\\tnop\" (%a)\n ret %o\n}\n"
  let text = match compile_target(src, Target::Arm64) {
    Ok(t) => t
    Err(_) => abort("compile failed")
  }
  assert_true(text.contains("\tnop\n\tnop\n"))
}

///|
test "inline asm is rejected loudly on backends without a lowering" {
  let src = "export function l $f(l %a) {\n@start\n %o =l asm \"nop\" (%a)\n ret %o\n}\n"
  for t in [Target::Amd64Sysv, Target::Amd64Win, Target::Rv64, Target::La64] {
    let msg = match compile_target(src, t) {
      Ok(_) => "no error"
      Err(e) => Repr(e).to_string()
    }
    assert_true(msg.contains("inline assembly is not supported"))
  }
}

///|
test "wasm rejects data pointers to undefined symbols" {
  let src = "data $p = { l $ext }\nexport function l $f() {\n@start\n %v =l loadl $p\n ret %v\n}\n"
  let ok = match compile_target(src, Target::Wasm32) {
    Ok(_) => false
    Err(e) => Repr(e).to_string().contains("undefined symbol")
  }
  assert_true(ok)
}

///|
test "wasm rejects static data overlapping the stack" {
  let src = "data $big = { z 70000 }\nexport function w $f() {\n@start\n ret 0\n}\n"
  let ok = match compile_target(src, Target::Wasm32) {
    Ok(_) => false
    Err(e) => Repr(e).to_string().contains("overlaps the stack")
  }
  assert_true(ok)
}
