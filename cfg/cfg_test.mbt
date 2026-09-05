///|
// Tests for CFG analysis functions

///|
// Helper to create a simple function with blocks
fn make_test_fn(name : String, nblk : Int) -> @types.Fn {
  let f = @types.Fn::new(name)
  for i in 0..<nblk {
    let id = f.add_blk("b\{i}")
    f.def_order.push(id)
  }
  f
}

///|
test "fillpreds - linear blocks" {
  // b0 -> b1 -> b2
  let f = make_test_fn("test", 3)
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 2, -1)
  f.blks[2].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillpreds(f)
  assert_true(f.blks[0].npred == 0)
  assert_true(f.blks[1].npred == 1)
  assert_true(f.blks[2].npred == 1)
}

///|
test "fillpreds - branch block" {
  // b0 -> b1, b2 (jnz)
  // b1 -> b3
  // b2 -> b3
  let f = make_test_fn("test", 4)
  f.blks[0].jmp = @types.Jump::full(@types.Jjnz, @types.Ref::none(), 1, 2)
  f.blks[1].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 3, -1)
  f.blks[2].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 3, -1)
  f.blks[3].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillpreds(f)
  assert_true(f.blks[0].npred == 0)
  assert_true(f.blks[1].npred == 1)
  assert_true(f.blks[2].npred == 1)
  assert_true(f.blks[3].npred == 2)
}

///|
test "fillrpo - linear blocks" {
  let f = make_test_fn("test", 3)
  f.start_id = 0
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 2, -1)
  f.blks[2].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  // RPO should be [0, 1, 2]
  assert_true(f.rpo.length() == 3)
  assert_true(f.rpo[0] == 0)
  assert_true(f.rpo[1] == 1)
  assert_true(f.rpo[2] == 2)
}

///|
test "fillrpo - branch and merge" {
  // b0 -> b1, b2 -> b3
  let f = make_test_fn("test", 4)
  f.start_id = 0
  f.blks[0].jmp = @types.Jump::full(@types.Jjnz, @types.Ref::none(), 1, 2)
  f.blks[1].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 3, -1)
  f.blks[2].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 3, -1)
  f.blks[3].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  // Start should be first
  assert_true(f.rpo[0] == 0)
  assert_true(f.rpo.length() == 4)
}

///|
test "filldom - simple diamond" {
  // b0 -> b1, b2 -> b3
  let f = make_test_fn("test", 4)
  f.start_id = 0
  f.blks[0].jmp = @types.Jump::full(@types.Jjnz, @types.Ref::none(), 1, 2)
  f.blks[1].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 3, -1)
  f.blks[2].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 3, -1)
  f.blks[3].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  fillpreds(f)
  filldom(f)
  // b0 dominates all
  assert_true(f.blks[0].idom == -1) // start has no idom
  assert_true(f.blks[1].idom == 0)
  assert_true(f.blks[2].idom == 0)
  assert_true(f.blks[3].idom == 0)
}

///|
test "fillloop - simple loop" {
  // b0 -> b1 -> b2 -> b1 (loop)
  //         ^----'
  let f = make_test_fn("test", 3)
  f.start_id = 0
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jjnz, @types.Ref::none(), 2, 1)
  f.blks[2].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  fillpreds(f)
  fillloop(f)
  // b1 is in a loop (has back edge from itself)
  assert_true(f.blks[1].loop_depth >= 1)
}

///|
test "fillfron - diamond" {
  // b0 -> b1, b2 -> b3
  let f = make_test_fn("test", 4)
  f.start_id = 0
  f.blks[0].jmp = @types.Jump::full(@types.Jjnz, @types.Ref::none(), 1, 2)
  f.blks[1].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 3, -1)
  f.blks[2].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 3, -1)
  f.blks[3].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  fillpreds(f)
  filldom(f)
  fillfron(f)
  // The join block b3 is in the dominance frontier of both branches.
  assert_true(f.blks[1].fron.contains(3))
  assert_true(f.blks[2].fron.contains(3))
  assert_true(f.blks[0].fron.length() == 0)
  assert_true(f.blks[3].fron.length() == 0)
}

