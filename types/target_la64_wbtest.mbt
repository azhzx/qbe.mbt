// White-box tests for the LoongArch64 (la64) target constants.

///|
test "la64: callee-save counts match the rclob list" {
  assert_eq(la64_rclob.length(), La64NCLR)
  // fp (r22) is globally live and must not appear in the callee-save list
  for pr in la64_rclob {
    assert_true(pr != LA_FP)
  }
}

///|
test "la64: caller-save counts match the rsave list" {
  let mut ngpr = 0
  let mut nfpr = 0
  for r in la64_rsave {
    if r < LA_FT0 {
      ngpr = ngpr + 1
    } else {
      nfpr = nfpr + 1
    }
  }
  assert_eq(ngpr, La64NGPS)
  assert_eq(nfpr, La64NFPS)
  assert_eq(la64_rsave.length(), La64NGPS + La64NFPS)
}

///|
test "la64: register ids fit the 0..63 space and do not collide" {
  // all 64 register ids 0..63 must be distinct across GPR + FPR
  let mut seen = 0UL
  let gprs = [
    LA_ZERO,
    LA_RA,
    LA_TP,
    LA_SP,
    LA_A0,
    LA_A1,
    LA_A2,
    LA_A3,
    LA_A4,
    LA_A5,
    LA_A6,
    LA_A7,
    LA_T0,
    LA_T1,
    LA_T2,
    LA_T3,
    LA_T4,
    LA_T5,
    LA_T6,
    LA_T7,
    LA_T8,
    LA_FP,
    LA_S0,
    LA_S1,
    LA_S2,
    LA_S3,
    LA_S4,
    LA_S5,
    LA_S6,
    LA_S7,
    LA_S8,
  ]
  let fprs = [
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
    LA_FS0,
    LA_FS1,
    LA_FS2,
    LA_FS3,
    LA_FS4,
    LA_FS5,
    LA_FS6,
    LA_FS7,
  ]
  for r in gprs {
    assert_true(r < La64Tmp0)
    assert_true((seen & (1UL << r)) == 0UL)
    seen = seen | (1UL << r)
  }
  for r in fprs {
    assert_true(r < La64Tmp0)
    assert_true((seen & (1UL << r)) == 0UL)
    seen = seen | (1UL << r)
  }
  // 31 GPR slots (zero + 30) + 32 FPR slots; exactly one id (31) is spare
  let mut ones = 0
  for b in 0..<64 {
    if (seen & (1UL << b)) != 0UL {
      ones = ones + 1
    }
  }
  assert_eq(ones, 63)
}

///|
test "la64: register ABI names" {
  assert_eq(la64_reg_name(LA_ZERO), "?")
  assert_eq(la64_reg_name(LA_SP), "sp")
  assert_eq(la64_reg_name(LA_RA), "ra")
  assert_eq(la64_reg_name(LA_FP), "fp")
  assert_eq(la64_reg_name(LA_A0), "a0")
  assert_eq(la64_reg_name(LA_A7), "a7")
  assert_eq(la64_reg_name(LA_T0), "t0")
  assert_eq(la64_reg_name(LA_T8), "t8")
  assert_eq(la64_reg_name(LA_S0), "s0")
  assert_eq(la64_reg_name(LA_S8), "s8")
  assert_eq(la64_reg_name(LA_FA0), "fa0")
  assert_eq(la64_reg_name(LA_FA7), "fa7")
  assert_eq(la64_reg_name(LA_FT0), "ft0")
  assert_eq(la64_reg_name(LA_FT15), "ft15")
  assert_eq(la64_reg_name(LA_FS0), "fs0")
  assert_eq(la64_reg_name(LA_FS7), "fs7")
  assert_eq(la64_reg_name(64), "?")
}

///|
test "la64: init target configures spill/rega" {
  init_la64_target()
  assert_eq(target_cfg.gpr_base, LA_T0)
  assert_eq(target_cfg.fpr_base, LA_FT0)
  assert_eq(target_cfg.ngpr, La64NGPR)
  assert_eq(target_cfg.nfpr, La64NFPR)
  assert_eq(target_cfg.fpr_class_base, LA_FT0)
  assert_eq(target_cfg.post_call_gpr, La64NGPS)
  assert_eq(target_cfg.post_call_fpr, La64NFPS)
  assert_eq(target_cfg.rglob_mask, la64_rglob_mask())
  // retregs: one int + one float result -> a0 | fa0
  let r = Ref::call(1 | (1 << 2))
  let rr = r.la64_retregs()
  assert_eq(rr.0, (1UL << LA_A0) | (1UL << LA_FA0))
  assert_eq(rr.1, 1)
  assert_eq(rr.2, 1)
  // argregs: two int args + one float arg -> a0, a1 | fa0
  let a = Ref::call((2 << 4) | (1 << 8))
  let aa = a.la64_argregs()
  assert_eq(aa.0, (1UL << LA_A0) | (1UL << LA_A1) | (1UL << LA_FA0))
  assert_eq(aa.1, 2)
  assert_eq(aa.2, 1)
  // restore the default target for other tests
  init_amd64_target()
}
