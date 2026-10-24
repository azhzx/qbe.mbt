///|
// RISC-V 64 (rv64) target constants.
// Mirrors target.mbt but for RISC-V 64-bit architecture.

///|
// RISC-V 64 register numbers (as virtual tmp ids, matching C enum Rv64Reg)

///|
// Caller-save registers (T0-T5, A0-A7)
pub const T0 : Int32 = 1

///|
pub const T1 : Int32 = 2

///|
pub const T2 : Int32 = 3

///|
pub const T3 : Int32 = 4

///|
pub const T4 : Int32 = 5

///|
pub const T5 : Int32 = 6

///|
pub const A0 : Int32 = 7

///|
pub const A1 : Int32 = 8

///|
pub const A2 : Int32 = 9

///|
pub const A3 : Int32 = 10

///|
pub const A4 : Int32 = 11

///|
pub const A5 : Int32 = 12

///|
pub const A6 : Int32 = 13

///|
pub const A7 : Int32 = 14

///|
// Callee-save registers (S1-S11)
pub const S1 : Int32 = 15

///|
pub const S2 : Int32 = 16

///|
pub const S3 : Int32 = 17

///|
pub const S4 : Int32 = 18

///|
pub const S5 : Int32 = 19

///|
pub const S6 : Int32 = 20

///|
pub const S7 : Int32 = 21

///|
pub const S8 : Int32 = 22

///|
pub const S9 : Int32 = 23

///|
pub const S10 : Int32 = 24

///|
pub const S11 : Int32 = 25

///|
// Globally live registers
pub const FP : Int32 = 26

///|
pub const SP : Int32 = 27

///|
pub const GP : Int32 = 28

///|
pub const TP : Int32 = 29

///|
pub const RA : Int32 = 30

///|
// FP caller-save registers (FT0-FT10, FA0-FA7)
pub const FT0 : Int32 = 31

///|
pub const FT1 : Int32 = 32

///|
pub const FT2 : Int32 = 33

///|
pub const FT3 : Int32 = 34

///|
pub const FT4 : Int32 = 35

///|
pub const FT5 : Int32 = 36

///|
pub const FT6 : Int32 = 37

///|
pub const FT7 : Int32 = 38

///|
pub const FT8 : Int32 = 39

///|
pub const FT9 : Int32 = 40

///|
pub const FT10 : Int32 = 41

///|
pub const FA0 : Int32 = 42

///|
pub const FA1 : Int32 = 43

///|
pub const FA2 : Int32 = 44

///|
pub const FA3 : Int32 = 45

///|
pub const FA4 : Int32 = 46

///|
pub const FA5 : Int32 = 47

///|
pub const FA6 : Int32 = 48

///|
pub const FA7 : Int32 = 49

///|
// FP callee-save registers (FS0-FS11)
pub const FS0 : Int32 = 50

///|
pub const FS1 : Int32 = 51

///|
pub const FS2 : Int32 = 52

///|
pub const FS3 : Int32 = 53

///|
pub const FS4 : Int32 = 54

///|
pub const FS5 : Int32 = 55

///|
pub const FS6 : Int32 = 56

///|
pub const FS7 : Int32 = 57

///|
pub const FS8 : Int32 = 58

///|
pub const FS9 : Int32 = 59

///|
pub const FS10 : Int32 = 60

///|
pub const FS11 : Int32 = 61

///|
// Reserved registers
pub const T6 : Int32 = 62

///|
pub const FT11 : Int32 = 63

///|
// Tmp0 - first non-register temporary
pub const Rv64Tmp0 : Int32 = 64

///|
// Number of general purpose registers (T0-RA)
pub const Rv64NGPR : Int32 = 30

///|
// Number of float registers (FT0-FS11)
pub const Rv64NFPR : Int32 = 32

///|
// Number of caller-save GPRs (T0-A7)
pub const Rv64NGPS : Int32 = 14

///|
// Number of caller-save FPRs (FA0-FA7 + FT0-FT10 = 19)
pub const Rv64NFPS : Int32 = 19

///|
// Number of callee-save registers (S1-S11, FS0-FS11)
pub const Rv64NCLR : Int32 = 23

///|
// RISC-V caller-save register list (C rv64_rsave in targ.c)
pub let rv64_rsave : Array[Int32] = [
  T0,
  T1,
  T2,
  T3,
  T4,
  T5,
  A0,
  A1,
  A2,
  A3,
  A4,
  A5,
  A6,
  A7,
  FA0,
  FA1,
  FA2,
  FA3,
  FA4,
  FA5,
  FA6,
  FA7,
  FT0,
  FT1,
  FT2,
  FT3,
  FT4,
  FT5,
  FT6,
  FT7,
  FT8,
  FT9,
  FT10,
]

///|
// RISC-V callee-save register list (C rv64_rclob in targ.c)
pub let rv64_rclob : Array[Int32] = [
  S1,
  S2,
  S3,
  S4,
  S5,
  S6,
  S7,
  S8,
  S9,
  S10,
  S11,
  FS0,
  FS1,
  FS2,
  FS3,
  FS4,
  FS5,
  FS6,
  FS7,
  FS8,
  FS9,
  FS10,
  FS11,
]

///|
// RISC-V globally live registers bitmask (FP | SP | GP | TP | RA)
pub fn rv64_rglob_mask() -> UInt64 {
  let one : UInt64 = 1
  (one << FP) | (one << SP) | (one << GP) | (one << TP) | (one << RA)
}

///|
// Number of globally live registers
pub const Rv64NRGLOB : Int32 = 5

