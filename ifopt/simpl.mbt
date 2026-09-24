///|
// Instruction simplification - corresponds to simpl.c in QBE.
//
// simpl() lowers udiv/urem by a power-of-two constant into a shift or a mask.
// The C reference also expands blit pairs (Oblit0/Oblit1), but those
// instructions cannot be represented in this port: @types.Op has neither
// constructor, @types.Ref has no RInt variant for the encoded size, and the
// parser never produces them.  The expansion itself is provided (unused by
// simpl) as the blit helper so the translation is complete.

///|
// The 64-entry de Bruijn table used by ulog2 (C simpl.c ulog2_tab64).
let ulog2_tab64 : Array[Int] = [
  63, 0, 1, 41, 37, 2, 16, 42, 38, 29, 32, 3, 12, 17, 43, 55, 39, 35, 30, 53, 33,
  21, 4, 23, 13, 9, 18, 6, 25, 44, 48, 56, 62, 40, 36, 15, 28, 31, 11, 54, 34, 52,
  20, 22, 8, 5, 24, 47, 61, 14, 27, 10, 51, 19, 7, 46, 60, 26, 50, 45, 59, 49, 58,
  57,
]

///|
// Floor log2 of a power of two (C simpl.c ulog2).
fn ulog2(pow2 : UInt64) -> Int {
  let idx = ((pow2 * 0x5b31ab928877a7eUL) >> 58).to_int()
  ulog2_tab64[idx]
}

///|
// Whether v is a power of two (C simpl.c ispow2).
fn ispow2(v : UInt64) -> Bool {
  v != 0 && (v & (v - 1)) == 0
}

///|
// Expand one blit into load/store/add instructions (C simpl.c blit).
// src is the source address (C sd[0]) and dst the destination address
// (C sd[1]); sz selects the direction (>= 0 forward, < 0 backward).  The
// returned instructions are in the order the C emit buffer produces them.
pub fn blit(
  src : @types.Ref,
  dst : @types.Ref,
  sz : Int,
  fn_ : @types.Fn,
) -> Array[@types.Ins] {
  let tbl : Array[(@types.Op, @types.Op, @types.Class, Int)] = [
    (@types.Storel, @types.Load, @types.Kl, 8),
    (@types.Storew, @types.Load, @types.Kw, 4),
    (@types.Storeh, @types.Loaduh, @types.Kw, 2),
    (@types.Storeb, @types.Loadub, @types.Kw, 1),
  ]
  let out : Array[@types.Ins] = []
  let fwd = sz >= 0
  let mut sz = if sz < 0 { -sz } else { sz }
  let mut off = if fwd { sz } else { 0 }
  for p in tbl {
    let (st, ld, cls, size) = p
    while sz >= size {
      off = off - (if fwd { size } else { 0 })
      let r = fn_.new_tmp("blt", @types.Kl)
      let r1 = fn_.new_tmp("blt", @types.Kl)
      let ro = fn_.get_con(off.to_int64())
      // emit(st, 0, R, r, r1) - the class of a store operand is word-sized (0)
      out.insert(
        0,
        @types.Ins::new_void(
          st,
          @types.Kw,
          @types.Ref::tmp(r),
          @types.Ref::tmp(r1),
        ),
      )
      // emit(Oadd, Kl, r1, sd[1], ro)
      out.insert(
        0,
        @types.Ins::new(
          @types.Add,
          @types.Kl,
          @types.Ref::tmp(r1),
          dst,
          @types.Ref::con(ro),
        ),
      )
      let r1 = fn_.new_tmp("blt", @types.Kl)
      // emit(ld, cls, r, r1, R)
      out.insert(
        0,
        @types.Ins::new(
          ld,
          cls,
          @types.Ref::tmp(r),
          @types.Ref::tmp(r1),
          @types.Ref::none(),
        ),
      )
      // emit(Oadd, Kl, r1, sd[0], ro)
      out.insert(
        0,
        @types.Ins::new(
          @types.Add,
          @types.Kl,
          @types.Ref::tmp(r1),
          src,
          @types.Ref::con(ro),
        ),
      )
      off = off + (if fwd { 0 } else { size })
      sz = sz - size
    }
  }
  out
}

///|
// Simplify a single instruction (C simpl.c ins).  The caller writes the result
// back into the block.  The blit case of the reference is unreachable here (see
// the file header), so only the udiv/urem lowering is performed.
fn simpl_ins(fn_ : @types.Fn, ins : @types.Ins) -> @types.Ins {
  let out = ins
  match out.op {
    @types.Udiv | @types.Urem =>
      if out.cls.base() == 0 {
        let r = out.arg2
        if r.is_con() {
          let c = fn_.cons[r.con_val()]
          if c.kind == @types.CBits {
            let v = c.bits.i.reinterpret_as_uint64()
            if ispow2(v) {
              let n = ulog2(v)
              if out.op == @types.Urem {
                out.op = @types.And
                out.arg2 = @types.Ref::con(
                  fn_.get_con(((1UL << n) - 1).reinterpret_as_int64()),
                )
              } else {
                out.op = @types.Shr
                out.arg2 = @types.Ref::con(fn_.get_con(n.to_int64()))
              }
            }
          }
        }
      }
    _ => ()
  }
  out
}

///|
// Simplify the instructions of a function (C simpl.c simpl).
// The reference emits no debug output, so the returned string is always empty.
pub fn simpl(
  fn_ : @types.Fn,
  print_dbg : Bool,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let _ = print_dbg
  let _ = interner
  let _ = all_typs
  for id in block_order(fn_) {
    let b = fn_.blks[id]
    // Scan the instructions backwards, like the reference for loop.
    let mut i = b.ins.length()
    while i > 0 {
      i = i - 1
      // Expand a blit0/blit1 pair into load/store/add chunks (C simpl.c ins
      // Oblit1 case).  The pair is replaced in place; the expansion is not
      // re-scanned (it only contains loads/stores/adds).
      if b.ins[i].op == @types.Blit1 && i > 0 && b.ins[i - 1].op == @types.Blit0 {
        let b1 = b.ins[i]
        let b0 = b.ins[i - 1]
        let expansion = blit(b0.arg1, b0.arg2, b1.arg1.rint_val(), fn_)
        ignore(b.ins.remove(i))
        ignore(b.ins.remove(i - 1))
        let mut k = 0
        while k < expansion.length() {
          b.ins.insert(i - 1 + k, expansion[k])
          k = k + 1
        }
        i = i - 1
      } else {
        b.ins[i] = simpl_ins(fn_, b.ins[i])
      }
    }
  }
  ""
}
