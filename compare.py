#!/usr/bin/env python3
"""Compare the MoonBit QBE implementation against the reference C QBE.

For every test file under `test/` (recursively, skipping files starting with
`_`) and every debug flag set given on the command line (defaults to the
implemented stages), the debug output (stderr) is diffed line by line against
`vendor/qbe/qbe`.

With `--asm`, the generated assembly (stdout, no debug flags) is compared
when the reference uses the same target-emission revision. The vendored
reference currently has different prologue and label policies, so CI uses the
debug differential suite and the backend-specific assembler gates instead.
Positional arguments are treated as specific test files in both modes.

Options:
  --cat <dir>   only run tests under test/<dir>/
  --jobs <n>    parallel workers (default 4)
  -G <flavor>   with --asm, compare the given gas flavor (e, m)
  --target <t>  compare a non-default backend target (e.g. arm64); both
                binaries are invoked with -t <target>

Usage:
    python compare.py [--asm] [-dP] [-dM] ... [test_file.ssa ...]
    python compare.py --asm [-G m]
    python compare.py --cat abi
    python compare.py --target arm64 --asm
"""
import subprocess, glob, os, sys, difflib, shutil
from concurrent.futures import ProcessPoolExecutor

ROOT = os.path.dirname(os.path.abspath(__file__))
TESTDIR = os.path.join(ROOT, "test")
MINE = os.path.join(ROOT, "_build", "native", "debug", "build", "cmd", "main", "main.exe")
MOON = shutil.which("moon") or os.path.expanduser("~/.moon/bin/moon")


