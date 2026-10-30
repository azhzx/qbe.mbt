# 对齐 QBE 的「顺序敏感点」（Array vs 链表 hypothesis 的修正版）

> 状态：草案，待审。目标：让移植在**顺序敏感**的地方与 QBE 逐字节一致，
> 从而消除自举语料对比里的 22 处差异。

## 0. 先修正假设（数据说话）

最初的假设是「移植用 Array 代替链表导致 bug」，但实测 QBE 自己**也基本是数组**：

| QBE 结构 | 实际形态 |
| --- | --- |
| `Blk.ins[]` / `Tmp[]` / `Con[]` | 数组（两边一致 ✓） |
| `Phi *link`、`Blk *link`、`Blk *dlink` | 链表，但只用于**挂接**，遍历顺序由插入序决定 |
| `Tmp.use[]`/`nuse` | 数组（两边一致 ✓） |

真正决定「输出逐字节相同」的，是 **4 个 `qsort` 比较器** + 哈希表遍历序：

| 位置 | 比较器 | 移植现状 | 结论 |
| --- | --- | --- | --- |
| `vendor/qbe/load.c:454` | `icmp` | `ssa/load.mbt` 手写 `qsort_log`（模拟 C qsort 不稳定行为） | ✅ 已对齐 |
| `vendor/qbe/mem.c:380` | `scmp` | `mem/coalesce.mbt` `sort_slots` = **稳定插入排序** | ❌ 键相等时顺序不同 |
| `vendor/qbe/rega.c:515` | `carve` | `rega/rega.mbt` `blk.sort_by(carve_cmp)` | ⚠️ 需证明无相等键（`id` 唯一 → 大概率安全） |
| `vendor/qbe/spill.c:184/187` | `tcmp0`/`tcmp1` | `spill/spill.mbt` `tarr.sort_by(...)` = MoonBit 默认排序 | ❌ 键相等时顺序不同 |

**证据**（本次真的量过）：

```
30ae032 (10-01)  → 76 identical /  0 differing   ← README 里那句 76/0 的出处
2d821cb (10-23)  → 59 identical / 17 differing   ← 工具链迁移提交
2183b58 (今天)   → 54 identical / 22 differing
```

`30ae032` 与 HEAD 的 `vendor/qbe` pin **完全相同**（`661ceb2`），所以这不是「参考版变了」，
而是代码生成真的出现了差异。而且差异是**逐字节 asm**，正是寄存器分配/指令选择顺序的指纹。

## 1. 范围

只做**一个子系统**：让所有「顺序会进入最终产物」的地方与 QBE 完全一致。
不做的事：不重写数据结构、不把 Array 换成链表（没有证据支持这条）、不动前端。

## 2. 文件结构

| 文件 | 责任 |
| --- | --- |
| `util/qsort.mbt`（新增） | 一个通用的「C qsort 模拟器」：median-of-three + Hoare 分区 + 尾元素作 pivot，对 `Array[T]` 就地排序，`cmp : (T, T) -> Int32` |
| `mem/coalesce.mbt` | `sort_slots` 改为调用 `util/qsort.mbt`（删掉稳定插入排序） |
| `spill/spill.mbt` | 两处 `sort_by` 改为 `qsort_c` |
| `rega/rega.mbt` | `carve` 排序先补一个「无相等键」的单元测试；若成立则保留 `sort_by`，否则也换 `qsort_c` |
| `gvn/gvn.mbt` | 审计 `dedupins` 的桶遍历序是否与 C `hmap` 一致 |
| `tools/selfhost_compare.sh`（新增） | 一键：构建 → 用 qpcc 编 vendor/qbe → 跑 76 夹具 → 打印 DIFFER 列表 + 汇总；**连跑两次**并断言两次结果相同（确定性检查） |

## 3. 任务（每步都可独立提交）

### T0 建立可重复的基线

