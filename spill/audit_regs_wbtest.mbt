///|
// C spill.c stores costs as uint and tcmp0 compares them as uint.
fn audit_spill_state(f : @types.Fn) -> SpillState {
  SpillState::{
    fn_: f,
    buf: [],
    fst: None,
    ntmp: f.ntmp(),
    locs: 0,
    slot4: 0,
    slot8: 0,
    mask: [],
  }
}

///|
test "audit registers: unsigned spill costs retain expensive temporary" {
  let f = @types.Fn::new("unsigned_cost")
  f.init_regs()
  let expensive = f.add_tmp("expensive", @types.Kw)
  let cheap = f.add_tmp("cheap", @types.Kw)
  // Three uses at a valid nine-level loop weight produce uint 3000000000.
  for _ in 0..<3 {
    tmpuse(f, @types.Ref::tmp(expensive), 1, 1000000000)
  }
  tmpuse(f, @types.Ref::tmp(cheap), 1, 1)
  let st = audit_spill_state(f)
  let live = @types.BSet::new(f.ntmp())
  live.set(expensive)
  live.set(cheap)
  limit(st, live, 1, None)
  assert_true(live.has(expensive))
  assert_true(!live.has(cheap))
  assert_eq(f.tmps[expensive].slot, -1)
  assert_eq(f.tmps[cheap].slot, 0)
}

///|
test "audit registers: physical cost outranks every lower unsigned cost" {
  let f = @types.Fn::new("physical_cost")
  f.init_regs()
  let t = f.add_tmp("virtual", @types.Kw)
  ignore(fillcost(f, false))
  // INT_MAX is not UINT_MAX: C gives the register strictly higher priority.
  f.tmps[t].cost = 2147483647
  let st = audit_spill_state(f)
  assert_eq(tcmp0(st, @types.RAX, t), -1)
  f.tmps[t].cost = -2
  assert_eq(tcmp0(st, @types.RAX, t), -1)
  f.tmps[t].cost = -1
  assert_eq(tcmp0(st, @types.RAX, t), 0)
}

///|
// C spill.c 58-59 prints nlive with "% 3d": the space flag keeps a leading
// space for non-negative values even when the value reaches the width (100).
// The old rpad call dropped it whenever the value had three or more digits.
test "audit registers: fillcost debug keeps C % 3d space flag" {
  let src =
    #|function w $f(w %n) {
    #|@start
    #|@loop
    #|  %i =w add %n, 1
    #|  jnz %i, @loop, @exit
    #|@exit
    #|  ret %i
    #|}
    #|
  let (f, interner, typs) = spill_parse_pipeline(src)
  @cfg.fillloop(f)
  let hd = f.blks[f.find_blk("loop")]
  hd.nlive_w = 105
  hd.nlive_d = 100
  let dbg = fillcost(f, true)
  // Reference: "\tloop       ( 105  100) [ ...".
  assert_true(dbg.contains(" 105  100)"))
  assert_true(!dbg.contains("(105"))
}

///|
// C spill.c 525 prints the loop value with "% 5d"; with the space flag a
// five-digit loop weight (four nested loops) keeps its leading space.
test "audit registers: spill block info keeps C % 5d space flag" {
  let src =
    #|function w $f(w %n) {
    #|@start
    #|@loop
    #|  %i =w add %n, 1
    #|  jnz %i, @loop, @exit
    #|@exit
    #|  ret %i
    #|}
    #|
  let (f, interner, typs) = spill_parse_pipeline(src)
  @cfg.fillloop(f)
  let dbg = spill_block_info_after_loop(f, interner, typs)
  assert_true(dbg.contains("( 10000) "))
  assert_true(!dbg.contains("(10000)"))
}

///|
fn spill_block_info_after_loop(
  f : @types.Fn,
  interner : @util.Interner,
  typs : Array[@types.Typ],
) -> String raise {
  // fillloop rewrites loop_depth (10^nesting), so force the width-triggering
  // value afterwards: the dump must still use C's "(% 5d)".
  @cfg.fillloop(f)
  f.blks[f.find_blk("loop")].loop_depth = 10000
  spill(f, true, interner, typs)
}
