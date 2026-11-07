#!/usr/bin/env python3
"""Mutation fuzzing at the IL level.

Takes the .ssa fixtures, applies random structural mutations (delete a line,
duplicate a line, swap two lines) and compiles each mutant with the port and
with the reference qbe built from vendor/qbe.

Only mutants the reference accepts are judged: for those the port must also
accept. A port panic or crash there is a robustness bug, because the reference
compiled the same bytes. Mutants the reference rejects are counted but not
judged - accepting them is a diagnostic-quality question, not a fidelity one.

With `--asm` the final amd64_sysv assembly is also compared byte for byte,
which exercises the spill/regalloc/emit stages that the staged dumps skip.
"""
import argparse, glob, os, random, subprocess, sys, tempfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def find_port():
    for base in (os.path.join(root, '_build'), os.path.join(os.path.dirname(root), '_build')):
        for dirpath, _dirs, files in os.walk(base) if os.path.isdir(base) else []:
            if 'main.exe' in files:
                return os.path.join(dirpath, 'main.exe')
    return None

def run(exe, path, args=()):
    try:
        p = subprocess.run([exe, *args, path], capture_output=True, timeout=180)
        return p
    except subprocess.TimeoutExpired:
        return None

def mutate(lines):
    lines = list(lines)
    for _ in range(random.randint(1, 3)):
        if len(lines) < 3:
            break
        r = random.random()
        i = random.randrange(len(lines))
        if r < 0.5:
            del lines[i]
        elif r < 0.8:
            lines.insert(i, lines[i])
        else:
            j = random.randrange(len(lines))
            lines[i], lines[j] = lines[j], lines[i]
    return lines

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--count', type=int, default=100)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--keep', default=None)
    ap.add_argument('--asm', action='store_true',
                    help='also compare the final amd64_sysv assembly byte for byte')
    a = ap.parse_args()
    port = find_port()
    ref = os.path.join(root, 'vendor', 'qbe', 'qbe')
    if not port or not os.path.exists(ref):
        sys.exit('need the port binary and vendor/qbe/qbe')
    seeds = sorted(glob.glob(os.path.join(root, 'test', '*.ssa')))
    if not seeds:
        sys.exit('no .ssa fixtures under test/')
    random.seed(a.seed)
    agree = rejects = 0
    differ = []
    crashes = []
    diffs = []
    asm_diffs = []
    tmp = tempfile.mkdtemp()
    keepdir = a.keep or os.path.join(root, 'build', 'ilfuzz')
    for n in range(a.count):
        src = random.choice(seeds)
        with open(src) as fh:
            lines = fh.read().split(chr(10))
        path = os.path.join(tmp, 'm%d.ssa' % n)
        with open(path, 'w') as fh:
            fh.write(chr(10).join(mutate(lines)))
        p_ref = run(ref, path)
        p_port = run(port, path)
        if p_ref is None or p_port is None:
            # a timeout is a hang, which is always a bug on our side
            crashes.append((path, 'timeout'))
            continue
        if p_ref.returncode != 0:
            rejects += 1
            continue
        if p_port.returncode in (-11, -6, -4, -8):
            crashes.append((path, p_port.returncode))
            os.makedirs(keepdir, exist_ok=True)
            dest = os.path.join(keepdir, 'crash_%d.ssa' % n)
            with open(dest, 'w') as fh:
                fh.write(open(path).read())
            continue
        if p_port.returncode != 0:
            differ.append((path, p_port.returncode))
            continue
        # Both accept: compare the deterministic staged dumps. Liveness,
        # spilling and regalloc are excluded because their tie-breaking depends
        # on the host qsort (see TODO.md), so they are not a fidelity signal.
        d_args = ['-t', 'amd64_sysv', '-dPMNCAGK']
        d_ref = run(ref, path, d_args)
        d_port = run(port, path, d_args)
        if d_ref is None or d_port is None:
            crashes.append((path, 'timeout-dump'))
            continue
        n_ref = d_ref.stderr.decode(errors='replace').replace(chr(13), '').split(chr(10))
        n_port = d_port.stderr.decode(errors='replace').replace(chr(13), '').split(chr(10))
        if n_ref != n_port:
            diffs.append((path, n_ref, n_port))
            os.makedirs(keepdir, exist_ok=True)
            dest = os.path.join(keepdir, 'diff_%d.ssa' % n)
            with open(dest, 'w') as fh:
                fh.write(open(path).read())
            continue
        if a.asm:
            s_ref = run(ref, path, ['-t', 'amd64_sysv'])
            s_port = run(port, path, ['-t', 'amd64_sysv'])
            if s_ref is None or s_port is None:
                crashes.append((path, 'timeout-asm'))
                continue
            if s_ref.stdout.replace(b'\r', b'') != s_port.stdout.replace(b'\r', b''):
                asm_diffs.append((path, s_ref.stdout, s_port.stdout))
                os.makedirs(keepdir, exist_ok=True)
                dest = os.path.join(keepdir, 'asmdiff_%d.ssa' % n)
                with open(dest, 'w') as fh:
                    fh.write(open(path).read())
                continue
        agree += 1
    print('il fuzz: %d agree, %d rejected a valid mutant, %d crashed, %d dump diffs, %d asm diffs, %d mutants the reference rejects (of %d)'
          % (agree, len(differ), len(crashes), len(diffs), len(asm_diffs), rejects, a.count))
    for p, _r1, _r2 in asm_diffs[:5]:
        print('  asm diff    ', p)
    for p, rcx in differ[:5]:
        print('  rejects valid', p, 'port rc=%s' % rcx)
    for p, rcx in crashes[:5]:
        print('  crash        ', p, 'port rc=%s' % rcx)
    for p, r1, r2 in diffs[:3]:
        print('  dump diff    ', p)
        import difflib
        for ln in list(difflib.unified_diff(r1, r2, lineterm='', fromfile='ref', tofile='moon'))[:20]:
            print('    ' + ln)
    sys.exit(0 if not differ and not crashes and not diffs and not asm_diffs else 1)

if __name__ == '__main__':
    main()