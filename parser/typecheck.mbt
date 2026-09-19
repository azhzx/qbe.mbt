///|
// Function validation after parsing (C parse.c typecheck()).
// Checks operand types, phi predecessors and undefined blocks.

///|
// Merge a temporary's class with a new definition (C util.c clsmerge).
// Returns true on conflict.
fn clsmerge(t : @types.Tmp, k : @types.Class) -> Bool {
  match t.cls {
    @types.Kx => {
      t.cls = k
      false
    }
    @types.Kw =>
      if k == @types.Kl {
        // stays Kw
        false
      } else {
        t.cls != k
      }
    @types.Kl =>
      if k == @types.Kw {
        t.cls = @types.Kw
        false
      } else {
        t.cls != k
      }
    _ => t.cls != k
  }
}

///|
// Check that a reference is usable as class k (C parse.c usecheck).
fn tc_usecheck(r : @types.Ref, k : Int, fn_ : @types.Fn) -> Bool {
  if !r.is_tmp() {
    return true
  }
  let c = fn_.tmps[r.tmp_val()].cls.code()
  c == k || (c == 1 && k == 0)
}

///|
// Argument class code of op's n-th operand for instruction class cls.
fn tc_argcls(op : @types.Op, cls : @types.Class, n : Int) -> Int {
  let info = @types.op_info(op)
  let arr = if n == 0 { info.a0 } else { info.a1 }
  let c = cls.code()
  let idx = if c < 0 { 0 } else { c }
  if idx >= arr.length() {
    -2
  } else {
    arr[idx]
  }
}

///|
fn Parser::typecheck(self : Self, fn_ : @types.Fn) -> Unit raise {
  let n = fn_.blks.length()
  // 1. assign phi destination classes and merge instruction destination types.
  for id in fn_.def_order {
    let b = fn_.blks[id]
    for p in b.phi {
      fn_.tmps[p.to.tmp_val()].cls = p.cls
    }
    for i in b.ins {
      if i.to.is_tmp() {
        let t = fn_.tmps[i.to.tmp_val()]
        if clsmerge(t, i.cls) {
          raise self.error("temporary %\{t.name} is assigned with multiple types")
        }
      }
    }
  }
  // 2. per-block operand and jump checks.
  for id in fn_.def_order {
    let b = fn_.blks[id]
    // predecessor set
    let pb : Array[Bool] = Array::make(n, false)
    for jid in fn_.def_order {
      let jb = fn_.blks[jid]
      if jb.jmp.s1 == id || (jb.jmp.s2 == id && jb.jmp.s2 != jb.jmp.s1) {
        pb[jid] = true
      }
    }
    for p in b.phi {
      let t = fn_.tmps[p.to.tmp_val()]
      let ppb : Array[Bool] = Array::make(n, false)
      for a in p.args {
        if a.blk_id >= 0 && a.blk_id < n && ppb[a.blk_id] {
          raise self.error(
            "multiple entries for @\{fn_.blks[a.blk_id].name} in phi %\{t.name}",
          )
        }
        if !tc_usecheck(a.value, t.cls.code(), fn_) {
          raise self.error(
            "invalid type for operand %\{fn_.tmps[a.value.tmp_val()].name} in phi %\{t.name}",
          )
        }
        if a.blk_id >= 0 && a.blk_id < n {
          ppb[a.blk_id] = true
        }
      }
      let mut same = true
      for i in 0..<n {
        if pb[i] != ppb[i] {
          same = false
          break
        }
      }
      if !same {
        raise self.error("predecessors not matched in phi %\{t.name}")
      }
    }
    for i in b.ins {
      for n2 in 0..<2 {
        let k = tc_argcls(i.op, i.cls, n2)
        let r = if n2 == 0 { i.arg1 } else { i.arg2 }
        if k == -2 {
          raise self.error("invalid instruction type in \{i.op.name()}")
        }
        if r.is_typ() {
          continue
        }
        if !r.is_none() && k == -1 {
          raise self.error(
            "no \{if n2 == 1 { "second" } else { "first" }} operand expected in \{i.op.name()}",
          )
        }
        if r.is_none() && k != -1 {
          raise self.error(
            "missing \{if n2 == 1 { "second" } else { "first" }} operand in \{i.op.name()}",
          )
        }
        if !tc_usecheck(r, k, fn_) {
          raise self.error(
            "invalid type for \{if n2 == 1 { "second" } else { "first" }} operand %\{fn_.tmps[r.tmp_val()].name} in \{i.op.name()}",
          )
        }
      }
    }
    let r = b.jmp.arg
    let j = b.jmp.kind
    let mut jerr = false
    if j.is_ret() {
      let k = match j {
        @types.Jretc => @types.Kl
        @types.Jretw => @types.Kw
        @types.Jretl => @types.Kl
        @types.Jrets => @types.Ks
        @types.Jretd => @types.Kd
        _ => @types.Kx
      }
      if !tc_usecheck(r, k.code(), fn_) {
        jerr = true
      }
    }
    if j == @types.Jjnz && !tc_usecheck(r, @types.Kw.code(), fn_) {
      jerr = true
    }
    if jerr {
      raise self.error(
        "invalid type for jump argument %\{fn_.tmps[r.tmp_val()].name} in block @\{b.name}",
      )
    }
    if b.jmp.s1 >= 0 && fn_.blks[b.jmp.s1].jmp.kind == @types.Jxxx {
      raise self.error("block @\{fn_.blks[b.jmp.s1].name} is used undefined")
    }
    if b.jmp.s2 >= 0 && fn_.blks[b.jmp.s2].jmp.kind == @types.Jxxx {
      raise self.error("block @\{fn_.blks[b.jmp.s2].name} is used undefined")
    }
  }
}
