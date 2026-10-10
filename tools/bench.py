#!/usr/bin/env python3
"""Benchmark the MoonBit QBE against the vendored reference C QBE.

Where compare.py answers "is the output identical?", this answers "how long did
it take?". Every case is timed through both binaries, so the headline number is
the *ratio* mine/reference, which is machine independent; absolute times are
reported alongside for context.

Usage:
    python tools/bench.py                      # whole corpus, one flag
    python tools/bench.py --cat stress         # the scale/stress series
    python tools/bench.py --by-flag            # one row per debug stage
    python tools/bench.py --jobs 8 --repeat 3
    python tools/bench.py --save bench.json
    python tools/bench.py --baseline bench.json     # exit 1 on a regression

The default flag is -dR (register allocation), the last stage: with any -d
flag QBE runs the whole pipeline, so the totals are comparable across flags and
the differences come from the dump stage itself.
"""
import argparse
import glob
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTDIR = os.path.join(ROOT, "test")
MINE = os.path.join(
    ROOT, "_build", "native", "debug", "build", "cmd", "main", "main.exe"
)
MOON = shutil.which("moon") or os.path.expanduser("~/.moon/bin/moon")
FLAGS = ["-dP", "-dM", "-dN", "-dC", "-dF", "-dA", "-dI", "-dL", "-dS", "-dR",
         "-dG", "-dK"]


def find_ref():
    env = os.environ.get("QBE_REF")
    if env:
        if not os.path.exists(env):
            sys.exit(f"error: QBE_REF={env} does not exist")
        return env
    suffix = ".exe" if os.name == "nt" else ""
    cand = os.path.join(ROOT, "vendor", "qbe", "qbe" + suffix)
    if os.path.exists(cand):
        return cand
    sys.exit("error: reference QBE binary not found (build vendor/qbe, or set QBE_REF)")


def collect(cat=None, include_hidden=False):
    """Inputs to time. Files starting with _ are skipped by default, matching
    compare.py: they are the scale/repro set rather than the exact-differential
    corpus, and --all brings them back for benchmarking."""
    base = os.path.join(TESTDIR, cat, "**") if cat else os.path.join(TESTDIR, "**")
    tests = sorted(glob.glob(os.path.join(base, "*.ssa"), recursive=True))
    tests += sorted(glob.glob(os.path.join(TESTDIR, "*.ssa")))
    tests = set(tests)
    if not include_hidden:
        tests = {t for t in tests if not os.path.basename(t).startswith("_")}
    return sorted(tests)


def time_one(argv):
    t0 = time.perf_counter()
    subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return time.perf_counter() - t0


def run_case(args):
    path, mine_flag, ref_flag, busy = args
    if busy:
        while os.path.exists(busy):
            time.sleep(0.001)
    t_mine = time_one([MINE, *mine_flag, path])
    t_ref = time_one([REF, *ref_flag, path])
    return path, t_mine, t_ref


def summarize(rows):
    mine = [r[1] for r in rows]
    ref = [r[2] for r in rows]
    s_mine, s_ref = sum(mine), sum(ref)
    return {
        "cases": len(rows),
        "mine_s": round(s_mine, 4),
        "ref_s": round(s_ref, 4),
        "ratio": round(s_mine / s_ref, 3) if s_ref else 0.0,
        "median_ms": round(statistics.median(mine) * 1000, 3),
        "p90_ms": round(sorted(mine)[int(len(mine) * 0.9)] * 1000, 3),
    }


def show(label, s):
    print(f"{label:<26} cases={s['cases']:<5} mine={s['mine_s']:>8.3f}s "
          f"ref={s['ref_s']:>8.3f}s ratio={s['ratio']:>6.3f} "
          f"median={s['median_ms']:>7.2f}ms p90={s['p90_ms']:>7.2f}ms")


def slowest(rows, n=8):
    rows = sorted(rows, key=lambda r: -r[1])[:n]
    print("  slowest cases (mine):")
    for path, t_mine, t_ref in rows:
        rel = os.path.relpath(path, ROOT)
        print(f"    {t_mine * 1000:>8.2f}ms  ref {t_ref * 1000:>7.2f}ms  {rel}")


