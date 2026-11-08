///|
test "audit driver: files share constants and debug indices but not type scope" {
  let a = "dbgfile \"one.c\"\ntype :local = { w }\nexport function d $audit_one() {\n@start\n dbgloc 1\n ret d_1.5\n}\n"
  let b = "dbgfile \"two.c\"\ntype :local = { d, d }\nexport function d $audit_two() {\n@start\n dbgloc 2\n ret d_2.5\n}\n"
  let text = match compile_sources([("one.ssa", a), ("two.ssa", b)], Arm64) {
    Ok(s) => s
    Err(_) => fail("compile failed")
  }
  assert_true(text.contains(".file 2 \"two.c\""))
  assert_eq(text.split(".Lfp0:").count(), 2)
  assert_true(text.contains(".Lfp1:"))
  assert_eq(text.split("/* floating point constants */").count(), 2)
  assert_eq(text.split(".note.GNU-stack").count(), 2)
  match
    compile_sources(
      [
        ("one.ssa", a),
        ("bad.ssa", "function :local $bad() {\n@start\n ret 0\n}\n"),
      ],
      Arm64,
    ) {
    Err(_) => ()
    Ok(_) => fail("type namespace leaked across files")
  }
}

///|
test "audit driver: repeated amd64 compilation resets local labels" {
  let source = "export function w $f(w %x) {\n@start\n jnz %x, @a, @b\n@a\n ret 1\n@b\n ret 2\n}\n"
  let a = match compile(source) {
    Ok(s) => s
    Err(_) => fail("compile a failed")
  }
  let b = match compile(source) {
    Ok(s) => s
    Err(_) => fail("compile b failed")
  }
  assert_eq(a, b)
}

///|
test "audit driver: post-isel loop weights are recomputed" {
  let source = "export function w $f(w %n) {\n@start\n jmp @loop\n@loop\n %i =w phi @start 0, @loop %next\n %next =w add %i, 1\n %c =w csltw %next, %n\n jnz %c, @loop, @end\n@end\n ret %next\n}\n"
  let (fs, _, _, ts, intern) = parse_module(source, "loop.ssa")
  let sink = StringBuilder::StringBuilder()
  run_passes(fs[0], intern, ts, DbFlags::new(), sink)
  let before = fs[0].blks.map(b => b.loop_depth)
  @cfg.fillloop(fs[0])
  assert_eq(before, fs[0].blks.map(b => b.loop_depth))
}