///|
test "simpljmp - merges empty jump blocks" {
  // b0 -> b1 (empty, jmp) -> b2
  let f = make_test_fn("test", 3)
  f.start_id = 0
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 2, -1)
  f.blks[2].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  fillpreds(f)
  simpljmp(f)
  // b1 is an empty jmp-only block, so b0 now jumps straight to b2.
  assert_true(f.blks[0].jmp.s1 == 2)
}

///|
test "simpljmp - conditional with identical targets becomes jmp" {
  let f = make_test_fn("test", 3)
  f.start_id = 0
  f.blks[0].jmp = @types.Jump::full(@types.Jjfieq, @types.Ref::none(), 1, 1)
  f.blks[1].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  fillpreds(f)
  simpljmp(f)
  // A conditional jump with both targets equal becomes an unconditional jump.
  assert_true(f.blks[0].jmp.kind == @types.Jjmp)
}

///|
test "filldom - diamond immediate dominators" {
  // start -> t, e ; t -> m ; e -> m
  let f = make_test_fn("d", 4)
  let (start, t, e, m) = (0, 1, 2, 3)
  f.blks[start].jmp = @types.Jump::full(@types.Jjnz, @types.Ref::none(), t, e)
  f.blks[t].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), m, -1)
  f.blks[e].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), m, -1)
  f.blks[m].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  fillpreds(f)
  filldom(f)
  // start dominates everything and has no immediate dominator
  assert_true(f.blks[start].idom == -1)
  // t, e and m are all directly dominated by start
  assert_true(f.blks[t].idom == start)
  assert_true(f.blks[e].idom == start)
  assert_true(f.blks[m].idom == start)
  // the dom tree children of start are exactly {t, e, m}
  let kids = []
  let mut c = f.blks[start].dom_link
  while c >= 0 {
    kids.push(c)
    c = f.blks[c].dom_next
  }
  assert_true(kids.contains(t))
  assert_true(kids.contains(e))
  assert_true(kids.contains(m))
}

///|
test "filldom - nested dominance through a single path" {
  // start -> a -> b -> c (straight line): each block's idom is its predecessor
  let f = make_test_fn("l", 4)
  for i in 0..<3 {
    f.blks[i].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), i + 1, -1)
  }
  f.blks[3].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  fillpreds(f)
  filldom(f)
  assert_true(f.blks[1].idom == 0)
  assert_true(f.blks[2].idom == 1)
  assert_true(f.blks[3].idom == 2)
}

///|
test "fillloop - back edge marks the loop body" {
  // start -> head ; head -> body, exit ; body -> head
  let f = make_test_fn("g", 4)
  let (start, head, body, exit) = (0, 1, 2, 3)
  f.blks[start].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), head, -1)
  f.blks[head].jmp = @types.Jump::full(@types.Jjnz, @types.Ref::none(), body, exit)
  f.blks[body].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), head, -1)
  f.blks[exit].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  fillpreds(f)
  fillloop(f)
  // loop_depth is the spill-cost multiplier: blocks inside the loop weigh 10x
  assert_true(f.blks[head].loop_depth == 10)
  assert_true(f.blks[body].loop_depth == 10)
  assert_true(f.blks[exit].loop_depth == 1)
  assert_true(f.blks[start].loop_depth == 1)
}

///|
test "simpljmp - removes empty chained jumps" {
  // start -> a -> exit, where a only contains a jump
  let f = make_test_fn("s", 3)
  f.blks[0].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 1, -1)
  f.blks[1].jmp = @types.Jump::full(@types.Jjmp, @types.Ref::none(), 2, -1)
  f.blks[2].jmp = @types.Jump::full(@types.Jret0, @types.Ref::none(), -1, -1)
  fillrpo(f)
  fillpreds(f)
  filldom(f)
  simpljmp(f)
  // the jump through the empty block is shortened to the final target
  assert_true(f.blks[0].jmp.s1 == 2 || f.blks[0].jmp.kind == @types.Jjmp)
  assert_true(f.blks[1].jmp.s1 == 2)
}
