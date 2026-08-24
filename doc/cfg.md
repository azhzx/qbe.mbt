# `cfg` 包接口介绍

包路径: `azhzx/qbe/cfg`

控制流图 (Control Flow Graph) 分析。在 `Fn` 的 `blks` 数组上计算前驱、后向序、支配者、支配边界、循环深度、别名信息等结构性质，供 SSA、live、spill、rega 等后续阶段使用。对应 QBE 原项目的 `cfg.c`。

## 主流程函数（按 main.c 调用顺序）

| 函数 | 用途 |
| --- | --- |
| `fillrpo(@types.Fn) -> Unit` | 计算反向后序 (`rpo` 数组与每个块的 `rpo_id`) |
| `fillpreds(@types.Fn) -> Unit` | 由 `jmp.s1/s2` 填充每个块的 `pred` 与 `npred` |
| `filldom(@types.Fn) -> Unit` | 计算直接支配者 (`idom`)，构建 dom 树 (`dom_link`/`dom_next`) |
| `fillfron(@types.Fn) -> Unit` | 计算支配边界 (`fron`) |
| `fillloop(@types.Fn) -> Unit` | 标记循环回边，计算每个块的 `loop_depth` |
| `fillalias(@types.Fn) -> Unit` | 别名分析，为每个临时变量填 `alias_info` |
| `simpljmp(@types.Fn) -> Unit` | 跳转简化：把跳到下一块 (RPO) 的 `jnz`/`jmp` 合并 |

典型调用顺序（参考 [cmd/main/main.mbt](../cmd/main/main.mbt)）：

```moonbit
@cfg.fillrpo(fn_)       // 1. 反向后序
@cfg.fillpreds(fn_)     // 2. 前驱列表（每次 CFG 改写后需重算）
@cfg.filldom(fn_)       // 3. 支配者
@cfg.fillfron(fn_)      // 4. 支配边界（用于 SSA 构造）
...
@cfg.fillloop(fn_)      // 5. 循环检测（影响寄存器分配优先级）
@cfg.fillalias(fn_)     // 6. 别名分析
```

## 支配树查询

```moonbit
pub fn dom(@types.Fn, Int, Int) -> Bool    // i 是否支配 j
pub fn sdom(@types.Fn, Int, Int) -> Bool    // i 是否严格支配 j
```

## 循环迭代

```moonbit
pub fn loopiter(@types.Fn, (Int, Int) -> Unit) -> Unit
```

遍历所有循环回边 `(head, latch)`，对每对调用回调。

## 别名查询

```moonbit
pub fn getalias(@types.Ref, @types.Fn) -> @types.AliasInfo
pub fn escapes(@types.Ref, @types.Fn) -> Bool
pub fn astack(@types.AliasType) -> Bool
pub fn check_alias(@types.Ref, Int, @types.Ref, Int, @types.Fn) -> (AliasResult, Int64)
```

`AliasResult` 取值：
- `MustAlias` - 两个引用一定指向同一地址
- `MayAlias` - 可能别名（保守估计）
- `NoAlias` - 一定不别名

`check_alias(r1, sz1, r2, sz2, fn)` 同时返回别名关系与字节偏移量。

## CFG 编辑

```moonbit
pub fn edgedel(@types.Fn, Int, Int) -> Unit
```

删除 `i -> j` 这条边，会同步更新前驱/后继信息。慎用，通常只在优化阶段内部调用。

## 类型

```moonbit
pub enum AliasResult { MustAlias; MayAlias; NoAlias }
```

## 依赖

- `azhzx/qbe/types`

## 注意

- 所有 `fill*` 函数**就地修改** `Fn` 的字段，不返回新对象。
- `fillpreds` 需要在每次 CFG 改写（如 phi 插入、寄存器分配后的简化）后重算。
- `fillrpo` 在 `def_order` 已建立时按链表序遍历，否则按块数组下标遍历（用于单元测试）。
