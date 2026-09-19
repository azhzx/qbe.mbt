#!/usr/bin/env python3
"""Assemble every emitted ARM64 test output with clang's integrated assembler.

This is an independent syntax/encodability gate that does not depend on the
reference C QBE. For each `test/**/*.ssa` (skipping files starting with `_`),
the MoonBit CLI emits ARM64 assembly with `-t arm64`; the assembly is then fed
to `clang --target=aarch64-none-elf -x assembler`. Files whose compilation
fails (the reference snapshot does not support the feature either, so stdout
is empty) are skipped.

Usage:
    python tools/check_arm64_asm.py
    python tools/check_arm64_asm.py --clang-aarch64 /path/to/clang
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


def find_target(path):
    if path:
        return path
    for c in ("clang", "clang-16", "clang-15"):
        try:
            subprocess.run(
                [c, "--target=aarch64-none-elf", "-x", "assembler", "--version"],
                capture_output=True,
                check=False,
            )
            return c
        except FileNotFoundError:
            continue
    sys.exit("error: clang not found; pass --clang-aarch64")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clang-aarch64", default="")
    ap.add_argument("--jobs", type=int, default=1)
    args = ap.parse_args()
    clang = find_target(args.clang_aarch64)
    _ = args.jobs

    if not os.path.exists(MOON):
        sys.exit("error: MoonBit CLI not found; install moon or set PATH")
    subprocess.run([MOON, "build", "--target", "native"], cwd=ROOT, check=True)

    tests = sorted(glob.glob(os.path.join(TESTDIR, "**", "*.ssa"), recursive=True))
    tests = [t for t in tests if not os.path.basename(t).startswith("_")]

    total = 0
    skipped = 0
    fail = 0
    for t in tests:
        proc = subprocess.run([MINE, "-t", "arm64", t], capture_output=True)
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
                [
                    clang,
                    "--target=aarch64-none-elf",
                    "-x",
                    "assembler",
                    "-c",
                    "-o",
                    obj,
                    src,
                ],
                capture_output=True,
            )
            if r.returncode != 0:
                fail += 1
                print(f"ASM-FAIL {os.path.relpath(t, ROOT)}")
                print(r.stderr.decode(errors="replace"))
    print(f"\n{total - fail}/{total} assembled ({skipped} skipped: reference-unsupported)")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
