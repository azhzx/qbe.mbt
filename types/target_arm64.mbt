///|
// ARM64 (AArch64) target constants, AAPCS64 ABI.
// Ported 1:1 from vendor/qbe/arm64/{all.h, targ.c} (the byte-level
// differential oracle). Register tmp ids are renumbered (QBE-style) instead
// of using the raw machine numbers so that the allocatable ranges stay
// contiguous.

///|
// ARM64 register numbers (as virtual tmp ids; matches C enum Arm64Reg where
// R0 = RXX + 1, so bit 0 of a register mask is always unused).

///|
// General purpose registers x0-x15.
pub const ARM64_R0 : Int = 1

///|
pub const ARM64_R1 : Int = 2

///|
pub const ARM64_R2 : Int = 3

///|
pub const ARM64_R3 : Int = 4

///|
pub const ARM64_R4 : Int = 5

///|
pub const ARM64_R5 : Int = 6

///|
pub const ARM64_R6 : Int = 7

///|
pub const ARM64_R7 : Int = 8

///|
// x8: indirect result location register (aggregate return).
pub const ARM64_R8 : Int = 9

///|
pub const ARM64_R9 : Int = 10

///|
pub const ARM64_R10 : Int = 11

///|
pub const ARM64_R11 : Int = 12

///|
pub const ARM64_R12 : Int = 13

///|
pub const ARM64_R13 : Int = 14

///|
pub const ARM64_R14 : Int = 15

///|
pub const ARM64_R15 : Int = 16

///|
// Intra-procedure call scratch registers (x16/x17). IP1 is globally live.
pub const ARM64_IP0 : Int = 17

///|
pub const ARM64_IP1 : Int = 18

///|
// Platform register x18 (reserved on Apple; globally live here).
pub const ARM64_R18 : Int = 19

///|
// Callee-save general purpose registers x19-x28.
pub const ARM64_R19 : Int = 20

///|
pub const ARM64_R20 : Int = 21

///|
pub const ARM64_R21 : Int = 22

///|
pub const ARM64_R22 : Int = 23

///|
pub const ARM64_R23 : Int = 24

///|
pub const ARM64_R24 : Int = 25

///|
pub const ARM64_R25 : Int = 26

///|
pub const ARM64_R26 : Int = 27

///|
pub const ARM64_R27 : Int = 28

///|
pub const ARM64_R28 : Int = 29

///|
// Frame pointer (x29) — globally live.
pub const ARM64_FP : Int = 30

///|
// Link register (x30) — caller-save on arm64.
pub const ARM64_LR : Int = 31

///|
// Stack pointer (x31) — globally live.
pub const ARM64_SP : Int = 32

///|
// FP caller-save registers v0-v7.
pub const ARM64_V0 : Int = 33

///|
pub const ARM64_V1 : Int = 34

///|
pub const ARM64_V2 : Int = 35

///|
pub const ARM64_V3 : Int = 36

///|
pub const ARM64_V4 : Int = 37

///|
pub const ARM64_V5 : Int = 38

///|
pub const ARM64_V6 : Int = 39

///|
pub const ARM64_V7 : Int = 40

///|
// FP callee-save registers v8-v15 (lower 64 bits only).
pub const ARM64_V8 : Int = 41

///|
pub const ARM64_V9 : Int = 42

///|
pub const ARM64_V10 : Int = 43

///|
pub const ARM64_V11 : Int = 44

///|
pub const ARM64_V12 : Int = 45

///|
pub const ARM64_V13 : Int = 46

///|
pub const ARM64_V14 : Int = 47

///|
pub const ARM64_V15 : Int = 48

///|
// FP caller-save registers v16-v30.
pub const ARM64_V16 : Int = 49

///|
pub const ARM64_V17 : Int = 50

///|
pub const ARM64_V18 : Int = 51

///|
pub const ARM64_V19 : Int = 52

///|
pub const ARM64_V20 : Int = 53

///|
pub const ARM64_V21 : Int = 54

///|
pub const ARM64_V22 : Int = 55

///|
pub const ARM64_V23 : Int = 56

///|
pub const ARM64_V24 : Int = 57

///|
pub const ARM64_V25 : Int = 58

///|
pub const ARM64_V26 : Int = 59

///|
pub const ARM64_V27 : Int = 60

///|
pub const ARM64_V28 : Int = 61