///|
// The registers returned by a call, given its RCall ref (C rv64_retregs).
// Returns (bits, ngp, nfpr).
pub fn Ref::rv64_retregs(self : Ref) -> (UInt64, Int32, Int32) {
  let mut b : UInt64 = 0
  let v = self.call_val()
  let ni = v & 3
  let nf = (v >> 2) & 3
  if ni >= 1 {
    b = b | (1UL << A0)
  }
  if ni >= 2 {
    b = b | (1UL << A1)
  }
  if nf >= 1 {
    b = b | (1UL << FA0)
  }
  if nf >= 2 {
    b = b | (1UL << FA1)
  }
  (b, ni, nf)
}

///|
// The registers used to pass arguments, given an RCall ref (C rv64_argregs).
// Returns (bits, ngp, nfpr).
pub fn Ref::rv64_argregs(self : Ref) -> (UInt64, Int32, Int32) {
  let mut b : UInt64 = 0
  let v = self.call_val()
  let ni = (v >> 4) & 15
  let nf = (v >> 8) & 15
  let t5 = (v >> 12) & 1
  for j in 0..<ni {
    b = b | (1UL << rv64_rsave[j])
  }
  for j in 0..<nf {
    b = b | (1UL << (FA0 + j))
  }
  if t5 != 0 {
    b = b | (1UL << T5)
  }
  (b, ni + t5, nf)
}

///|
// Map RISC-V register number to name string (C rname in emit.c)
pub fn rv64_reg_name(reg : Int32) -> String {
  match reg {
    FP => "fp"
    SP => "sp"
    GP => "gp"
    TP => "tp"
    RA => "ra"
    T0 => "t0"
    T1 => "t1"
    T2 => "t2"
    T3 => "t3"
    T4 => "t4"
    T5 => "t5"
    A0 => "a0"
    A1 => "a1"
    A2 => "a2"
    A3 => "a3"
    A4 => "a4"
    A5 => "a5"
    A6 => "a6"
    A7 => "a7"
    S1 => "s1"
    S2 => "s2"
    S3 => "s3"
    S4 => "s4"
    S5 => "s5"
    S6 => "s6"
    S7 => "s7"
    S8 => "s8"
    S9 => "s9"
    S10 => "s10"
    S11 => "s11"
    FT0 => "ft0"
    FT1 => "ft1"
    FT2 => "ft2"
    FT3 => "ft3"
    FT4 => "ft4"
    FT5 => "ft5"
    FT6 => "ft6"
    FT7 => "ft7"
    FT8 => "ft8"
    FT9 => "ft9"
    FT10 => "ft10"
    FA0 => "fa0"
    FA1 => "fa1"
    FA2 => "fa2"
    FA3 => "fa3"
    FA4 => "fa4"
    FA5 => "fa5"
    FA6 => "fa6"
    FA7 => "fa7"
    FS0 => "fs0"
    FS1 => "fs1"
    FS2 => "fs2"
    FS3 => "fs3"
    FS4 => "fs4"
    FS5 => "fs5"
    FS6 => "fs6"
    FS7 => "fs7"
    FS8 => "fs8"
    FS9 => "fs9"
    FS10 => "fs10"
    FS11 => "fs11"
    T6 => "t6"
    FT11 => "ft11"
    _ => "?"
  }
}

///|
// RISC-V pointer size: Kl (64-bit).
// On amd64 Km=Kl; on wasm32 Km=Kw; on rv64 Km=Kl.
pub const Rv64KmIsWide : Int32 = 1

///|
// RISC-V call return registers (C rv64 retregs): A0/A1 and FA0/FA1.
fn rv64_target_retregs(r : Ref) -> (UInt64, Int32, Int32) {
  let mut b : UInt64 = 0
  let v = r.call_val()
  let ni = v & 3
  let nf = (v >> 2) & 3
  if ni >= 1 {
    b = b | (1UL << A0)
  }
  if ni >= 2 {
    b = b | (1UL << A1)
  }
  if nf >= 1 {
    b = b | (1UL << FA0)
  }
  if nf >= 2 {
    b = b | (1UL << FA1)
  }
  (b, ni, nf)
}

///|
// RISC-V call argument registers (C rv64 argregs): A0.. and FA0...
fn rv64_target_argregs(r : Ref) -> (UInt64, Int32, Int32) {
  let mut b : UInt64 = 0
  let v = r.call_val()
  let ni = (v >> 4) & 15
  let nf = (v >> 8) & 15
  let ra = (v >> 12) & 1
  for j in 0..<ni {
    b = b | (1UL << (A0 + j))
  }
  for j in 0..<nf {
    b = b | (1UL << (FA0 + j))
  }
  if ra != 0 {
    b = b | (1UL << A0)
  }
  (b, ni + ra, nf)
}

///|
// Select the rv64 target (C init(T_rv64)).
pub fn init_rv64_target() -> Unit {
  target_cfg.gpr_base = T0
  target_cfg.fpr_base = FT0
  target_cfg.ngpr = Rv64NGPR
  target_cfg.nfpr = Rv64NFPR
  target_cfg.fpr_class_base = FT0
  target_cfg.post_call_gpr = Rv64NGPS
  target_cfg.post_call_fpr = Rv64NFPS
  target_cfg.rglob_mask = rv64_rglob_mask()
  target_cfg.memargs = fn(op) { op_info(op).nmem }
  target_cfg.rsave = rv64_rsave
  target_cfg.retregs = rv64_target_retregs
  target_cfg.argregs = rv64_target_argregs
}