def main():
    global REF
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cat", help="only run tests under test/<cat>/")
    ap.add_argument("--target", default="amd64_sysv")
    ap.add_argument("--flag", default="-dR", help="debug flag to drive each run")
    ap.add_argument("--by-flag", action="store_true", help="one row per debug stage")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=1,
                    help="parallel workers for the timing loop (default 1: per-case CPU)")
    ap.add_argument("--save", help="write the results as JSON")
    ap.add_argument("--baseline", help="compare against a saved JSON baseline")
    ap.add_argument("--tolerance", type=float, default=0.25,
                    help="allowed ratio regression vs the baseline (default 0.25)")
    ap.add_argument("--all", action="store_true",
                    help="also time inputs whose name starts with _ (excluded "
                         "from the differential suite)")
    ap.add_argument("--no-build", action="store_true",
                    help="do not run moon build first")
    args = ap.parse_args()

    if not os.path.exists(MINE):
        sys.exit(f"error: {MINE} not found; build with: moon build --target native cmd")
    if not args.no_build:
        subprocess.run([MOON, "build", "--target", "native"], cwd=ROOT, check=True)
    REF = find_ref()

    tests = collect(args.cat, include_hidden=args.all)
    if not tests:
        sys.exit(f"error: no .ssa inputs under {TESTDIR}/{args.cat or ''}")

    flags = FLAGS if args.by_flag else [args.flag]
    results = {"target": args.target, "flags": {}, "cases": {}}
    print(f"corpus: {len(tests)} files under test/{args.cat or ''} "
          f"target={args.target} jobs={args.jobs} repeat={args.repeat}")

    for flag in flags:
        busy = None
        if args.jobs > 1:
            # A start gate keeps process startup aligned so the wall clock
            # reflects throughput rather than spawn skew.
            busy = os.path.join(ROOT, ".bench.gate")
            with open(busy, "w", encoding="utf-8") as f:
                f.write("go")
        jobs = [(t, [flag], [flag], busy) for t in tests]
        rows = []
        for _ in range(args.repeat):
            if args.jobs > 1:
                with ProcessPoolExecutor(max_workers=args.jobs) as ex:
                    rows = list(ex.map(run_case, jobs))
            else:
                rows = [run_case(j) for j in jobs]
        if busy:
            os.remove(busy)
        s = summarize(rows)
        show(f"{flag}", s)
        if len(flags) == 1:
            slowest(rows)
        results["flags"][flag] = s

    all_mine = sum(v["mine_s"] for v in results["flags"].values())
    all_ref = sum(v["ref_s"] for v in results["flags"].values())
    if len(flags) > 1:
        print(f"{'total':<26} cases={len(tests) * len(flags):<5} "
              f"mine={all_mine:>8.3f}s ref={all_ref:>8.3f}s "
              f"ratio={(all_mine / all_ref if all_ref else 0):>6.3f}")
    results["total"] = {"mine_s": round(all_mine, 4), "ref_s": round(all_ref, 4),
                        "ratio": round(all_mine / all_ref, 3) if all_ref else 0.0}

    if args.save:
        with open(args.save, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, sort_keys=True)
        print(f"saved {args.save}")

    if args.baseline:
        with open(args.baseline, encoding="utf-8") as f:
            base = json.load(f)
        bad = []
        for flag, cur in results["flags"].items():
            old = base.get("flags", {}).get(flag)
            if not old or not old.get("ratio"):
                continue
            grew = cur["ratio"] / old["ratio"] - 1.0
            if grew > args.tolerance:
                bad.append((flag, old["ratio"], cur["ratio"], grew))
        for flag, old_r, new_r, grew in bad:
            print(f"REGRESSION {flag}: ratio {old_r} -> {new_r} "
                  f"({grew * 100:+.1f}%, tolerance {args.tolerance * 100:.0f}%)")
        if bad:
            return 1
        print(f"baseline ok (tolerance {args.tolerance * 100:.0f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
