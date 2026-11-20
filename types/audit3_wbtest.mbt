///|
// audit3 (types): declarations that the earlier rounds left without a
// pinned translation relation, plus the C helpers the dump printer needs.

///|
// C rsval (all.h): the IL stores RInt/RSlot payloads in a 29-bit bitfield, so
// bit 28 is a sign bit. Reference printref prints RInt through rsval, which is
// why `dbgloc 268435456` dumps as `dbgloc -268435456` there. The port used to
// print the raw payload; this helper is the transcription the printer and the
// emitters share.
test "audit3 rsval sign-extends the 29-bit payload" {
  assert_eq(Ref::rint(0).rsval(), 0)
  assert_eq(Ref::rint(5).rsval(), 5)
  assert_eq(Ref::rint(0x0FFFFFFF).rsval(), 0x0FFFFFFF)
  // bit 28 set: the payload is a negative number
  assert_eq(Ref::rint(0x10000000).rsval(), -0x10000000)
  assert_eq(Ref::rint(0x1FFFFFFF).rsval(), -1)
  // slot values are masked to 29 bits when constructed, so -3 round-trips
  assert_eq(Ref::slot(-3).rsval(), -3)
  assert_eq(Ref::slot(5).rsval(), 5)
  assert_eq(Ref::slot(0x1FFFFFFF).rsval(), -1)
  assert_eq(Ref::tmp(3).rsval(), 3)
  assert_eq(Ref::none().rsval(), 0)
}

///|
// C enum J order and the port's JumpKind::index table differ (the port groups
// its returns), so pin exactly what the code relies on: index/from_index are
// inverses over all 32 kinds, is_ret is C's INRANGE(Jretw, Jret0) set, the
// four sub-word returns are exactly C's isretbh set, and the 18 comparison
// codes form the contiguous block Jjf..Jjf1 that the emitters index with
// (kind.index() - Jjfieq.index()) and rebuild with from_index(Jjfieq + x).
test "audit3 JumpKind index table relations" {
  for i in 0..<32 {
    assert_eq(JumpKind::from_index(i).index(), i)
  }
  // returns
  assert_true(Jretw.is_ret() && Jretl.is_ret() && Jrets.is_ret())
  assert_true(Jretd.is_ret() && Jretc.is_ret() && Jret0.is_ret())
  assert_true(Jretsb.is_ret() && Jretub.is_ret())
  assert_true(Jretsh.is_ret() && Jretuh.is_ret())
  assert_true(!Jjmp.is_ret() && !Jjnz.is_ret() && !Jhlt.is_ret())
  assert_true(!Jjfieq.is_ret() && !Jjffuo.is_ret())
  // sub-word returns
  assert_true(Jretsb.is_ret_bh() && Jretub.is_ret_bh())
  assert_true(Jretsh.is_ret_bh() && Jretuh.is_ret_bh())
  assert_true(!Jretw.is_ret_bh() && !Jretc.is_ret_bh())
  assert_true(!Jjfieq.is_ret_bh())
  // 18 comparison kinds, contiguous, right after jnz
  assert_eq(Jjffuo.index() - Jjfieq.index(), 17)
  assert_eq(Jjfieq.index() - Jjnz.index(), 1)
  assert_eq(Jjfieq.index() - Jjmp.index(), 2)
  // C Jjf = Jjfieq and Jjf1 = Jjffuo; C adds the integer/fp code halves
  // with NCmpI = 10, so the second half starts at Jjfieq + 10.
  assert_eq(Jjffeq.index() - Jjfieq.index(), 10)
  assert_eq(Jjffuo.index() - Jjnz.index(), 18)
}

///|
// C newcon compares Con.type, Sym (type + id) and bits.i; two addresses with
// the same label but different thread/extern bits must not be interned
// together (symeq would reject them).
test "audit3 constant interning keeps symbol type identity" {
  let f = Fn::new("symtype")
  let plain = f.get_con_by(Con::addr_sym(7, 0))
  let thr = f.get_con_by(Con::addr_sym(7, SYM_THR))
  let ext = f.get_con_by(Con::addr_sym(7, SYM_EXT))
  let both = f.get_con_by(Con::addr_sym(7, SYM_THR | SYM_EXT))
  assert_true(plain != thr)
  assert_true(plain != ext)
  assert_true(thr != ext)
  assert_true(thr != both)
  assert_eq(f.get_con_by(Con::addr_sym(7, 0)), plain)
  assert_eq(f.get_con_by(Con::addr_sym(7, SYM_THR)), thr)
  // same bits, different type: CAddr never interns with CBits
  let bits7 = f.get_con_by(Con::int(7))
  assert_true(bits7 != plain)
}

