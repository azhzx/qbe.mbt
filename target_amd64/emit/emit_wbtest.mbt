///|
// Tests for GAS assembly emission (C amd64/emit.c).
// Full-function output is checked with inspect snapshots; the snapshots are
// generated with `moon test --update` and verified against the reference C QBE
// output once by hand.

///|
// Bring a parsed function through the complete amd64_sysv pipeline, ready to
// emit.
fn emit_parse_pipeline(
  text : String,
) -> (@types.Fn, @util.Interner, Array[@types.Typ]) raise {
  let lexer = @lexer.Lexer::new(text, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let f = parser.get_funcs()[0]
  let typs = parser.get_typs()
  let interner = parser.interner_ref()
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  @ssa.memopt(f)
  @cfg.filldom(f)
  @cfg.fillfron(f)
  let _ = @live.filllive(f, false)
  @ssa.phiins(f)
  @ssa.renblk(f)
  @ssa.filluse(f)
  @ssa.ssacheck(f)
  @cfg.fillloop(f)
  @cfg.fillalias(f)
  let _ = @ssa.loadopt(f, false, interner, typs)
  @ssa.filluse(f)
  @ssa.ssacheck(f)
  let _ = @ssa.copy(f, false, interner, typs)
  @ssa.filluse(f)
  let _ = @fold.fold(f, false, interner, typs)
  let _ = @abi_amd64.abi(f, typs, false, interner, typs)
  @cfg.fillpreds(f)
  @ssa.filluse(f)
  let _ = @isel.isel(f, interner, false, typs)
  @cfg.fillrpo(f)
  let _ = @live.filllive(f, false)
  let _ = @spill.fillcost(f, false)
  let _ = @spill.spill(f, false, interner, typs)
  let _ = @rega.rega(f, false, interner, typs)
  @cfg.fillrpo(f)
  @cfg.simpljmp(f)
  @cfg.fillrpo(f)
  @cfg.fillpreds(f)
  (f, interner, typs)
}

///|
fn emit_gas(src : String, gasloc : String, gassym : String) -> String raise {
  let (f, interner, typs) = emit_parse_pipeline(src)
  let sb = StringBuilder::StringBuilder()
  emitfn(f, interner, gasloc, gassym, false, sb)
  sb.to_string()
}

///|
test "emit: add function to ELF GAS (snapshot)" {
  let src =
    #|function w $add(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let asm = emit_gas(src, ".L", "")
  inspect(
    asm,
    content=(
      #|.text
      #|.balign 16
      #|add:
      #|	endbr64
      #|	movl %edi, %eax
      #|	addl %esi, %eax
      #|	ret
      #|.type add, @function
      #|.size add, .-add
      #|
    ),
  )
}

///|
test "emit: -g adds DWARF CFI" {
  let src =
    #|function w $fact(w %n) {
    #|@start
    #|  jnz %n, @rec, @done
    #|@rec
    #|  %n2 =w sub %n, 1
    #|  %r =w call $fact(w %n2)
    #|  %m =w mul %n, %r
    #|  ret %m
    #|@done
    #|  ret 1
    #|}
    #|
  @util.set_debug_info(true)
  let asm = emit_gas(src, ".L", "")
  @util.set_debug_info(false)
  assert_true(asm.contains("\t.cfi_startproc\n"))
  assert_true(asm.contains("\t.cfi_def_cfa_offset 16\n"))
  assert_true(asm.contains("\t.cfi_offset %rbp, -16\n"))
  assert_true(asm.contains("\t.cfi_def_cfa_register %rbp\n"))
  assert_true(asm.contains("\t.cfi_def_cfa %rsp, 8\n"))
  assert_true(asm.contains("\t.cfi_restore %rbp\n"))
  assert_true(asm.contains("\t.cfi_endproc\n"))
  // The default (flag off) output carries no CFI.
  let plain = emit_gas(src, ".L", "")
  assert_true(!plain.contains(".cfi_"))
}

///|
test "emit: macho flavor prefixes symbols and uses plain local labels" {
  let src =
    #|function w $add(w %a, w %b) {
    #|@start
    #|  %s =w add %a, %b
    #|  ret %s
    #|}
    #|
  let asm = emit_gas(src, "L", "_")
  assert_true(asm.contains("_add:"))
  assert_true(!asm.contains(".L"))
}

///|
test "emit: float constants appear in the rodata section" {
  let src =
    #|export function s $f() {
    #|@start
    #|  ret s_1.5
    #|}
    #|
  let asm = emit_gas(src, ".L", "")
  assert_true(asm.contains(".text"))
  // the float literal is materialized from a stashed rodata constant
  assert_true(asm.contains(".Lfp0"))
  assert_true(asm.contains("movss"))
}

///|
test "emit: gasemitdat writes data items and gasemitfin closes the file" {
  let src =
    #|data $buf = { b "hi", b 0 }
    #|
  let lexer = @lexer.Lexer::new(src, "<test>")
  let parser = @parser.Parser::new(lexer.tokenize(), "<test>")
  parser.parse()
  let datas = parser.get_datas()
  let sb = StringBuilder::StringBuilder()
  let mut i = 0
  while i < datas.length() {
    gasemitdat(datas[i], ".L", "", sb)
    i = i + 1
    if datas[i - 1].kind == @types.DEnd {
      break
    }
  }
  gasemitfin(".L", false, sb)
  let out = sb.to_string()
  assert_true(out.contains(".data"))
  assert_true(out.contains(".ascii \"hi\""))
  assert_true(out.contains(".byte 0"))
}
