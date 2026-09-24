# C ABI builder example

`capi_smoke.c` builds two functions **through the C ABI**, emits a Mach-O arm64
object for each, and writes `add.o` / `fib.o` into the output directory.
`capi_driver.c` is a plain C `main` that calls them after linking.

Run the whole thing with:

```sh
bash scripts/build_capi.sh
```

which builds `ir_builder_capi` (`pkgtype(kind: "foreign_library")`), compiles
this example against [`include/qbe_builder.h`](../../include/qbe_builder.h),
links the generated objects with the driver, runs it, and checks
`add(20,22) == 42` and `fib(10) == 55`.

See [`doc/ir_builder.md`](../../doc/ir_builder.md) for the API overview.