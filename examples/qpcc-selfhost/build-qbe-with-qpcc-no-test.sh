#!/bin/sh
# Quick self-host build: compile and link vendor/qbe with QPCC, without the
# corpus comparison that build-qbe-with-qpcc.sh runs afterwards.
#
# POSIX sh on purpose, so `sh`, `bash` and `zsh` all behave the same. Nothing
# here relies on arrays or on word splitting of an unquoted variable, because
# zsh does not split those by default.
#
# Usage:  sh examples/qpcc-selfhost/build-qbe-with-qpcc-no-test.sh [output-dir]
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=${1:-"$root/.qpcc_build-quick"}

exe="$root/_build/native/debug/build/qpcc/cmd/cmd.exe"

command -v moon >/dev/null || { echo "error: moon is not on PATH" >&2; exit 1; }
command -v clang >/dev/null || { echo "error: clang is not on PATH" >&2; exit 1; }

echo "== building QPCC"
(cd "$root" && moon build --target native qpcc/cmd >/dev/null)
[ -x "$exe" ] || { echo "error: qpcc was not built at $exe" >&2; exit 1; }

echo "== compiling vendor/qbe with QPCC"
rm -rf "$out"
mkdir -p "$out/obj"
sources=$(ls "$root"/vendor/qbe/*.c "$root"/vendor/qbe/amd64/*.c "$root"/vendor/qbe/arm64/*.c "$root"/vendor/qbe/rv64/*.c)
n=0
for src in $sources; do
  obj=$(printf "%s" "$src" | sed "s|^$root/||; s|/|_|g; s|\.c$|.o|")
  clang -E -P -nostdinc -I "$root/qpcc/include/qbe" -I "$root/vendor/qbe" -I "$root/vendor/qbe/amd64" -I "$root/vendor/qbe/arm64" -I "$root/vendor/qbe/rv64" "$src" > "$out/obj/$obj.i"
  "$exe" "$out/obj/$obj.i" -o "$out/obj/$obj"
  n=$((n + 1))
done
echo "    compiled $n translation units"

echo "== linking $out/qbe"
if command -v xcrun >/dev/null 2>&1 && [ "$(uname -s)" = Darwin ]; then
  xcrun ld -syslibroot "$(xcrun --show-sdk-path)" -o "$out/qbe" -lSystem "$out"/obj/*.o
elif [ "$(uname -s)" = Linux ]; then
  cc -o "$out/qbe" "$out"/obj/*.o
else
  echo "error: no linker recipe for this platform" >&2
  exit 1
fi
[ -x "$out/qbe" ] || { echo "error: link failed" >&2; exit 1; }

echo "artifacts:      $out/qbe"
