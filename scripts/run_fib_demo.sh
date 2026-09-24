#!/usr/bin/env sh
# Compile demo/10_fibonacci.ssa with qbe.mbt, assemble and link the emitted
# assembly with a tiny C driver, then run it. This is the scripted form of:
#
#   moon run cmd/main --target native -- -t <target> -G <gas> -o fib.s demo/10_fibonacci.ssa
#   clang -o fibdemo fib.s main.c
#   ./fibdemo 10
#
# The SSA exports `function l $fib(l %n)`, so the driver calls `long fib(long)`.
#
# Usage: ./scripts/run_fib_demo.sh [n]
#   n   argument passed to fib (default: 10)

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

n=${1:-10}
demo=demo/10_fibonacci.ssa

# The assembly has to match the host to be linkable+runnable directly:
# any macOS wants Mach-O (-G m); the ELF output is for Linux/BSD hosts.
case "$(uname -s)" in
  Darwin)
    gas=m
    case "$(uname -m)" in
      arm64|aarch64) target=arm64 ;;
      *)             target=amd64_sysv ;;
    esac
    ;;
  *)
    gas=e
    target=amd64_sysv
    ;;
esac

work=$(mktemp -d "${TMPDIR:-/tmp}/qbe-fib.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM

# 1. SSA -> assembly (also builds the CLI if needed).
moon run cmd/main --target native -- \
  -t "$target" -G "$gas" -o "$work/fib.s" "$demo"

# 2. A tiny C driver.
cat > "$work/main.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>

long fib(long n);

int main(int argc, char **argv) {
    long n = (argc > 1) ? atol(argv[1]) : 10;
    printf("fib(%ld) = %ld\n", n, fib(n));
    return 0;
}
EOF

# 3. Assemble + link the generated assembly with the driver.
clang -O0 -o "$work/fibdemo" "$work/fib.s" "$work/main.c"

# 4. Run it.
"$work/fibdemo" "$n"
