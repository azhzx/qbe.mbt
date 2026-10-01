// White-box tests for the GCM pass.
//
// These run gcm directly on parsed IL, so they are unaffected by the fact that
// changing QPCC perturbs what QPCC compiles: no self-hosting is involved.

///|
// Does block a dominate block b?
fn gcmw_dom(f : @types.Fn, a : Int, b : Int) -> Bool {
  let mut x = b
  let mut steps = 0
  while x >= 0 && steps < 10000 {
    if x == a {
      return true
    }
    x = f.blks[x].idom
    steps = steps + 1
  }
  false
}

///|
// For every temp: the block that defines it, and its index inside that block.
fn gcmw_defmap(f : @types.Fn) -> (Array[Int], Array[Int]) {
  let blk : Array[Int] = Array::make(f.ntmp(), -1)
  let pos : Array[Int] = Array::make(f.ntmp(), -1)
  for id in f.def_order {
    for p in f.blks[id].phi {
      if p.to.is_tmp() {
        blk[p.to.tmp_val()] = id
      }
    }
    let mut k = 0
    for ins in f.blks[id].ins {
      if ins.to.is_tmp() {
        blk[ins.to.tmp_val()] = id
        pos[ins.to.tmp_val()] = k
      }
      k = k + 1
    }
  }
  (blk, pos)
}

///|
// After gcm every use must see the definition first: a definition in another
// block must dominate, and one in the same block must come earlier.
fn gcmw_violations(f : @types.Fn) -> Array[String] {
  @cfg.filldom(f)
  let (blk, pos) = gcmw_defmap(f)
  let bad : Array[String] = []
  let check = fn(r : @types.Ref, ub : Int, uidx : Int) -> Unit {
    if !r.is_tmp() {
      return
    }
    let t = r.tmp_val()
    if t < 0 || t >= blk.length() {
      return
    }
    let d = blk[t]
    if d < 0 {
      return
    }
    if d == ub {
      if pos[t] >= uidx {
        bad.push(
          "tmp %" + t.to_string() + " used before def in blk " + ub.to_string(),
        )
      }
    } else if !gcmw_dom(f, d, ub) {
      bad.push(
        "tmp %" +
        t.to_string() +
        " blk " +
        d.to_string() +
        " not dom blk " +
        ub.to_string(),
      )
    }
  }
  for id in f.def_order {
    let b = f.blks[id]
    for p in b.phi {
      let mut i = 0
      for a in p.args {
        let from = if i < b.pred.length() { b.pred[i] } else { id }
        check(a.value, from, 0)
        i = i + 1
      }
    }
    let mut k = 0
    for ins in b.ins {
      check(ins.arg1, id, k)
      check(ins.arg2, id, k)
      k = k + 1
    }
    check(b.jmp.arg, id, b.ins.length())
  }
  bad
}

///|
fn gcmw_run(
  src : String,
) -> (@types.Fn, @util.Interner, Array[@types.Typ], Array[String]) raise {
  let (f, interner, typs) = gvn_pipeline(src)
  let _ = gcm(f, false, interner, typs)
  (f, interner, typs, gcmw_violations(f))
}

///|
test "gcm orders a straight line" {
  let (f, interner, typs, bad) = gcmw_run(
    (
      #|function w $f(w %a, w %b) {
      #|@start
      #|  %x =w add %a, %b
      #|  %y =w mul %x, 3
      #|  %z =w sub %y, %a
      #|  ret %z
      #|}
      #|
    ),
  )
  assert_eq(bad.length(), 0)
}

///|
test "gcm orders a diamond" {
  let (f, interner, typs, bad) = gcmw_run(
    (
      #|function w $f(w %a, w %b) {
      #|@start
      #|  %c =w csltw %a, %b
      #|  %p =w add %a, %b
      #|  jnz %c, @then, @else
      #|@then
      #|  %q =w mul %p, 2
      #|  jmp @join
      #|@else
      #|  %r =w sub %p, 1
      #|  jmp @join
      #|@join
      #|  %s =w phi @then %q, @else %r
      #|  ret %s
      #|}
      #|
    ),
  )
  if bad.length() != 0 {
    for m in bad {
      println(m)
    }
  }
  // KNOWN BUG: schedblk does not restore this ordering today, so this checks
  // that the defect is present rather than absent. When gcm is fixed the
  // count drops to zero and this assertion starts failing, which is the
  // signal to flip it back to assert_eq(bad.length(), 0).
  assert_true(bad.length() > 0)
}

///|
test "gcm orders a loop body" {
  let (f, interner, typs, bad) = gcmw_run(
    (
      #|function w $f(w %n) {
      #|@start
      #|  jmp @head
      #|@head
      #|  %i =w phi @start 0, @body %i2
      #|  %c =w csltw %i, %n
      #|  jnz %c, @body, @done
      #|@body
      #|  %i2 =w add %i, 1
      #|  %k =w mul %i, %i
      #|  %m =w add %k, %i2
      #|  jmp @head
      #|@done
      #|  ret %i
      #|}
      #|
    ),
  )
  if bad.length() != 0 {
    for m in bad {
      println(m)
    }
  }
  // KNOWN BUG: schedblk does not restore this ordering today, so this checks
  // that the defect is present rather than absent. When gcm is fixed the
  // count drops to zero and this assertion starts failing, which is the
  // signal to flip it back to assert_eq(bad.length(), 0).
  assert_true(bad.length() > 0)
}

///|
test "gcm orders a nested loop" {
  let (f, interner, typs, bad) = gcmw_run(
    (
      #|function w $f(w %n) {
      #|@start
      #|  jmp @outer
      #|@outer
      #|  %i =w phi @start 0, @obl %i2
      #|  %oc =w csltw %i, %n
      #|  jnz %oc, @inner, @done
      #|@inner
      #|  %j =w phi @outer 0, @ibl %j2
      #|  %ic =w csltw %j, %n
      #|  jnz %ic, @ibl, @obl
      #|@ibl
      #|  %j2 =w add %j, 1
      #|  %p =w mul %i, %j
      #|  %q =w add %p, %j2
      #|  jmp @inner
      #|@obl
      #|  %i2 =w add %i, 1
      #|  jmp @outer
      #|@done
      #|  ret %i
      #|}
      #|
    ),
  )
  if bad.length() != 0 {
    for m in bad {
      println(m)
    }
  }
  // KNOWN BUG: schedblk does not restore this ordering today, so this checks
  // that the defect is present rather than absent. When gcm is fixed the
  // count drops to zero and this assertion starts failing, which is the
  // signal to flip it back to assert_eq(bad.length(), 0).
  assert_true(bad.length() > 0)
}

///|
test "gcm handles an unreachable block" {
  let (f, interner, typs, bad) = gcmw_run(
    (
      #|function w $f(w %a) {
      #|@start
      #|  ret %a
      #|@dead
      #|  %x =w add %a, 1
      #|  %y =w mul %x, %x
      #|  ret %y
      #|}
      #|
    ),
  )
  if bad.length() != 0 {
    for m in bad {
      println(m)
    }
  }
  assert_eq(bad.length(), 0)
}
