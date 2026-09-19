#!/usr/bin/env python3
"""Assemble every emitted RISC-V 64 test output with clang's integrated assembler.

This is an independent syntax/encodability gate that does not depend on the
reference C QBE. For each `test/**/*.ssa` (skipping files starting with `_`),
the MoonBit CLI emits RISC-V assembly with `-t rv64`; the assembly is then fed
to `clang --target=riscv64-none-elf -march=rv64gc -mabi=lp64d -x assembler`.
Files whose compilation fails are skipped.

Usage:
    python tools/check_rv64_asm.py
    python tools/check_rv64_asm.py --clang-riscv /path/to/clang
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTDIR = os.path.join(ROOT, "test")
MINE = os.path.join(
    ROOT, "_build", "native", "debug", "build", "cmd", "main", "main.exe"
)
MOON = shutil.which("moon") or os.path.expanduser("~/.moon/bin/moon")
TARGET_ARGS = ["--target=riscv64-none-elf", "-march=rv64gc", "-mabi=lp64d"]


def find_target(path):
    if path:
        return path
    for c in ("clang", "clang-16", "clang-15"):
        try:
            subprocess.run(
                [c, *TARGET_ARGS, "-x", "assembler", "--version"],
                capture_output=True,
                check=False,
            )
            return c
        except FileNotFoundError:
            continue
    sys.exit("error: clang not found; pass --clang-riscv")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clang-riscv", default="")
    args = ap.parse_args()
    clang = find_target(args.clang_riscv)

    if not os.path.exists(MOON):
        sys.exit("error: MoonBit CLI not found; install moon or set PATH")
    if not os.path.exists(MINE):
        subprocess.run([MOON, "build", "--target", "native"], cwd=ROOT, check=True)

    tests = sorted(glob.glob(os.path.join(TESTDIR, "**", "*.ssa"), recursive=True))
    tests = [t for t in tests if not os.path.basename(t).startswith("_")]

    total = 0
    skipped = 0
    fail = 0
    for t in tests:
        proc = subprocess.run([MINE, "-t", "rv64", t], capture_output=True)
        asm = proc.stdout
        if not asm:
            skipped += 1
            continue
        total += 1
        with tempfile.TemporaryDirectory() as td:
            src = os.path.join(td, "in.s")
            obj = os.path.join(td, "out.o")
            with open(src, "wb") as f:
                f.write(asm)
            r = subprocess.run(
                [clang, *TARGET_ARGS, "-x", "assembler", "-c", "-o", obj, src],
                capture_output=True,
            )
            if r.returncode != 0:
                fail += 1
                print(f"ASM-FAIL {os.path.relpath(t, ROOT)}")
                print(r.stderr.decode(errors="replace"))
    print(f"\n{total - fail}/{total} assembled ({skipped} skipped: compile-failed)")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
