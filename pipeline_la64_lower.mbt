///|
// la64 has no scalar unsigned float/int conversion instructions accepted by
// clang's assembler. This target-local lowering expands stoui/dtoui/uwtof/
// ultof with the portable bit tricks the reference amd64 isel uses. There is
// no upstream loongarch64 backend, so this is an allowed innovation (covered
// by check_la64_asm.py).

///|
fn la64_lower_tmp(fn_ : @types.Fn, k : @types.Class) -> @types.Ref {
  @types.Ref::tmp(fn_.new_tmp("uconv", k))
}

///|
fn la64_lower_con(fn_ : @types.Fn, v : Int64) -> @types.Ref {
  @types.Ref::con(fn_.get_con(v))
}

///|
fn la64_lower_unsigned_ins(
  fn_ : @types.Fn,
  i : @types.Ins,
) -> Array[@types.Ins] {
  let k = i.cls
  let a = i.arg1
  let out : Array[@types.Ins] = []
  match i.op {
    @types.Uwtof => {
      let r0 = la64_lower_tmp(fn_, @types.Kl)
      out.push(
        @types.Ins::new(@types.Extuw, @types.Kl, r0, a, @types.Ref::none()),
      )
      out.push(@types.Ins::new(@types.Sltof, k, i.to, r0, @types.Ref::none()))
    }
    @types.Ultowf => {
      let kc = if k == @types.Ks { @types.Kw } else { @types.Kl }
      let sh = if k == @types.Ks { 23L } else { 52L }
      let r0 = la64_lower_tmp(fn_, k)
      let t0 = la64_lower_tmp(fn_, @types.Kl)
      let t1 = la64_lower_tmp(fn_, @types.Kl)
      let t2 = la64_lower_tmp(fn_, @types.Kl)
      let t3 = la64_lower_tmp(fn_, @types.Kl)
      let t4 = la64_lower_tmp(fn_, kc)
      let t5 = la64_lower_tmp(fn_, kc)
      let t6 = la64_lower_tmp(fn_, kc)
      out.push(
        @types.Ins::new(@types.And, @types.Kl, t0, a, la64_lower_con(fn_, 1L)),
      )
      out.push(
        @types.Ins::new(@types.Shr, @types.Kl, t1, a, la64_lower_con(fn_, 63L)),
      )
      out.push(@types.Ins::new(@types.Shr, @types.Kl, t2, a, t1))
      out.push(@types.Ins::new(@types.Or, @types.Kl, t3, t0, t2))
      out.push(@types.Ins::new(@types.Sltof, k, r0, t3, @types.Ref::none()))
      out.push(@types.Ins::new(@types.Cast, kc, t4, r0, @types.Ref::none()))
      out.push(@types.Ins::new(@types.Shl, kc, t5, t1, la64_lower_con(fn_, sh)))
      out.push(@types.Ins::new(@types.Add, kc, t6, t4, t5))
      out.push(@types.Ins::new(@types.Cast, k, i.to, t6, @types.Ref::none()))
    }
    @types.Stoui | @types.Dtoui => {
      let kc = if i.op == @types.Stoui { @types.Ks } else { @types.Kd }
      let opsi = if i.op == @types.Stoui { @types.Stosi } else { @types.Dtosi }
      let bias = if kc == @types.Ks {
        0xDF000000L
      } else {
        0xC3E0000000000000UL.reinterpret_as_int64()
      }
      if k == @types.Kw {
        let r0 = la64_lower_tmp(fn_, @types.Kl)
        out.push(@types.Ins::new(opsi, @types.Kl, r0, a, @types.Ref::none()))
        out.push(
          @types.Ins::new(@types.Copy, @types.Kw, i.to, r0, @types.Ref::none()),
        )
      } else {
        let r0 = la64_lower_tmp(fn_, kc)
        let t0 = la64_lower_tmp(fn_, @types.Kl)
        let t1 = la64_lower_tmp(fn_, @types.Kl)
        let t2 = la64_lower_tmp(fn_, @types.Kl)
        let t3 = la64_lower_tmp(fn_, @types.Kl)
        out.push(@types.Ins::new(opsi, @types.Kl, t0, a, @types.Ref::none()))
        out.push(
          @types.Ins::new(
            @types.Sar,
            @types.Kl,
            t1,
            t0,
            la64_lower_con(fn_, 63L),
          ),
        )
        out.push(
          @types.Ins::new(@types.Add, kc, r0, a, la64_lower_con(fn_, bias)),
        )
        out.push(@types.Ins::new(opsi, @types.Kl, t2, r0, @types.Ref::none()))
        out.push(@types.Ins::new(@types.And, @types.Kl, t3, t2, t1))
        out.push(@types.Ins::new(@types.Or, @types.Kl, i.to, t0, t3))
      }
    }
    _ => ()
  }
  out
}

///|
fn lower_unsigned_la64(fn_ : @types.Fn) -> Unit {
  for bi in 0..<fn_.blks.length() {
    let b = fn_.blks[bi]
    if b.ins.length() == 0 {
      continue
    }
    let out : Array[@types.Ins] = []
    let mut changed = false
    for i in b.ins {
      match i.op {
        @types.Stoui | @types.Dtoui | @types.Uwtof | @types.Ultowf => {
          changed = true
          for x in la64_lower_unsigned_ins(fn_, i) {
            out.push(x)
          }
        }
        _ => out.push(i)
      }
    }
    if changed {
      b.ins.clear()
      for x in out {
        b.ins.push(x)
      }
    }
  }
}
