///|
// Target abstraction - corresponds to struct Target and amd64/all.h

///|
// AMD64 register numbers (as virtual tmp ids, matching C enum Amd64Reg)
pub const RXX : Int32 = 0

///|
pub const RAX : Int32 = 1

///|
pub const RCX : Int32 = 2

///|
pub const RDX : Int32 = 3

///|
pub const RSI : Int32 = 4

///|
pub const RDI : Int32 = 5

///|
pub const R8 : Int32 = 6

///|
pub const R9 : Int32 = 7

///|
pub const R10 : Int32 = 8

///|
pub const R11 : Int32 = 9

///|
pub const RBX : Int32 = 10

///|
pub const R12 : Int32 = 11

///|
pub const R13 : Int32 = 12

///|
pub const R14 : Int32 = 13

///|
pub const R15 : Int32 = 14

///|
pub const RBP : Int32 = 15

///|
pub const RSP : Int32 = 16

///|
pub const XMM0 : Int32 = 17

///|
pub const XMM1 : Int32 = 18

///|
pub const XMM2 : Int32 = 19

///|
pub const XMM3 : Int32 = 20

///|
pub const XMM4 : Int32 = 21

///|
pub const XMM5 : Int32 = 22

///|
pub const XMM6 : Int32 = 23

///|
pub const XMM7 : Int32 = 24

///|
pub const XMM8 : Int32 = 25

///|
pub const XMM9 : Int32 = 26

///|
pub const XMM10 : Int32 = 27

///|
pub const XMM11 : Int32 = 28

///|
pub const XMM12 : Int32 = 29

///|
pub const XMM13 : Int32 = 30

///|
pub const XMM14 : Int32 = 31

///|
pub const XMM15 : Int32 = 32

///|
// Tmp0 - first non-register temporary (NBit = 64)
pub const Tmp0 : Int32 = 64

///|
// Number of general purpose registers
pub const NGPR : Int32 = RSP - RAX + 1

///|
// Number of float registers
pub const NFPR : Int32 = XMM14 - XMM0 + 1

///|
// Number of caller-save GPRs (RAX..R11)
pub const NGPS : Int32 = R11 - RAX + 1

///|
// Number of caller-save FPRs
pub const NFPS : Int32 = NFPR

///|
// Number of callee-save registers (RBX..R15)
pub const NCLR : Int32 = R15 - RBX + 1

///|
// Caller-save registers for amd64 sysv (C amd64_sysv_rsave in sysv.c).
// These are the argument/return registers used by retregs/argregs and by
// the spill/rega passes (T.rsave).
pub let rsave : Array[Int32] = [
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
pub let rclob : Array[Int32] = [RBX, R12, R13, R14, R15]

///|
// The registers returned by a call, given its RCall ref (C retregs).
// Returns (bits, ngp, nfpr).
pub fn Ref::retregs(self : Ref) -> (UInt64, Int32, Int32) {
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
pub fn Ref::argregs(self : Ref) -> (UInt64, Int32, Int32) {
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
pub const NRGLOB : Int32 = 2

///|
// Target description - corresponds to C's `struct Target T` (all.h).
// spill/rega are target-agnostic and read the current target through the
// `target_cfg` global, which is selected by `init_amd64_target` /
// `init_rv64_target` before the post-isel passes run.
pub struct TargetCfg {
  // First GPR/FPR tmp ids scanned by rega (C T.gpr_base / T.fpr_base).
  mut gpr_base : Int32
  mut fpr_base : Int32
  // Number of registers scanned by rega/spill (C T.ngpr / T.nfpr).
  mut ngpr : Int32
  mut nfpr : Int32
  // First FPR id in class-order scans (spill classifies tmp ids).
  mut fpr_class_base : Int32
  // Register limits applied right after a call (C limit2(v, NGPS, NFPS)).
  mut post_call_gpr : Int32
  mut post_call_fpr : Int32
  // Globally live registers bitmask (C T.rglob).
  mut rglob_mask : UInt64
  // Caller-save registers (C T.rsave).
  mut rsave : Array[Int32]
  // How many operands of an op may stay in memory (C T.memargs).
  // This is target-specific: arm64 has no memory operands at all,
  // amd64 and the load/store backends accept one.
  mut memargs : (Op) -> Int32
  // Call return/argument register mapping (C T.retregs / T.argregs).
  mut retregs : (Ref) -> (UInt64, Int32, Int32)
  mut argregs : (Ref) -> (UInt64, Int32, Int32)
}

///|
// amd64_sysv call return registers (C amd64_sysv retregs).
fn amd64_target_retregs(r : Ref) -> (UInt64, Int32, Int32) {
  let mut b : UInt64 = 0
  let v = r.call_val()
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
// amd64_sysv call argument registers (C amd64_sysv argregs).
fn amd64_target_argregs(r : Ref) -> (UInt64, Int32, Int32) {
  let mut b : UInt64 = 0
  let v = r.call_val()
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
// The amd64_sysv target configuration (the historical default).
fn amd64_target_cfg() -> TargetCfg {
  TargetCfg::{
    gpr_base: RAX,
    fpr_base: XMM0,
    ngpr: NGPR,
    nfpr: NFPR,
    fpr_class_base: XMM0,
    post_call_gpr: NGPS,
    post_call_fpr: NFPS,
    rglob_mask: rglob_mask(),
    rsave,
    memargs: fn(op) { op_info(op).nmem },
    retregs: amd64_target_retregs,
    argregs: amd64_target_argregs,
  }
}

///|
// The current target, defaulting to amd64_sysv.
pub let target_cfg : TargetCfg = amd64_target_cfg()

///|
// Select the amd64_sysv target (C init(T_amd64_sysv)).
pub fn init_amd64_target() -> Unit {
  let amd = amd64_target_cfg()
  target_cfg.gpr_base = amd.gpr_base
  target_cfg.fpr_base = amd.fpr_base
  target_cfg.ngpr = amd.ngpr
  target_cfg.nfpr = amd.nfpr
  target_cfg.fpr_class_base = amd.fpr_class_base
  target_cfg.post_call_gpr = amd.post_call_gpr
  target_cfg.post_call_fpr = amd.post_call_fpr
  target_cfg.rglob_mask = amd.rglob_mask
  target_cfg.rsave = amd.rsave
  target_cfg.memargs = amd.memargs
  target_cfg.retregs = amd.retregs
  target_cfg.argregs = amd.argregs
}

///|
// The registers returned by a call on the current target (C T.retregs).
pub fn target_retregs(r : Ref) -> (UInt64, Int32, Int32) {
  (target_cfg.retregs)(r)
}

///|
// The registers used to pass arguments on the current target (C T.argregs).
pub fn target_argregs(r : Ref) -> (UInt64, Int32, Int32) {
  (target_cfg.argregs)(r)
}
