#!/usr/bin/env python3
"""Runtime semantics gate for the wasm32 backend.

`check_wasm.py` only proves that the emitted module validates; it does not run
it. This gate executes a few programs on the reference semantic engine (the
SSA interpreter, `--run`) and on the wasm backend (`--run-wasm`) and requires
the same result. Cases cover constructs whose wasm lowering is not obvious:
parallel phi assignment on a loop back-edge, a loop-carried accumulator, and
i32/i64 narrowing around calls.

Requires node and moon-wasm-opt (the same tools `--run-wasm` uses).

Usage:
    python tools/check_wasm_runtime.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MINE = os.path.join(
    ROOT, "_build", "native", "debug", "build", "cmd", "main", "main.exe"
)
MOON = shutil.which("moon") or os.path.expanduser("~/.moon/bin/moon")

CASES = [
    (
        "phi swap on a loop back-edge",
        """export function w $f(w %a, w %b) {
@start
  jmp @loop
@loop
  %x =w phi @start %a, @body %y
  %y =w phi @start %b, @body %x
  %c =w csltw %x, %y
  jnz %c, @body, @done
@body
  jmp @loop
@done
  ret %y
}
""",
        "f,1,2",
        "1",
    ),
    (
        "loop-carried accumulator",
        """export function w $sum(w %n) {
@start
  jmp @head
@head
  %i =w phi @start 0, @body %i2
  %s =w phi @start 0, @body %s2
  %c =w csltw %i, %n
  jnz %c, @body, @done
@body
  %s2 =w add %s, %i
  %i2 =w add %i, 1
  jmp @head
@done
  ret %s
}
""",
        "sum,10",
        "45",
    ),
    (
        "unsigned word conversions",
        """export function w $f(w %a) {
@start
  %s =s uwtof %a
  %b =w stoui %s
  ret %b
}
""",
        "f,42",
        "42",
    ),
    (
        "unsigned long conversions",
        """export function l $f(l %a) {
@start
  %d =d ultof %a
  %b =l dtoui %d
  ret %b
}
""",
        "f,42",
        "42",
    ),

    (
        "i64 parameter used in a word context",
        """export function w $f(l %a, w %c) {
@start
  %b =w add %a, 1
  %s =w add %b, %c
  ret %s
}
""",
        "f,41,0",
        "42",
    ),

    (
        "word extensions of a long temporary",
        """export function w $f(l %a) {
@start
  %b =w extsb %a
  %c =w extsh %a
  %d =w extub %a
  %e =w extuh %a
  %x =w add %b, %c
  %y =w add %d, %e
  %z =w add %x, %y
  ret %z
}
""",
        "f,4294967297",
        "4",
    ),
    (
        "cast between float and integer bit patterns",
        """export function w $f(w %a) {
@start
  %s =s cast %a
  %t =s mul %s, s_2.0
  %u =w cast %t
  ret %u
}
""",
        "f,7",
        "14",
    ),
    (
        "forward blit copies chunks",
        """export function l $f(l %a) {
@start
  %p =l alloc8 8
  %q =l alloc8 8
  storel %a, %p
  blit %p, %q, 8
  %v =l loadl %q
  ret %v
}
""",
        "f,42",
        "42",
    ),
    (
        "long arithmetic and narrow return",
        """export function l $f(l %a, l %b) {
@start
  %m =l mul %a, %b
  %s =l sub %m, %a
  ret %s
}
""",
        "f,6,7",
        "36",
    ),
]


def run(cmd):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, timeout=120)


def last_line(out):
    lines = [ln for ln in out.decode(errors="replace").splitlines() if ln.strip()]
    return lines[-1].strip() if lines else ""


def main():
    if not os.path.exists(MINE):
        subprocess.run([MOON, "build", "--target", "native"], cwd=ROOT, check=True)
    if not shutil.which("node"):
        sys.exit("error: node is required for --run-wasm")
    if not os.path.exists(os.path.expanduser("~/.moon/bin/moon-wasm-opt")):
        sys.exit("error: moon-wasm-opt is required for --run-wasm")

    failed = 0
    with tempfile.TemporaryDirectory() as td:
        for i, (name, src, spec, want) in enumerate(CASES):
            path = os.path.join(td, "case%d.ssa" % i)
            with open(path, "w") as f:
                f.write(src)
            interp = run([MINE, "--run", spec, path])
            wasm = run([MINE, "-t", "wasm", "--run-wasm", spec, path])
            got_i = last_line(interp.stdout)
            got_w = last_line(wasm.stdout)
            ok = got_i == want and got_w == want
            if not ok:
                failed += 1
                print("FAIL %s: interpreter=%r wasm=%r want=%r" % (name, got_i, got_w, want))
                if wasm.stderr:
                    print(wasm.stderr.decode(errors="replace"))
            else:
                print("ok   %s -> %s" % (name, want))
    print("\n%d/%d runtime cases agree" % (len(CASES) - failed, len(CASES)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
