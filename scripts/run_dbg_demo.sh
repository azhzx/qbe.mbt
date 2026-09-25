#!/usr/bin/env bash
# Debug-info smoke test: emit arm64 assembly with -g, assemble and link it
# with clang, then check that lldb can set a source breakpoint and unwind.
# Runs on macOS (lldb is part of the toolchain).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
M="$ROOT/_build/native/debug/build/cmd/main/main.exe"

# lldb ships with Xcode; on CI it may only be reachable through xcrun.
LLDB=()
if command -v lldb >/dev/null 2>&1; then
  LLDB=(lldb)
elif command -v xcrun >/dev/null 2>&1 && xcrun -f lldb >/dev/null 2>&1; then
  LLDB=(xcrun lldb)
else
  echo "SKIP: lldb not available"
  exit 0
fi

moon build --target native >/dev/null

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/one.c" <<'EOF'
int helper(void) {
  int a = 1;
  int b = 2;
  return a + b;
}
int main(void) {
  return 9;
}
EOF

cat > "$WORK/demo.ssa" <<'EOF'
dbgfile "one.c"
export function w $main() {
@start
	dbgloc 3
	%a =w add 1, 2
	dbgloc 5, 9
	%b =w mul %a, 3
	ret %b
}
EOF

( cd "$WORK" && "$M" -g -t arm64 -G m demo.ssa > demo.s )
clang -c -g "$WORK/demo.s" -o "$WORK/demo.o"
clang "$WORK/demo.o" -o "$WORK/demo_prog"
# A stale debug map bundle would shadow the object lldb reads.
rm -rf "$WORK/demo_prog.dSYM"

echo "=== lldb ==="
OUT="$("${LLDB[@]}" -b -o 'breakpoint set --file one.c --line 3' -o run -o bt -o quit "$WORK/demo_prog" 2>&1 || true)"
echo "$OUT"
echo "$OUT" | grep -q 'stop reason = breakpoint' || {
  echo "FAIL: lldb did not stop at the breakpoint" >&2
  exit 1
}
echo "debug info demo OK"
