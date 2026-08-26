///|
// Target abstraction - corresponds to struct Target and amd64/all.h

///|
// AMD64 register numbers (as virtual tmp ids, matching C enum Amd64Reg)
pub const RXX : Int = 0

///|
pub const RAX : Int = 1

///|
pub const RCX : Int = 2

///|
pub const RDX : Int = 3

///|
pub const RSI : Int = 4

///|
pub const RDI : Int = 5

///|
pub const R8 : Int = 6

///|
pub const R9 : Int = 7

///|
pub const R10 : Int = 8

///|
pub const R11 : Int = 9

///|
pub const RBX : Int = 10

///|
pub const R12 : Int = 11

///|
pub const R13 : Int = 12

///|
pub const R14 : Int = 13

///|
pub const R15 : Int = 14

///|
pub const RBP : Int = 15

///|
pub const RSP : Int = 16

///|
pub const XMM0 : Int = 17

///|
pub const XMM1 : Int = 18

///|
pub const XMM2 : Int = 19

///|
pub const XMM3 : Int = 20

///|
pub const XMM4 : Int = 21

///|
pub const XMM5 : Int = 22

///|
pub const XMM6 : Int = 23

///|
pub const XMM7 : Int = 24

///|
pub const XMM8 : Int = 25

///|
pub const XMM9 : Int = 26

///|
pub const XMM10 : Int = 27

///|
pub const XMM11 : Int = 28

///|
pub const XMM12 : Int = 29

///|
pub const XMM13 : Int = 30

///|
pub const XMM14 : Int = 31

///|
pub const XMM15 : Int = 32

///|
// Tmp0 - first non-register temporary (NBit = 64)
pub const Tmp0 : Int = 64

///|
// Number of general purpose registers
pub const NGPR : Int = RSP - RAX + 1

///|
// Number of float registers
pub const NFPR : Int = XMM14 - XMM0 + 1

///|
// Number of caller-save GPRs (RAX..R11)
pub const NGPS : Int = R11 - RAX + 1

///|
// Number of caller-save FPRs
pub const NFPS : Int = NFPR

///|
// Number of callee-save registers (RBX..R15)
pub const NCLR : Int = R15 - RBX + 1

///|
// Caller-save registers for amd64 sysv (C amd64_sysv_rsave in sysv.c).
// These are the argument/return registers used by retregs/argregs and by
// the spill/rega passes (T.rsave).
pub let rsave : Array[Int] = [
  RDI,
  RSI,
  RDX,
  RCX,
  R8,
  R9,
  R10,
  R11,
  RAX,
  XMM0,
  XMM1,
  XMM2,
  XMM3,
  XMM4,
  XMM5,
  XMM6,
  XMM7,
  XMM8,
  XMM9,
  XMM10,
  XMM11,
  XMM12,
  XMM13,
  XMM14,
]

///|
// Callee-save registers (C amd64_sysv_rclob in sysv.c).
pub let rclob : Array[Int] = [RBX, R12, R13, R14, R15]

///|
// The registers returned by a call, given its RCall ref (C retregs).
// Returns (bits, ngp, nfpr).
#as_free_fn(retregs, deprecated="use `Ref::retregs` instead")
pub fn Ref::retregs(self : Ref) -> (UInt64, Int, Int) {
  let mut b : UInt64 = 0
  let v = self.call_val()
  let ni = v & 3
  let nf = (v >> 2) & 3
  if ni >= 1 {
    b = b | (1UL << RAX)
  }
  if ni >= 2 {
    b = b | (1UL << RDX)
  }
  if nf >= 1 {
    b = b | (1UL << XMM0)
  }
  if nf >= 2 {
    b = b | (1UL << XMM1)
  }
  (b, ni, nf)
}

///|
// The registers used to pass arguments, given an RCall ref (C argregs).
// Returns (bits, ngp, nfpr).
#as_free_fn(argregs, deprecated="use `Ref::argregs` instead")
pub fn Ref::argregs(self : Ref) -> (UInt64, Int, Int) {
  let mut b : UInt64 = 0
  let v = self.call_val()
  let ni = (v >> 4) & 15
  let nf = (v >> 8) & 15
  let ra = (v >> 12) & 1
  for j in 0..<ni {
    b = b | (1UL << rsave[j])
  }
  for j in 0..<nf {
    b = b | (1UL << (XMM0 + j))
  }
  if ra != 0 {
    b = b | (1UL << RAX)
  }
  (b, ni + ra, nf)
}

///|
// Globally live registers bitmask (RBP | RSP)
pub fn rglob_mask() -> UInt64 {
  let one : UInt64 = 1
  (one << RBP) | (one << RSP)
}

///|
// Number of globally live registers
pub const NRGLOB : Int = 2
