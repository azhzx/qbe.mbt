///|
// WAT (WebAssembly Text) emission.

///|
priv struct WatEmitState {
  fn_ : @types.Fn
  interner : @util.Interner
  sb : StringBuilder
  mut indent : Int
}

///|
fn wat_emit_new(
  fn_ : @types.Fn,
  interner : @util.Interner,
  sb : StringBuilder,
) -> WatEmitState {
  WatEmitState::{ fn_, interner, sb, indent: 0, }
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
    @types.Ceqw | @types.Ceql | @types.Ceqs | @types.Ceqd =>
      match cls {
        @types.Kw => "i32.eq"
        @types.Kl => "i64.eq"
        @types.Ks => "f32.eq"
        @types.Kd => "f64.eq"
        _ => "i32.eq"
      }
    @types.Cnew | @types.Cnel | @types.Cnes | @types.Cned =>
      match cls {
        @types.Kw => "i32.ne"
        @types.Kl => "i64.ne"
        @types.Ks => "f32.ne"
        @types.Kd => "f64.ne"
        _ => "i32.ne"
      }
    @types.Csltw | @types.Csltl => "i32.lt_s"
    @types.Cslew | @types.Cslel => "i32.le_s"
    @types.Csgtw | @types.Csgtl => "i32.gt_s"
    @types.Csgew | @types.Csgel => "i32.ge_s"
    @types.Cultw | @types.Cultl => "i32.lt_u"
    @types.Culew | @types.Culel => "i32.le_u"
    @types.Cugtw | @types.Cugtl => "i32.gt_u"
    @types.Cugew | @types.Cugel => "i32.ge_u"
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
fn emit_ref(st : WatEmitState, r : @types.Ref) -> Unit {
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
        if con.flt == 0 {
          wat_writeln(st, "i32.const \{con.bits.i}")
        } else if con.flt == 1 {
          wat_writeln(st, "f32.const \{con.bits.s}")
        } else {
          wat_writeln(st, "f64.const \{con.bits.d}")
        }
      @types.CAddr =>
        wat_writeln(st, "i32.const $\{st.interner.get(con.label)}")
      _ => wat_writeln(st, "i32.const 0")
    }
  } else if r.is_slot() {
    wat_writeln(st, "local.get $s\{r.slot_val()}")
  }
}

///|
fn emit_store(st : WatEmitState, ins : @types.Ins) -> Unit {
  emit_ref(st, ins.arg2)
  emit_ref(st, ins.arg1)
  wat_writeln(st, @types.wasm_store_op(ins.cls))
}

///|
fn emit_load(st : WatEmitState, ins : @types.Ins) -> Unit {
  emit_ref(st, ins.arg1)
  wat_writeln(st, @types.wasm_load_op(ins.cls))
}