///|
pub const ARM64_V29 : Int = 62

///|
pub const ARM64_V30 : Int = 63

///|
// Tmp0 - first non-register temporary (NBit = 64; V30 < Tmp0 holds).
pub const Arm64Tmp0 : Int = 64

///|
// Number of general purpose registers (R0-SP, matches C NGPR).
pub const Arm64NGPR : Int = 32

///|
// Number of float registers (V0-V30, matches C NFPR).
pub const Arm64NFPR : Int = 31

///|
// Number of caller-save GPRs (R0-R15, IP0, IP1, R18, LR = 20).
pub const Arm64NGPS : Int = 20

///|
// Number of caller-save FPRs (v0-v7 and v16-v30, matches C NFPS).
pub const Arm64NFPS : Int = 23

///|
// Number of callee-save registers (x19-x28 and v8-v15, matches C NCLR).
pub const Arm64NCLR : Int = 18

///|
// Number of globally live registers (FP, SP, R18).
pub const Arm64NRGLOB : Int = 3

///|
// ARM64 caller-save register list (C arm64_rsave in targ.c).
pub let arm64_rsave : Array[Int] = [
  ARM64_R0,
  ARM64_R1,
  ARM64_R2,
  ARM64_R3,
  ARM64_R4,
  ARM64_R5,
  ARM64_R6,
  ARM64_R7,
  ARM64_R8,
  ARM64_R9,
  ARM64_R10,
  ARM64_R11,
  ARM64_R12,
  ARM64_R13,
  ARM64_R14,
  ARM64_R15,
  ARM64_IP0,
  ARM64_IP1,
  ARM64_R18,
  ARM64_LR,
  ARM64_V0,
  ARM64_V1,
  ARM64_V2,
  ARM64_V3,
  ARM64_V4,
  ARM64_V5,
  ARM64_V6,
  ARM64_V7,
  ARM64_V16,
  ARM64_V17,
  ARM64_V18,
  ARM64_V19,
  ARM64_V20,
  ARM64_V21,
  ARM64_V22,
  ARM64_V23,
  ARM64_V24,
  ARM64_V25,
  ARM64_V26,
  ARM64_V27,
  ARM64_V28,
  ARM64_V29,
  ARM64_V30,
]

///|
// ARM64 callee-save register list (C arm64_rclob in targ.c).
pub let arm64_rclob : Array[Int] = [
  ARM64_R19,
  ARM64_R20,
  ARM64_R21,
  ARM64_R22,
  ARM64_R23,
  ARM64_R24,
  ARM64_R25,
  ARM64_R26,
  ARM64_R27,
  ARM64_R28,
  ARM64_V8,
  ARM64_V9,
  ARM64_V10,
  ARM64_V11,
  ARM64_V12,
  ARM64_V13,
  ARM64_V14,
  ARM64_V15,
]

///|
// ARM64 globally live registers bitmask (C RGLOB: FP | SP | IP1 | R18).
// These overlap no argument register (C MAKESURE globals_are_not_arguments).
pub fn arm64_rglob_mask() -> UInt64 {
  let one : UInt64 = 1
  (one << ARM64_FP) | (one << ARM64_SP) | (one << ARM64_IP1) | (one << ARM64_R18)
}

///|
// The registers returned by a call, given its RCall ref
// (C arm64_retregs in abi.c). Returns (bits, ngp, nfpr).
pub fn Ref::arm64_retregs(self : Ref) -> (UInt64, Int, Int) {
  let mut b : UInt64 = 0
  let v = self.call_val()
  let mut ngp = v & 3
  let mut nfp = (v >> 2) & 7
  while ngp > 0 {
    ngp = ngp - 1
    b = b | (1UL << (ARM64_R0 + ngp))
  }
  while nfp > 0 {
    nfp = nfp - 1
    b = b | (1UL << (ARM64_V0 + nfp))
  }
  (b, v & 3, (v >> 2) & 7)
}

///|
// The registers used to pass arguments, given an RCall ref
// (C arm64_argregs in abi.c). x8 carries the aggregate-return hidden pointer
// (bit 13).
pub fn Ref::arm64_argregs(self : Ref) -> (UInt64, Int, Int) {
  let mut b : UInt64 = 0
  let v = self.call_val()
  let mut ngp = (v >> 5) & 15
  let mut nfp = (v >> 9) & 15
  let x8 = (v >> 13) & 1
  while ngp > 0 {
    ngp = ngp - 1
    b = b | (1UL << (ARM64_R0 + ngp))
  }
  while nfp > 0 {
    nfp = nfp - 1
    b = b | (1UL << (ARM64_V0 + nfp))
  }
  if x8 != 0 {
    b = b | (1UL << ARM64_R8)
  }
  (b, ((v >> 5) & 15) + x8, (v >> 9) & 15)
}

