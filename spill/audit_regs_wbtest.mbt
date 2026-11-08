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
