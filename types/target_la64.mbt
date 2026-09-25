///|
// LoongArch 64 (la64) target constants, LP64D ABI.
// Mirrors target.mbt / target_rv64.mbt but for the LoongArch64 architecture.
// Register tmp ids are renumbered (QBE-style) instead of using the raw
// machine numbers so that the allocatable ranges stay contiguous.

///|
// LoongArch 64 register numbers (as virtual tmp ids).

///|
// The hard-wired zero register ($zero / $r0).
pub const LA_ZERO : Int = 0

///|
// Caller-save GPR temporaries (t0-t7; t8 is reserved as emitter scratch).
pub const LA_T0 : Int = 1

///|
pub const LA_T1 : Int = 2

///|
pub const LA_T2 : Int = 3

///|
pub const LA_T3 : Int = 4

///|
pub const LA_T4 : Int = 5

///|
pub const LA_T5 : Int = 6

///|
pub const LA_T6 : Int = 7

///|
pub const LA_T7 : Int = 8

///|
// Argument registers (a0-a7)
pub const LA_A0 : Int = 9

///|
pub const LA_A1 : Int = 10

///|
pub const LA_A2 : Int = 11

///|
pub const LA_A3 : Int = 12

///|
pub const LA_A4 : Int = 13

///|
pub const LA_A5 : Int = 14

///|
pub const LA_A6 : Int = 15

///|
pub const LA_A7 : Int = 16

///|
// Callee-save registers (s0-s8)
pub const LA_S0 : Int = 17

///|
pub const LA_S1 : Int = 18

///|
pub const LA_S2 : Int = 19

///|
pub const LA_S3 : Int = 20

///|
pub const LA_S4 : Int = 21

///|
pub const LA_S5 : Int = 22

///|
pub const LA_S6 : Int = 23

///|
pub const LA_S7 : Int = 24

///|
pub const LA_S8 : Int = 25

///|
// Globally live registers
pub const LA_FP : Int = 26

///|
pub const LA_SP : Int = 27

///|
pub const LA_TP : Int = 28

///|
pub const LA_RA : Int = 29

///|
// Reserved scratch register (t8), used by the emitter and for env arguments.
pub const LA_T8 : Int = 30

///|
// FP caller-save registers (ft0-ft15)
pub const LA_FT0 : Int = 32

///|
pub const LA_FT1 : Int = 33

///|
pub const LA_FT2 : Int = 34

///|
pub const LA_FT3 : Int = 35

///|
pub const LA_FT4 : Int = 36

///|
pub const LA_FT5 : Int = 37

///|
pub const LA_FT6 : Int = 38

///|
pub const LA_FT7 : Int = 39

///|
pub const LA_FT8 : Int = 40

///|
pub const LA_FT9 : Int = 41

///|
pub const LA_FT10 : Int = 42

///|
pub const LA_FT11 : Int = 43

///|
pub const LA_FT12 : Int = 44

///|
pub const LA_FT13 : Int = 45

///|
pub const LA_FT14 : Int = 46

///|
pub const LA_FT15 : Int = 47

///|
// FP argument registers (fa0-fa7)
pub const LA_FA0 : Int = 48

///|
pub const LA_FA1 : Int = 49

///|
pub const LA_FA2 : Int = 50

///|
pub const LA_FA3 : Int = 51

///|
pub const LA_FA4 : Int = 52

///|
pub const LA_FA5 : Int = 53

///|
pub const LA_FA6 : Int = 54

///|
pub const LA_FA7 : Int = 55

///|
// FP callee-save registers (fs0-fs7)
pub const LA_FS0 : Int = 56

///|
pub const LA_FS1 : Int = 57

///|
pub const LA_FS2 : Int = 58

///|
pub const LA_FS3 : Int = 59

///|
pub const LA_FS4 : Int = 60

///|
pub const LA_FS5 : Int = 61

///|
pub const LA_FS6 : Int = 62

///|
pub const LA_FS7 : Int = 63

