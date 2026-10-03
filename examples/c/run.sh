#!/bin/sh
# QPCC C example runner: build QPCC, compile the given C files (or every *.c
# in this directory), link them with clang, run them and print the output.
#
#   sh examples/c/run.sh                 # run every *.c in this directory
#   sh examples/c/run.sh hello.c         # run one file
#   sh examples/c/run.sh hello.c fib.c   # run several
#
# A relative argument is resolved against the directory holding this script,
# so the examples can be selected from any working directory. A file may pin
# its language mode with a `// std=c2y` first line; C2y examples then also see
# qpcc/include/qbe (stddefer.h, stdcountof.h).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
exe="$root/_build/native/debug/build/qpcc/cmd/cmd.exe"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$root"
moon build --target native qpcc/cmd >/dev/null 2>&1

# No arguments: every *.c in this directory.
if [ "$#" -eq 0 ]; then
  set -- "$here"/*.c
fi

for c in "$@"; do
  case "$c" in
    /*) ;;
    *) c="$here/$c" ;;
  esac
  if [ ! -f "$c" ]; then
    echo "no such file: $c" >&2
    exit 1
  fi

  base=$(basename "$c" .c)
  hdr=$(head -2 "$c")
  std=""
  inc=""
  case "$hdr" in
    *"std=c2y"*)
      std="-std=c2y"
      inc="$root/qpcc/include/qbe"
      ;;
    *"std=c23"*) std="-std=c23" ;;
  esac

  echo "=== $base ==="
  if [ -n "$inc" ]; then
    clang -E -P $std -I "$inc" "$c" > "$tmp/$base.i"
  else
    clang -E -P $std "$c" > "$tmp/$base.i"
  fi
  "$exe" "$tmp/$base.i" $std -o "$tmp/$base.o"
  clang "$tmp/$base.o" -o "$tmp/$base"
  set +e
  "$tmp/$base"
  rc=$?
  set -e
  echo "(exit $rc)"
  echo
done
