///|
// White-box tests for the ARM64 (AAPCS64) ABI lowering.
// Each test parses a small IL snippet, runs the target-agnostic frontend
// passes (mirroring pipeline.mbt up to abi), lowers the ABI and inspects the
// resulting IR / debug dump.

///|
fn arm64_abi_parse_frontend(
  text : String,
) -> (@types.Fn, @util.Interner, Array[@types.Typ]) raise {
  let lexer = @lexer.Lexer::new(text, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  let typs = parser.get_typs()
  let interner = parser.interner_ref()
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  @ssa.memopt(f)
  @cfg.filldom(f)
  @cfg.fillfron(f)
  let _ = @live.filllive(f, false)
  @ssa.phiins(f)
  @ssa.renblk(f)
  @ssa.filluse(f)
  @ssa.ssacheck(f)
  @cfg.fillloop(f)
  @cfg.fillalias(f)
  let _ = @ssa.loadopt(f, false, interner, typs)
  @ssa.filluse(f)
  @ssa.ssacheck(f)
  let _ = @ssa.copy(f, false, interner, typs)
  @ssa.filluse(f)
  let _ = @fold.fold(f, false, interner, typs)
  (f, interner, typs)
}

///|
test "arm64 abi: word parameters come in via x0 and x1" {
  let src =
    #|function w $f(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let dbg = abi_arm64(f, typs, true, interner, false, typs)
  // registers print as R<tmp id>: x0 is tmp 1, x1 is tmp 2
  assert_true(dbg.contains("R1"))
  assert_true(dbg.contains("R2"))
  // the result is returned through x0
  assert_true(dbg.contains("R1 =w copy"))
}

///|
test "arm64 abi: float parameters come in via v0 and v1" {
  let src =
    #|function s $f(s %a, s %b) {
    #|@start
    #|  %s =s add %a, %b
    #|  ret %s
    #|}
    #|
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let dbg = abi_arm64(f, typs, true, interner, false, typs)
  // v0 is tmp 33, v1 is tmp 34
  assert_true(dbg.contains("R33"))
  assert_true(dbg.contains("R34"))
}

///|
test "arm64 abi: call lowering passes arguments in registers" {
  let src =
    #|export function w $main() {
    #|@start
    #|  %r =w call $g(w 1, w 2)
    #|  ret %r
    #|}
    #|
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let dbg = abi_arm64(f, typs, true, interner, false, typs)
  assert_true(dbg.contains("call $g"))
  let start = f.blks[f.start_id]
  let mut calls = 0
  for ins in start.ins {
    if ins.op == @types.Call {
      calls = calls + 1
      // two gp args (bits 5-8) + one gp return (bit 0)
      assert_eq(ins.arg2.call_val(), 1 | (2 << 5))
    }
  }
  assert_eq(calls, 1)
}

///|
test "arm64 abi: large aggregate parameter is passed by pointer" {
  let src =
    #|type :big = { l, l, l }
    #|function w $f(:big %p) {
    #|@start
    #|  %a =w loadw %p
    #|  ret %a
    #|}
    #|
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let dbg = abi_arm64(f, typs, true, interner, false, typs)
  // the pointer arrives in x0 (tmp 1) and no stack blob is materialized
  assert_true(dbg.contains("copy R1"))
}

///|
test "arm64 abi: small aggregate parameter is reassembled from registers" {
  let src =
    #|type :p = { w, w }
    #|function w $f(:p %p) {
    #|@start
    #|  %a =w loadw %p
    #|  ret %a
    #|}
    #|
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let _ = abi_arm64(f, typs, false, interner, false, typs)
  let start = f.blks[f.start_id]
  // the blob is allocated (alloc4 8) and one 8-byte block is stored into it
  let mut allocs = 0
  let mut stores = 0
  for ins in start.ins {
    if ins.op == @types.Alloc4 {
      allocs = allocs + 1
    }
    if ins.op == @types.Storel {
      stores = stores + 1
    }
  }
  assert_eq(allocs, 1)
  assert_eq(stores, 1)
}

///|
test "arm64 abi: hfa parameter occupies consecutive float registers" {
  let src =
    #|type :hfa = { s, s }
    #|function $f(:hfa %h) {
    #|@start
    #|  ret
    #|}
    #|
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let dbg = abi_arm64(f, typs, true, interner, false, typs)
  // v0 and v1 (tmp 33/34) hold the two float elements; no GP register used
  assert_true(dbg.contains("R33"))
  assert_true(dbg.contains("R34"))
}

///|
test "arm64 abi: aggregate return reserves x8" {
  let src =
    #|type :big = { l, l, l }
    #|function :big $g(w %a) {
    #|@start
    #|  %b =l alloc8 24
    #|  ret %b
    #|}
    #|
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let _ = abi_arm64(f, typs, false, interner, false, typs)
  // the hidden result pointer arrives in x8 and is copied to fn.retr
  assert_true(f.retr.is_tmp())
  let start = f.blks[f.start_id]
  let mut x8_copies = 0
  for ins in start.ins {
    if ins.op == @types.Copy && ins.arg1.is_tmp() {
      if ins.arg1.tmp_val() == @types.ARM64_R8 {
        x8_copies = x8_copies + 1
      }
    }
  }
  assert_eq(x8_copies, 1)
}

///|
test "arm64 abi: vararg functions keep the shared register pool" {
  let src =
    #|export function w $f(w %n, ...) {
    #|@start
    #|  %ap =l alloc8 24
    #|  vastart %ap
    #|  ret %n
    #|}
    #|
  let (f, interner, typs) = arm64_abi_parse_frontend(src)
  let _ = abi_arm64(f, typs, false, interner, false, typs)
  // vastart writes the va_list fields relative to the save area (slot -1)
  let start = f.blks[f.start_id]
  let mut addr_ops = 0
  let mut storew_zero_base = 0
  for ins in start.ins {
    if ins.op == @types.Addr {
      addr_ops = addr_ops + 1
    }
    if ins.op == @types.Storew && ins.arg1.is_con() {
      storew_zero_base = storew_zero_base + 1
    }
  }
  // one Slotaddr for the save area, two Storew for the gr/vr offsets
  assert_eq(addr_ops, 1)
  assert_eq(storew_zero_base, 2)
}
