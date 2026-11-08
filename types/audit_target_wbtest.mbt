///|
// Upstream rv64/abi.c:75-94: integer arguments start at A0, not T0.
test "audit rv64 public argregs uses argument registers" {
  let r = Ref::call((2 << 4) | (1 << 8) | (1 << 12))
  let (mask, ngp, nfp) = r.rv64_argregs()
  assert_eq(mask, (1UL << A0) | (1UL << A1) | (1UL << FA0) | (1UL << T5))
  assert_eq(ngp, 3)
  assert_eq(nfp, 1)
}

///|
// The active callback is what liveness/spill/rega consume.
test "audit rv64 active argregs preserves environment register" {
  init_rv64_target()
  let result = target_argregs(Ref::call(1 << 12))
  init_amd64_target()
  assert_eq(result, (1UL << T5, 1, 0))
}

///|
// rv64/all.h excludes the reserved T6 and FT11 from the FPR range.
test "audit rv64 register initialization excludes reserved T6 from FPRs" {
  init_rv64_target()
  let f = Fn::new("register_range")
  f.init_regs()
  let end = target_cfg.fpr_base + target_cfg.nfpr
  init_amd64_target()
  assert_eq(f.tmps[T6].cls, Kl)
  assert_eq(end, FS11 + 1)
}

///|
// rv64/targ.c:28-31 returns zero for every operation.
test "audit rv64 spilling never keeps memory operands" {
  init_rv64_target()
  let add = (target_cfg.memargs)(Add)
  let mul = (target_cfg.memargs)(Mul)
  let shl = (target_cfg.memargs)(Shl)
  init_amd64_target()
  assert_eq((add, mul, shl), (0, 0, 0))
}

///|
// arm64/abi.c:321-340 includes both x8 and x9 in mask and count.
test "audit arm64 argregs preserves environment and indirect result" {
  init_arm64_target()
  let result = target_argregs(
    Ref::call((1 << 5) | (1 << 9) | (1 << 13) | (1 << 14)),
  )
  init_amd64_target()
  assert_eq(
    result,
    (
      (1UL << ARM64_R0) |
      (1UL << ARM64_V0) |
      (1UL << ARM64_R8) |
      (1UL << ARM64_R9),
      3,
      1,
    ),
  )
}

///|
test "audit arm64 globally live count includes IP1" {
  assert_eq(Arm64NRGLOB, arm64_rglob_mask().popcnt())
}
