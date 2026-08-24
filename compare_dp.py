#!/usr/bin/env python3
"""Legacy per-file -dP diff script; prefer `python compare.py`."""
import subprocess, os, sys, difflib

ROOT = os.path.dirname(os.path.abspath(__file__))
QBE_REF = os.path.join(ROOT, "qbe-master", "obj_qbe.exe")
MINE = os.path.join(ROOT, "_build", "native", "debug", "build", "cmd", "main", "main.exe")


def run(cmd):
    return subprocess.run(cmd, capture_output=True)


def normalize(text):
    return [ln.rstrip("\r") for ln in text.split("\n")]


def main():
    subprocess.run(["moon", "build", "--target", "native"], cwd=ROOT, check=True)
    tests = sorted(f for f in os.listdir(os.path.join(ROOT, "test")) if f.endswith(".ssa") and not f.startswith("_"))
    fail = total = 0
    for f in tests:
        total += 1
        t = os.path.join(ROOT, "test", f)
        r1 = run([QBE_REF, "-dP", t])
        r2 = run([MINE, "-dP", t])
        out1, out2 = normalize(r1.stderr.decode(errors="replace")), normalize(r2.stderr.decode(errors="replace"))
        if out1 != out2:
            fail += 1
            print(f"FAIL {f}")
            for ln in difflib.unified_diff(out1, out2, lineterm="", fromfile="c", tofile="moon"):
                print("  " + ln)
        else:
            print(f"OK   {f}")
    print(f"\n{total - fail}/{total} passed")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
