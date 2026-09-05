///|
// Tests for wasm instruction selection and control-flow conversion.

///|
// Parse IL text and populate RPO/preds so CFG-based helpers work.
fn wasm_isel_parse(text : String) -> @types.Fn raise {
  let lexer = @lexer.Lexer::new(text, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  f
}

///|
test "is_simple_addr: only [base + offset] qualifies" {
  assert_true(is_simple_addr(@types.Ref::tmp(5), @types.Ref::none(), 1))
  assert_true(!is_simple_addr(@types.Ref::tmp(5), @types.Ref::tmp(6), 1))
  assert_true(!is_simple_addr(@types.Ref::tmp(5), @types.Ref::none(), 4))
}

///|
test "is_wasm_mem_offset: non-negative integer constants only" {
  assert_true(is_wasm_mem_offset(@types.Con::int(8)))
  assert_true(is_wasm_mem_offset(@types.Con::int(0)))
  assert_true(!is_wasm_mem_offset(@types.Con::int(-1)))
}

///|
test "wasm_mem_offset: extracts the numeric value" {
  assert_eq(wasm_mem_offset(@types.Con::int(16)), 16L)
  assert_eq(wasm_mem_offset(@types.Con::int(-3)), -3L)
}

///|
test "is_loop_header / get_loop_header: detect back-edge targets" {
  // b0 -> b1 -> b2 -> b1 (back edge to b1)
  let src =
    #|function w $f(w %n) {
    #|@start
    #|  jmp @head
    #|@head
    #|  %i =w add %n, 1
    #|  jnz %i, @body, @exit
    #|@body
    #|  jmp @head
    #|@exit
    #|  ret %i
    #|}
    #|
  let f = wasm_isel_parse(src)
  assert_true(is_loop_header(f, f.blk_names["head"]))
  assert_true(!is_loop_header(f, f.blk_names["start"]))
  assert_eq(get_loop_header(f, f.blk_names["head"]), f.blk_names["head"])
  assert_eq(get_loop_header(f, f.blk_names["exit"]), -1)
}

///|
test "convert_ctrl_flow: diamond CFG yields br_if and return" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %c =w cslew %a, %b
    #|  jnz %c, @t, @e
    #|@t
    #|  jmp @exit
    #|@e
    #|  jmp @exit
    #|@exit
    #|  ret %a
    #|}
    #|
  let f = wasm_isel_parse(src)
  let ctrl = convert_ctrl_flow(f, @util.Interner::new())
  let start_ctrl = ctrl[f.blk_names["start"]]
  let mut has_brif = false
  for c in start_ctrl {
    match c {
      WBrIf(_) => has_brif = true
      _ => ()
    }
  }
  assert_true(has_brif)
  let exit_ctrl = ctrl[f.blk_names["exit"]]
  assert_true(exit_ctrl.length() == 1)
  match exit_ctrl[0] {
    WReturn => ()
    _ => assert_true(false)
  }
}

///|
test "isel_wasm: arithmetic passes through, amd64-only ops are dropped" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  %d =w div %s, 7
    #|  ret %d
    #|}
    #|
  let f = wasm_isel_parse(src)
  let dbg = isel_wasm(f, @util.Interner::new(), true, [])
  assert_true(dbg.contains("After wasm instruction selection"))
  // Add survives; the amd64-only xidiv lowering never appears on wasm
  assert_true(!dbg.contains("xidiv"))
  assert_true(dbg.contains("add"))
}

///|
test "isel_wasm: debug output is empty when print_dbg is false" {
  let src =
    #|function w $f(w %a) {
    #|@start
    #|  ret %a
    #|}
    #|
  let f = wasm_isel_parse(src)
  let quiet = isel_wasm(f, @util.Interner::new(), false, [])
  assert_eq(quiet, "")
}
