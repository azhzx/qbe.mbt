#!/usr/bin/env python3
"""Cross-backend validity gate: compile every test through all five targets
and validate the emitted artifact with an independent tool.

Targets and validators:
    amd64_sysv / arm64 / rv64 / la64 -> clang's integrated assembler
    wasm                              -> moon-wasm-opt (wat2wasm + validator)

Inputs that the vendored reference QBE also rejects (identified with
vendor/qbe/qbe on the default target) are reported as unsupported and skipped,
so only genuine backend gaps fail the gate.

Usage:
    python tools/check_all_backends.py
    python tools/check_all_backends.py --target la64 --jobs 8
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTDIR = os.path.join(ROOT, "test")
MINE = os.path.join(
    ROOT, "_build", "native", "debug", "build", "cmd", "main", "main.exe"
)
REF = os.path.join(ROOT, "vendor", "qbe", "qbe")
MOON = shutil.which("moon") or os.path.expanduser("~/.moon/bin/moon")
WASM_OPT = os.path.expanduser("~/.moon/bin/moon-wasm-opt")

TARGETS = ["amd64_sysv", "arm64", "rv64", "la64", "wasm"]
ASM_ARGS = {
    "amd64_sysv": ["--target=x86_64-none-elf"],
    "arm64": ["--target=aarch64-none-elf"],
    "rv64": ["--target=riscv64-none-elf", "-march=rv64gc", "-mabi=lp64d"],
    "la64": ["--target=loongarch64-unknown-linux-gnu"],
}


def run(cmd):
    return subprocess.run(cmd, capture_output=True)


def reference_ok(path):
    if not os.path.exists(REF):
        return True
    r = run([REF, path])
    return r.returncode == 0 and bool(r.stdout)


def check_one(job):
    path, target = job
    rel = os.path.relpath(path, ROOT)
    r = run([MINE, "-t", target, path])
    if r.returncode != 0 or not r.stdout:
        return (target, rel, "compile")
    out = r.stdout
    with tempfile.TemporaryDirectory() as td:
        if target == "wasm":
            src = os.path.join(td, "a.wat")
            obj = os.path.join(td, "a.wasm")
            with open(src, "wb") as f:
                f.write(out)
            g = run([WASM_OPT, src, "-o", obj])
            return (target, rel, "ok" if g.returncode == 0 else "invalid")
        src = os.path.join(td, "a.s")
        obj = os.path.join(td, "a.o")
        with open(src, "wb") as f:
            f.write(out)
        g = run(["clang", *ASM_ARGS[target], "-x", "assembler", "-c", "-o", obj, src])
        return (target, rel, "ok" if g.returncode == 0 else "asm")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", action="append", default=[])
    ap.add_argument("--jobs", type=int, default=8)
    args = ap.parse_args()

    if not os.path.exists(MOON):
        sys.exit("error: MoonBit CLI not found; install moon or set PATH")
    if not os.path.exists(MINE):
        subprocess.run([MOON, "build", "--target", "native"], cwd=ROOT, check=True)

    which = args.target or TARGETS
    tests = sorted(glob.glob(os.path.join(TESTDIR, "**", "*.ssa"), recursive=True))
    tests = [t for t in tests if not os.path.basename(t).startswith("_")]
    ref_ok = {t: reference_ok(t) for t in tests}
    valid = [t for t in tests if ref_ok[t]]
    unsupported = [t for t in tests if not ref_ok[t]]

    jobs = [(t, target) for target in which for t in valid]
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        results = list(ex.map(check_one, jobs))

    by = {}
    for target, rel, kind in results:
        by.setdefault(target, {}).setdefault(kind, []).append(rel)

    failed = False
    print(
        f"valid inputs: {len(valid)}   reference-unsupported: {len(unsupported)}"
    )
    for target in which:
        d = by.get(target, {})
        ok = len(d.get("ok", []))
        bad = []
        for kind in ("compile", "asm", "invalid"):
            bad += d.get(kind, [])
        status = "PASS" if not bad else "FAIL"
        if bad:
            failed = True
        print(f"  {target:<11} {status}  {ok}/{len(valid)}")
        for rel in bad[:10]:
            print(f"      {rel}")
        if len(bad) > 10:
            print(f"      ... +{len(bad) - 10} more")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
