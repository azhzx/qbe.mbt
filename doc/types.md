# `types` Package API Reference

Package path: `azhzx/qbe/types`

The core data structure layer for the entire compilation backend. Defines all entities needed in SSA representation: functions (`Fn`), basic blocks (`Blk`), temporary variables (`Tmp`), instructions (`Ins`), phi nodes (`Phi`), jumps (`Jump`), constants (`Con`), memory addresses (`Addr`), aggregate types (`Typ`), data segment items (`Dat`), etc. All other phases (parser, cfg, ssa, abi, isel, live, spill, rega, emit) depend on this package.

[中文版本 (Chinese Version)](zh/types.md)

## Top-level Constants

Register numbers and hardware limits (amd64_sysv):

| Constant | Meaning |
| --- | --- |
| `RAX..R15`, `XMM0..XMM15`, `RBP`, `RSP` | Register numbers (1..32, 16, 0/15) |
| `RXX` | "No register" sentinel (0) |
| `Tmp0` | First user temporary variable number (64) |
| `NGPR`/`NFPR`/`NGPS`/`NFPS`/`NCLR` | General/floating-point/parameter register counts (16/15/9/15/5) |
| `NRGLOB` | Number of globally preserved registers (2) |

`rsave : Array[Int]` and `rclob : Array[Int]` are the callee-saved and caller-saved register lists used during register allocation.

## Classes and Register References

```moonbit
pub enum Class { Kx; Kw; Kl; Ks; Kd }   // Type class: any/word(32)/long(64)/single/double
pub enum Ref {
  RNone; RTmp(Int); RCon(Int); RType(Int); RSlot(Int); RCall(Int); RMem(Int)
}
```

`Ref` is an operand reference: temporary variable, constant, type, stack slot, call point, memory. Associated methods: `is_tmp`/`is_con`/`is_slot`/`is_mem`/`is_none`, `tmp`/`con`/`slot`/`mem`/`typ`/`call` (constructors), `*_val` (extract value).

Register reference queries:

```moonbit
pub fn req(Ref, Ref) -> Bool         // equality (including register mask comparison)
pub fn rtype(Ref) -> Int            // reference type
pub fn ref_none() -> Ref            // null reference
pub fn argregs(Ref) -> (UInt64, Int, Int)  // parameter register mask
pub fn retregs(Ref) -> (UInt64, Int, Int)  // return register mask
pub fn is_callersave(Int) -> Bool
pub fn rglob_mask() -> UInt64
pub fn regname(Int) -> String       // register name (rax, xmm0, ...)
```

## `Fn` - Function Entity

```moonbit
pub(all) struct Fn {
  name : String
  mut start_id : Int
  blks : Array[Blk]
  blk_names : Map[String, Int]
  tmps : Array[Tmp]
  cons : Array[Con]
  mems : Array[Addr]
  rpo : Array[Int]            // reverse postorder
  def_order : Array[Int]      // definition order
  mut ret_ty : Int            // return aggregate type index (-1 if none)
  mut retr : Ref              // return reference
  mut reg : UInt64            // used register mask
  mut slot : Int              // stack slot count
  mut is_export : Bool
  mut is_vararg : Bool
  mut has_dynalloc : Bool
}
```

Key methods:

| Method | Purpose |
| --- | --- |
| `Fn::new(String)` | Create empty function |
| `add_blk(String) -> Int` | Add basic block, return id |
| `find_blk(String) -> Int` | Find block by name (-1 if not found) |
| `blk(Int) -> Blk` / `nblk() -> Int` | Get block by index / block count |
| `add_tmp(String, Class) -> Int` | Add temporary variable, return id |
| `new_tmp(String, Class) -> Int` | Same (for unnamed generation) |
| `tmp(Int) -> Tmp` / `ntmp() -> Int` | Get temporary variable / count |
| `add_con(Con) -> Int` | Add constant, return id |
| `get_con(Int64) -> Int` | Get/create integer constant id |
| `get_con_by(Con) -> Int` | Get/create constant id (by value match) |
| `con(Int) -> Con` / `ncon() -> Int` | Get constant / count |
| `init_regs()` | Initialize register allocation related fields |

## `Blk` - Basic Block

