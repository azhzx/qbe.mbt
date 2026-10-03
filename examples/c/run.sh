#!/bin/sh
# QPCC C example runner: build QPCC, compile one C file, link it with clang,
# run it and print the output.
#
#   sh examples/c/run.sh                 # run every *.c in this directory
#   sh examples/c/run.sh hello.c         # run one file
#   sh examples/c/run.sh args.c 1 2      # run it with argv[1]=1 argv[2]=2
#
# A relative file argument is resolved against the directory holding this
# script, so the examples can be selected from any working directory. Any
# further arguments are passed to the compiled program, not treated as more
# C files. A `// std=c2y` first line selects C2y mode; the bundled
# qpcc/include/qbe directory is always on the include path so the
# hand-written stddefer.h / stdcountof.h aliases resolve.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
exe="$root/_build/native/debug/build/qpcc/cmd/cmd.exe"
inc="$root/qpcc/include/qbe"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$root"
moon build --target native qpcc/cmd >/dev/null 2>&1

# Compile one source file and run it, forwarding the remaining arguments.
run_one() {
  src=$1
  shift
  base=$(basename "$src" .c)
  hdr=$(head -2 "$src")
  std=""
  extra=""
  case "$hdr" in
    *"std=c2y"*) std="-std=c2y" ;;
    *"std=c23"*) std="-std=c23" ;;
  esac
  case "$hdr" in
    *"tagged"*) extra="-f_tagged_union" ;;
  esac

  echo "=== $base ==="
  clang -E -P $std -I "$inc" "$src" > "$tmp/$base.i"
  "$exe" "$tmp/$base.i" $std $extra -o "$tmp/$base.o"
  clang "$tmp/$base.o" -o "$tmp/$base"
  set +e
  "$tmp/$base" "$@"
  rc=$?
  set -e
  echo "(exit $rc)"
  echo
}

# No arguments: run every *.c in this directory, with no program arguments.
if [ "$#" -eq 0 ]; then
  for c in "$here"/*.c; do
    run_one "$c"
  done
  exit 0
fi

# Otherwise the first argument is the source file; the rest go to the program.
src=$1
shift
# A relative path may be relative to the caller's directory or to this
# script's directory; prefer the former when it exists.
if [ ! -f "$src" ]; then
  case "$src" in
    /*) ;;
    *) src="$here/$src" ;;
  esac
fi
if [ ! -f "$src" ]; then
  echo "no such file: $src" >&2
  exit 1
fi
run_one "$src" "$@"
