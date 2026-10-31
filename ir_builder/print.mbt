///|
// Serialize builder-constructed IR back to QBE IL text.
//
// Unlike `@parser.printfn` (the internal `-dP` debug dump, which omits the
// function signature and prints `retw`/`retl` jump-kind names), this produces
// text the textual parser accepts: the round-trip test builds IR, prints it,
// re-parses it and checks the emitted assembly is identical.

///|
// Return-class text used in a function signature (`""` for void).
pub fn Ret::text(self : Ret) -> String {
  match self {
    Void => ""
    Word => "w"
    Long => "l"
    Single => "s"
    Double => "d"
    // An aggregate return carries no class letter: the signature spells it
    // `function :type.N $f(...)` instead, so il_func handles it. Reaching here
    // means a caller expected a letter for a wide return, which is a bug.
    Wide => abort("Ret::text: a wide return has no class letter")
  }
}

///|
// Class to the one-character IL spelling.
fn ktoc(k : @types.Class) -> String {
  match k {
    @types.Kw => "w"
    @types.Kl => "l"
    @types.Ks => "s"
    @types.Kd => "d"
    @types.Kx => "?"
  }
}

///|
fn Builder::tmp_of(self : Builder, h : Int32) -> Int32 {
  match self.vals[h] {
    @types.RTmp(v) => v
    _ => -1
  }
}

///|
// Print a reference (temporary, constant, literal, slot or type).
fn Builder::il_ref(
  self : Builder,
  f : @types.Fn,
  r : @types.Ref,
  sb : StringBuilder,
) -> Unit {
  match r {
    @types.RNone => ()
    @types.RTmp(v) =>
      if v >= 0 && v < f.tmps.length() && f.tmps[v].name != "" {
        sb.write_char('%')
        sb.write_string(f.tmps[v].name)
      } else {
        sb.write_string("%t\{v}")
      }
    @types.RCon(v) => self.il_con(f, f.cons[v], sb)
    @types.RInt(v) => sb.write_string(v.to_string())
    @types.RSlot(v) => {
      sb.write_char('S')
      sb.write_string(v.to_string())
    }
    @types.RCall(v) => sb.write_string("\{v}")
    @types.RType(v) => {
      sb.write_char(':')
      sb.write_string(self.typs[v].name)
    }
    @types.RMem(v) => sb.write_string("M\{v}")
  }
}

