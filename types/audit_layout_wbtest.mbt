///|
// parsefields records at most NField=32 entries but accounts for full size.
test "audit aggregate layout caps field records without truncating size" {
  let t = Typ::new("many")
  for _ in 0..<40 {
    t.fields.push(Field::new(Fb, 1))
  }
  t.compute_layout([])
  assert_eq(t.size, 40L)
  assert_eq(t.fields.length(), 33)
  assert_eq(t.fields[32].kind, FEnd)
}

///|
// Empty union alternatives still occupy their own FEnd-delimited list.
test "audit aggregate layout preserves empty union alternatives" {
  let t = Typ::new("empty_member")
  t.nunion = 3
  t.fields.push(Field::end())
  t.fields.push(Field::end())
  t.fields.push(Field::new(Fw, 4))
  t.fields.push(Field::end())
  t.compute_layout([])
  assert_eq(t.fields, [
    Field::end(),
    Field::end(),
    Field::new(Fw, 4),
    Field::end(),
  ])
}

///|
// uint64_t maximum selection must not discard a size with its high bit set.
test "audit aggregate layout compares sizes as unsigned" {
  let huge = Typ::new("huge")
  huge.size = -16L
  huge.align = 0
  let t = Typ::new("wrap")
  t.fields.push(Field::new(FTyp, 0))
  t.compute_layout([huge])
  assert_eq(t.size, -16L)
}

///|
// util.c bsinit allocates whole words; set/clr may address their padding bits.
test "audit bitset rounded word capacity is addressable" {
  let b = BSet::new(1)
  b.set(63)
  assert_true(b.has(63))
  assert_eq(b.iter(1), 63)
  b.clr(63)
  assert_eq(b.count(), 0)
}
