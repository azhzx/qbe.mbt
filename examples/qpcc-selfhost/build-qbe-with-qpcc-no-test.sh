cd /Users/Admin/Desktop/qbe.mbt
moon build --target native qpcc/cmd
QPCC=$PWD/_build/native/debug/build/qpcc/cmd/cmd.exe

INC=(-nostdinc -I qpcc/include/qbe \
     -I vendor/qbe -I vendor/qbe/amd64 -I vendor/qbe/arm64 -I vendor/qbe/rv64)

# A separate directory from build-qbe-with-qpcc.sh: that one wipes its own
# output at the start, so sharing a directory makes the two race.
OUT=$PWD/.qpcc_build-quick
rm -rf "$OUT"
mkdir -p "$OUT"
for src in vendor/qbe/*.c vendor/qbe/amd64/*.c vendor/qbe/arm64/*.c vendor/qbe/rv64/*.c; do
  b=$(print -r -- "$src" | tr '/' '_' | sed 's/\.c$//')
  clang -E -P $INC "$src" > "$OUT/$b.i"
  $QPCC "$OUT/$b.i" -o "$OUT/$b.o"
done

xcrun ld -syslibroot $(xcrun --show-sdk-path) -o "$OUT/qbe" -lSystem "$OUT"/*.o