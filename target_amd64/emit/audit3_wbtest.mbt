///|
// Audit round 3: emit-side checks (vendor/qbe/amd64/emit.c).

///|
test "emit: an unrepresentable instruction class raises instead of panicking" {
  // C amd64/emit.c reads clstoa[i->cls] unchecked; a class outside Kw..Kd
  // cannot be spelled in an instruction format, so the port reports it as a
  // compile error instead of indexing out of bounds.
  let src =
    #|function w $f() {
    #|@start
    #|  ret 0
    #|}
    #|
  let (f, interner, typs) = emit_parse_pipeline(src)
  let sb = StringBuilder::StringBuilder()
  let st = EmitState::{
    fn_: f,
    interner,
    gasloc: ".L",
    gassym: "",
    apple: false,
    windows: false,
    sb,
    fp: "%rbp",
    fsz: 0L,
    nclob: 0,
  }
  let ins = @types.Ins::new(
    @types.Copy,
    @types.Kx,
    @types.Ref::none(),
    @types.Ref::none(),
    @types.Ref::none(),
  )
  let raised = try {
    emitf(st, "mov%k %0, %=", ins)
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

///|
test "emit: a dark aggregate call argument is rejected cleanly" {
  // A struct holding a dark type classifies to Kx in the port: upstream C
  // reads uninitialised Typ fields here (parsetyp returns before assigning
  // ty->fields/ty->nunion for dark types), so there is no defined reference
  // behaviour to transcribe. The call argument chunk then carries a Kx class;
  // the port must report a compile error, not panic in emitf.
  //
  // Reference output for this input is arbitrary (it indexes clstoa[-1] and
  // picks the float register path); the port's -dA differs by design.
  let src =
    #|type :dk = align 8 { 16 }
    #|type :st = { :dk }
    #|export function $f(:st %a) {
    #|@start
    #|  call $g(:st %a)
    #|  ret
    #|}
    #|
  let raised = try {
    ignore(emit_gas(src, ".L", ""))
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}