///|
// Map ARM64 register number to its asm name (C arm64 reg mapping in emit.c).
// The width variants (w0/d0/s0) are applied by the emitter per class.
pub fn arm64_reg_name(reg : Int) -> String {
  match reg {
    ARM64_R0 => "x0"
    ARM64_R1 => "x1"
    ARM64_R2 => "x2"
    ARM64_R3 => "x3"
    ARM64_R4 => "x4"
    ARM64_R5 => "x5"
    ARM64_R6 => "x6"
    ARM64_R7 => "x7"
    ARM64_R8 => "x8"
    ARM64_R9 => "x9"
    ARM64_R10 => "x10"
    ARM64_R11 => "x11"
    ARM64_R12 => "x12"
    ARM64_R13 => "x13"
    ARM64_R14 => "x14"
    ARM64_R15 => "x15"
    ARM64_IP0 => "x16"
    ARM64_IP1 => "x17"
    ARM64_R18 => "x18"
    ARM64_R19 => "x19"
    ARM64_R20 => "x20"
    ARM64_R21 => "x21"
    ARM64_R22 => "x22"
    ARM64_R23 => "x23"
    ARM64_R24 => "x24"
    ARM64_R25 => "x25"
    ARM64_R26 => "x26"
    ARM64_R27 => "x27"
    ARM64_R28 => "x28"
    ARM64_FP => "x29"
    ARM64_LR => "x30"
    ARM64_SP => "sp"
    ARM64_V0 => "v0"
    ARM64_V1 => "v1"
    ARM64_V2 => "v2"
    ARM64_V3 => "v3"
    ARM64_V4 => "v4"
    ARM64_V5 => "v5"
    ARM64_V6 => "v6"
    ARM64_V7 => "v7"
    ARM64_V8 => "v8"
    ARM64_V9 => "v9"
    ARM64_V10 => "v10"
    ARM64_V11 => "v11"
    ARM64_V12 => "v12"
    ARM64_V13 => "v13"
    ARM64_V14 => "v14"
    ARM64_V15 => "v15"
    ARM64_V16 => "v16"
    ARM64_V17 => "v17"
    ARM64_V18 => "v18"
    ARM64_V19 => "v19"
    ARM64_V20 => "v20"
    ARM64_V21 => "v21"
    ARM64_V22 => "v22"
    ARM64_V23 => "v23"
    ARM64_V24 => "v24"
    ARM64_V25 => "v25"
    ARM64_V26 => "v26"
    ARM64_V27 => "v27"
    ARM64_V28 => "v28"
    ARM64_V29 => "v29"
    ARM64_V30 => "v30"
    _ => "?"
  }
}

///|
// ARM64 pointer size: Kl (64-bit).
pub const Arm64KmIsWide : Int = 1

///|
// ARM64 call return registers: x0/x1 and v0-v3 (C arm64_retregs).
fn arm64_target_retregs(r : Ref) -> (UInt64, Int, Int) {
  r.arm64_retregs()
}

///|
// ARM64 call argument registers: x0.. and v0.., x8/x9 flags (C arm64_argregs).
fn arm64_target_argregs(r : Ref) -> (UInt64, Int, Int) {
  r.arm64_argregs()
}

///|
// Select the arm64 target (C T_arm64, ELF flavor).
pub fn init_arm64_target() -> Unit {
  target_cfg.gpr_base = ARM64_R0
  target_cfg.fpr_base = ARM64_V0
  target_cfg.ngpr = Arm64NGPR
  target_cfg.nfpr = Arm64NFPR
  target_cfg.fpr_class_base = ARM64_V0
  target_cfg.post_call_gpr = Arm64NGPS
  target_cfg.post_call_fpr = Arm64NFPS
  target_cfg.rglob_mask = arm64_rglob_mask()
  target_cfg.rsave = arm64_rsave
  target_cfg.retregs = arm64_target_retregs
  target_cfg.argregs = arm64_target_argregs
}
