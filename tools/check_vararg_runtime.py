#!/usr/bin/env python3
"""Runtime semantics gate for variadic functions.

Runs one self-contained variadic program on every surface that can execute
code and asserts the same result (42):

    * the SSA interpreter        (--run main)
    * the wasm32 backend         (-t wasm --run-wasm main)
    * the la64 backend           (assemble + link + qemu-loongarch64)

The la64 leg is skipped when qemu-loongarch64 is not installed.

Usage:
    python tools/check_vararg_runtime.py
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

SRC = """function w $sum(w %n, ...) {
@start
\t%ap =l alloc8 32
\tvastart %ap
\t%i =w copy 0
\t%r =w copy 0
@loop
\t%i1 =w phi @start %i, @body %i2
\t%r1 =w phi @start %r, @body %r2
\t%c =w csltw %i1, %n
\tjnz %c, @body, @end
@body
\t%v =w vaarg %ap
\t%r2 =w add %r1, %v
\t%i2 =w add %i1, 1
\tjmp @loop
@end
\tret %r1
}

export function w $main() {
@start
\t%r =w call $sum(w 3, ..., w 10, w 20, w 12)
\tret %r
}
"""

START = """.text
.globl _start
_start:
\tbl main
\tli.d $a7, 93
\tsyscall 0
"""


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def last_value(out):
    lines = [ln for ln in out.splitlines() if not ln.startswith("warning:")]
    return lines[-1].strip() if lines else ""


def main():
    if not os.path.exists(MINE):
        subprocess.run([MOON, "build", "--target", "native"], cwd=ROOT, check=True)

    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "va.ssa")
        with open(src, "w") as f:
            f.write(SRC)
        failures = []

        # 1. interpreter
        r = run([MINE, "--run", "main", src])
        out = (r.stdout + r.stderr).decode(errors="replace").strip()
        if last_value(out) != "42":
            failures.append("interp: %r" % out[-120:])
        else:
            print("interp   OK (42)")

        # 2. wasm32
        r = run([MINE, "-t", "wasm", "--run-wasm", "main", src])
        out = (r.stdout + r.stderr).decode(errors="replace").strip()
        if last_value(out) != "42":
            failures.append("wasm: %r" % out[-120:])
        else:
            print("wasm     OK (42)")

        # 3. la64 under qemu (skipped when qemu-user is unavailable)
        qemu = shutil.which("qemu-loongarch64") or shutil.which(
            "qemu-loongarch64-static"
        )
        clang = shutil.which("clang")
        if qemu and clang:
            s = os.path.join(td, "va.s")
            o = os.path.join(td, "va.o")
            start_s = os.path.join(td, "start.s")
            start_o = os.path.join(td, "start.o")
            exe = os.path.join(td, "va.elf")
            asm = run([MINE, "-t", "la64", src]).stdout
            with open(s, "wb") as f:
                f.write(asm)
            with open(start_s, "w") as f:
                f.write(START)
            target = ["--target=loongarch64-unknown-linux-gnu"]
            r1 = run([clang, *target, "-x", "assembler", "-c", "-o", o, s])
            r2 = run([clang, *target, "-x", "assembler", "-c", "-o", start_o, start_s])
            r3 = run(
                [clang, *target, "-fuse-ld=lld", "-nostdlib", "-static", "-o", exe, start_o, o]
            )
            if r1.returncode or r2.returncode or r3.returncode:
                failures.append("la64 link: " + r3.stderr.decode(errors="replace")[-160:])
            else:
                rr = run([qemu, exe])
                if rr.returncode != 42:
                    failures.append("la64 run: exit %d" % rr.returncode)
                else:
                    print("la64     OK (42 via qemu)")
        else:
            print("la64     SKIP (qemu-loongarch64 not found)")

        if failures:
            for msg in failures:
                print("FAIL " + msg)
            sys.exit(1)
        print("vararg runtime: all available surfaces agree")


if __name__ == "__main__":
    main()
