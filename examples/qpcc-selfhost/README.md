# Building QBE with QPCC

`build-qbe-with-qpcc.sh` compiles the vendored QBE C sources with **QPCC**, the
C compiler in this repository, and then checks the resulting binary against a
reference build.

The interesting part is the second half: the binary QPCC produced is itself a
working QBE, so it is asked to compile QBE's own test corpus, and its assembly
output is compared byte for byte with the assembly the reference QBE emits.

## Run it

```sh
git submodule update --init          # if vendor/qbe is empty
sh examples/qpcc-selfhost/build-qbe-with-qpcc.sh
```

The script writes everything under `qbe-qpcc-build/` in the current directory
(pass a different directory as the first argument). It exits non-zero if any
fixture differs.

```
== 1/4  building QPCC
== 2/4  compiling vendor/qbe with QPCC
    compiled 32 translation units
== 3/4  linking ./qbe-qpcc
== 4/4  reference build and corpus comparison

artifacts:      /…/qbe-qpcc-build/qbe-qpcc
test corpus:    76 identical, 0 differing, 76 total
OK: the QPCC-built qbe matches the reference on every fixture
```

## What each step shows

1. **Building QPCC** — `moon build --target native qpcc/cmd` produces
   `_build/native/debug/build/qpcc/cmd/cmd.exe`.

2. **Compiling the corpus** — QBE is ordinary C11: about 17k lines spread over
   the core, the shared `emit.c`, and the `amd64`/`arm64`/`rv64` back ends.
   QPCC has an external preprocessor by design, so each source is first run
   through `clang -E -P -nostdinc` with the QBE include paths, then compiled to
   a Mach-O arm64 object.

3. **Linking** — on macOS the objects are linked with
   `xcrun ld -lSystem`; on Linux a plain `cc` link is enough.

4. **Comparison** — the reference `qbe` is built with the system compiler from
   the same sources. Both binaries then compile every `vendor/qbe/test/*.ssa`
   fixture (stored with CRLF endings, hence the `tr`), and the full output,
   including diagnostics, must match exactly.

## Using QPCC on your own C

```sh
# 1. preprocess (QPCC does not run cpp itself)
clang -E -P your.c > your.i

# 2. compile
moon build --target native qpcc/cmd
_build/native/debug/build/qpcc/cmd/cmd.exe your.i -o your.o

# 3. link and run
clang your.o -o your
./your
```

```sh
# no separate preprocessing step if the file has no directives:
qpcc your.c -o your.o
```

Useful flags: `--emit obj|asm|qbe` to see QPCC's IR instead of an object,
`-std=c11` or `-std=c23` to pick the dialect, and `--check` for
parse/semantic checking only.

## Regression suite

`sh qpcc/test.sh` compiles every fixture under `qpcc/tests/` with both clang
and QPCC, links both, runs both, and compares exit codes and stdout. This script
is the large-scale version of the same idea.
