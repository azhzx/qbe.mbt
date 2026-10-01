#!/bin/sh
# Build QBE (vendor/qbe) with QPCC, then check the result against the reference.
#
# QPCC is the C compiler in this repository. This script exercises it on a real
# C program: QBE's own sources (about 17k lines of C plus three back ends).
#
#   step 1  compile every vendor/qbe source with QPCC into Mach-O arm64 objects
#   step 2  link those objects into ./qbe-qpcc
#   step 3  build the reference ./qbe with the system compiler
#   step 4  run both over QBE's test corpus and diff their assembly output
#
# Requires: moon, clang, and (on macOS) xcrun ld.
#
# Usage:  sh examples/qpcc-selfhost/build-qbe-with-qpcc.sh [output-dir]
#
# Everything is written under .qpcc_build/ at the repository root (already in
# .gitignore); pass a directory to put it elsewhere.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-"$root/.qpcc_build"}

exe="$root/_build/native/debug/build/qpcc/cmd/cmd.exe"

say() { printf "%s\n" "$*"; }
die() { printf "error: %s\n" "$*" >&2; exit 1; }

command -v moon >/dev/null || die "moon is not on PATH"
command -v clang >/dev/null || die "clang is not on PATH"
[ -d "$root/vendor/qbe" ] || die "vendor/qbe is missing (run: git submodule update --init)"

say "== 1/4  building QPCC"
(cd "$root" && moon build --target native qpcc/cmd >/dev/null)
[ -x "$exe" ] || die "qpcc was not built at $exe"

say "== 2/4  compiling vendor/qbe with QPCC"
rm -rf "$out"
mkdir -p "$out/obj"
# QBE includes its own headers through these paths; QPCC takes preprocessed
# input, so clang -E runs first (the documented split: external preprocessor,
# QPCC front end). Exactly the sources the QBE build uses, minus
# vendor/qbe/tools, which holds host build tools that are not part of qbe.
incs="-I $root/qpcc/include/qbe -I $root/vendor/qbe -I $root/vendor/qbe/amd64 -I $root/vendor/qbe/arm64 -I $root/vendor/qbe/rv64"
sources=$(ls "$root"/vendor/qbe/*.c "$root"/vendor/qbe/amd64/*.c "$root"/vendor/qbe/arm64/*.c "$root"/vendor/qbe/rv64/*.c)
n=0
for src in $sources; do
  obj=$(printf "%s" "$src" | sed "s|^$root/||; s|/|_|g; s|\.c$|.o|")
  clang -E -P -nostdinc $incs "$src" > "$out/obj/$obj.i" 2>/dev/null \
    || die "preprocessing failed: $src"
  "$exe" "$out/obj/$obj.i" -o "$out/obj/$obj" || die "qpcc failed: $src"
  n=$((n + 1))
done
say "    compiled $n translation units"

say "== 3/4  linking $out/qbe-qpcc"
if command -v xcrun >/dev/null 2>&1 && [ "$(uname -s)" = Darwin ]; then
  sdk=$(xcrun --show-sdk-path)
  xcrun ld -syslibroot "$sdk" -o "$out/qbe-qpcc" -lSystem "$out"/obj/*.o
elif [ "$(uname -s)" = Linux ]; then
  cc -o "$out/qbe-qpcc" "$out"/obj/*.o
else
  die "no linker recipe for this platform"
fi
[ -x "$out/qbe-qpcc" ] || die "link failed"

say "== 4/4  reference build and corpus comparison"
make -C "$root/vendor/qbe" >/dev/null 2>&1 || die "could not build vendor/qbe"
ref="$root/vendor/qbe/qbe"
[ -x "$ref" ] || die "reference qbe is missing"

# QBE stores its test files with CRLF line endings.
mkdir -p "$out/corpus"
for f in "$root"/vendor/qbe/test/*.ssa; do
  [ -f "$f" ] || continue
  tr -d "\r" < "$f" > "$out/corpus/$(basename "$f")"
done

# macOS has no timeout(1), so cap each run with a background watchdog: a
# few fixtures loop forever when a compiler has a bug, and the comparison must
# not hang on them.
run_limited() {
  ( "$1" "$2" > "$out/.run.out" 2>&1 ) &
  p=$!
  ( sleep 8; kill -9 "$p" 2>/dev/null ) &
  w=$!
  wait "$p" 2>/dev/null
  rc=$?
  kill "$w" 2>/dev/null
  cat "$out/.run.out"
  return $rc
}

same=0
diffn=0
total=0
for f in "$out"/corpus/*.ssa; do
  [ -f "$f" ] || continue
  total=$((total + 1))
  # Both compilers may reject a fixture (some expect an error); the full
  # output, diagnostics included, has to match either way.
  a=$(run_limited "$ref" "$f" || true)
  b=$(run_limited "$out/qbe-qpcc" "$f" || true)
  if [ "$a" = "$b" ]; then
    same=$((same + 1))
  else
    diffn=$((diffn + 1))
    say "    DIFFER $(basename "$f")"
  fi
done

say ""
say "artifacts:      $out/qbe-qpcc"
say "test corpus:    $same identical, $diffn differing, $total total"
[ "$diffn" -eq 0 ] || exit 1
say "OK: the QPCC-built qbe matches the reference on every fixture"
