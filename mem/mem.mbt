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
fn loadsz(i : @types.Ins) -> Int {
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
fn storesz(i : @types.Ins) -> Int {
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
  mut kind : @types.AliasType
  mut base : Int
  mut offset : Int64
  mut slot : Int
  mut sz : Int
  mut m : UInt64
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
// C getalias, adapted to the local AliasL (cfg/alias.mbt copy).
fn local_getalias(
  r : @types.Ref,
  fn_ : @types.Fn,
  al : Array[AliasL],
) -> AliasL {
  match r {
    @types.RTmp(v) => {
      let a = alias_copy(al[v])
      if a.kind.astack() {
        if a.slot >= 0 {
          a.kind = al[a.slot].kind
        }
      }
      a
    }
    @types.RCon(v) => {
      let c = fn_.cons[v]
      AliasL::{
        kind: if c.kind == @types.CAddr {
          @types.ASym
        } else {
          @types.ACon
        },
        base: -1,
        offset: c.bits.i,
        slot: -1,
        sz: -1,
        m: 0UL,
      }
    }
    _ => alias_default()
  }
}

///|
// C esc.
fn local_esc(r : @types.Ref, al : Array[AliasL]) -> Unit {
  match r {
    @types.RTmp(v) => {
      let a = al[v]
      if a.kind.astack() && a.slot >= 0 {
        al[a.slot].kind = @types.AEsc
      }
    }
    _ => ()
  }
}

///|
// C fillalias's store mask accumulation.
fn local_store(r : @types.Ref, sz : Int, al : Array[AliasL]) -> Unit {
  match r {
    @types.RTmp(v) => {
      let a = al[v]
      if a.slot >= 0 {
        let off = a.offset
        let m = if sz >= 64 || off < 0L || off >= 64L {
          0xFFFFFFFFFFFFFFFFUL
        } else {
          ((1UL << sz) - 1UL) << off.to_int()
        }
        al[a.slot].m = al[a.slot].m | m
      }
    }
    _ => ()
  }
}

///|
// Port of C fillalias keeping the slot size and store mask that coalesce needs.
// The blit0 branch of the reference is omitted (the MoonBit Op has no blit0).
fn local_fillalias(fn_ : @types.Fn, al : Array[AliasL]) -> Unit {
  for t in 0..<fn_.ntmp() {
    al[t].kind = @types.ABot
    al[t].base = -1
    al[t].offset = 0
    al[t].slot = -1
    al[t].sz = -1
    al[t].m = 0UL
  }
  for n in 0..<fn_.rpo.length() {
    let b = fn_.blks[fn_.rpo[n]]
    for p in b.phi {
      let to = p.to.tmp_val()
      al[to].kind = @types.AUnk
      al[to].base = to
      al[to].offset = 0
      al[to].slot = -1
    }
    for ins in b.ins {
      if !ins.to.is_none() {
        let to = ins.to.tmp_val()
        if ins.op == @types.Alloc4 ||
          ins.op == @types.Alloc8 ||
          ins.op == @types.Alloc16 {
          al[to].kind = @types.ALoc
          al[to].slot = to
          al[to].sz = -1
          if ins.arg1.is_con() {
            let c = fn_.cons[ins.arg1.con_val()]
            if c.kind == @types.CBits {
              let x = c.bits.i
              if x >= 0L && x <= 64L {
                al[to].sz = x.to_int()
              }
            }
          }
        } else {
          al[to].kind = @types.AUnk
          al[to].slot = -1
        }
        al[to].base = to
        al[to].offset = 0
      }
      if ins.op == @types.Copy {
        let to = ins.to.tmp_val()
        al[to] = local_getalias(ins.arg1, fn_, al)
      }
      if ins.op == @types.Add {
        let a0 = local_getalias(ins.arg1, fn_, al)
        let a1 = local_getalias(ins.arg2, fn_, al)
        let to = ins.to.tmp_val()
        if a0.kind == @types.ACon {
          al[to] = a1
          al[to].offset = al[to].offset + a0.offset
        } else if a1.kind == @types.ACon {
          al[to] = a0
          al[to].offset = al[to].offset + a1.offset
        }
      }
      let has_to = !ins.to.is_none()
      let cur = if has_to { al[ins.to.tmp_val()].kind } else { @types.AUnk }
      if !has_to || cur == @types.AUnk {
        if !ins.op.is_load() {
          local_esc(ins.arg1, al)
        }
        if !ins.op.is_store() {
          if ins.op != @types.Argc {
            local_esc(ins.arg2, al)
          }
        }
      }
      if ins.op.is_store() {
        local_store(ins.arg2, storesz(ins), al)
      }
    }
    if b.jmp.kind != @types.Jretc {
      local_esc(b.jmp.arg, al)
    }
  }
  for id in fn_.def_order {
    let b = fn_.blks[id]
    for p in b.phi {
      for a in p.args {
        local_esc(a.value, al)
      }
    }
  }
}
