# QPCC C examples

Small C programs compiled by QPCC (the C front end in `qpcc/`) and linked
with clang.

```sh
sh examples/c/run.sh                 # run every *.c in this directory
sh examples/c/run.sh hello.c         # run one file
sh examples/c/run.sh args.c 1 2      # run it with argv[1]=1 argv[2]=2
```

Exactly one source file is compiled per invocation; the first argument is
the file and any further arguments are passed to the compiled program, not
treated as more C files. A relative file argument is tried against the
current directory first and then against this directory, so both
`run.sh c2y.c` and `run.sh examples/c/c2y.c` work. A missing file is
reported with a non-zero exit.

The script builds `qpcc/cmd`, preprocesses the `*.c` with `clang -E -P`
(QPCC's preprocessor is external), compiles it to a Mach-O arm64 object,
links with clang and runs the result, printing the exit code. The bundled
`qpcc/include/qbe` is always on the include path, so the hand-written
`stddefer.h` and `stdcountof.h` aliases resolve; a first line containing
`std=c2y` additionally selects C2y mode.

| File | Shows |
| --- | --- |
| `hello.c` | a first program: `printf` through the bundled `stdio.h` |
| `fib.c` | recursion and a loop |
| `args.c` | `argc`/`argv` and passing arguments through `run.sh` |
| `c2y.c` | `-std=c2y`: `_Countof` / `countof`, `_Maxof` / `maxof`, `_Minof` / `minof`, a named loop and `_Defer` / `defer` |
