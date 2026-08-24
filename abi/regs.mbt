///|
// amd64 SysV register conventions - re-exported from the types package
// (moved there so the spill/rega/live passes can share them).

///|
pub let rsave : Array[Int] = @types.rsave

///|
pub let rclob : Array[Int] = @types.rclob

///|
// The registers returned by a call, given its RCall ref. Returns (bits, ngp, nfpr).
pub fn retregs(r : @types.Ref) -> (UInt64, Int, Int) {
  @types.retregs(r)
}

///|
// The registers used to pass arguments, given an RCall ref. Returns (bits, ngp, nfpr).
pub fn argregs(r : @types.Ref) -> (UInt64, Int, Int) {
  @types.argregs(r)
}
