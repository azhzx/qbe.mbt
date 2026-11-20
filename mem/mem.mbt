///|
// mem package: port of vendor/qbe/mem.c (promote + coalesce).
//
// The shared port does not expose everything mem.c relies on:
//   * load sizes come from types.Ins::load_size/store_size (the single
//     transcription of C load.c loadsz/storesz).
//   * cfg/alias.mbt's getalias is public and carries every field mem.c's slot()
//     needs (kind/base/offset/slot/sz/m), so coalescing reads it directly
//     instead of keeping a second alias table.
//   * types.Tmp has no def pointer -> coalesce builds a local (blk, idx) table.

///|
// Map a load op to its extension op (C: Oextsb + (op - Oloadsb)).
fn load_to_ext(op : @types.Op) -> @types.Op {
  @types.Op::from_index(
    @types.Extsb.index() + op.index() - @types.Loadsb.index(),
  )
}
