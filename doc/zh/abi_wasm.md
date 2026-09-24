# `abi_wasm` 包接口介绍

包路径: `azhzx/qbe/target_wasm/abi`

Wasm ABI 处理。在指令选择前把抽象的函数参数/返回值引用替换为 wasm 的局部变量引用。与 amd64 不同，wasm 是栈机架构，没有寄存器，参数通过函数签名的参数列表直接传递。

## 入口

```moonbit
pub fn abi_wasm(
  @types.Fn,
  Array[@types.Typ],     // 全局类型表
  Bool,                  // 调试开关
  @util.Interner,        // 字符串驻留器
  Array[@types.Typ],     // typs 副本
) -> String
```

`abi_wasm()` 完成以下工作：

1. **参数传递**：保留 `Par`/`Parc`/`Pare`，让发射器按真实 class 声明 wasm 签名参数；同时保留调用实参 `Arg`/`Arge`，由发射器压栈供随后的 `call` 消费。只有仅承载类型信息的 `Argc` 变成 `Nop`。
2. **返回值**：将 `Ret` 跳转中的返回值引用替换为对局部变量的赋值。
3. **Call 简化**：去掉 `Call` 的返回类型操作数，只保留被调函数引用。

## 与 amd64 ABI 的区别

| 特性 | amd64_sysv | wasm |
|------|-----------|------|
| 参数传递 | 寄存器 (rdi, rsi, ...) | 函数签名参数 |
| 返回值 | 寄存器 (rax, rdx) | 函数签名返回值 |
| 栈帧 | 手动管理 | 由运行时管理 |
| 可变参数 | vastart/vaarg | 需要手动实现 |
| 聚合类型 | 按大小走寄存器或内存 | 始终通过内存指针 |

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- `abi_wasm` 是从抽象 SSA 到 wasm 相关 SSA 的**关键转换点**。在该函数返回前，所有引用都是抽象的 `RTmp`/`RCon`；返回后，参数/实参带着真实 class 交给发射器。
- wasm32 指针宽度为 32 位（`Km = Kw`），没有 `Kl` 类型。
- 当前不支持 wasm 的可变参数和超过 16 字节的聚合类型（与 amd64 的行为不同）。