```moonbit
pub(all) struct Blk {
  id : Int; name : String
  phi : Array[Phi]
  ins : Array[Ins]
  mut jmp : Jump
  pred : Array[Int]; mut npred : Int
  mut idom : Int; mut dom_link : Int; mut dom_next : Int
  fron : Array[Int]
  mut rpo_id : Int; mut loop_depth : Int
  mut nlive_w : Int; mut nlive_d : Int
  mut in_set : BSet?; mut out_set : BSet?
  mut gen_set : BSet?
  mut link : Int; mut visit : Int
}
```

Field semantics:
- `phi`/`ins`/`jmp`: Block phi nodes, instructions, jump
- `pred`/`npred`: Predecessor list
- `idom`/`dom_link`/`dom_next`: Dominator tree (immediate dominator, first child, sibling)
- `fron`: Dominance frontier
- `rpo_id`: Reverse postorder number; `loop_depth`: Loop depth
- `nlive_w`/`nlive_d`: Word/double liveness count at block boundary
- `in_set`/`out_set`/`gen_set`: Liveness variable sets
- `link`/`visit`: Linked list and traversal helpers

## `Ins` / `Phi` / `Jump`

```moonbit
pub(all) struct Ins {
  mut op : Op; mut cls : Class
  mut to : Ref; mut arg1 : Ref; mut arg2 : Ref
}
pub fn Ins::new(Op, Class, Ref, Ref, Ref) -> Ins
pub fn Ins::new_void(Op, Class, Ref, Ref) -> Ins   // to = RNone

pub(all) struct Phi {
  mut cls : Class; mut to : Ref; args : Array[PhiArg]
}
pub(all) struct PhiArg { mut value : Ref; mut blk_id : Int }

pub(all) struct Jump {
  mut kind : JumpKind; mut arg : Ref; mut s1 : Int; mut s2 : Int
}
```

`JumpKind` includes all QBE jump forms: `Jjmp`, `Jjnz`, `Jret*` (5 returns), `Jjfi*` (8 integer conditional jumps), `Jjff*` (8 floating-point conditional jumps).

## `Op` - Instruction Opcodes

Covers all 100+ QBE instructions: arithmetic (`Add`/`Sub`/`Mul`/`Div`/`Rem`/`Udiv`/`Urem`), bitwise (`And`/`Or`/`Xor`), shifts (`Sar`/`Shr`/`Shl`), comparisons (`Ceqw`..`Cuod`), load/store (`Loadsb`..`Stored`), extensions/conversions (`Extsb`..`Sltof`), memory allocation (`Alloc4`/`Alloc8`/`Alloc16`), variadic arguments (`Vaarg`/`Vastart`), call-related (`Par`/`Arg`/`Call`/`Vacall`/`Flag*`).

Query functions:

```moonbit
pub fn op_from_string(String) -> Op
pub fn op_from_index(Int) -> Op
pub fn op_index(Op) -> Int
pub fn op_info(Op) -> OpInfo          // metadata (operand properties, foldable, etc.)
pub fn is_load(Op) / is_store(Op) / is_ext(Op) / is_arg(Op) / is_par(Op) -> Bool
pub fn load_width_idx(Op) / ext_width_idx(Op) / store_width_idx / loadsz / storesz -> Int
```

## `Con` - Constants

```moonbit
pub enum ConType { CUndef; CBits; CAddr }
pub(all) struct Con {
  kind : ConType; label : Int
  bits : ConBits; flt : Int
  is_local : Bool
}
pub fn Con::new() -> Con
pub fn Con::int(Int64) -> Con          // integer constant
pub fn Con::single(Float) -> Con       // single-precision float
pub fn Con::double(Double) -> Con      // double-precision float
pub fn Con::addr(Int) -> Con           // address (label reference)
pub fn Con::is_zero(Self, Bool) -> Bool
pub fn con_eq(Con, Con) -> Bool
pub fn con_raw_bits(Con) -> Int64
pub fn addcon(Con, Con) -> Con         // constant addition (address offset merging)
```

## `Addr` - Memory Address

```moonbit
pub(all) struct Addr {
  mut offset : Con; mut base : Ref; mut index : Ref; mut scale : Int
}
pub fn Addr::new() -> Addr
```

amd64-style addressing: `offset + base + index * scale`.

## `Typ` / `Field` - Aggregate Types

```moonbit
pub(all) struct Typ {
  mut name : String; mut dark : Int; mut align : Int
  mut size : Int64; mut nunion : Int; fields : Array[Field]
}
pub(all) struct Field { kind : FieldType; len : Int }
pub enum FieldType { FEnd; Fb; Fh; Fw; Fl; Fs; Fd; FPad; FTyp }
```

