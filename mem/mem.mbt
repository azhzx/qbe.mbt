///|
// mem package: port of vendor/qbe/mem.c (promote + coalesce).
//
// The shared port does not expose everything mem.c relies on, so this package
// carries local equivalents:
//   * ssa/use.mbt's loadsz/storesz are package-private -> copied here.
//   * cfg/alias.mbt's getalias is package-private -> the local AliasL record
//     reproduces mem.c's use of Alias, including the slot size (sz) and the
//     accumulated store mask (m), which have no field on types.AliasInfo.
//   * types.Tmp has no def pointer -> coalesce builds a local (blk, idx) table.
//   * types.Op has no blit0/blit1 (aggregate copies are expanded before this
//     pass in the MoonBit port), so the C blit0-specific branches are omitted.

///|
// Load size in bytes (C load.c loadsz; mirrors ssa/use.mbt).
fn loadsz(i : @types.Ins) -> Int32 {
  match i.op {
    @types.Loadsb | @types.Loadub => 1
    @types.Loadsh | @types.Loaduh => 2
    @types.Loadsw | @types.Loaduw => 4
    @types.Load => if i.cls.wide() == 1 { 8 } else { 4 }
    _ => 0
  }
}

///|
// Store size in bytes (C load.c storesz; mirrors ssa/use.mbt).
fn storesz(i : @types.Ins) -> Int32 {
  match i.op {
    @types.Storeb => 1
    @types.Storeh => 2
    @types.Storew | @types.Stores => 4
    _ => 8
  }
}

///|
// Map a load op to its extension op (C: Oextsb + (op - Oloadsb)).
fn load_to_ext(op : @types.Op) -> @types.Op {
  @types.Op::from_index(
    @types.Extsb.index() + op.index() - @types.Loadsb.index(),
  )
}

///|
// Local alias record mirroring the parts of C's Alias used by mem.c.
priv struct AliasL {
  kind : @types.AliasType
  base : Int32
  offset : Int64
  slot : Int32
  sz : Int32
  m : UInt64
}

///|
fn alias_default() -> AliasL {
  AliasL::{ kind: @types.ABot, base: -1, offset: 0, slot: -1, sz: -1, m: 0UL, }
}

///|
fn alias_copy(a : AliasL) -> AliasL {
  AliasL::{
    kind: a.kind,
    base: a.base,
    offset: a.offset,
    slot: a.slot,
    sz: a.sz,
    m: a.m,
  }
}

///|
// C mem.c reads the alias table fillalias built; there is no second pass here.
// This adapts AliasInfo to the shape coalescing wants (base as a temp index).
fn load_alias_from_fn(fn_ : @types.Fn, al : Array[AliasL]) -> Unit {
  for t in 0..<fn_.ntmp() {
    let a = fn_.tmps[t].alias_info
    al[t] = AliasL::{
      kind: a.kind,
      base: if a.base.is_tmp() { a.base.tmp_val() } else { -1 },
      offset: a.offset,
      slot: a.slot,
      sz: a.sz,
      m: a.m,
    }
  }
}
