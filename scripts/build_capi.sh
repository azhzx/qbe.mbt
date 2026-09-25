#!/usr/bin/env bash
# Build the C API foreign library and run the C smoke test end to end:
#   capi_smoke builds add.o + fib.o through the C ABI,
#   cc links them with capi_driver.c, and the produced program is run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-$(mktemp -d /tmp/qbe_capi.XXXXXX)}"
mkdir -p "$OUT"

OBJ="_build/native/debug/build/ir_builder_capi/__moonbit_link_core__/ir_builder_capi.o"

# Locate the foreign-library object. A `foreign_library` package also links an
# (unwanted) executable; on toolchains that fail that final link, the object is
# still emitted first, so tolerate a failed *link* but not a failed *compile*.
find_obj() {
  find _build -name "ir_builder_capi.o" -path "*ir_builder_capi*" 2>/dev/null \
    | head -n 1
}

rm -f "$OBJ"
if ! moon build --target native ir_builder_capi >"$OUT/build.log" 2>&1; then
  if [ ! -f "$OBJ" ]; then
    OBJ="$(find_obj)"
  fi
  if [ -z "${OBJ:-}" ] || [ ! -f "$OBJ" ]; then
    echo "error: ir_builder_capi failed to compile" >&2
    tail -40 "$OUT/build.log" >&2
    exit 1
  fi
fi

MOON_INC="${MOON_HOME:-$HOME/.moon}/include"
MOON_LIB="${MOON_HOME:-$HOME/.moon}/lib"

cc -I"$ROOT/include" -I"$MOON_INC" -Wall -Wextra \
  -c examples/capi/capi_smoke.c -o "$OUT/capi_smoke.o"
cc -o "$OUT/capi_smoke" "$OUT/capi_smoke.o" "$OBJ" \
  _build/native/debug/build/run_asm/run_asm_stub.o \
  "$MOON_LIB/libmoonbitrun.o" _build/native/debug/build/libruntime.a \
  -lm "$MOON_LIB/libbacktrace.a"

"$OUT/capi_smoke" "$OUT"

cc -o "$OUT/run" examples/capi/capi_driver.c "$OUT/add.o" "$OUT/fib.o"
"$OUT/run"

echo "capi smoke test passed"