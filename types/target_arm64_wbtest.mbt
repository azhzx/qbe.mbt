// White-box tests for the ARM64 (AAPCS64) target constants.

///|
test "arm64: callee-save counts match the rclob list" {
  assert_eq(arm64_rclob.length(), Arm64NCLR)
  // FP, SP, IP1 and R18 are globally live and must not be callee-save
  for pr in arm64_rclob {
    assert_true(pr != ARM64_FP)
    assert_true(pr != ARM64_SP)
    assert_true(pr != ARM64_IP1)
    assert_true(pr != ARM64_R18)
  }
}

///|
test "arm64: caller-save counts match the rsave list" {
  let mut ngpr = 0
  let mut nfpr = 0
  for r in arm64_rsave {
    if r < ARM64_V0 {
      ngpr = ngpr + 1
    } else {
      nfpr = nfpr + 1
    }
  }
  assert_eq(ngpr, Arm64NGPS)
  assert_eq(nfpr, Arm64NFPS)
  assert_eq(arm64_rsave.length(), Arm64NGPS + Arm64NFPS)
}

///|
test "arm64: register ids fit the 0..63 space and do not collide" {
  // the C port guarantees V30 < Tmp0 and R0 = RXX + 1 (bit 0 unused)
  let mut seen = 0UL
  let gprs = [
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
    ARM64_FP,
    ARM64_LR,
    ARM64_SP,
  ]
  let fprs = [
    ARM64_V0,
    ARM64_V1,
    ARM64_V2,
    ARM64_V3,
    ARM64_V4,
    ARM64_V5,
    ARM64_V6,
    ARM64_V7,
    ARM64_V8,
    ARM64_V9,
    ARM64_V10,
    ARM64_V11,
    ARM64_V12,
    ARM64_V13,
    ARM64_V14,
    ARM64_V15,
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
  for r in gprs {
    assert_true(r < Arm64Tmp0)
    assert_true((seen & (1UL << r)) == 0UL)
    seen = seen | (1UL << r)
  }
  for r in fprs {
    assert_true(r < Arm64Tmp0)
    assert_true((seen & (1UL << r)) == 0UL)
    seen = seen | (1UL << r)
  }
  // bit 0 (RXX) is unused; ids 1..63 are all occupied
  assert_true((seen & 1UL) == 0UL)
  let mut ones = 0
  for b in 0..<64 {
    if (seen & (1UL << b)) != 0UL {
      ones = ones + 1
    }
  }
  assert_eq(ones, 63)
  // the globally live mask is disjoint from the argument registers x0-x8
  assert_true((arm64_rglob_mask() & ((1UL << (ARM64_R8 + 1)) - 1UL)) == 0UL)
}

///|
test "arm64: register ABI names" {
  assert_eq(arm64_reg_name(ARM64_R0), "x0")
  assert_eq(arm64_reg_name(ARM64_R8), "x8")
  assert_eq(arm64_reg_name(ARM64_IP0), "x16")
  assert_eq(arm64_reg_name(ARM64_IP1), "x17")
  assert_eq(arm64_reg_name(ARM64_R18), "x18")
  assert_eq(arm64_reg_name(ARM64_R28), "x28")
  assert_eq(arm64_reg_name(ARM64_FP), "x29")
  assert_eq(arm64_reg_name(ARM64_LR), "x30")
  assert_eq(arm64_reg_name(ARM64_SP), "sp")
  assert_eq(arm64_reg_name(ARM64_V0), "v0")
  assert_eq(arm64_reg_name(ARM64_V7), "v7")
  assert_eq(arm64_reg_name(ARM64_V8), "v8")
  assert_eq(arm64_reg_name(ARM64_V30), "v30")
  assert_eq(arm64_reg_name(64), "?")
}

///|
test "arm64: init target configures spill/rega" {
  init_arm64_target()
  assert_eq(target_cfg.gpr_base, ARM64_R0)
  assert_eq(target_cfg.fpr_base, ARM64_V0)
  assert_eq(target_cfg.ngpr, Arm64NGPR)
  assert_eq(target_cfg.nfpr, Arm64NFPR)
  assert_eq(target_cfg.fpr_class_base, ARM64_V0)
  assert_eq(target_cfg.post_call_gpr, Arm64NGPS)
  assert_eq(target_cfg.post_call_fpr, Arm64NFPS)
  assert_eq(target_cfg.rglob_mask, arm64_rglob_mask())
  // retregs: one int + one float result -> x0 | v0 (C bit layout:
  // gp count in bits 0-1, fp count in bits 2-4)
  let r = Ref::call(1 | (1 << 2))
  let rr = r.arm64_retregs()
  assert_eq(rr.0, (1UL << ARM64_R0) | (1UL << ARM64_V0))
  assert_eq(rr.1, 1)
  assert_eq(rr.2, 1)
  // retregs: two float results (HFA return) -> v0 | v1
  let r2 = Ref::call(2 << 2)
  let rr2 = r2.arm64_retregs()
  assert_eq(rr2.0, (1UL << ARM64_V0) | (1UL << ARM64_V1))
  assert_eq(rr2.2, 2)
  // argregs: two int args + one float arg (C bit layout: gp in bits 5-8,
  // fp in bits 9-12, x8 in bit 13, env x9 in bit 14)
  let a = Ref::call((2 << 5) | (1 << 9))
  let aa = a.arm64_argregs()
  assert_eq(aa.0, (1UL << ARM64_R0) | (1UL << ARM64_R1) | (1UL << ARM64_V0))
  assert_eq(aa.1, 2)
  assert_eq(aa.2, 1)
  // argregs: one int arg + aggregate-return x8 pointer
  let a2 = Ref::call((1 << 5) | (1 << 13))
  let aa2 = a2.arm64_argregs()
  assert_eq(aa2.0, (1UL << ARM64_R0) | (1UL << ARM64_R8))
  assert_eq(aa2.1, 2)
  // restore the default target for other tests
  init_amd64_target()
}