///|
fn Builder::il_con(
  self : Builder,
  _f : @types.Fn,
  c : @types.Con,
  sb : StringBuilder,
) -> Unit {
  match c.kind {
    @types.CUndef => ()
    @types.CAddr => {
      sb.write_char('$')
      sb.write_string(self.interner.get(c.label))
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
// Print one non-call instruction.
fn Builder::il_ins(
  self : Builder,
  f : @types.Fn,
  ins : @types.Ins,
  sb : StringBuilder,
) -> Unit {
  sb.write_char('\t')
  if !ins.to.is_none() {
    self.il_ref(f, ins.to, sb)
    sb.write_string(" =")
    sb.write_string(ktoc(ins.cls))
    sb.write_char(' ')
  }
  sb.write_string(ins.op.name())
  if !ins.arg1.is_none() {
    sb.write_char(' ')
    self.il_ref(f, ins.arg1, sb)
  }
  if !ins.arg2.is_none() {
    sb.write_string(", ")
    self.il_ref(f, ins.arg2, sb)
  }
  sb.write_char('\n')
}

///|
// Print a call, folding the buffered `Arg`/`Argc`/`Arge`/`Argv` instructions
// back into the `call $f(w %a, ...)` textual form.
fn Builder::il_call(
  self : Builder,
  f : @types.Fn,
  ins : @types.Ins,
  args : Array[@types.Ins],
  sb : StringBuilder,
) -> Unit {
  sb.write_char('\t')
  if !ins.to.is_none() {
    self.il_ref(f, ins.to, sb)
    sb.write_string(" =")
    sb.write_string(ktoc(ins.cls))
    sb.write_char(' ')
  }
  sb.write_string("call ")
  self.il_ref(f, ins.arg1, sb)
  sb.write_char('(')
  let mut first = true
  for a in args {
    if !first {
      sb.write_string(", ")
    }
    first = false
    match a.op {
      @types.Arg => {
        sb.write_string(ktoc(a.cls))
        sb.write_char(' ')
        self.il_ref(f, a.arg1, sb)
      }
      @types.Argc => {
        self.il_ref(f, a.arg1, sb)
        sb.write_char(' ')
        self.il_ref(f, a.arg2, sb)
      }
      @types.Arge => {
        sb.write_string("env ")
        self.il_ref(f, a.arg1, sb)
      }
      @types.Argv => sb.write_string("...")
      _ => ()
    }
  }
  sb.write_string(")\n")
}

///|
// Skip `Par` (it lives in the signature) and reconstruct calls.
fn Builder::il_body(
  self : Builder,
  f : @types.Fn,
  b : @types.Blk,
  sb : StringBuilder,
) -> Unit {
  let args : Array[@types.Ins] = []
  for ins in b.ins {
    match ins.op {
      @types.Par => ()
      @types.Arg | @types.Argc | @types.Arge | @types.Argv => args.push(ins)
      @types.Call => {
        self.il_call(f, ins, args, sb)
        args.clear()
      }
      _ => self.il_ins(f, ins, sb)
    }
  }
}

///|
fn Builder::il_term(
  self : Builder,
  f : @types.Fn,
  b : @types.Blk,
  sb : StringBuilder,
) -> Unit {
  match b.jmp.kind {
    @types.Jret0 => sb.write_string("\tret\n")
    @types.Jretw | @types.Jretl | @types.Jrets | @types.Jretd | @types.Jretc => {
      sb.write_string("\tret ")
      self.il_ref(f, b.jmp.arg, sb)
      sb.write_char('\n')
    }
    @types.Jjmp => {
      sb.write_string("\tjmp @")
      sb.write_string(f.blks[b.jmp.s1].name)
      sb.write_char('\n')
    }
    @types.Jjnz => {
      sb.write_string("\tjnz ")
      self.il_ref(f, b.jmp.arg, sb)
      sb.write_string(", @")
      sb.write_string(f.blks[b.jmp.s1].name)
      sb.write_string(", @")
      sb.write_string(f.blks[b.jmp.s2].name)
      sb.write_char('\n')
    }
    _ => sb.write_string("\t# unsupported jump kind\n")
  }
}

///|
fn Builder::il_func(self : Builder, fid : Int32, sb : StringBuilder) -> Unit {
  let f = self.funcs[fid]
  if f.is_export {
    sb.write_string("export ")
  }
  sb.write_string("function")
  // `function :type.N $f(...)` for an aggregate return, `function w $f(...)`
  // for a scalar one (the IL spells the return type either way).
  match self.rets[fid] {
    Wide => {
      if f.ret_ty < 0 {
        abort("il_func: a wide return needs a ret_ty; use add_func_ty")
      }
      sb.write_char(' ')
      sb.write_string(":type.")
      sb.write_string(f.ret_ty.to_string())
    }
    r => {
      let rc = r.text()
      if rc != "" {
        sb.write_char(' ')
        sb.write_string(rc)
      }
    }
  }
  sb.write_string(" $")
  sb.write_string(f.name)
  sb.write_char('(')
  let ps = self.params[fid]
  for i in 0..<ps.length() {
    if i > 0 {
      sb.write_string(", ")
    }
    let tid = self.tmp_of(ps[i])
    sb.write_string(ktoc(f.tmps[tid].cls))
    sb.write_string(" %")
    sb.write_string(f.tmps[tid].name)
  }
  if f.is_vararg {
    if ps.length() > 0 {
      sb.write_string(", ")
    }
    sb.write_string("...")
  }
  sb.write_string(") {\n")
  for bid in f.def_order {
    let b = f.blks[bid]
    sb.write_char('@')
    sb.write_string(b.name)
    sb.write_char('\n')
    for p in b.phi {
      sb.write_char('\t')
      self.il_ref(f, p.to, sb)
      sb.write_string(" =")
      sb.write_string(ktoc(p.cls))
      sb.write_string(" phi ")
      let mut first = true
      for a in p.args {
        if !first {
          sb.write_string(", ")
        }
        first = false
        sb.write_char('@')
        sb.write_string(f.blks[a.blk_id].name)
        sb.write_char(' ')
        self.il_ref(f, a.value, sb)
      }
      sb.write_char('\n')
    }
    self.il_body(f, b, sb)
    self.il_term(f, b, sb)
  }
  sb.write_string("}\n")
}

///|
fn il_string_literal(sb : StringBuilder, s : String) -> Unit {
  sb.write_char('"')
  let mut esc = false
  for c in s.to_array() {
    if c == '"' && !esc {
      sb.write_char('\\')
    }
    sb.write_char(c)
    esc = c == '\\' && !esc
  }
  sb.write_char('"')
}

///|
fn il_data_item(d : @types.Dat, sb : StringBuilder) -> Unit {
  match d.kind {
    @types.DB =>
      if d.is_str {
        sb.write_string("b ")
        il_string_literal(sb, d.str)
      } else {
        sb.write_string("b ")
        sb.write_string(d.num.to_string())
      }
    @types.DH => {
      sb.write_string("h ")
      sb.write_string(d.num.to_string())
    }
    @types.DW => {
      sb.write_string("w ")
      sb.write_string(d.num.to_string())
    }
    @types.DL =>
      if d.is_ref {
        sb.write_char('$')
        sb.write_string(d.ref_name)
      } else {
        sb.write_string("l ")
        sb.write_string(d.num.to_string())
      }
    @types.DZ => {
      sb.write_string("z ")
      sb.write_string(d.num.to_string())
    }
    _ => ()
  }
}

///|
// Print one `data` section starting at `start`; returns the next index.
fn Builder::il_data(self : Builder, start : Int32, sb : StringBuilder) -> Int32 {
  let mut end = start
  let mut name = ""
  let mut is_export = false
  let mut align : Int64 = 0
  for j in start..<self.datas.length() {
    let d = self.datas[j]
    match d.kind {
      @types.DStart => is_export = is_export || d.is_export
      @types.DAlign => align = d.num
      @types.DName => {
        name = d.str
        is_export = is_export || d.is_export
      }
      @types.DEnd => {
        end = j
        break
      }
      _ => ()
    }
  }
  if is_export {
    sb.write_string("export ")
  }
  sb.write_string("data $")
  sb.write_string(name)
  sb.write_string(" = ")
  if align > 0L {
    sb.write_string("align ")
    sb.write_string(align.to_string())
    sb.write_char(' ')
  }
  sb.write_char('{')
  let mut first = true
  for k in start..<end {
    let d = self.datas[k]
    match d.kind {
      @types.DStart | @types.DAlign | @types.DName => ()
      _ => {
        if first {
          sb.write_char(' ')
        } else {
          sb.write_string(", ")
        }
        first = false
        il_data_item(d, sb)
      }
    }
  }
  if !first {
    sb.write_char(' ')
  }
  sb.write_string("}\n")
  end + 1
}

///|
// Print one aggregate type definition. The IL has no explicit padding, it is
// implied by the alignment rules, so FPad is skipped. Unions would need the
// nested-brace form and a record of where each member starts, which the field
// table does not keep; refuse rather than print a struct instead.
fn Builder::il_type(self : Builder, ti : Int32, sb : StringBuilder) -> Unit {
  let t = self.typs[ti]
  if t.nunion > 1 {
    abort("il_type: printing a union type is not supported")
  }
  sb.write_string("type :")
  sb.write_string(t.name)
  sb.write_string(" = align ")
  sb.write_string((1 << t.align).to_string())
  sb.write_string(" {")
  let mut first = true
  for f in t.fields {
    let part = match f.kind {
      @types.FEnd | @types.FPad => ""
      @types.FTyp => " :type." + f.len.to_string() + " 1"
      @types.Fb => " b 1"
      @types.Fh => " h 1"
      @types.Fw => " w 1"
      @types.Fl => " l 1"
      @types.Fs => " s 1"
      @types.Fd => " d 1"
    }
    if part != "" {
      if !first {
        sb.write_string(",")
      }
      sb.write_string(part)
      first = false
    }
  }
  sb.write_string(" }\n")
}

///|
// Serialize the module to QBE IL text. The output is accepted by the textual
// parser, so `emit_il` followed by `@qbe.compile_arm64` reproduces `emit_asm`.
pub fn Builder::emit_il(self : Builder) -> String {
  self.finalize()
  let sb = StringBuilder::StringBuilder()
  let mut fi = 0
  let mut di = 0
  let mut ti = 0
  for item in self.order {
    if item == "f" {
      self.il_func(fi, sb)
      fi = fi + 1
    } else if item == "t" {
      self.il_type(ti, sb)
      ti = ti + 1
    } else {
      di = self.il_data(di, sb)
    }
  }
  sb.to_string()
}
