///|
// IR printing - corresponds to printfn/printref/printcon in parse.c
// Used for the -dP debug flag and testing.

///|
// Class to character
fn ktoc(k : @types.Class) -> Char {
  match k {
    @types.Kw => 'w'
    @types.Kl => 'l'
    @types.Ks => 's'
    @types.Kd => 'd'
    @types.Kx => '?'
  }
}

///|
// Jump kind to string
fn jtoa(j : @types.JumpKind) -> String {
  match j {
    @types.Jret0 => "ret0"
    @types.Jretw => "retw"
    @types.Jretl => "retl"
    @types.Jrets => "rets"
    @types.Jretd => "retd"
    @types.Jretc => "retc"
    @types.Jjmp => "jmp"
    @types.Jjnz => "jnz"
    @types.Jjfieq => "jfieq"
    @types.Jjfine => "jfine"
    @types.Jjfisge => "jfisge"
    @types.Jjfisgt => "jfisgt"
    @types.Jjfisle => "jfisle"
    @types.Jjfislt => "jfislt"
    @types.Jjfiuge => "jfiuge"
    @types.Jjfiugt => "jfiugt"
    @types.Jjfiule => "jfiule"
    @types.Jjfiult => "jfiult"
    @types.Jjffeq => "jffeq"
    @types.Jjffge => "jffge"
    @types.Jjffgt => "jffgt"
    @types.Jjffle => "jffle"
    @types.Jjfflt => "jfflt"
    @types.Jjffne => "jffne"
    @types.Jjffo => "jffo"
    @types.Jjffuo => "jffuo"
    @types.Jxxx => "???"
  }
}

///|
// Print a constant
fn printcon(
  c : @types.Con,
  interner : @util.Interner,
  sb : StringBuilder,
) -> Unit {
  match c.kind {
    @types.CUndef => ()
    @types.CAddr => {
      sb.write_string("$")
      sb.write_string(interner.get(c.label))
    }
    @types.CBits =>
      if c.flt == 1 {
        sb.write_string("s_")
        sb.write_string(@util.fmt_fixed(c.bits.s.to_double(), 6))
      } else if c.flt == 2 {
        sb.write_string("d_")
        sb.write_string(@util.fmt_fixed(c.bits.d, 6))
      } else {
        sb.write_string(c.bits.i.to_string())
      }
  }
}

///|
// Print a reference
pub fn printref(
  r : @types.Ref,
  fn_ : @types.Fn,
  interner : @util.Interner,
  sb : StringBuilder,
  all_typs : Array[@types.Typ],
) -> Unit {
  match r {
    RNone => ()
    RTmp(v) =>
      if v < @types.Tmp0 {
        // register
        sb.write_string("R\{v}")
      } else if v >= 0 {
        sb.write_string("%")
        sb.write_string(fn_.tmps[v].name)
      }
    RCon(v) => printcon(fn_.cons[v], interner, sb)
    RSlot(v) => {
      sb.write_string("S")
      let s = if (v & (1 << 28)) != 0 { v - (1 << 29) } else { v }
      sb.write_string(s.to_string())
    }
    RCall(v) => {
      // %04x
      let h = hex4(v)
      sb.write_string(h)
    }
    RType(v) => {
      sb.write_string(":")
      sb.write_string(all_typs[v].name)
    }
    RMem(v) => printmem(fn_.mems[v], fn_, interner, sb, all_typs)
  }
}

///|
// Format an int as at least 4 lowercase hex digits (%04x in C).
fn hex4(v : Int) -> String {
  let sb = StringBuilder::new()
  let chars : Array[Char] = Array::new()
  let mut x = v
  if x == 0 {
    chars.push('0')
  }
  while x != 0 {
    chars.push(hex_digit(x & 0xF))
    x = x >> 4
  }
  while chars.length() < 4 {
    chars.push('0')
  }
  for k = chars.length() - 1; k >= 0; k = k - 1 {
    sb.write_char(chars[k])
  }
  sb.to_string()
}

///|
fn hex_digit(v : Int) -> Char {
  if v < 10 {
    (48 + v).unsafe_to_char() // '0'
  } else {
    (87 + v).unsafe_to_char() // 'a' + v - 10
  }
}

