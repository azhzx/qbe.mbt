///|
// WAT (WebAssembly Text) emission.

///|
priv struct WatEmitState {
  fn_ : @types.Fn
  interner : @util.Interner
  sb : StringBuilder
  // Resolved addresses of global data labels (name -> linear-memory offset).
  dats : Array[(String, Int)]
  // Names of module functions that return no value; a call to one must not be
  // followed by local.set even if the IL names a result.
  void_fns : Array[String]
  // Declared parameter types of each module function (name -> wasm types),
  // used to pad or drop call arguments so wasm's fixed arity is satisfied.
  fn_params : Array[(String, Array[String])]
  mut pending_args : Int
  mut indent : Int
}

///|
fn wat_emit_new(
  fn_ : @types.Fn,
  interner : @util.Interner,
  sb : StringBuilder,
  dats : Array[(String, Int)],
  void_fns : Array[String],
  fn_params : Array[(String, Array[String])],
) -> WatEmitState {
  WatEmitState::{
    fn_,
    interner,
    sb,
    dats,
    void_fns,
    fn_params,
    pending_args: 0,
    indent: 0,
  }
}

///|
fn zero_const(t : String) -> String {
  match t {
    "i64" => "i64.const 0"
    "f32" => "f32.const 0"
    "f64" => "f64.const 0"
    _ => "i32.const 0"
  }
}

///|
// Resolve a global data label to its linear-memory address, or 0 when the
// label is external / not defined in this module.
fn wat_data_addr(st : WatEmitState, name : String) -> Int64 {
  for p in st.dats {
    if p.0 == name {
      return p.1.to_int64()
    }
  }
  0L
}

///|
fn wat_indent(st : WatEmitState) -> Unit {
  for _ in 0..<st.indent {
    st.sb.write_string("  ")
  }
}

///|
fn wat_writeln(st : WatEmitState, s : String) -> Unit {
  wat_indent(st)
  st.sb.write_string(s)
  st.sb.write_string("\n")
}

///|
fn wasm_type(cls : @types.Class) -> String {
  @types.wasm_type_name(cls)
}

///|
// The class the function returns, taken from its Jret* terminator.
fn return_class(st : WatEmitState) -> @types.Class? {
  for bid in st.fn_.def_order {
    match st.fn_.blks[bid].jmp.kind {
      @types.Jretw => return Some(@types.Kw)
      @types.Jretl => return Some(@types.Kl)
      @types.Jrets => return Some(@types.Ks)
      @types.Jretd => return Some(@types.Kd)
      @types.Jretc => return Some(@types.Kl)
      _ => ()
    }
  }
  None
}

///|
fn operand_class(op : @types.Op, cls : @types.Class) -> @types.Class {
  match op {
    @types.Ceqw
    | @types.Cnew
    | @types.Csgew
    | @types.Csgtw
    | @types.Cslew
    | @types.Csltw
    | @types.Cugew
    | @types.Cugtw
    | @types.Culew
    | @types.Cultw => @types.Kw
    @types.Ceql
    | @types.Cnel
    | @types.Csgel
    | @types.Csgtl
    | @types.Cslel
    | @types.Csltl
    | @types.Cugel
    | @types.Cugtl
    | @types.Culel
    | @types.Cultl => @types.Kl
    @types.Ceqs
    | @types.Cges
    | @types.Cgts
    | @types.Cles
    | @types.Clts
    | @types.Cnes
    | @types.Cos
    | @types.Cuos => @types.Ks
    @types.Ceqd
    | @types.Cged
    | @types.Cgtd
    | @types.Cled
    | @types.Cltd
    | @types.Cned
    | @types.Cod
    | @types.Cuod => @types.Kd
    _ => cls
  }
}

///|
fn icmp_op(name : String, cls : @types.Class) -> String {
  match cls {
    @types.Kl => "i64." + name
    _ => "i32." + name
  }
}

