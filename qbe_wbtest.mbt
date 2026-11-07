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
