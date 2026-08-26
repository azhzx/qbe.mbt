///|
// Comparison helpers and floating-point constant stash for amd64 isel.

///|
// Number of int comparison codes (C NCmpI).
const NCMPI = 10

///|
// ICmp codes (C CmpI enum in all.h).
const CIEQ = 0

///|
const CINE = 1

///|
const CISGE = 2

///|
const CISGT = 3

///|
const CISLE = 4

///|
const CISLT = 5

///|
const CIUGE = 6

///|
const CIUGT = 7

///|
const CIULE = 8

///|
const CIULT = 9

///|
// Whether op is a comparison; returns (ok, class, icmp code).
// Matches util.c iscmp: float comparisons map to NCmpI + offset (the
// CmpF enum positions), which index the Flagfeq..Flagfuo flag ops.
fn iscmp(op : @types.Op) -> (Bool, @types.Class, Int) {
  let i = op.index()
  let w = @types.Ceqw.index()
  let l = @types.Ceql.index()
  let s = @types.Ceqs.index()
  let d = @types.Ceqd.index()
  if i >= w && i <= w + 9 {
    (true, @types.Kw, i - w)
  } else if i >= l && i <= l + 9 {
    (true, @types.Kl, i - l)
  } else if i >= s && i <= s + 7 {
    (true, @types.Ks, NCMPI + (i - s))
  } else if i >= d && i <= d + 7 {
    (true, @types.Kd, NCMPI + (i - d))
  } else {
    (false, @types.Kx, 0)
  }
}

///|
// The swap version of a comparison code (C cmpop, cmptab).
fn cmpop(c : Int) -> Int {
  if c == CIULE {
    CIUGE
  } else if c == CIULT {
    CIUGT
  } else if c == CIUGT {
    CIULT
  } else if c == CIUGE {
    CIULE
  } else if c == CISLE {
    CISGE
  } else if c == CISLT {
    CISGT
  } else if c == CISGT {
    CISLT
  } else if c == CISGE {
    CISLE
  } else if c == CIEQ {
    CIEQ
  } else if c == CINE {
    CINE
  } else if c == NCMPI + 0 {
    // NCmpI+Cfle -> NCmpI+Cfge
    NCMPI + 3
  } else if c == NCMPI + 1 {
    // NCmpI+Cfl0t -> NCmpI+Cfgt
    NCMPI + 2
  } else if c == NCMPI + 2 {
    // NCmpI+Cfgt -> NCmpI+Cfl0t
    NCMPI + 1
  } else if c == NCMPI + 3 {
    // NCmpI+Cfge -> NCmpI+Cfle
    NCMPI + 0
  } else if c == NCMPI + 4 {
    // NCmpI+Cfne -> NCmpI+Cfne
    NCMPI + 4
  } else if c == NCMPI + 5 {
    // NCmpI+Cfeq -> NCmpI+Cfeq
    NCMPI + 5
  } else if c == NCMPI + 6 {
    // NCmpI+Cfo -> NCmpI+Cfuo
    NCMPI + 7
  } else if c == NCMPI + 7 {
    // NCmpI+Cfuo -> NCmpI+Cfo
    NCMPI + 6
  } else {
    0
  }
}

///|
// The flag-setting op for an ICmp code (C Oflag + x).
fn flag_op(x : Int) -> @types.Op {
  @types.Op::from_index(@types.Flagieq.index() + x)
}

///|
// The conditional jump kind for an ICmp code (C Jjf + x).
fn jjf_op(x : Int) -> @types.JumpKind {
  @types.JumpKind::from_index(@types.Jjfieq.index() + x)
}
