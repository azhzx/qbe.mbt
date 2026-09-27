# qopple-cli

Pure-Rust subprocess wrapper around the `qbe` executable from
[qbe.mbt](https://github.com/azhzx/qbe.mbt). Nothing is linked at build time.

```sh
cargo add qopple-cli
```

```rust
use qopple_cli::Qbe;

let qbe = Qbe::find()?;                       // $QOPPLE_BIN, PATH, ~/.local/bin
let asm = qbe.emit_asm("input.ssa", Some("arm64"))?;
println!("{asm}");
# Ok::<(), qopple_cli::Error>(())
```

The crate also installs a `qopple` binary that forwards all arguments to the
located compiler:

```sh
cargo install qopple-cli
qopple --run adiff,20,22 test/programs/001_abs_diff.ssa
```

For in-process IR construction and JIT (no external binary), use the
[`qopple`](https://crates.io/crates/qopple) crate instead.
