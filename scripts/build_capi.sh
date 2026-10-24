#!/usr/bin/env bash
# Build the C API foreign library and run the C smoke test end to end:
#   capi_smoke builds add.o + fib.o through the C ABI,
#   cc links them with capi_driver.c, and the produced program is run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-$(mktemp -d /tmp/qbe_capi.XXXXXX)}"
mkdir -p "$OUT"

# The native runtime archive and the generated stub are emitted by a full
# native build; building only the foreign-library target does not produce them,
# and CI runs this script on a clean tree. Build them if they are missing.
if [ ! -f "_build/native/debug/build/libruntime.a" ] ||
   [ ! -f "_build/native/debug/build/native/native_stub.o" ]; then
  if ! moon build --target native >"$OUT/build-runtime.log" 2>&1; then
    echo "error: the native build the C ABI needs failed" >&2
    tail -40 "$OUT/build-runtime.log" >&2
    exit 1
  fi
fi

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
# The foreign-library archive carries helpers (moonbit_is_unique_ptr and
# friends) that the linker only pulls in when the archive is on the command
# line; the single object leaves them undefined with newer toolchains.
CAPI_LIB="_build/native/debug/build/ir_builder_capi/ir_builder_capi.a"
EXTRA_LIB=""
if [ -f "$CAPI_LIB" ]; then
  EXTRA_LIB="$CAPI_LIB"
fi
cc -o "$OUT/capi_smoke" "$OUT/capi_smoke.o" "$OBJ" $EXTRA_LIB \
  _build/native/debug/build/native/native_stub.o \
  "$MOON_LIB/libmoonbitrun.o" _build/native/debug/build/libruntime.a \
  -lm "$MOON_LIB/libbacktrace.a"

"$OUT/capi_smoke" "$OUT"

cc -o "$OUT/run" examples/capi/capi_driver.c "$OUT/add.o" "$OUT/fib.o"
"$OUT/run"

echo "capi smoke test passed"
