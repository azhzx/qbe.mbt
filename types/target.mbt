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
// Caller-save registers for amd64
pub let amd64_rsave : Array[Int] = [
  RAX,
  RCX,
  RDX,
  RSI,
  RDI,
  R8,
  R9,
  R10,
  R11,
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
  XMM15,
]

///|
// Globally live registers bitmask (RBP | RSP)
pub fn rglob_mask() -> UInt64 {
  let one : UInt64 = 1
  (one << RBP) | (one << RSP)
}

///|
// Number of globally live registers
pub const NRGLOB : Int = 2

///|
// Get the name of a register (for emission)
pub fn regname(r : Int) -> String {
  if r >= XMM0 {
    "xmm\{r - XMM0}"
  } else {
    match r {
      0 => "???"
      1 => "rax"
      2 => "rcx"
      3 => "rdx"
      4 => "rsi"
      5 => "rdi"
      6 => "r8"
      7 => "r9"
      8 => "r10"
      9 => "r11"
      10 => "rbx"
      11 => "r12"
      12 => "r13"
      13 => "r14"
      14 => "r15"
      15 => "rbp"
      16 => "rsp"
      _ => "???"
    }
  }
}

///|
// Whether a register is caller-save (index into rsave)
pub fn is_callersave(r : Int) -> Bool {
  (RAX <= r && r <= R11) || (XMM0 <= r && r < XMM0 + NFPS)
}

///|
// Number of registers per class: [ngpr, nfpr]
pub let nregs_per_class : Array[Int] = [NGPR, NFPR]
