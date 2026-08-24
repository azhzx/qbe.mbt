# qbe.mbt 演示样例 (demo)

本目录提供一组 QBE IL (`.ssa`) 源文件，演示 qbe.mbt 编译后端接受的中间表示语法与语义。

## 使用方法

通过 `cmd/main` 编译单个 `.ssa` 文件，生成 amd64_sysv 汇编：

```bash
moon run main -- demo/01_arith.ssa -o demo/01_arith.s
# 或直接输出到 stdout
moon run main -- demo/02_control_flow.ssa
```

调试 dump (输出到 stderr)：

```bash
moon run main -- demo/03_loop_phi.ssa -dM      # 打印内存优化后
moon run main -- demo/03_loop_phi.ssa -dN      # 打印支配者与 SSA 构造
moon run main -- demo/03_loop_phi.ssa -dC      # 打印 copy 传播
moon run main -- demo/03_loop_phi.ssa -dA      # 打印 ABI 处理
moon run main -- demo/03_loop_phi.ssa -dI      # 打印指令选择
moon run main -- demo/03_loop_phi.ssa -dL      # 打印活跃变量
moon run main -- demo/03_loop_phi.ssa -dS      # 打印溢出代价与分配
moon run main -- demo/03_loop_phi.ssa -dR      # 打印寄存器分配
```

## 演示文件列表

| 文件 | 主题 | 展示特性 |
| --- | --- | --- |
| [01_arith.ssa](01_arith.ssa) | 基础算术 | `add`/`sub`/`mul`、`ret`、`w`/`l` 类型 |
| [02_control_flow.ssa](02_control_flow.ssa) | 控制流 | `jnz` 条件跳转、多基本块 |
| [03_loop_phi.ssa](03_loop_phi.ssa) | 循环与 phi | `phi` 节点、`jmp`、循环结构 |
| [04_recursion.ssa](04_recursion.ssa) | 递归调用 | `call`、递归函数 |
| [05_float.ssa](05_float.ssa) | 浮点运算 | `d`/`s` 类型、浮点常量 |
| [06_memory.ssa](06_memory.ssa) | 内存访问 | `load`/`store`、`alloc`、全局数据 |
| [07_data.ssa](07_data.ssa) | 数据段 | `data`、字符串/数值、`type` |
| [08_compare.ssa](08_compare.ssa) | 比较 | 有/无符号、整数/浮点比较 |
| [09_bitwise.ssa](09_bitwise.ssa) | 位运算 | `and`/`or`/`xor`、`sar`/`shr`/`shl` |
| [10_fibonacci.ssa](10_fibonacci.ssa) | 综合示例 | 迭代斐波那契，phi + 循环 + 长 |

## IL 语法速查

- 函数定义：`function <cls> $name(<cls> %arg, ...) { ... }`
- 基本块：`@label`
- 临时变量：`%name`，类型后缀：`w` (32位), `l` (64位), `s` (单精度浮点), `d` (双精度浮点)
- 常量：`42`, `-1`, `d_2.0`, `s_1.5`
- 全局符号：`$name`
- 指令：`%r =<cls> op <args>`
- 控制流：`jmp @label`，`jnz %cond, @then, @else`，`ret %val`

更完整的指令集可参考 [test/](../test/) 目录的回归测试。
