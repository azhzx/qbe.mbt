///|
// Self-contained (route B) end-to-end check: build a Mach-O object with
// object/macho.mbt, link it with the system linker and run it.

///|
test "object: hand-built Mach-O object links and runs" {
  let text = @object.words_to_bytes([
    @object.enc_add_imm(0, 0, 1),
    @object.enc_ret(),
  ])
  let sections : Array[@object.MachoSection] = [
    @object.MachoSection::{
      name: "__text",
      seg: "__TEXT",
      data: text,
      align: 2,
      flags: @object.section_flags_text(),
      relocs: [],
    },
  ]
  let syms : Array[@object.MachoSym] = [
    @object.MachoSym::{ name: "_add1", sect: 1, value: 0, is_ext: true, },
  ]
  let obj = @object.write_object(sections, syms)
  let driver =
    #|long add1(long);
    #|int main(void) { return add1(41) == 42 ? 0 : 1; }
    #|
  write_file("/tmp/qbe_macho_link.o", obj)
  write_file("/tmp/qbe_macho_driver.c", @utf8.encode(driver))
  assert_eq(
    run_command(
      "clang -o /tmp/qbe_macho_exe /tmp/qbe_macho_link.o /tmp/qbe_macho_driver.c",
    ),
    0,
  )
  assert_eq(run_command("/tmp/qbe_macho_exe"), 0)
}

///|
test "run-asm: execute in-memory arm64 code (self-contained)" {
  let text = @object.words_to_bytes([
    @object.enc_add_imm(0, 0, 1),
    @object.enc_ret(),
  ])
  let m = ExecBlock::load_text(text)
  assert_eq(m.call1(41L), 42L)
  assert_eq(m.call1(0L), 1L)
}
