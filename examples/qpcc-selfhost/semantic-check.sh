#!/bin/sh
# Semantic check of the QPCC-built qbe.
#
# The byte-for-byte comparison in build-qbe-with-qpcc.sh says "the two
# compilers emit the same assembly". That is a stricter question than the one
# that matters, and a compiler that emits different but equally correct code
# fails it. This script asks the question that matters instead:
#
#   build each fixture with both qbe binaries, assemble and link each result
#   with the driver the fixture carries, run it, and compare the run against
#   the output the fixture says it should produce.
#
# Modeled on vendor/qbe/tools/test.sh. On Apple Silicon the two compilers
# default to amd64_sysv, so the assembly is x86-64 and the runner needs
# -arch x86_64 (Rosetta).
#
# Usage: sh examples/qpcc-selfhost/semantic-check.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

ref=${QBE_REF:-"$root/vendor/qbe/qbe"}
new=${QBE_NEW:-"$root/.qpcc_build/qbe-qpcc"}
[ -x "$ref" ] || { echo "missing reference qbe: $ref" >&2; exit 1; }
[ -x "$new" ] || { echo "missing qpcc qbe (run build-qbe-with-qpcc.sh first): $new" >&2; exit 1; }

cc="cc"
target="arm64_apple"
# arm64_apple is the only target whose assembly this machine can both
# assemble and run: the default amd64_sysv emits Linux x86-64.
arch=""

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

extract() {
  awk -v w="$1" '$0 ~ "^# >>> " w { p = 1; next } /^# <<</ { p = 0 } p' "$2" \
    | sed -e 's/# //' -e 's/#$//'
}

# build_run <qbe> <fixture> <tag> <outdir>; echoes "rc<TAB>output"
build_run() {
  qbe=$1; f=$2; tag=$3; d=$4
  mkdir -p "$d"
  if ! "$qbe" -t $target "$f" > "$d/$tag.s" 2>"$d/$tag.err"; then
    printf "COMPILE-FAIL\t%s\n" "$(head -1 "$d/$tag.err")"
    return
  fi
  extract driver "$f" > "$d/$tag.drv.c"
  extract output "$f" > "$d/$tag.want"
  if [ -s "$d/$tag.drv.c" ]; then src="$d/$tag.drv.c $d/$tag.s"; else src="$d/$tag.s"; fi
  if ! $cc $arch -w -o "$d/$tag.exe" $src 2>"$d/$tag.cerr"; then
    printf "LINK-FAIL\t%s\n" "$(head -1 "$d/$tag.cerr")"
    return
  fi
  ( "$d/$tag.exe" a b c > "$d/$tag.out" 2>&1 ) & p=$!
  ( sleep 8; kill -9 $p 2>/dev/null ) & w=$!
  wait $p 2>/dev/null; rc=$?
  kill $w 2>/dev/null
  printf "%s\t%s\n" "$rc" "$(cat "$d/$tag.out")"
}

both_ok=0; ref_ok=0; new_ok=0; neither=0; total=0
printf "%-14s %-8s %-8s %s\n" fixture ref new note
for f in "$root"/vendor/qbe/test/[!_]*.ssa; do
  b=$(basename "$f" .ssa)
  total=$((total + 1))
  f="$f"
  # the fixtures are CRLF
  fixture="$work/$b.ssa"
  tr -d '\r' < "$f" > "$fixture"
  want=$(extract output "$fixture")
  r=$(build_run "$ref" "$fixture" ref "$work/$b.r"); rr=${r%%	*}
  n=$(build_run "$new" "$fixture" new "$work/$b.n"); nr=${n%%	*}
  ro=${r#*	}; no=${n#*	}
  rok=no; nok=no
  if [ -n "$want" ]; then
    [ "$ro" = "$want" ] && rok=yes
    [ "$no" = "$want" ] && nok=yes
  else
    [ "$rr" = "0" ] && rok=yes
    [ "$nr" = "0" ] && nok=yes
  fi
  note=""
  case "$rok:$nok" in
    yes:yes) both_ok=$((both_ok + 1)); note="both correct" ;;
    yes:no)  ref_ok=$((ref_ok + 1));  note="only reference correct" ;;
    no:yes)  new_ok=$((new_ok + 1));  note="ONLY QPCC CORRECT" ;;
    no:no)   neither=$((neither + 1)); note="excluding here: rc=$rr/$nr" ;;
  esac
  printf "%-14s %-8s %-8s %s\n" "$b" "$rok" "$nok" "$note"
done

echo
echo "total $total: both correct $both_ok, only reference $ref_ok, only qpcc $new_ok, neither $neither"

