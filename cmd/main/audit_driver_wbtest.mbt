///|
async test "audit driver: nonalphabetic debug flags do not suppress assembly" {
  cli_failed[0] = false
  let text = process_file("test/audit_driver_one.ssa", "123?!", "e", "arm64")
  assert_true(text.contains("audit_one:"))
  assert_true(!cli_failed[0])
}
