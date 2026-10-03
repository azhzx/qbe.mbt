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
treated as more C files. A relative file argument is resolved against this
directory, so the examples can be selected from any working directory, and
a missing file is reported with a non-zero exit.

The script builds `qpcc/cmd`, preprocesses the `*.c` with `clang -E -P`
(QPCC's preprocessor is external), compiles it to a Mach-O arm64 object,
links with clang and runs the result, printing the exit code.

| File | Shows |
| --- | --- |
| `hello.c` | a first program: `printf` through the bundled `stdio.h` |
| `fib.c` | recursion and a loop |
| `args.c` | `argc`/`argv` and passing arguments through `run.sh` |
| `c2y.c` | `-std=c2y`: `_Countof` / `countof`, `_Maxof`, `_Minof`, a named loop and `_Defer` / `defer` |

A file whose first line contains `std=c2y` is compiled in C2y mode with
`-I qpcc/include/qbe` so that the hand-written `stddefer.h` and
`stdcountof.h` aliases resolve.
