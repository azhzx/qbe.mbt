#!/usr/bin/env bash
# Debug-variable smoke test: build a module with the Rust builder, declare a
# variable, emit arm64 assembly, link it, and check that lldb shows the
# variable (DWARF .debug_info + .debug_loc). Runs on macOS (clang + lldb).
set -Eeuo pipefail
trap 'echo "ERROR: run_dbg_vars_demo.sh failed at line $LINENO" >&2' ERR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LLDB=()
if command -v lldb >/dev/null 2>&1; then
  LLDB=(lldb)
elif command -v xcrun >/dev/null 2>&1 && xcrun -f lldb >/dev/null 2>&1; then
  LLDB=(xcrun lldb)
else
  echo "SKIP: lldb not available"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cargo run --quiet --manifest-path rust/Cargo.toml --example dbg_vars > "$WORK/demo.s"
clang -c -g "$WORK/demo.s" -o "$WORK/demo.o"
clang "$WORK/demo.o" -o "$WORK/demo_prog"
rm -rf "$WORK/demo_prog.dSYM"

echo "=== lldb ==="
OUT="$("${LLDB[@]}" -b -o 'breakpoint set --name f' -o run -o 'thread step-inst' \
  -o 'thread step-inst' -o 'thread step-inst' -o 'frame variable' -o quit \
  "$WORK/demo_prog" 2>&1 || true)"
echo "$OUT"
echo "$OUT" | grep -q '(int) sum = 41' || {
  echo "FAIL: lldb did not show the declared variable" >&2
  exit 1
}
echo "debug variables demo OK"
