# `types` 包接口介绍

包路径: `azhzx/qbe/types`

整个编译后端的核心数据结构层。定义了函数 (`Fn`)、基本块 (`Blk`)、临时变量 (`Tmp`)、指令 (`Ins`)、phi 节点 (`Phi`)、跳转 (`Jump`)、常量 (`Con`)、内存地址 (`Addr`)、聚合类型 (`Typ`)、数据段项 (`Dat`) 等所有 SSA 表示中需要用到的实体。其它所有阶段（parser、cfg、ssa、abi、isel、live、spill、rega、emit）都依赖本包。

## 顶层常量

寄存器编号与硬件限制（amd64_sysv）：

| 常量 | 含义 |
| --- | --- |
| `RAX..R15`、`XMM0..XMM15`、`RBP`, `RSP` | 寄存器编号 (1..32, 16, 0/15) |
| `RXX` | "无寄存器" 哨兵 (0) |
| `Tmp0` | 第一个用户临时变量编号 (64) |
| `NGPR`/`NFPR`/`NGPS`/`NFPS`/`NCLR` | 通用/浮点/参数寄存器数 (16/15/9/15/5) |
| `NRGLOB` | 全局保留寄存器数 (2) |

`rsave : Array[Int]` 与 `rclob : Array[Int]` 是寄存器分配时使用的 callee-saved 与 caller-saved 列表。

## 类与寄存器引用

```moonbit
pub enum Class { Kx; Kw; Kl; Ks; Kd }   // 类型类: 任意/word(32)/long(64)/single/double
pub enum Ref {
  RNone; RTmp(Int); RCon(Int); RType(Int); RSlot(Int); RCall(Int); RMem(Int)
}
```

`Ref` 是操作数引用：临时变量、常量、类型、栈槽、调用点、内存。配套方法：`is_tmp`/`is_con`/`is_slot`/`is_mem`/`is_none`、`tmp`/`con`/`slot`/`mem`/`typ`/`call`（构造）、`*_val`（取值）。

寄存器引用的查询：

```moonbit
pub fn req(Ref, Ref) -> Bool         // 相等（含寄存器掩码比较）
pub fn rtype(Ref) -> Int            // 引用类型
pub fn ref_none() -> Ref            // 空引用
pub fn argregs(Ref) -> (UInt64, Int, Int)  // 参数寄存器掩码
pub fn retregs(Ref) -> (UInt64, Int, Int)  // 返回寄存器掩码
pub fn is_callersave(Int) -> Bool
pub fn rglob_mask() -> UInt64
pub fn regname(Int) -> String       // 寄存器名 (rax, xmm0, ...)
```

## `Fn` - 函数实体

```moonbit
pub(all) struct Fn {
  name : String
  mut start_id : Int
  blks : Array[Blk]
  blk_names : Map[String, Int]
  tmps : Array[Tmp]
  cons : Array[Con]
  mems : Array[Addr]
  rpo : Array[Int]            // 反向后序
  def_order : Array[Int]      // 定义序
  mut ret_ty : Int            // 返回聚合类型索引 (-1 表示无)
  mut retr : Ref              // 返回引用
  mut reg : UInt64            // 已用寄存器掩码
  mut slot : Int              // 栈槽数
  mut is_export : Bool
  mut is_vararg : Bool
  mut has_dynalloc : Bool
}
```

主要方法：

| 方法 | 用途 |
| --- | --- |
| `Fn::new(String)` | 创建空函数 |
| `add_blk(String) -> Int` | 添加基本块，返回 id |
| `find_blk(String) -> Int` | 按名查找块 (-1 表示未找到) |
| `blk(Int) -> Blk` / `nblk() -> Int` | 按索引取块 / 块数 |
| `add_tmp(String, Class) -> Int` | 添加临时变量，返回 id |
| `new_tmp(String, Class) -> Int` | 同上（用于未命名生成） |
| `tmp(Int) -> Tmp` / `ntmp() -> Int` | 取临时变量 / 计数 |
| `add_con(Con) -> Int` | 添加常量，返回 id |
| `get_con(Int64) -> Int` | 取/创建整数常量 id |
| `get_con_by(Con) -> Int` | 取/创建常量 id (按值匹配) |
| `con(Int) -> Con` / `ncon() -> Int` | 取常量 / 计数 |
| `init_regs()` | 初始化寄存器分配相关字段 |

## `Blk` - 基本块

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

字段语义：
- `phi`/`ins`/`jmp`：块内 phi、指令、跳转
- `pred`/`npred`：前驱列表
- `idom`/`dom_link`/`dom_next`：支配树（直接支配者、长子、兄弟）
- `fron`：支配边界
- `rpo_id`：反向后序编号；`loop_depth`：循环深度
- `nlive_w`/`nlive_d`：块边界处 word/double 活跃数
- `in_set`/`out_set`/`gen_set`：活跃变量集合
- `link`/`visit`：链表与遍历辅助

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