///|
fn wasm_op_name(op : @types.Op, cls : @types.Class) -> String {
  match op {
    @types.Add =>
      match cls {
        @types.Kw => "i32.add"
        @types.Kl => "i64.add"
        @types.Ks => "f32.add"
        @types.Kd => "f64.add"
        _ => "i32.add"
      }
    @types.Sub =>
      match cls {
        @types.Kw => "i32.sub"
        @types.Kl => "i64.sub"
        @types.Ks => "f32.sub"
        @types.Kd => "f64.sub"
        _ => "i32.sub"
      }
    @types.Mul =>
      match cls {
        @types.Kw => "i32.mul"
        @types.Kl => "i64.mul"
        @types.Ks => "f32.mul"
        @types.Kd => "f64.mul"
        _ => "i32.mul"
      }
    @types.Div =>
      match cls {
        @types.Kw => "i32.div_s"
        @types.Kl => "i64.div_s"
        @types.Ks => "f32.div"
        @types.Kd => "f64.div"
        _ => "i32.div_s"
      }
    @types.Udiv =>
      match cls {
        @types.Kw => "i32.div_u"
        @types.Kl => "i64.div_u"
        _ => "i32.div_u"
      }
    @types.Rem =>
      match cls {
        @types.Kw => "i32.rem_s"
        @types.Kl => "i64.rem_s"
        _ => "i32.rem_s"
      }
    @types.Urem =>
      match cls {
        @types.Kw => "i32.rem_u"
        @types.Kl => "i64.rem_u"
        _ => "i32.rem_u"
      }
    @types.And =>
      match cls {
        @types.Kw => "i32.and"
        @types.Kl => "i64.and"
        _ => "i32.and"
      }
    @types.Or =>
      match cls {
        @types.Kw => "i32.or"
        @types.Kl => "i64.or"
        _ => "i32.or"
      }
    @types.Xor =>
      match cls {
        @types.Kw => "i32.xor"
        @types.Kl => "i64.xor"
        _ => "i32.xor"
      }
    @types.Shl =>
      match cls {
        @types.Kw => "i32.shl"
        @types.Kl => "i64.shl"
        _ => "i32.shl"
      }
    @types.Shr =>
      match cls {
        @types.Kw => "i32.shr_u"
        @types.Kl => "i64.shr_u"
        _ => "i32.shr_u"
      }
    @types.Sar =>
      match cls {
        @types.Kw => "i32.shr_s"
        @types.Kl => "i64.shr_s"
        _ => "i32.shr_s"
      }
    @types.Ceqw => "i32.eq"
    @types.Cnew => "i32.ne"
    @types.Ceql => "i64.eq"
    @types.Cnel => "i64.ne"
    @types.Ceqs => "f32.eq"
    @types.Cnes => "f32.ne"
    @types.Ceqd => "f64.eq"
    @types.Cned => "f64.ne"
    @types.Csltw | @types.Csltl => icmp_op("lt_s", operand_class(op, cls))
    @types.Cslew | @types.Cslel => icmp_op("le_s", operand_class(op, cls))
    @types.Csgtw | @types.Csgtl => icmp_op("gt_s", operand_class(op, cls))
    @types.Csgew | @types.Csgel => icmp_op("ge_s", operand_class(op, cls))
    @types.Cultw | @types.Cultl => icmp_op("lt_u", operand_class(op, cls))
    @types.Culew | @types.Culel => icmp_op("le_u", operand_class(op, cls))
    @types.Cugtw | @types.Cugtl => icmp_op("gt_u", operand_class(op, cls))
    @types.Cugew | @types.Cugel => icmp_op("ge_u", operand_class(op, cls))
    @types.Clts => "f32.lt"
    @types.Cles => "f32.le"
    @types.Cgts => "f32.gt"
    @types.Cges => "f32.ge"
    @types.Cltd => "f64.lt"
    @types.Cled => "f64.le"
    @types.Cgtd => "f64.gt"
    @types.Cged => "f64.ge"
    @types.Copy => "local.set"
    _ => "nop"
  }
}