def find_qbe_ref():
    """Locate the reference C QBE binary.

    Priority: $QBE_REF -> vendor/qbe build output.
    """
    env = os.environ.get("QBE_REF")
    if env:
        if os.path.exists(env):
            return env
        sys.exit(f"error: QBE_REF={env} does not exist")
    suffix = ".exe" if os.name == "nt" else ""
    candidates = [
        os.path.join(ROOT, "vendor", "qbe", "qbe" + suffix),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    sys.exit(
        "error: reference QBE binary not found.\n"
        "Build it from the vendored submodule:\n"
        "    git submodule update --init --recursive\n"
        "    make -C vendor/qbe\n"
        "or point the QBE_REF environment variable at an existing binary."
    )


QBE_REF = None  # resolved in main()


DEFAULT_FLAGS = ["-dP", "-dM", "-dN", "-dC", "-dF", "-dA", "-dI", "-dL", "-dS", "-dR", "-dG", "-dK", "-dPM", "-dPN", "-dPC", "-dPMNC"]

_qbe_g_support = None


# Port target name -> reference target for the Mach-O ("-G m") flavor.
APPLE_TARGET = {
    "amd64_sysv": "amd64_apple",
    "arm64": "arm64_apple",
}


def target_of(fset):
    """Return the target requested by a flagset, or None for the default."""
    for i, a in enumerate(fset):
        if a == "-t" and i + 1 < len(fset):
            return fset[i + 1]
    return None


def ref_flavor_args(fset, qbe_ref):
    """Translate a flagset for the MoonBit binary into one the reference
    binary understands (gas flavor selection differs across versions).

    The vendored reference has no -G option: the ELF flavor is its default and
    the Mach-O flavor is selected with -t <target>_apple.  When the requested
    target has no Mach-O variant (e.g. rv64) the comparison is impossible, so
    None is returned and the caller skips it."""
    global _qbe_g_support
    if "-G" not in fset:
        return list(fset)
    if _qbe_g_support is None:
        probe_in = os.path.join(ROOT, "test", "puts10.ssa")
        probe = run([qbe_ref, "-G", "e", probe_in])
        ok_with_g = probe.returncode == 0 and probe.stdout != b""
        _qbe_g_support = ok_with_g
    if _qbe_g_support:
        return list(fset)
    i = fset.index("-G")
    flavor = fset[i + 1] if i + 1 < len(fset) else "e"
    translated = [a for j, a in enumerate(fset) if a != "-G" and (j == 0 or fset[j-1] != "-G")]
    if flavor == "m":
        apple = APPLE_TARGET.get(target_of(fset))
        if apple is None:
            return None
        translated += ["-t", apple]
    return translated


def normalize(text):
    """Split into lines, tolerant of CRLF vs LF."""
    return [ln.rstrip("\r") for ln in text.split("\n")]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def check(label, out1, out2):
    n1, n2 = normalize(out1.decode(errors="replace")), normalize(out2.decode(errors="replace"))
    if n1 != n2:
        return (label, (n1, n2))
    return None


def one(args):
    """Run one (flagset, test) pair; returns (label, None|(n1,n2)).

    Debug dumps are written to stderr; generated assembly is written to
    stdout.  Compare the stream that the mode actually produces.
    """
    ref_fset, mine_fset, t, qbe_ref, asm = args
    r1 = run([qbe_ref, *ref_fset, t])
    r2 = run([MINE, *mine_fset, t])
    label = (" ".join(mine_fset) + " " if mine_fset else "") + os.path.basename(t)
    if asm:
        return check(label, r1.stdout, r2.stdout)
    return check(label, r1.stderr, r2.stderr)


def main():
    global QBE_REF
    QBE_REF = find_qbe_ref()
    asm_mode = "--asm" in sys.argv
    rest = [a for a in sys.argv[1:] if a != "--asm"]
    cat = None
    jobs = 4
    out = []

    if "--cat" in rest:
        i = rest.index("--cat")
        cat = rest[i + 1]
        rest = rest[:i] + rest[i + 2:]
    if "--jobs" in rest:
        i = rest.index("--jobs")
        jobs = int(rest[i + 1])
        rest = rest[:i] + rest[i + 2:]
    target = None
    if "--target" in rest:
        i = rest.index("--target")
        target = rest[i + 1]
        rest = rest[:i] + rest[i + 2:]
    # The vendored binary defaults to the host target (arm64 on Apple
    # Silicon), while the MoonBit facade defaults to amd64_sysv. Make the
    # default explicit so differential tests are host-independent.
    if target is None:
        target = "amd64_sysv"

    if not os.path.exists(MOON):
        sys.exit("error: MoonBit CLI not found; install moon or set PATH")
    subprocess.run([MOON, "build", "--target", "native"], cwd=ROOT, check=True)

    # Positional arguments that look like test files are a test subset.
    subset = [a for a in rest if a.endswith(".ssa")]
    flags = [a for a in rest if not a.endswith(".ssa")]

    base = os.path.join(TESTDIR, cat, "**") if cat else os.path.join(TESTDIR, "**")
    all_tests = sorted(glob.glob(os.path.join(base, "*.ssa"), recursive=True))
    all_tests += sorted(glob.glob(os.path.join(TESTDIR, "*.ssa")))
    all_tests = sorted(set(t for t in all_tests if not os.path.basename(t).startswith("_")))
    if subset:
        tests = []
        for t in subset:
            # accept both repo-root-relative and subdirectory paths
            cand = t if os.path.exists(t) else os.path.join(TESTDIR, os.path.basename(t))
            if not os.path.exists(cand):
                sys.exit(f"error: test file not found: {t}")
            tests.append(cand)
    else:
        tests = all_tests

    if asm_mode:
        if flags:
            flagsets = [flags]
        else:
            flagsets = [["-G", "e"]]
        if target:
            # non-default backend target: -t goes to both binaries
            flagsets = [["-t", target, *fs] for fs in flagsets]
    else:
        if not flags:
            flags = DEFAULT_FLAGS
        flagsets = [[fl] for fl in flags]
        if target:
            flagsets = [["-t", target, *fs] for fs in flagsets]

    # Some reference builds (e.g. ripe-lang/qbe) have no -G option and select
    # the flavor via -t targets instead. Translate the flagset for the
    # reference binary accordingly.
    ref_flagsets = {tuple(fs): ref_flavor_args(fs, QBE_REF) for fs in flagsets}

    jobs_list = []
    for fset in flagsets:
        ref_fset = ref_flagsets[tuple(fset)]
        if ref_fset is None:
            # e.g. -G m on a target with no Mach-O variant
            continue
        for t in tests:
            jobs_list.append((ref_fset, fset, t, QBE_REF, asm_mode))
    total = len(jobs_list)
    fail = 0
    results = []
    with ProcessPoolExecutor(max_workers=jobs) as ex:
        for r in ex.map(one, jobs_list):
            results.append(r)
    results.sort(key=lambda r: r[0] if r else "")
    for r in results:
        if r is None:
            continue
        label, (n1, n2) = r
        fail += 1
        print(f"FAIL {label}")
        for ln in difflib.unified_diff(n1, n2, lineterm="", fromfile="ref", tofile="moon"):
            print("  " + ln)
    print(f"\n{total - fail}/{total} passed")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
