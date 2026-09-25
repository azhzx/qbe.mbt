# Rust 胶水层（qbe-builder）

`rust/` 是一个基于 [`include/qbe_builder.h`](../include/qbe_builder.h) C ABI 的
Rust 胶水层，接口风格对齐 Cranelift/inkwell。

完整指南见 [`rust/README.md`](../rust/README.md)。摘要：

```rust
use qbe_builder::{Context, Signature, Type};

let ctx = Context::new();
let mut module = ctx.create_module();
let f = module.add_function("add", Signature::new([Type::I32, Type::I32], Some(Type::I32)));
{
    let mut b = module.builder(f);
    let a = b.params()[0];
    let c = b.params()[1];
    let r = b.ins().iadd(a, c);
    b.ins().return_(&[r]);
}
let il = module.emit_il();
let asm = module.emit_asm()?;
let obj = module.emit_object()?;
```

## 链接方式

构建脚本 `rust/build.rs`：

1. 运行 `moon build --target native ir_builder_capi`（可用 `QBE_CAPI_OBJ` /
   `QBE_NO_MOON_BUILD` 跳过），并定位 `ir_builder_capi.o`；
2. 编译 `rust/src/shim.c`：封装 MoonBit `Bytes` 辅助函数
   （`moonbit_make_bytes`、`Moonbit_array_length`、`moonbit_decref`）以及一次性的
   `moonbit_runtime_init` + `moonbit_init`；
3. 把 foreign library 目标文件、`libmoonbitrun.o`、`libruntime.a`、`libbacktrace.a`
   合成 `libqbe_builder_native.a` 并链接（外加 `-lm`）。

## API 映射

| Rust | C ABI |
| --- | --- |
| `Context::new` / `create_module` | 运行时初始化 + `qbe_builder_new` |
| `Module::add_function` | `qbe_add_func` / `qbe_func_param` |
| `Module::builder` / `switch_to_block` | `qbe_entry_block` / `qbe_switch_to` |
| `append_block_param` | `qbe_block_param` |
| `ins().iadd/..` | `qbe_emit` + 类型化 class |
| `ins().icmp/fcmp` | `ceqw`/`ceql`/`ceqs`/... / `cgtd`/... |
| `ins().load/store` | `loaduw`/`load`/`loads`/`loadd` / `storew`/... |
| `ins().call` | `qbe_arg` + `qbe_call` |
| `ins().jump/brif` | `qbe_jmp_n` / `qbe_jnz_n` |
| `ins().return_` | `qbe_ret` |
| `emit_il` / `emit_asm` / `emit_object` | `qbe_emit_il` / `qbe_emit_asm` / `qbe_emit_object` |

## 验证

```sh
cargo test --manifest-path rust/Cargo.toml
```

单元测试覆盖 IL 文本与汇编；端到端测试生成 Mach-O 对象、用 `cc` 链接并运行
（macOS/aarch64）。