- 新建 `tools/selfhost_compare.sh`：
  - 参数：可选 commit（默认当前树）；
  - 步骤：`moon build --target native qpcc/cmd` → 逐 TU `clang -E` + `qpcc -o .o` → 链接 → 对 76 个 `.ssa` 各跑 `qpcc-built qbe` 与参考 `vendor/qbe/qbe`，逐字节比较；
  - 输出：`DIFFER <file>` 逐行 + `test corpus: N identical, M differing, 76 total`；
  - **连跑两次**，若两次的 DIFFER 集合不同则打印 `NONDETERMINISTIC` 并以 2 退出。
- **验收**：同一 commit 连跑两次结果一致；当前树上稳定得到 `54/22`（若不是，先修确定性再往下做）。

### T1 通用 C-qsort 模拟器

- 新建 `util/qsort.mbt`：
  ```moonbit
  pub fn qsort_c[T](a : Array[T], cmp : (T, T) -> Int32) -> Unit
  ```
  - 用与 `ssa/load.mbt:qsort_log` **同一套**算法（median-of-three、Hoare 分区、pivot 置尾），
    保证与 glibc/macOS 的 `qsort` 在相等键上的置换行为一致；
  - 抽 `ssa/load.mbt` 的 `qsort_log` 改用它（**保持行为不变**，这是重构）。
- **测试**（`util/qsort_wbtest.mbt`）：
  - 给定含大量相等键的输入，断言输出序列的**完整下标排列**等于一组固定快照（从 C 版 qsort 实测得到）；
  - 属性测试：排序后非递减 + 元素多重集不变。
- **验收**：`moon test` 通过；差分 `6720/6720` 不变。

### T2 `scmp` 对齐（`mem/coalesce.mbt`）

- 删掉 `sort_slots` 的稳定插入排序，改为 `qsort_c(sl, scmp)`；
- `scmp` 必须保持 C 的写法：`sz` 降序，再按 `r.a` 升序（**注意 C 里 `return a->r.a - b->r.a` 是 Int32 减法，不要改成比较**）；
- **测试**：构造 3 个 `sz` 相同、`r.a` 相同的 Slot，断言排序后顺序等于 C 版（快照来自实测）；
- **验收**：`compare.py` 仍 `6720/6720`；`tools/selfhost_compare.sh` 的 differing 数**不增加**。

### T3 `tcmp0/tcmp1` 对齐（`spill/spill.mbt`）

- 两处 `tarr.sort_by(fn(pa, pb) { tcmp0(st, pa, pb) })` → `qsort_c(tarr, ...)`；
- 注意 `tcmp0` 返回 `(cb < ca) ? -1 : (cb > ca)`，相等时返回 **0**；
- **测试**：构造 3 个 cost 相同的 temp，断言顺序与 C 版一致；
- **验收**：同 T2。

### T4 `carve` 验证（`rega/rega.mbt`）

- 不急着改：先加单元测试证明 `carve_cmp` 在任意两个不同 block 上**不返回 0**（`id` 唯一）；
- 若成立 → 该排序无相等键，稳定/不稳定不影响结果 → **保留 `sort_by`** 并写注释说明原因；
- 若不成立 → 换成 `qsort_c`。

### T5 `gvn` 的桶遍历序（`gvn/gvn.mbt`）

- C 版 `hmap`：`hmap[hash & msk]` 线性探测，`dedupins` 遍历桶时按**桶序**；
- 审计移植的 `tbl : Array[Ins?]`：哈希函数、探测步长、遍历方向是否与 C 相同；
- **测试**：对一段含相同 `Ins` 的 IL，断言 GVN 保留的是**同一条**（与 C 版比 `-dG` 转储）；
- **验收**：`compare.py -dG` 仍 `5040/5040`，且 selfhost differing 数不增加。

### T6 端到端

- `tools/selfhost_compare.sh` 期望 `76 identical, 0 differing`；
- 全部门禁：`moon test`、`compare.py`（6720）、`--asm`（420）、`-d...`（5040）；
- CI 绿；两仓提交。

## 4. 为什么这个顺序