///|
// Tmp0 - first non-register temporary
pub const La64Tmp0 : Int = 64

///|
// Number of general purpose registers (LA_T0-LA_RA)
pub const La64NGPR : Int = 29

///|
// Number of float registers (LA_FT0-LA_FS7)
pub const La64NFPR : Int = 32

///|
// Number of caller-save GPRs (LA_T0-LA_A7)
pub const La64NGPS : Int = 16

///|
// Number of caller-save FPRs (LA_FT0-LA_FA7)
pub const La64NFPS : Int = 24

///|
// Number of callee-save registers (LA_S0-LA_S8, LA_FS0-LA_FS7)
pub const La64NCLR : Int = 17

///|
// Number of globally live registers (LA_FP, LA_SP, LA_TP, LA_RA)
pub const La64NRGLOB : Int = 4

///|
// LoongArch caller-save register list (C la64_rsave in a hypothetical
// upstream targ.c; not present in vendor/qbe).
pub let la64_rsave : Array[Int] = [
  LA_T0,
  LA_T1,
  LA_T2,
  LA_T3,
  LA_T4,
  LA_T5,
  LA_T6,
  LA_T7,
  LA_A0,
  LA_A1,
  LA_A2,
  LA_A3,
  LA_A4,
  LA_A5,
  LA_A6,
  LA_A7,
  LA_FA0,
  LA_FA1,
  LA_FA2,
  LA_FA3,
  LA_FA4,
  LA_FA5,
  LA_FA6,
  LA_FA7,
  LA_FT0,
  LA_FT1,
  LA_FT2,
  LA_FT3,
  LA_FT4,
  LA_FT5,
  LA_FT6,
  LA_FT7,
  LA_FT8,
  LA_FT9,
  LA_FT10,
  LA_FT11,
  LA_FT12,
  LA_FT13,
  LA_FT14,
  LA_FT15,
]

///|
// LoongArch callee-save register list (fp is globally live, not saved here).
pub let la64_rclob : Array[Int] = [
  LA_S0,
  LA_S1,
  LA_S2,
  LA_S3,
  LA_S4,
  LA_S5,
  LA_S6,
  LA_S7,
  LA_S8,
  LA_FS0,
  LA_FS1,
  LA_FS2,
  LA_FS3,
  LA_FS4,
  LA_FS5,
  LA_FS6,
  LA_FS7,
]

///|
// LoongArch globally live registers bitmask (FP | SP | TP | RA) plus the
// emitter's fixed scratch registers (t8 and ft15), which rega must never
// allocate: the emitter writes them for far slots, swaps and conversions.
pub fn la64_rglob_mask() -> UInt64 {
  let one : UInt64 = 1
  (one << LA_FP) |
  (one << LA_SP) |
  (one << LA_TP) |
  (one << LA_RA) |
  (one << LA_T8) |
  (one << LA_FT15)
}

///|
// The registers returned by a call, given its RCall ref.
// Returns (bits, ngp, nfpr): a0/a1 and fa0/fa1.
pub fn Ref::la64_retregs(self : Ref) -> (UInt64, Int, Int) {
  let mut b : UInt64 = 0
  let v = self.call_val()
  let ni = v & 3
  let nf = (v >> 2) & 3
  if ni >= 1 {
    b = b | (1UL << LA_A0)
  }
  if ni >= 2 {
    b = b | (1UL << LA_A1)
  }
  if nf >= 1 {
    b = b | (1UL << LA_FA0)
  }
  if nf >= 2 {
    b = b | (1UL << LA_FA1)
  }
  (b, ni, nf)
}

