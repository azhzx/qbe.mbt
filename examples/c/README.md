# QPCC C examples

Small C programs compiled by QPCC (the C front end in `qpcc/`) and linked
with clang.

```sh
sh examples/c/run.sh                 # run every *.c in this directory
sh examples/c/run.sh hello.c         # run one file
sh examples/c/run.sh hello.c fib.c   # run several
```

A relative argument is resolved against this directory, so the examples can
be selected from any working directory. A missing file is reported and the
script exits non-zero.

The script builds `qpcc/cmd`, preprocesses each `*.c` with `clang -E -P`
(QPCC's preprocessor is external), compiles it to a Mach-O arm64 object,
links with clang and runs the result, printing the exit code.

| File | Shows |
| --- | --- |
| `hello.c` | a first program: `printf` through the bundled `stdio.h` |
| `fib.c` | recursion and a loop |
| `c2y.c` | `-std=c2y`: `_Countof` / `countof`, `_Maxof`, `_Minof`, a named loop and `_Defer` / `defer` |

A file whose first line contains `std=c2y` is compiled in C2y mode with
`-I qpcc/include/qbe` so that the hand-written `stddefer.h` and
`stdcountof.h` aliases resolve.