1. T0 先让**信号可信**（当前对比会抖动，二分会追到噪声上——这次已经踩过：`1f2d5a6` 只改了个脚本却被判为 first bad）；
2. T1 把「C qsort 模拟」抽成一处，后面两处改动都只是换调用；
3. T2/T3 是最可疑的两处（都有相等键）；
4. T4/T5 先验证再改，避免无谓改动破坏 6720 的字节对齐；
5. T6 才是最终判据。

## 5. 风险与回退

| 风险 | 缓解 |
| --- | --- |
| 改排序破坏 `6720/6720` 字节对齐 | 每步单独提交，出错即 `git revert`；这正是我们**唯一可信的**回归基线 |
| 自举对比仍有残差（不是排序引起） | T0 的确定性检查会先暴露；若连跑两次一致但仍有差异，再逐个 fixture 对比 asm，按 `rega`/`spill`/`isel` 归类 |
| MoonBit `sort_by` 本身不稳定 | 不依赖它的稳定性；统一改用 `qsort_c` |
| 工具链与旧提交不兼容 | 只在 `2d821cb` 之后的提交上验证（旧的需 moonc 0.10.14，已不可得） |

## 6. 已知的、与本计划无关的差异

- `icmp` 的「同块 phi」分支：C 版返回 0，移植注释声称 macOS qsort 稳定（这条注释是**错的**），T1 会顺带用实测快照固定下来；
- `sic` 的 `duplicate symbol _strlcpy`：链接期问题，独立于本计划。
---

## 7. 执行结果（T1–T5 已完成，T6 目标需修正）

| 任务 | 结果 |
| --- | --- |
| T1 | ✅ `util/qsort.mbt`（`qsort_c` / `qsort_c_n`）抽出；`ssa/load.mbt` 改用它 |
| T2 | ✅ `mem/coalesce.mbt` 的 `sort_slots` 由稳定插入排序改为 `qsort_c_n` + `scmp` |
| T3 | ✅ `spill/spill.mbt` 两处 `sort_by` 改为 `qsort_c` |
| T4 | ✅ `carve_cmp` 经证实为全序（`rpo_id` 唯一）→ 保留 `sort_by`，注释说明原因 |
| T5 | ✅ 审计结论：`gvn` 的表**已与** C `gvndup` 一致（`nins+nins/2` 槽、`ihash % n`、线性探测回绕）→ 无需改动 |
| T6 | ⚠️ **目标写错了**，见下 |

门禁（提交 `d9c0894`）：`moon test` 350/350、差分 6720/6720、汇编 420/420。

### T6 的修正：自举语料对比不属于本计划的判据

计划里假设「22 处差异 = 后端的排序不一致」，但这条链路不成立：

```
Qiang 编译 C → ir_builder → native（对象/JIT）   ← 不经过 mem/spill/rega
自举对比 = Qiang 编译 vendor/qbe 的 C，再拿产出的 qbe-Qiang 与 clang 编的 qbe
          分别吃同样的 76 个 .ssa，比较 **它们输出的汇编**
```

也就是说，自举对比测的是 **Qiang 这个 C 编译器的代码生成**，不是本仓库的后端优化器。
本计划的 T1–T3 只影响 `compare.py` 的差分（6720 仍全绿），对自举对比**没有影响**。

那 22 处差异因此有两类可能，且目前证据偏向第一类：

1. **合法差异**：QBE 自身的输出依赖指针序/哈希布局（`rega` 的寄存器选择、
   `.Lfp` 常量池顺序），同一个程序被两个编译器编出的两份**不同二进制**，
   输出不同但都正确 —— 实测差异正是这种形态（`movl $42,%edi` vs `movq $42,%rdi`、
   `%xmm1` vs `%xmm3`）；
2. **Qiang 的 miscompile**：需要单独查（把 `puts10` 少 `leaq` 之类逐条归因）。

因此：**自举对比不能作为「必须 76/0」的门禁**，只能当分数看（README 已改成这个口径）。
若要恢复它作为硬门禁，需要先让比较对「等价输出」不敏感（例如比较程序的行为而非 asm 文本）。