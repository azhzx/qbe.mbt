# `emit_wasm` 包接口介绍

包路径: `azhzx/qbe/emit_wasm`

Wasm 汇编输出。将经过指令选择的 SSA 函数转换为 WAT (WebAssembly Text) 格式文本。

## 入口

```moonbit
pub fn emit_fn(
  @types.Fn,
  Array[@types.Typ],     // 全局类型表
  @util.Interner,        // 字符串驻留器
) -> String

pub fn emit_wat_module(
  Array[@types.Fn],
  Array[@types.Typ],
  @util.Interner,
) -> String
```

`emit_fn()` 输出单个函数的 WAT 文本；`emit_wat_module()` 输出完整模块。

## 输出格式

### 函数签名

```wasm
(func $add (param $a i32) (param $b i32) (result i32)
  ;; 函数体
)
```

### 局部变量

```wasm
(local $s i32)
(local $tmp i32)
```

### 操作码映射

| SSA Op | WAT 指令 | 说明 |
|--------|----------|------|
| `add` | `i32.add` | 整数加法 |
| `sub` | `i32.sub` | 整数减法 |
| `mul` | `i32.mul` | 整数乘法 |
| `div` | `i32.div_s`/`i32.div_u` | 有符号/无符号除法 |
| `rem` | `i32.rem_s`/`i32.rem_u` | 取余 |
| `and`/`or`/`xor` | `i32.and`/`i32.or`/`i32.xor` | 位运算 |
| `shl`/`shr`/`sar` | `i32.shl`/`i32.shr_u`/`i32.shr_s` | 移位 |
| `eq`/`ne`/`lt`/`gt`/`le`/`ge` | `i32.eq`/`i32.ne`/`i32.lt_s`/... | 比较（有符号） |
| `load` | `i32.load` | 加载 32 位 |
| `store` | `i32.store` | 存储 32 位 |
| `load8` | `i32.load8_s`/`i32.load8_u` | 加载字节 |
| `load16` | `i32.load16_s`/`i32.load16_u` | 加载半字 |
| `store8` | `i32.store8` | 存储字节 |
| `store16` | `i32.store16` | 存储半字 |
| `call` | `call $fn` | 函数调用 |
| `jmp` | `br $label` | 无条件跳转 |
| `jnz` | `br_if $label` | 条件跳转 |
| `ret` | `return`/`end` | 返回 |

### 控制流

```wasm
;; 循环
(loop $continue
  ;; 循环体
  br_if $continue  ;; 继续循环
)

;; 条件分支
(if (result i32)
  (i32.eqz (local.get $cond))
  (then
    ;; true 分支
  )
  (else
    ;; false 分支
  )
)
```

## 调试输出

`emit_wat_module()` 返回完整的 WAT 模块文本，包含：
- 模块头 `(module ...)`
- 函数定义 `(func ...)`
- 导出声明 `(export ...)`

## 依赖

- `azhzx/qbe/types`
- `azhzx/qbe/util`

## 备注

- WAT 是 WebAssembly 的文本表示，可直接被 `wasm-tools` 等工具解析。
- wasm32 使用 32 位指针，所有 `i32` 操作对应 wasm 的 `i32` 类型。
- 当前不支持浮点操作（wasm 的 `f32`/`f64` 类型）。
- 不支持内存增长 (`memory.grow`)——需要配合线性内存使用。
- 输出的 WAT 格式符合 WebAssembly 规范 1.0。