///|
// Print a memory address
fn printmem(
  m : @types.Addr,
  fn_ : @types.Fn,
  interner : @util.Interner,
  sb : StringBuilder,
  all_typs : Array[@types.Typ],
) -> Unit {
  let mut first = false
  sb.write_char('[')
  if m.offset.kind != @types.CUndef {
    printcon(m.offset, interner, sb)
    first = true
  }
  if !m.base.is_none() {
    if first {
      sb.write_string(" + ")
    }
    printref(m.base, fn_, interner, sb, all_typs)
    first = true
  }
  if !m.index.is_none() {
    if first {
      sb.write_string(" + ")
    }
    sb.write_string("\{m.scale} * ")
    printref(m.index, fn_, interner, sb, all_typs)
  }
  sb.write_char(']')
}

///|
// Print a function in IL format (corresponds to printfn)
pub fn printfn(
  fn_ : @types.Fn,
  interner : @util.Interner,
  all_typs : Array[@types.Typ],
) -> String {
  let sb = StringBuilder::new()
  if fn_.is_export {
    sb.write_string("export ")
  }
  sb.write_string("function $\{fn_.name}() {\n")
  for id in fn_.def_order {
    let b = fn_.blks[id]
    sb.write_string("@\{b.name}\n")
    // Phi nodes
    for p in b.phi {
      sb.write_char('\t')
      printref(p.to, fn_, interner, sb, all_typs)
      sb.write_string(" =\{ktoc(p.cls)} phi ")
      let mut first = true
      for a in p.args {
        if !first {
          sb.write_string(", ")
        }
        first = false
        sb.write_string("@\{fn_.blks[a.blk_id].name} ")
        printref(a.value, fn_, interner, sb, all_typs)
      }
      sb.write_string("\n")
    }
    // Instructions
    for ins in b.ins {
      sb.write_char('\t')
      if !ins.to.is_none() {
        printref(ins.to, fn_, interner, sb, all_typs)
        sb.write_string(" =\{ktoc(ins.cls)} ")
      }
      sb.write_string(ins.op.name())
      if ins.to.is_none() {
        // Class suffix for void-result ops (arg, swap, xcmp, ...)
        match ins.op {
          @types.Arg
          | @types.Swap
          | @types.Xcmp
          | @types.Acmp
          | @types.Acmn
          | @types.Afcmp
          | @types.Xtest
          | @types.Xdiv
          | @types.Xidiv => sb.write_char(ktoc(ins.cls))
          _ => ()
        }
      }
      if !ins.arg1.is_none() {
        sb.write_char(' ')
        printref(ins.arg1, fn_, interner, sb, all_typs)
      }
      if !ins.arg2.is_none() {
        sb.write_string(", ")
        printref(ins.arg2, fn_, interner, sb, all_typs)
      }
      sb.write_string("\n")
    }
    // Jump
    match b.jmp.kind {
      @types.Jjmp => {
        // Omit jmp to the next block in definition order (fall-through)
        let mut next = -1
        for i in 0..<fn_.def_order.length() {
          if fn_.def_order[i] == b.id {
            if i + 1 < fn_.def_order.length() {
              next = fn_.def_order[i + 1]
            }
            break
          }
        }
        if b.jmp.s1 >= 0 && b.jmp.s1 != next {
          sb.write_string("\tjmp @\{fn_.blks[b.jmp.s1].name}\n")
        }
      }
      @types.Jret0
      | @types.Jretw
      | @types.Jretl
      | @types.Jrets
      | @types.Jretd
      | @types.Jretc => {
        sb.write_string("\t\{jtoa(b.jmp.kind)}")
        if !(b.jmp.kind == @types.Jret0 && b.jmp.arg.is_none()) {
          sb.write_char(' ')
          printref(b.jmp.arg, fn_, interner, sb, all_typs)
        }
        if b.jmp.kind == @types.Jretc {
          sb.write_string(", :")
          sb.write_string(all_typs[fn_.ret_ty].name)
        }
        sb.write_string("\n")
      }
      _ => {
        sb.write_string("\t\{jtoa(b.jmp.kind)} ")
        if b.jmp.kind == @types.Jjnz {
          printref(b.jmp.arg, fn_, interner, sb, all_typs)
          sb.write_string(", ")
        }
        sb.write_string(
          "@\{fn_.blks[b.jmp.s1].name}, @\{fn_.blks[b.jmp.s2].name}\n",
        )
      }
    }
  }
  sb.write_string("}")
  sb.to_string()
}
