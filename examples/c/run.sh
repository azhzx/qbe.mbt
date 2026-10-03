#!/bin/sh
# QPCC C example runner: build QPCC, compile every *.c in this directory,
# link it with clang, run it and print the program output.
#
#   sh examples/c/run.sh
#
# A file may pin its language mode with a `// std=c2y` first line; C2y
# examples then also see qpcc/include/qbe (stddefer.h, stdcountof.h).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
exe="$root/_build/native/debug/build/qpcc/cmd/cmd.exe"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cd "$root"
moon build --target native qpcc/cmd >/dev/null 2>&1

for c in "$here"/*.c; do
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