///|
fn emit_ref(st : WatEmitState, r : @types.Ref, k : @types.Class) -> Unit {
  if r.is_none() {
    return
  }
  if r.is_tmp() {
    let tid = r.tmp_val()
    wat_writeln(st, "local.get $t\{tid}")
  } else if r.is_con() {
    let cid = r.con_val()
    let con = st.fn_.cons[cid]
    match con.kind {
      @types.CBits =>
        // The operand class decides the constant type: the interner compares
        // only raw bits (as C QBE's union does), so an integer 0 and a
        // double 0.0 share a Con whose flt flag cannot be trusted.
        if k == @types.Ks {
          let v = if con.flt == 1 {
            con.bits.s
          } else if con.flt == 2 {
            Float::from_double(con.bits.d)
          } else {
            Float::from_double(con.bits.i.to_double())
          }
          wat_writeln(st, "f32.const \{v}")
        } else if k == @types.Kd {
          let v = if con.flt == 2 {
            con.bits.d
          } else if con.flt == 1 {
            con.bits.s.to_double()
          } else {
            con.bits.i.to_double()
          }
          wat_writeln(st, "f64.const \{v}")
        } else if k == @types.Kl {
          wat_writeln(st, "i64.const \{con.bits.i}")
        } else {
          wat_writeln(st, "i32.const \{con.bits.i}")
        }
      @types.CAddr => {
        let addr = wat_data_addr(st, st.interner.get(con.label)) + con.bits.i
        // A data address is an i64 value when used as a QBE `l` operand.
        if k == @types.Kl {
          wat_writeln(st, "i64.const \{addr}")
        } else {
          wat_writeln(st, "i32.const \{addr}")
        }
      }
      _ => wat_writeln(st, "i32.const 0")
    }
  } else if r.is_slot() {
    wat_writeln(st, "local.get $s\{r.slot_val()}")
  }
}

///|
// Emit a memory index (i32 on wasm32). QBE pointers are `l` (i64) values,
// so a register address is wrapped; constant data addresses are already i32.
fn emit_addr32(st : WatEmitState, r : @types.Ref) -> Unit {
  if r.is_tmp() {
    let tid = r.tmp_val()
    wat_writeln(st, "local.get $t\{tid}")
    if st.fn_.tmps[tid].cls.wide() == 1 {
      wat_writeln(st, "i32.wrap_i64")
    }
  } else if r.is_con() {
    emit_ref(st, r, @types.Kw)
  } else if r.is_slot() {
    wat_writeln(st, "local.get $s\{r.slot_val()}")
  }
}

///|
// Emit an operand of class `k`, truncating a wider integer temp to i32.
fn emit_operand(st : WatEmitState, r : @types.Ref, k : @types.Class) -> Unit {
  if r.is_tmp() &&
    st.fn_.tmps[r.tmp_val()].cls.wide() == 1 &&
    k != @types.Kl &&
    k != @types.Kd {
    wat_writeln(st, "local.get $t\{r.tmp_val()}")
    wat_writeln(st, "i32.wrap_i64")
  } else {
    emit_ref(st, r, k)
  }
}

// Store the value currently on the wasm stack into the destination local.

///|
fn set_dest(st : WatEmitState, ins : @types.Ins) -> Unit {
  if ins.to.is_tmp() {
    wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
  }
}

///|
fn store_class(op : @types.Op) -> @types.Class {
  match op {
    @types.Storel => @types.Kl
    @types.Stores => @types.Ks
    @types.Stored => @types.Kd
    _ => @types.Kw
  }
}

///|
fn emit_store(st : WatEmitState, ins : @types.Ins) -> Unit {
  emit_addr32(st, ins.arg2)
  let k = store_class(ins.op)
  emit_ref(st, ins.arg1, k)
  wat_writeln(st, @types.wasm_store_op(k))
}

///|
fn emit_load(st : WatEmitState, ins : @types.Ins) -> Unit {
  emit_addr32(st, ins.arg1)
  wat_writeln(st, @types.wasm_load_op(ins.cls))
}