`JumpKind` 包含所有 QBE 的跳转形式：`Jjmp`, `Jjnz`, `Jret*`（5 种返回）, `Jjfi*`（8 种整数条件跳转）, `Jjff*`（8 种浮点条件跳转）。

## `Op` - 指令操作码

涵盖 QBE 全部 100+ 指令：算术 (`Add`/`Sub`/`Mul`/`Div`/`Rem`/`Udiv`/`Urem`)、位运算 (`And`/`Or`/`Xor`)、移位 (`Sar`/`Shr`/`Shl`)、比较 (`Ceqw`..`Cuod`)、load/store (`Loadsb`..`Stored`)、扩展/转换 (`Extsb`..`Sltof`)、内存分配 (`Alloc4`/`Alloc8`/`Alloc16`)、变长参数 (`Vaarg`/`Vastart`)、调用相关 (`Par`/`Arg`/`Call`/`Vacall`/`Flag*`)。

查询函数：

```moonbit
pub fn op_from_string(String) -> Op
pub fn op_from_index(Int) -> Op
pub fn op_index(Op) -> Int
pub fn op_info(Op) -> OpInfo          // 元数据 (操作数属性、可折叠等)
pub fn is_load(Op) / is_store(Op) / is_ext(Op) / is_arg(Op) / is_par(Op) -> Bool
pub fn load_width_idx(Op) / ext_width_idx(Op) / store_width_idx / loadsz / storesz -> Int
```

## `Con` - 常量

```moonbit
pub enum ConType { CUndef; CBits; CAddr }
pub(all) struct Con {
  kind : ConType; label : Int
  bits : ConBits; flt : Int
  is_local : Bool
}
pub fn Con::new() -> Con
pub fn Con::int(Int64) -> Con          // 整数常量
pub fn Con::single(Float) -> Con       // 单精度浮点
pub fn Con::double(Double) -> Con      // 双精度浮点
pub fn Con::addr(Int) -> Con           // 地址 (label 引用)
pub fn Con::is_zero(Self, Bool) -> Bool
pub fn con_eq(Con, Con) -> Bool
pub fn con_raw_bits(Con) -> Int64
pub fn addcon(Con, Con) -> Con         // 常量加法（地址偏移合并）
```

## `Addr` - 内存地址

```moonbit
pub(all) struct Addr {
  mut offset : Con; mut base : Ref; mut index : Ref; mut scale : Int
}
pub fn Addr::new() -> Addr
```

amd64 风格寻址：`offset + base + index * scale`。

## `Typ` / `Field` - 聚合类型

```moonbit
pub(all) struct Typ {
  mut name : String; mut dark : Int; mut align : Int
  mut size : Int64; mut nunion : Int; fields : Array[Field]
}
pub(all) struct Field { kind : FieldType; len : Int }
pub enum FieldType { FEnd; Fb; Fh; Fw; Fl; Fs; Fd; FPad; FTyp }
```

`Typ::new(String)` 创建空类型；`Field::new(FieldType, Int)` / `Field::end()` 创建字段。

## `Dat` - 数据段项

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

`Dat` 是流水线中数据段 (`data $x = { ... }`) 的中间表示；`DatRef` (name + offset) 用于跨段引用。

## `BSet` - 位集

紧凑位集，用于活跃变量、寄存器掩码等：

```moonbit
pub(all) struct BSet { nt : Int; bits : Array[UInt64] }
pub fn BSet::new(Int) -> BSet
pub fn BSet::set/clr/has/count/equal/copy_from/zero/union/inter/diff
pub fn BSet::iter(Self, Int) -> Int       // 迭代器，返回下一个 set 的位
```

辅助函数 `dumpts(BSet, Array[Tmp]) -> String` 把位集渲染成 `%name` 列表。

## 其它结构

- `Tmp`：临时变量元数据（name/uses/ndef/nuse/cost/slot/cls/hint/width/alias_info/visit）
- `Use` / `UseKind`：使用位置（在 phi/ins/jmp 中）
- `AliasInfo` / `AliasType`：别名分析结果 (`ABot`/`ALoc`/`ACon`/`AEsc`/`ASym`/`AUnk`)
- `RegHint`：寄存器分配提示 (r/w/m)
- `TmpWidth`：临时变量的位宽变体 (`WFull`/`Wsb`/`Wub`/`Wsh`/`Wuh`/`Wsw`/`Wuw`)
- `FpBits` + `fp_stash_at/fp_stash_len`：浮点常数缓冲
- `gasstash(Int64, Int64, Int) -> Int`：数据段位置管理

## 类型别名

```moonbit
pub type BlkId = Int
```