///|
// The registers used to pass arguments, given an RCall ref.
// Returns (bits, ngp, nfpr): a0.. and fa0.., plus t8 for the env argument.
pub fn Ref::la64_argregs(self : Ref) -> (UInt64, Int, Int) {
  let mut b : UInt64 = 0
  let v = self.call_val()
  let ni = (v >> 4) & 15
  let nf = (v >> 8) & 15
  let env = (v >> 12) & 1
  for j in 0..<ni {
    b = b | (1UL << (LA_A0 + j))
  }
  for j in 0..<nf {
    b = b | (1UL << (LA_FA0 + j))
  }
  if env != 0 {
    b = b | (1UL << LA_T8)
  }
  (b, ni + env, nf)
}

///|
// Map LoongArch register number to ABI name string (without the `$` prefix).
pub fn la64_reg_name(reg : Int) -> String {
  match reg {
    LA_FP => "fp"
    LA_SP => "sp"
    LA_TP => "tp"
    LA_RA => "ra"
    LA_T0 => "t0"
    LA_T1 => "t1"
    LA_T2 => "t2"
    LA_T3 => "t3"
    LA_T4 => "t4"
    LA_T5 => "t5"
    LA_T6 => "t6"
    LA_T7 => "t7"
    LA_T8 => "t8"
    LA_A0 => "a0"
    LA_A1 => "a1"
    LA_A2 => "a2"
    LA_A3 => "a3"
    LA_A4 => "a4"
    LA_A5 => "a5"
    LA_A6 => "a6"
    LA_A7 => "a7"
    LA_S0 => "s0"
    LA_S1 => "s1"
    LA_S2 => "s2"
    LA_S3 => "s3"
    LA_S4 => "s4"
    LA_S5 => "s5"
    LA_S6 => "s6"
    LA_S7 => "s7"
    LA_S8 => "s8"
    LA_FT0 => "ft0"
    LA_FT1 => "ft1"
    LA_FT2 => "ft2"
    LA_FT3 => "ft3"
    LA_FT4 => "ft4"
    LA_FT5 => "ft5"
    LA_FT6 => "ft6"
    LA_FT7 => "ft7"
    LA_FT8 => "ft8"
    LA_FT9 => "ft9"
    LA_FT10 => "ft10"
    LA_FT11 => "ft11"
    LA_FT12 => "ft12"
    LA_FT13 => "ft13"
    LA_FT14 => "ft14"
    LA_FT15 => "ft15"
    LA_FA0 => "fa0"
    LA_FA1 => "fa1"
    LA_FA2 => "fa2"
    LA_FA3 => "fa3"
    LA_FA4 => "fa4"
    LA_FA5 => "fa5"
    LA_FA6 => "fa6"
    LA_FA7 => "fa7"
    LA_FS0 => "fs0"
    LA_FS1 => "fs1"
    LA_FS2 => "fs2"
    LA_FS3 => "fs3"
    LA_FS4 => "fs4"
    LA_FS5 => "fs5"
    LA_FS6 => "fs6"
    LA_FS7 => "fs7"
    _ => "?"
  }
}

///|
// LoongArch pointer size: Kl (64-bit).
pub const La64KmIsWide : Int = 1

///|
// LoongArch call return registers: LA_A0/LA_A1 and LA_FA0/LA_FA1.
fn la64_target_retregs(r : Ref) -> (UInt64, Int, Int) {
  r.la64_retregs()
}

///|
// LoongArch call argument registers: LA_A0.. and LA_FA0...
fn la64_target_argregs(r : Ref) -> (UInt64, Int, Int) {
  r.la64_argregs()
}

///|
// Select the la64 target (LoongArch64 LP64D).
pub fn init_la64_target() -> Unit {
  target_cfg.gpr_base = LA_T0
  target_cfg.fpr_base = LA_FT0
  target_cfg.ngpr = La64NGPR
  target_cfg.nfpr = La64NFPR
  target_cfg.fpr_class_base = LA_FT0
  target_cfg.post_call_gpr = La64NGPS
  target_cfg.post_call_fpr = La64NFPS
  target_cfg.rglob_mask = la64_rglob_mask()
  target_cfg.rsave = la64_rsave
  target_cfg.retregs = la64_target_retregs
  target_cfg.argregs = la64_target_argregs
}