///|
// C loadsz/storesz have exactly one implementation in load.c. The port used to
// carry two (Ins::load_size/store_size in types/ins.mbt and op_loadsz/
// op_storesz in types/opinfo.mbt); this test keeps the copies equal.
test "audit3 load and store size helpers agree" {
  let loads : Array[(Op, Class)] = [
    (Loadsb, Kw),
    (Loadub, Kw),
    (Loadsh, Kw),
    (Loaduh, Kw),
    (Loadsw, Kl),
    (Loaduw, Kl),
    (Load, Kw),
    (Load, Kl),
    (Load, Ks),
    (Load, Kd),
  ]
  for l in loads {
    let i = Ins::new(l.0, l.1, Ref::none(), Ref::none(), Ref::none())
    assert_eq(i.load_size(), op_loadsz(i))
  }
  let stores : Array[(Op, Class)] = [
    (Storeb, Kw),
    (Storeh, Kw),
    (Storew, Kw),
    (Storel, Kl),
    (Stores, Ks),
    (Stored, Kd),
  ]
  for s in stores {
    let i = Ins::new(s.0, s.1, Ref::none(), Ref::none(), Ref::none())
    assert_eq(i.store_size(), op_storesz(i))
  }
}

///|
// C ssa.c/load.c use Wsb + (op - Oloadsb) and Wsb + (op - Oextsb); pin both
// families for every member instead of the two values the old test checked.
test "audit3 load/ext width index families" {
  let loads : Array[(Op, Int32)] = [
    (Loadsb, 1),
    (Loadub, 2),
    (Loadsh, 3),
    (Loaduh, 4),
    (Loadsw, 5),
    (Loaduw, 6),
  ]
  for l in loads {
    assert_eq(l.0.load_width_idx(), l.1)
  }
  let exts : Array[(Op, Int32)] = [
    (Extsb, 1),
    (Extub, 2),
    (Extsh, 3),
    (Extuh, 4),
    (Extsw, 5),
    (Extuw, 6),
  ]
  for e in exts {
    assert_eq(e.0.ext_width_idx(), e.1)
  }
}

///|
// C parsefields keeps the running size and alignment across union
// alternatives (ty->size/ty->align are carried into the next call). Pin that
// for the shared layout helper the programmatic builder uses.
test "audit3 union layout carries alignment across alternatives" {
  let t = Typ::new("u")
  t.nunion = 2
  t.fields.push(Field::new(Fb, 1))
  t.fields.push(Field::end())
  t.fields.push(Field::new(Fl, 8))
  t.fields.push(Field::end())
  t.compute_layout([])
  assert_eq(t.size, 8L)
  assert_eq(t.align, 3)
}

///|
// An aggregate field's size and alignment come from the referenced type, and
// rounding is to the largest alignment seen so far (C parsefields).
test "audit3 nested aggregate layout" {
  let inner = Typ::new("inner")
  inner.fields.push(Field::new(Fl, 8))
  inner.fields.push(Field::end())
  inner.compute_layout([])
  assert_eq(inner.size, 8L)
  assert_eq(inner.align, 3)
  let outer = Typ::new("outer")
  outer.fields.push(Field::new(Fb, 1))
  outer.fields.push(Field::new(FTyp, 0))
  outer.fields.push(Field::end())
  outer.compute_layout([inner])
  // byte 0, then pad to 8, then the 8-byte inner type
  assert_eq(outer.size, 16L)
  assert_eq(outer.align, 3)
}

///|
// C bsinit rounds the element count up to whole words; a zero-element set has
// no addressable bit but the read-only queries must stay total.
test "audit3 empty bitset queries" {
  let b = BSet::new(0)
  assert_eq(b.count(), 0)
  assert_true(!b.has(0))
  assert_eq(b.iter(0), -1)
  let hits : Array[Int32] = []
  b.each(t => hits.push(t))
  assert_eq(hits.length(), 0)
}

///|
// C emit.c stashbits: reuse an entry iff size <= b->size AND b->n == n.
// Comparing a prefix of the bytes is not the same rule (it folded a 4-byte
// request into an 8-byte entry with the same low word, changing the emitted
// pool). Patterns here are chosen not to collide with the other stash tests.
test "audit3 fp stash identity is the full word plus its size class" {
  let big = 0x7FEEDDCCBBAA9988L
  let low = 0xBBAA9988L
  let i8 = gasstash(big, 0L, 8)
  // a 4-byte request whose word is the low half of the 8-byte entry is a
  // different constant for the reference: it gets its own label.
  let i4 = gasstash(low, 0L, 4)
  assert_true(i4 != i8)
  assert_eq(gasstash(big, 0L, 8), i8)
  // a smaller request with the same full word does reuse a bigger entry.
  let v = 0x1122334455667701L
  let a8 = gasstash(v, 0L, 8)
  assert_eq(gasstash(v, 0L, 4), a8)
  // size 16 entries are compared on the same word (C prints a zero second
  // half, so the high half is always zero in the reference too).
  let w = 0x1122334455667702L
  let b16 = gasstash(w, 0L, 16)
  assert_eq(gasstash(w, 0L, 8), b16)
  assert_eq(gasstash(w, 0L, 4), b16)
}
