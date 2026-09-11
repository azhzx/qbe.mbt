# `isel_wasm` 包接口介绍

包路径: `azhzx/qbe/isel_wasm`

Wasm 指令选择。将 QBE 的通用 SSA 操作码映射为 wasm 的等效操作，同时处理地址模式分解和 CFG 到结构化控制流的转换。

## 入口

```moonbit
pub fn isel_wasm(
  @types.Fn,
  Array[@types.Typ],     // 全局类型表
  Bool,                  // 调试开关
  @util.Interner,        // 字符串驻留器
  Array[@types.Typ],     // typs 副本
) -> String
```

`isel_wasm()` 完成以下工作：

1. **指令选择**：遍历所有块的所有指令，将 QBE Op 映射为 wasm Op：
   - 算术：`add`/`sub`/`mul` → `i32.add`/`i32.sub`/`i32.mul`
   - 位运算：`and`/`or`/`xor`/`shl`/`shr`/`sar` → 对应 wasm 位操作
   - 比较：`ceql`/`cnel`/`cgtl` 等 → `i32.eq`/`i32.ne`/`i32.gt_s` 等
   - 转换：`extsb`/`extub`/`extsw`/`extuw` → `i32.extend8_s` 等
   - 加载/存储：`load`/`store` → `i32.load`/`i32.store`（带类型后缀）
   - 函数调用：`call` → `call`
   - 跳转：`jmp`/`jnz`/`jz` → `br`/`br_if`

2. **地址模式分解**：`addr_wasm` 将复杂地址 `base + index * scale + offset` 分解为 wasm 可表达的形式：
   - 仅支持 `base + offset` 形式
   - `index * scale` 需要先计算为临时变量

3. **CFG → 结构化控制流**：`ctrl_wasm` 将任意 CFG 转换为 wasm 的结构化控制流：
   - 检测循环头（回边）并构建循环嵌套
   - 使用支配树确定嵌套深度
   - 生成 `block`/`loop`/`if`/`br` 指令
   - 处理多目标跳转（通过跳转深度计算）

## wasm 操作码映射

| QBE Op | wasm Op | 说明 |
|--------|---------|------|
| `add` | `i32.add` | 整数加法 |
| `sub` | `i32.sub` | 整数减法 |
| `mul` | `i32.mul` | 整数乘法 |
| `udiv`/`sdiv` | `i32.div_u`/`i32.div_s` | 整数除法 |
| `and`/`or`/`xor` | `i32.and`/`i32.or`/`i32.xor` | 位运算 |
| `shl`/`shr`/`sar` | `i32.shl`/`i32.shr_u`/`i32.shr_s` | 移位 |
| `ceql`..`cofl` | `i32.eq`..`f64.le` | 比较（返回 0/1） |
| `extsb`/`extub` | `i32.extend8_s`/`i32.extend8_s` | 字节扩展 |
| `extsw`/`extuw` | `i32.extend_i32_s`/`i32.extend_i32_u` | 字扩展 |
| `storeb`/`storeh`/`storew`/`storel` | `i32.store8`/`i32.store16`/`i32.store`/`i64.store` | 存储 |
| `loadsb`/`loadub` | `i32.load8_s`/`i32.load8_u` | 加载字节 |
| `loadsw`/`loaduw` | `i32.load16_s`/`i32.load16_u` | 加载半字 |
| `load`/`loadl` | `i32.load`/`i64.load` | 加载字/双字 |
| `truncd` | `i32.trunc_f64_s` | 浮点截断 |
| `truncf` | `i32.trunc_f32_s` | 浮点截断 |
| `extsd` | `f64.promote_f32` | 单精度提升 |
| `truncsd` | `f64_demote_f64` | 双精度降级 |
| `stosi`/`stoui` | `i32.trunc_f64_s`/`i32.trunc_f64_u` | 浮点→整数 |
| `dtosi`/`dtoui` | `i32.trunc_f64_s`/`i32.trunc_f64_u` | 浮点→整数 |

## 结构化控制流转换

wasm 不支持任意跳转，只支持结构化的 `block`/`loop`/`if`/`br`。`ctrl_wasm` 将 QBE 的 CFG 转换为嵌套结构：

```
QBE CFG:                    Wasm 结构化:
  A ──► B                     (block $exit
  A ──► C                       (loop $continue
  B ──► D                         ;; A 的代码
  C ──► D                         br_if $continue  ;; 跳到 B
                                   ;; B 的代码
                                   br $exit
                                 ) ;; C 的代码
                               ) ;; D 的代码
```

关键算法：
1. 通过支配树计算每个块的嵌套深度
2. 检测回边（目标深度 ≥ 源深度）识别循环头
3. 为每个循环生成 `loop` + `continue` 标签
4. 为每个函数生成 `block` + `exit` 标签
5. 跳转深度 = 目标块的嵌套深度

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`
- `azhzx/qbe/parser`

## 备注

- wasm32 指针宽度为 32 位（`Km = Kw`），没有 `Kl` 类型。
- `Tmp0 = 0` 表示"无物理寄存器"，与 amd64 的 `Tmp0 = 64` 不同。
- 跳过 `spill`/`rega` 阶段——wasm 是栈机，不需要寄存器分配。
- 地址模式仅支持 `base + offset`，不支持 `base + index * scale`。