`Typ::new(String)` creates empty type; `Field::new(FieldType, Int)` / `Field::end()` create fields.

## `Dat` - Data Segment Items

```moonbit
pub enum DatKind { DStart; DEnd; DName; DAlign; DB; DH; DW; DL; DZ }
pub(all) struct Dat {
  mut kind : DatKind; num : Int64; fltd : Double; flts : Float
  str : String; ref_name : String; ref_offset : Int64
  is_ref : Bool; is_str : Bool; mut is_export : Bool
}
pub fn Dat::start() / end() / name(String, Bool) / align(Int64) / byte(Int64) /
       zero(Int64) / string(String) / ref_to(String, Int64) -> Dat
```

`Dat` is the intermediate representation of data segments (`data $x = { ... }`) in the pipeline; `DatRef` (name + offset) is used for cross-segment references.

## `BSet` - Bit Set

Compact bit set for liveness variables, register masks, etc.:

```moonbit
pub(all) struct BSet { nt : Int; bits : Array[UInt64] }
pub fn BSet::new(Int) -> BSet
pub fn BSet::set/clr/has/count/equal/copy_from/zero/union/inter/diff
pub fn BSet::iter(Self, Int) -> Int       // iterator, returns next set bit
```

Helper function `dumpts(BSet, Array[Tmp]) -> String` renders the bit set as a `%name` list.

## Other Structures

- `Tmp`: Temporary variable metadata (name/uses/ndef/nuse/cost/slot/cls/hint/width/alias_info/visit)
- `Use` / `UseKind`: Use locations (in phi/ins/jmp)
- `AliasInfo` / `AliasType`: Alias analysis results (`ABot`/`ALoc`/`ACon`/`AEsc`/`ASym`/`AUnk`)
- `RegHint`: Register allocation hints (r/w/m)
- `TmpWidth`: Temporary variable bit-width variants (`WFull`/`Wsb`/`Wub`/`Wsh`/`Wuh`/`Wsw`/`Wuw`)
- `FpBits` + `fp_stash_at/fp_stash_len`: Floating-point constant buffer
- `gasstash(Int64, Int64, Int) -> Int`: Data segment position management

## Target Abstraction `TargetCfg`

`spill`/`rega` are target-independent passes that read the current target's register layout through the global `target_cfg` — corresponding to C QBE's `struct Target T` (`all.h`):

```moonbit
pub struct TargetCfg {
  mut gpr_base : Int          // first GPR number for rega scan
  mut fpr_base : Int          // first FPR number for rega scan
  mut ngpr : Int              // GPR count (rega/spill scan width)
  mut nfpr : Int              // FPR count
  mut fpr_class_base : Int    // spill floating-point temporary classification start id
  mut post_call_gpr : Int     // GPR limit effective immediately after call
  mut post_call_fpr : Int     // FPR limit effective immediately after call
  mut rglob_mask : UInt64     // globally live register bitmask (RBP|RSP etc.)
  mut rsave : Array[Int]      // caller-saved register list
  mut retregs : (Ref) -> (UInt64, Int, Int)   // call return register mapping
  mut argregs : (Ref) -> (UInt64, Int, Int)   // call parameter register mapping
}

pub let target_cfg : TargetCfg          // current target, default amd64_sysv
pub fn init_amd64_target() -> Unit      // select amd64_sysv
pub fn init_rv64_target() -> Unit       // select rv64
pub fn target_retregs(Ref) -> (UInt64, Int, Int)
pub fn target_argregs(Ref) -> (UInt64, Int, Int)
```

- `pipeline.mbt` calls `init_amd64_target()` / `init_rv64_target()` at the post-isel stage of the amd64 and rv64 pipelines respectively to complete the switch; the wasm pipeline skips spill/rega and does not depend on this configuration.
- amd64 register numbers are in `target.mbt`: `RAX=1..RSP=16`, `XMM0=17..XMM15=32`, `Tmp0=64`; rv64 numbers are in `target_rv64.mbt`: `T0=1..A7=14`, `S1..S11=15..25`, `FP/SP/GP/TP/RA=26..30`, `FT0..FA7=31..49`, `FS0..FS11=50..61`, `Rv64Tmp0=64`.
- `abi`/`isel`/`emit` (amd64-specific) and `abi_rv64`/`isel_rv64`/`emit_rv64` still use constants directly from their respective `target*.mbt` files, not through `TargetCfg`.

## Type Aliases

```moonbit
pub type BlkId = Int
```