///|
fn emit_ins(st : WatEmitState, ins : @types.Ins) -> Unit {
  match ins.op {
    @types.Nop | @types.Par | @types.Parc | @types.Pare => ()
    // Call arguments: push the value so the following call consumes it.
    @types.Arg | @types.Arge => {
      emit_ref(st, ins.arg1, ins.cls)
      st.pending_args = st.pending_args + 1
    }
    // Aggregate argument: pass the aggregate's memory address as an i64
    // pointer, matching the i64 Parc parameter.
    @types.Argc => {
      emit_addr32(st, ins.arg2)
      wat_writeln(st, "i64.extend_i32_u")
      st.pending_args = st.pending_args + 1
    }
    // Varargs: wasm32 has no variadic ABI, so a va_arg yields a typed zero and
    // va_start is a no-op. This keeps the module valid; the values are not the
    // caller's actual varargs.
    @types.Vastart => ()
    @types.Vaarg => {
      wat_writeln(st, zero_const(wasm_type(ins.cls)))
      set_dest(st, ins)
    }
    @types.Copy => {
      emit_ref(st, ins.arg1, ins.cls)
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Load
    | @types.Loadsb
    | @types.Loadub
    | @types.Loadsh
    | @types.Loaduh
    | @types.Loadsw
    | @types.Loaduw => {
      emit_load(st, ins)
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Storeb
    | @types.Storeh
    | @types.Storew
    | @types.Storel
    | @types.Stores
    | @types.Stored => emit_store(st, ins)
    @types.Call | @types.Vacall => {
      let mut target = ""
      if ins.arg1.is_con() {
        let cid = ins.arg1.con_val()
        let con = st.fn_.cons[cid]
        if con.kind == @types.CAddr {
          target = st.interner.get(con.label)
        }
      }
      // Reconcile the pushed argument count with the callee's fixed arity:
      // drop extra varargs, or pad missing arguments with zeroes.
      let mut params : Array[String] = []
      let mut found = false
      for p in st.fn_params {
        if p.0 == target {
          params = p.1
          found = true
        }
      }
      if found {
        while st.pending_args > params.length() {
          wat_writeln(st, "drop")
          st.pending_args = st.pending_args - 1
        }
        while st.pending_args < params.length() {
          wat_writeln(st, zero_const(params[st.pending_args]))
          st.pending_args = st.pending_args + 1
        }
      }
      st.pending_args = 0
      if target != "" {
        wat_writeln(st, "call $" + target)
      }
      let mut is_void = false
      for n in st.void_fns {
        if n == target {
          is_void = true
        }
      }
      if ins.to.is_tmp() && !is_void {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Alloc4 | @types.Alloc8 | @types.Alloc16 => {
      let align = match ins.op {
        @types.Alloc4 => 4
        @types.Alloc8 => 8
        @types.Alloc16 => 16
        _ => 4
      }
      // to = (i64) sp
      wat_writeln(st, "global.get $sp")
      wat_writeln(st, "i64.extend_i32_u")
      set_dest(st, ins)
      // sp = (sp + size + align-1) & -align  (i32 arithmetic)
      wat_writeln(st, "global.get $sp")
      emit_addr32(st, ins.arg1)
      wat_writeln(st, "i32.add")
      wat_writeln(st, "i32.const \{align - 1}")
      wat_writeln(st, "i32.add")
      wat_writeln(st, "i32.const \{-align}")
      wat_writeln(st, "i32.and")
      wat_writeln(st, "global.set $sp")
    }
    @types.Extsb => {
      emit_ref(st, ins.arg1, @types.Kw)
      wat_writeln(st, "i32.extend8_s")
      set_dest(st, ins)
    }
    @types.Extsh => {
      emit_ref(st, ins.arg1, @types.Kw)
      wat_writeln(st, "i32.extend16_s")
      set_dest(st, ins)
    }
    @types.Extub => {
      emit_ref(st, ins.arg1, @types.Kw)
      wat_writeln(st, "i32.const 255")
      wat_writeln(st, "i32.and")
      set_dest(st, ins)
    }
    @types.Extuh => {
      emit_ref(st, ins.arg1, @types.Kw)
      wat_writeln(st, "i32.const 65535")
      wat_writeln(st, "i32.and")
      set_dest(st, ins)
    }
    @types.Extsw => {
      emit_ref(st, ins.arg1, @types.Kw)
      wat_writeln(st, "i64.extend_i32_s")
      set_dest(st, ins)
    }
    @types.Extuw => {
      emit_ref(st, ins.arg1, @types.Kw)
      wat_writeln(st, "i64.extend_i32_u")
      set_dest(st, ins)
    }
    @types.Exts => {
      emit_ref(st, ins.arg1, @types.Ks)
      wat_writeln(st, "f64.promote_f32")
      set_dest(st, ins)
    }
    @types.Truncd => {
      emit_ref(st, ins.arg1, @types.Kd)
      wat_writeln(st, "f32.demote_f64")
      set_dest(st, ins)
    }
    @types.Swtof => {
      emit_ref(st, ins.arg1, @types.Kw)
      wat_writeln(
        st,
        if ins.cls == @types.Kd {
          "f64.convert_i32_s"
        } else {
          "f32.convert_i32_s"
        },
      )
      set_dest(st, ins)
    }
    @types.Sltof => {
      emit_ref(st, ins.arg1, @types.Kl)
      wat_writeln(
        st,
        if ins.cls == @types.Ks {
          "f32.convert_i64_s"
        } else {
          "f64.convert_i64_s"
        },
      )
      set_dest(st, ins)
    }
    @types.Stosi => {
      emit_ref(st, ins.arg1, @types.Ks)
      wat_writeln(
        st,
        if ins.cls == @types.Kl {
          "i64.trunc_f32_s"
        } else {
          "i32.trunc_f32_s"
        },
      )
      set_dest(st, ins)
    }
    @types.Dtosi => {
      emit_ref(st, ins.arg1, @types.Kd)
      wat_writeln(
        st,
        if ins.cls == @types.Kl {
          "i64.trunc_f64_s"
        } else {
          "i32.trunc_f64_s"
        },
      )
      set_dest(st, ins)
    }
    @types.Cast => {
      // Bitcast between same-width integer and float representations.
      let arg_k = match ins.cls {
        @types.Kw => @types.Ks
        @types.Kl => @types.Kd
        @types.Ks => @types.Kw
        @types.Kd => @types.Kl
        _ => @types.Kw
      }
      emit_ref(st, ins.arg1, arg_k)
      let op = match ins.cls {
        @types.Kw => "i32.reinterpret_f32"
        @types.Kl => "i64.reinterpret_f64"
        @types.Ks => "f32.reinterpret_i32"
        @types.Kd => "f64.reinterpret_i64"
        _ => "nop"
      }
      if op != "nop" {
        wat_writeln(st, op)
      }
      set_dest(st, ins)
    }
    _ => {
      let k = operand_class(ins.op, ins.cls)
      emit_operand(st, ins.arg1, k)
      emit_operand(st, ins.arg2, k)
      wat_writeln(st, wasm_op_name(ins.op, ins.cls))
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
  }
}

///|
// True for the parameter ops retained by the wasm ABI.
fn is_param_op(op : @types.Op) -> Bool {
  match op {
    @types.Par | @types.Parc | @types.Pare => true
    _ => false
  }
}

///|
fn emit_params(st : WatEmitState) -> Unit {
  for bid in st.fn_.def_order {
    for ins in st.fn_.blks[bid].ins {
      if ins.op == @types.Par && ins.to.is_tmp() {
        st.sb.write_string(
          " (param $t\{ins.to.tmp_val()} \{wasm_type(ins.cls)})",
        )
      } else if (ins.op == @types.Parc || ins.op == @types.Pare) &&
        ins.to.is_tmp() {
        st.sb.write_string(" (param $t\{ins.to.tmp_val()} i64)")
      }
    }
  }
}

///|
fn is_cmp_op(op : @types.Op) -> Bool {
  match op {
    @types.Ceqw
    | @types.Cnew
    | @types.Csgew
    | @types.Csgtw
    | @types.Cslew
    | @types.Csltw
    | @types.Cugew
    | @types.Cugtw
    | @types.Culew
    | @types.Cultw
    | @types.Ceql
    | @types.Cnel
    | @types.Csgel
    | @types.Csgtl
    | @types.Cslel
    | @types.Csltl
    | @types.Cugel
    | @types.Cugtl
    | @types.Culel
    | @types.Cultl
    | @types.Ceqs
    | @types.Cges
    | @types.Cgts
    | @types.Cles
    | @types.Clts
    | @types.Cnes
    | @types.Cos
    | @types.Cuos
    | @types.Ceqd
    | @types.Cged
    | @types.Cgtd
    | @types.Cled
    | @types.Cltd
    | @types.Cned
    | @types.Cod
    | @types.Cuod => true
    _ => false
  }
}

///|
fn emit_locals(st : WatEmitState) -> Unit {
  // dispatch-loop program counter
  wat_writeln(st, "(local $pc i32)")
  let declared : Array[Bool] = Array::make(st.fn_.ntmp(), false)
  for bid in st.fn_.def_order {
    for p in st.fn_.blks[bid].phi {
      if p.to.is_tmp() {
        let tid = p.to.tmp_val()
        if tid >= @types.WasmTmp0 && !declared[tid] {
          declared[tid] = true
          wat_writeln(st, "(local $t\{tid} \{wasm_type(p.cls)})")
        }
      }
    }
    for ins in st.fn_.blks[bid].ins {
      if ins.to.is_tmp() && !is_param_op(ins.op) {
        let tid = ins.to.tmp_val()
        if tid >= @types.WasmTmp0 && !declared[tid] {
          declared[tid] = true
          let lc = if is_cmp_op(ins.op) { @types.Kw } else { ins.cls }
          wat_writeln(st, "(local $t\{tid} \{wasm_type(lc)})")
        }
      }
    }
  }
}

///|
fn emit_body(st : WatEmitState) -> Unit {
  let rpo = st.fn_.rpo
  let n = rpo.length()
  wat_writeln(
    st,
    "i32.const " + st.fn_.blks[st.fn_.start_id].rpo_id.to_string(),
  )
  wat_writeln(st, "local.set $pc")
  wat_writeln(st, "(block $exit")
  st.indent = st.indent + 1
  wat_writeln(st, "(loop $dispatch")
  st.indent = st.indent + 1
  let mut i = n
  while i > 0 {
    i = i - 1
    wat_writeln(st, "(block $case" + i.to_string())
    st.indent = st.indent + 1
  }
  wat_writeln(st, "local.get $pc")
  let mut tbl = "br_table"
  for k in 0..<n {
    tbl = tbl + " $case" + k.to_string()
  }
  wat_writeln(st, tbl)
  for k in 0..<n {
    st.indent = st.indent - 1
    wat_writeln(st, ")")
    emit_block_body(st, st.fn_.blks[rpo[k]])
  }
  st.indent = st.indent - 1
  wat_writeln(st, ")")
  st.indent = st.indent - 1
  wat_writeln(st, ")")
}

///|
// Copy succ's phi arguments that come from pred into the phi locals.
fn emit_phi_copies(st : WatEmitState, succ_bid : Int, pred_bid : Int) -> Unit {
  for p in st.fn_.blks[succ_bid].phi {
    for a in p.args {
      if a.blk_id == pred_bid {
        emit_ref(st, a.value, p.cls)
        if p.to.is_tmp() {
          wat_writeln(st, "local.set $t" + p.to.tmp_val().to_string())
        }
      }
    }
  }
}

///|
// Point the pc at succ and re-enter the dispatch loop.
fn emit_goto(st : WatEmitState, succ_bid : Int) -> Unit {
  wat_writeln(st, "i32.const " + st.fn_.blks[succ_bid].rpo_id.to_string())
  wat_writeln(st, "local.set $pc")
  wat_writeln(st, "br $dispatch")
}

///|
fn emit_block_body(st : WatEmitState, blk : @types.Blk) -> Unit {
  for ins in blk.ins {
    emit_ins(st, ins)
  }
  match blk.jmp.kind {
    @types.Jjmp =>
      if blk.jmp.s1 >= 0 {
        emit_phi_copies(st, blk.jmp.s1, blk.id)
        emit_goto(st, blk.jmp.s1)
      }
    @types.Jjnz => {
      emit_ref(st, blk.jmp.arg, @types.Kw)
      wat_writeln(st, "if")
      st.indent = st.indent + 1
      if blk.jmp.s1 >= 0 {
        emit_phi_copies(st, blk.jmp.s1, blk.id)
        wat_writeln(
          st,
          "i32.const " + st.fn_.blks[blk.jmp.s1].rpo_id.to_string(),
        )
        wat_writeln(st, "local.set $pc")
      }
      st.indent = st.indent - 1
      wat_writeln(st, "else")
      st.indent = st.indent + 1
      if blk.jmp.s2 >= 0 {
        emit_phi_copies(st, blk.jmp.s2, blk.id)
        wat_writeln(
          st,
          "i32.const " + st.fn_.blks[blk.jmp.s2].rpo_id.to_string(),
        )
        wat_writeln(st, "local.set $pc")
      }
      st.indent = st.indent - 1
      wat_writeln(st, "end")
      wat_writeln(st, "br $dispatch")
    }
    @types.Jretw | @types.Jretl | @types.Jrets | @types.Jretd | @types.Jretc => {
      let k = match blk.jmp.kind {
        @types.Jretl => @types.Kl
        @types.Jrets => @types.Ks
        @types.Jretd => @types.Kd
        @types.Jretc => @types.Kl
        _ => @types.Kw
      }
      emit_ref(st, blk.jmp.arg, k)
      wat_writeln(st, "return")
    }
    @types.Jret0 => wat_writeln(st, "return")
    _ => ()
  }
}

///|
// Byte width of a scalar data item.
fn dat_width(kind : @types.DatKind) -> Int {
  match kind {
    @types.DB => 1
    @types.DH => 2
    @types.DW => 4
    @types.DL => 8
    _ => 0
  }
}

///|
// Size in bytes of one data item (strings occupy their encoded length).
fn dat_item_size(d : @types.Dat) -> Int {
  if d.is_str {
    @utf8.encode(d.str).length()
  } else {
    dat_width(d.kind)
  }
}

///|
fn align_up(v : Int, a : Int) -> Int {
  if a <= 1 {
    v
  } else {
    (v + a - 1) / a * a
  }
}

///|
fn put_le(buf : Array[Int], off : Int, v : Int64, n : Int) -> Unit {
  let mut x = v
  for i in 0..<n {
    buf[off + i] = (x & 0xFFL).to_int()
    x = x >> 8
  }
}

///|
let wat_hex_digits : Array[String] = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
]

///|
// Render a byte array as a WAT string literal (every byte hex-escaped, which
// the text format always accepts).
fn wat_byte_string(a : Array[Int]) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_string("\"")
  for b in a {
    sb.write_string("\\")
    sb.write_string(wat_hex_digits[(b >> 4) & 15])
    sb.write_string(wat_hex_digits[b & 15])
  }
  sb.write_string("\"")
  sb.to_string()
}

///|
// Lay out all data items in linear memory. Returns the label -> address map
// and the flat byte image starting at WASM_DATA_BASE.
fn wasm_layout_data(
  datas : Array[@types.Dat],
) -> (Array[(String, Int)], Array[Int]) {
  let addr_of : Array[(String, Int)] = []
  // Pass 1: assign addresses (block sizes are independent of ref values).
  let mut off = 0
  let mut align = 8
  for d in datas {
    match d.kind {
      @types.DStart => align = 8
      @types.DAlign => align = d.num.to_int()
      @types.DName => {
        off = align_up(off, align)
        addr_of.push((d.str, @types.WASM_DATA_BASE + off))
      }
      @types.DEnd => ()
      @types.DZ => off = off + d.num.to_int()
      _ => off = off + dat_item_size(d)
    }
  }
  // Pass 2: fill the image.
  let buf : Array[Int] = Array::make(off, 0)
  let mut cur = 0
  let mut align = 8
  for d in datas {
    match d.kind {
      @types.DStart => align = 8
      @types.DAlign => align = d.num.to_int()
      @types.DName => cur = align_up(cur, align)
      @types.DEnd => ()
      @types.DZ => cur = cur + d.num.to_int()
      _ => {
        let w = dat_item_size(d)
        if d.is_str {
          let b = @utf8.encode(d.str)
          for i in 0..<b.length() {
            buf[cur + i] = b[i].to_int()
          }
        } else if d.is_ref {
          let mut base = 0L
          for p in addr_of {
            if p.0 == d.ref_name {
              base = p.1.to_int64()
            }
          }
          put_le(buf, cur, base + d.ref_offset, w)
        } else {
          let mut v = d.num
          if d.num == 0L && d.flts != 0.0 {
            v = d.flts.reinterpret_as_uint().to_int64()
          } else if d.num == 0L && d.fltd != 0.0 {
            v = d.fltd.reinterpret_as_int64()
          }
          put_le(buf, cur, v, w)
        }
        cur = cur + w
      }
    }
  }
  (addr_of, buf)
}

///|
pub fn emit_fn(
  fn_ : @types.Fn,
  interner : @util.Interner,
  sb : StringBuilder,
  dats? : Array[(String, Int)] = [],
  void_fns? : Array[String] = [],
  fn_params? : Array[(String, Array[String])] = [],
) -> Unit {
  let st = wat_emit_new(fn_, interner, sb, dats, void_fns, fn_params)
  sb.write_string("  (func $\{fn_.name}")
  emit_params(st)
  match return_class(st) {
    Some(c) => sb.write_string(" (result \{wasm_type(c)})")
    None => ()
  }
  sb.write_string("\n")
  emit_locals(st)
  st.indent = 2
  emit_body(st)
  sb.write_string("  )\n")
}

///|
// Collect calls to functions that are not defined in this module so they can
// be declared as wasm imports. Parameter types are recovered from the Arg /
// Arge / Argc instructions that precede each call.
fn collect_extern_calls(
  funcs : Array[@types.Fn],
  interner : @util.Interner,
) -> Array[(String, Array[String], String)] {
  let out : Array[(String, Array[String], String)] = []
  for f in funcs {
    for bid in f.def_order {
      let b = f.blks[bid]
      let mut i = 0
      while i < b.ins.length() {
        let ins = b.ins[i]
        if ins.op == @types.Call || ins.op == @types.Vacall {
          let mut target = ""
          if ins.arg1.is_con() {
            let con = f.cons[ins.arg1.con_val()]
            if con.kind == @types.CAddr {
              target = interner.get(con.label)
            }
          }
          if target != "" {
            let mut is_def = false
            for g in funcs {
              if g.name == target {
                is_def = true
              }
            }
            if !is_def {
              let params : Array[String] = []
              let mut j = i
              while j > 0 {
                let p = b.ins[j - 1]
                if p.op == @types.Arg {
                  params.push(wasm_type(p.cls))
                } else if p.op == @types.Arge || p.op == @types.Argc {
                  params.push("i64")
                } else {
                  break
                }
                j = j - 1
              }
              let rparams : Array[String] = []
              let mut k = params.length()
              while k > 0 {
                k = k - 1
                rparams.push(params[k])
              }
              let ret = if ins.to.is_tmp() { wasm_type(ins.cls) } else { "" }
              let mut found = false
              for e in out {
                if e.0 == target {
                  found = true
                }
              }
              if !found {
                out.push((target, rparams, ret))
              }
            }
          }
        }
        i = i + 1
      }
    }
  }
  out
}

///|
pub fn emit_wat_module(
  funcs : Array[@types.Fn],
  _datas : Array[@types.Dat],
  _order : Array[String],
  _interner : @util.Interner,
  sb : StringBuilder,
) -> Unit {
  sb.write_string("(module\n")
  let imports = collect_extern_calls(funcs, _interner)
  if imports.length() > 0 {
    sb.write_string("  ;; Imports\n")
    for entry in imports {
      let name = entry.0
      let params = entry.1
      let ret = entry.2
      sb.write_string("  (import \"env\" \"" + name + "\" (func $" + name)
      for p in params {
        sb.write_string(" (param " + p + ")")
      }
      if ret != "" {
        sb.write_string(" (result " + ret + ")")
      }
      sb.write_string("))\n")
    }
    sb.write_string("\n")
  }
  sb.write_string("  ;; Memory\n")
  sb.write_string(
    "  (memory (export \"memory\") \{@types.WASM_MEMORY_PAGES})\n",
  )
  sb.write_string("\n")
  sb.write_string("  ;; Stack pointer\n")
  sb.write_string(
    "  (global $sp (mut i32) (i32.const \{@types.WASM_STACK_BASE}))\n",
  )
  sb.write_string("\n")
  let (dats, image) = wasm_layout_data(_datas)
  if image.length() > 0 {
    sb.write_string("  ;; Data\n")
    sb.write_string(
      "  (data (i32.const \{@types.WASM_DATA_BASE}) \{wat_byte_string(image)})\n",
    )
    sb.write_string("\n")
  }
  // Functions that return no value: their calls must not local.set.
  let void_fns : Array[String] = []
  for fn_ in funcs {
    let mut has_ret = false
    for bid in fn_.def_order {
      match fn_.blks[bid].jmp.kind {
        @types.Jretw
        | @types.Jretl
        | @types.Jrets
        | @types.Jretd
        | @types.Jretc => has_ret = true
        _ => ()
      }
    }
    if !has_ret {
      void_fns.push(fn_.name)
    }
  }
  // Declared parameter types per function, in signature order.
  let fn_params : Array[(String, Array[String])] = []
  for fn_ in funcs {
    let ps : Array[String] = []
    for ins in fn_.blks[fn_.start_id].ins {
      match ins.op {
        @types.Par => ps.push(wasm_type(ins.cls))
        @types.Parc | @types.Pare => ps.push("i64")
        _ => ()
      }
    }
    fn_params.push((fn_.name, ps))
  }
  sb.write_string("  ;; Functions\n")
  for fn_ in funcs {
    emit_fn(fn_, _interner, sb, dats~, void_fns~, fn_params~)
    sb.write_string("\n")
  }
  sb.write_string("  ;; Exports\n")
  for fn_ in funcs {
    if fn_.is_export {
      sb.write_string("  (export \"\{fn_.name}\" (func $\{fn_.name}))\n")
    }
  }
  sb.write_string(")\n")
}