///|
fn emit_ins(st : WatEmitState, ins : @types.Ins) -> Unit {
  match ins.op {
    @types.Nop => ()
    @types.Copy => {
      emit_ref(st, ins.arg1)
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
      if ins.arg1.is_con() {
        let cid = ins.arg1.con_val()
        let con = st.fn_.cons[cid]
        if con.kind == @types.CAddr {
          wat_writeln(st, "call $\{st.interner.get(con.label)}")
        }
      }
      if ins.to.is_tmp() {
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
      wat_writeln(st, "global.get $sp")
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
      wat_writeln(st, "global.get $sp")
      emit_ref(st, ins.arg1)
      wat_writeln(st, "i32.const \{align - 1}")
      wat_writeln(st, "i32.add")
      wat_writeln(st, "i32.const \{align - 1}")
      wat_writeln(st, "i32.xor")
      wat_writeln(st, "global.set $sp")
    }
    @types.Extsb => {
      emit_ref(st, ins.arg1)
      wat_writeln(st, "i32.extend8_s")
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Extsh => {
      emit_ref(st, ins.arg1)
      wat_writeln(st, "i32.extend16_s")
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Exts => {
      emit_ref(st, ins.arg1)
      wat_writeln(st, "f64.promote_f32")
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Truncd => {
      emit_ref(st, ins.arg1)
      wat_writeln(st, "f32.demote_f64")
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Swtof => {
      emit_ref(st, ins.arg1)
      wat_writeln(st, "f32.convert_i32_s")
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Sltof => {
      emit_ref(st, ins.arg1)
      wat_writeln(st, "f64.convert_i64_s")
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Stosi => {
      emit_ref(st, ins.arg1)
      wat_writeln(st, "i32.trunc_f32_s")
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Dtosi => {
      emit_ref(st, ins.arg1)
      wat_writeln(st, "i32.trunc_f64_s")
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    @types.Cast => {
      emit_ref(st, ins.arg1)
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
    _ => {
      emit_ref(st, ins.arg1)
      emit_ref(st, ins.arg2)
      wat_writeln(st, wasm_op_name(ins.op, ins.cls))
      if ins.to.is_tmp() {
        wat_writeln(st, "local.set $t\{ins.to.tmp_val()}")
      }
    }
  }
}

///|
fn emit_params(st : WatEmitState) -> Unit {
  for bid in st.fn_.def_order {
    let blk = st.fn_.blks[bid]
    for ins in blk.ins {
      match ins.op {
        @types.Par =>
          st.sb.write_string(
            " (param $t\{ins.to.tmp_val()} \{wasm_type(ins.cls)})",
          )
        @types.Parc => st.sb.write_string(" (param $t\{ins.to.tmp_val()} i32)")
        _ => ()
      }
    }
    break
  }
}

///|
fn emit_locals(st : WatEmitState) -> Unit {
  for bid in st.fn_.def_order {
    let blk = st.fn_.blks[bid]
    for ins in blk.ins {
      if ins.to.is_tmp() {
        let tid = ins.to.tmp_val()
        if tid >= @types.WasmTmp0 {
          if ins.op != @types.Par && ins.op != @types.Parc {
            wat_writeln(st, "(local $t\{tid} \{wasm_type(ins.cls)})")
          }
        }
      }
    }
  }
}

///|
fn emit_body(st : WatEmitState) -> Unit {
  for bid in st.fn_.rpo {
    let blk = st.fn_.blks[bid]
    if bid != st.fn_.start_id {
      st.sb.write_string("\n")
      wat_writeln(st, ";; block \{blk.name}")
    }
    for ins in blk.ins {
      emit_ins(st, ins)
    }
    emit_jump(st, blk)
  }
}

///|
fn emit_jump(st : WatEmitState, blk : @types.Blk) -> Unit {
  let jmp = blk.jmp
  match jmp.kind {
    @types.Jjmp =>
      if jmp.s1 >= 0 {
        let target = st.fn_.blks[jmp.s1]
        wat_writeln(st, "br $label_\{target.name}")
      }
    @types.Jjnz => {
      emit_ref(st, jmp.arg)
      if jmp.s2 >= 0 {
        let target = st.fn_.blks[jmp.s2]
        wat_writeln(st, "br_if $label_\{target.name}")
      }
      if jmp.s1 >= 0 {
        let target = st.fn_.blks[jmp.s1]
        wat_writeln(st, "br $label_\{target.name}")
      }
    }
    @types.Jretw | @types.Jretl => {
      emit_ref(st, jmp.arg)
      wat_writeln(st, "return")
    }
    @types.Jrets | @types.Jretd => {
      emit_ref(st, jmp.arg)
      wat_writeln(st, "return")
    }
    @types.Jretc | @types.Jret0 => wat_writeln(st, "return")
    _ => ()
  }
}

///|
pub fn emit_fn(
  fn_ : @types.Fn,
  interner : @util.Interner,
  sb : StringBuilder,
) -> Unit {
  let st = wat_emit_new(fn_, interner, sb)
  sb.write_string("  (func $\{fn_.name}")
  emit_params(st)
  if fn_.ret_ty >= 0 {
    sb.write_string(" (result \{wasm_type(@types.Kw)})")
  }
  sb.write_string("\n")
  emit_locals(st)
  st.indent = 2
  emit_body(st)
  sb.write_string("  )\n")
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
  sb.write_string("  ;; Functions\n")
  for fn_ in funcs {
    emit_fn(fn_, _interner, sb)
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
