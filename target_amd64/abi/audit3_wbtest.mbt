///|
// Audit round 3: transcription checks for the SysV ABI aggregate path
// (vendor/qbe/amd64/sysv.c selpar).

///|
test "abi: aggregate chunk temporaries are Kl like C selpar" {
  // C selpar creates both register-chunk temporaries of an aggregate
  // parameter with class Kl, regardless of the eightbyte classes:
  //
  //     a->ref[1] = newtmp("abi", Kl, fn);
  //     ...
  //     a->ref[0] = newtmp("abi", Kl, fn);
  //
  // and then copies into them with the eightbyte class:
  //
  //     emit(Ocopy, a->cls[0], a->ref[0], r, R);
  //
  // The temporary class is what live/rega read (KBASE(tmp.cls) selects the
  // register file and nlive[] bucket), so it must be Kl even for a float
  // aggregate.
  let src =
    #|type :hfa = { d, d }
    #|function d $f(:hfa %a) {
    #|@start
    #|  %v =d load %a
    #|  ret %v
    #|}
    #|
  let (f, interner, typs) = abi_parse_frontend(src)
  ignore(abi(f, typs, false, interner, typs))
  let mut checked = 0
  for id in f.def_order {
    for ins in f.blks[id].ins {
      if ins.op == @types.Copy &&
        ins.cls == @types.Kd &&
        ins.to.is_tmp() &&
        f.tmps[ins.to.tmp_val()].name.has_prefix("abi") {
        assert_eq(f.tmps[ins.to.tmp_val()].cls, @types.Kl)
        checked = checked + 1
      }
    }
  }
  // the HFA parameter is copied in two double chunks
  assert_eq(checked, 2)
}
