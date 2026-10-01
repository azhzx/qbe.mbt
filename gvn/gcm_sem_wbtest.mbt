// Semantic verdict for GCM.
//
// gcm is an optimization: interpreting a function before and after it must
// produce the same answer.  This is the check the structural invariants could
// not give us -- they were all silent while the arm64 output was still wrong.

///|
// Interpret the same source twice, once with gcm and once without.
fn gcm_sem(
  fn_name : String,
  src : String,
  args : Array[@interp.InterpValue],
) -> @interp.InterpValue? raise {
  let (f0, i0, _) = gvn_pipeline(src)
  let before = match @interp.run_module([f0], [], i0, fn_name, args) {
    Ok((v, _)) => Some(v)
    Err(_) => None
  }
  let (f1, i1, t1) = gvn_pipeline(src)
  let _ = gcm(f1, false, i1, t1)
  let after = match @interp.run_module([f1], [], i1, fn_name, args) {
    Ok((v, _)) => Some(v)
    Err(_) => None
  }
  match (before, after) {
    (Some(a), Some(b)) => assert_true(a == b)
    (None, None) => ()
    (_, _) => abort(fn_name + ": gcm changed whether it runs at all")
  }
  after
}

///|
fn gcm_sem_check(
  name : String,
  src : String,
  args : Array[@interp.InterpValue],
) -> Unit raise {
  ignore(gcm_sem("f", src, args))
  ignore(name)
}

///|
test "gcm preserves a straight line" {
  gcm_sem_check(
    "line",
    (
      #|export function w $f(w %a, w %b) {
      #|@start
      #|  %x =w add %a, %b
      #|  %y =w mul %x, 3
      #|  %z =w sub %y, %a
      #|  ret %z
      #|}
      #|
    ),
    [@interp.VInt(7L), @interp.VInt(4L)],
  )
}

///|
test "gcm preserves a diamond" {
  gcm_sem_check(
    "diamond",
    (
      #|export function w $f(w %a, w %b) {
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
    [@interp.VInt(3L), @interp.VInt(9L)],
  )
}

///|
test "gcm preserves a loop" {
  gcm_sem_check(
    "loop",
    (
      #|export function w $f(w %n) {
      #|@start
      #|  jmp @head
      #|@head
      #|  %i =w phi @start 0, @body %i2
      #|  %acc =w phi @start 0, @body %acc2
      #|  %c =w csltw %i, %n
      #|  jnz %c, @body, @done
      #|@body
      #|  %k =w mul %i, %i
      #|  %acc2 =w add %acc, %k
      #|  %i2 =w add %i, 1
      #|  jmp @head
      #|@done
      #|  ret %acc
      #|}
      #|
    ),
    [@interp.VInt(6L)],
  )
}

///|
test "gcm preserves a nested loop" {
  gcm_sem_check(
    "nested",
    (
      #|export function w $f(w %n) {
      #|@start
      #|  jmp @outer
      #|@outer
      #|  %i =w phi @start 0, @obl %i2
      #|  %acc =w phi @start 0, @obl %acc2
      #|  %oc =w csltw %i, %n
      #|  jnz %oc, @inner, @done
      #|@inner
      #|  %j =w phi @outer 0, @ibl %j2
      #|  %ic =w csltw %j, %n
      #|  jnz %ic, @ibl, @obl
      #|@ibl
      #|  %p =w mul %i, %j
      #|  %acc3 =w add %acc, %p
      #|  %j2 =w add %j, 1
      #|  jmp @inner
      #|@obl
      #|  %acc2 =w add %acc3, 0
      #|  %i2 =w add %i, 1
      #|  jmp @outer
      #|@done
      #|  ret %acc
      #|}
      #|
    ),
    [@interp.VInt(4L)],
  )
}
