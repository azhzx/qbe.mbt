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
    // Cfeq -> Cfeq
    NCMPI + 0
  } else if c == NCMPI + 1 {
    // Cfge -> Cfle
    NCMPI + 3
  } else if c == NCMPI + 2 {
    // Cfgt -> Cflt
    NCMPI + 4
  } else if c == NCMPI + 3 {
    // Cfle -> Cfge
    NCMPI + 1
  } else if c == NCMPI + 4 {
    // Cflt -> Cfgt
    NCMPI + 2
  } else if c == NCMPI + 5 {
    // Cfne -> Cfne
    NCMPI + 5
  } else if c == NCMPI + 6 {
    // Cfo -> Cfo
    NCMPI + 6
  } else if c == NCMPI + 7 {
    // Cfuo -> Cfuo
    NCMPI + 7
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

///|
// Whether op is a conditional-select op (C isxsel).
fn isxsel(op : @types.Op) -> Bool {
  let i = op.index()
  i >= @types.Xselieq.index() && i <= @types.Xselfuo.index()
}

///|
// The xsel op for an ICmp code (C Oxsel + x).
fn xsel_op(x : Int) -> @types.Op {
  @types.Op::from_index(@types.Xselieq.index() + x)
}

///|
// Whether the operands must be swapped for a comparison code (C cmpswap).
fn cmpswap(a0 : @types.Ref, c : Int) -> Bool {
  if c == NCMPI + 4 || c == NCMPI + 3 {
    // Cflt, Cfle
    true
  } else if c == NCMPI + 2 || c == NCMPI + 1 {
    // Cfgt, Cfge
    false
  } else {
    a0.is_con()
  }
}
