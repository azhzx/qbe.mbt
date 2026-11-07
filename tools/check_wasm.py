#!/usr/bin/env python3
"""Validate every emitted WASM test output with moon-wasm-opt.

An independent validity gate for the wasm32 backend: each test/**/*.ssa
(skipping files starting with _) is compiled with -t wasm and the resulting
WAT is passed to moon-wasm-opt (wat2wasm + the wasm validator). A file is
skipped only when the vendored reference QBE also rejects it; if the reference
accepts the input but our wasm backend produces no output, that is a gap and
the gate fails (it used to be counted as a skip).

Usage:
    python tools/check_wasm.py
    python tools/check_wasm.py --wasm-opt /path/to/moon-wasm-opt
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
REF = os.path.join(ROOT, "vendor", "qbe", "qbe")


def reference_ok(path):
    if not os.path.exists(REF):
        return False
    r = subprocess.run([REF, path], capture_output=True)
    return r.returncode == 0 and bool(r.stdout)


def find_wasm_opt(path):
    if path:
        return path
    cand = os.path.expanduser("~/.moon/bin/moon-wasm-opt")
    if os.path.exists(cand):
        return cand
    found = shutil.which("moon-wasm-opt")
    if found:
        return found
    sys.exit("error: moon-wasm-opt not found; pass --wasm-opt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wasm-opt", default="")
    args = ap.parse_args()
    wasm_opt = find_wasm_opt(args.wasm_opt)

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
        proc = subprocess.run([MINE, "-t", "wasm", t], capture_output=True)
        wat = proc.stdout
        if not wat:
            # Only inputs the reference itself rejects are unsupported; a
            # reference-valid input that we cannot compile is a wasm gap.
            if reference_ok(t):
                fail += 1
                print(f"COMPILE-FAIL {os.path.relpath(t, ROOT)}")
                print(proc.stderr.decode(errors="replace"))
            else:
                skipped += 1
            continue
        total += 1
        with tempfile.TemporaryDirectory() as td:
            src = os.path.join(td, "in.wat")
            obj = os.path.join(td, "out.wasm")
            with open(src, "wb") as f:
                f.write(wat)
            r = subprocess.run([wasm_opt, src, "-o", obj], capture_output=True)
            if r.returncode != 0:
                fail += 1
                print(f"WAT-FAIL {os.path.relpath(t, ROOT)}")
                print(r.stderr.decode(errors="replace"))
    print(
        f"\n{total - fail}/{total} valid "
        f"({skipped} skipped: reference-unsupported, {fail} compile failures)"
    )
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
