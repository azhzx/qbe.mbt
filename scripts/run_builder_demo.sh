#!/usr/bin/env bash
# Build the C-API builder demo and run it end to end:
#   1. scripts/build_capi.sh builds the foreign library (+ smoke test),
#   2. demo/12_builder_capi.c constructs $tri and $add through the C ABI,
#      prints their arm64 assembly and writes 12_tri.o / 12_add.o,
#   3. demo/12_builder_capi_driver.c links those objects and calls them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-$(mktemp -d /tmp/qbe_builder_demo.XXXXXX)}"
mkdir -p "$OUT"

# Reuse the C-API build (and its own smoke test).
bash scripts/build_capi.sh "$OUT/capi" >/dev/null

OBJ="$(find _build -name 'ir_builder_capi.o' -path '*ir_builder_capi*' 2>/dev/null | head -n 1)"
if [ -z "$OBJ" ]; then
  echo "error: ir_builder_capi.o not found" >&2
  exit 1
fi

MOON_INC="${MOON_HOME:-$HOME/.moon}/include"
MOON_LIB="${MOON_HOME:-$HOME/.moon}/lib"

cc -I"$ROOT/include" -I"$MOON_INC" -Wall -Wextra \
  -c demo/12_builder_capi.c -o "$OUT/demo.o"
cc -o "$OUT/demo" "$OUT/demo.o" "$OBJ" \
  "$MOON_LIB/libmoonbitrun.o" _build/native/debug/build/libruntime.a \
  -lm "$MOON_LIB/libbacktrace.a"

echo "=== generated arm64 assembly ==="
"$OUT/demo" "$OUT"

echo "=== linking the generated objects and running ==="
cc -o "$OUT/run" demo/12_builder_capi_driver.c "$OUT/12_tri.o" "$OUT/12_add.o"
"$OUT/run"

echo "builder C demo passed"