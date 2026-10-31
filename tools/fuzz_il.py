#!/usr/bin/env python3
"""Mutation fuzzing at the IL level.

Takes the .ssa fixtures, applies random structural mutations (delete a line,
duplicate a line, swap two lines) and compiles each mutant with the port and
with the reference qbe built from vendor/qbe.

Only mutants the reference accepts are judged: for those the port must also
accept. A port panic or crash there is a robustness bug, because the reference
compiled the same bytes. Mutants the reference rejects are counted but not
judged - accepting them is a diagnostic-quality question, not a fidelity one.
"""
import argparse, glob, os, random, subprocess, sys, tempfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def find_port():
    for base in (os.path.join(root, '_build'), os.path.join(os.path.dirname(root), '_build')):
        for dirpath, _dirs, files in os.walk(base) if os.path.isdir(base) else []:
            if 'main.exe' in files:
                return os.path.join(dirpath, 'main.exe')
    return None

def run(exe, path):
    try:
        return subprocess.run([exe, path], capture_output=True, timeout=60).returncode
    except subprocess.TimeoutExpired:
        return 'timeout'

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
    tmp = tempfile.mkdtemp()
    keepdir = a.keep or os.path.join(root, 'build', 'ilfuzz')
    for n in range(a.count):
        src = random.choice(seeds)
        with open(src) as fh:
            lines = fh.read().split(chr(10))
        path = os.path.join(tmp, 'm%d.ssa' % n)
        with open(path, 'w') as fh:
            fh.write(chr(10).join(mutate(lines)))
        rc_ref = run(ref, path)
        rc_port = run(port, path)
        if rc_ref != 0:
            rejects += 1
            continue
        if rc_port in (-11, -6, -4, -8):
            crashes.append((path, rc_port))
            os.makedirs(keepdir, exist_ok=True)
            dest = os.path.join(keepdir, 'crash_%d.ssa' % n)
            with open(dest, 'w') as fh:
                fh.write(open(path).read())
            continue
        if rc_port == 0:
            agree += 1
        else:
            differ.append((path, rc_port))
    print('il fuzz: %d agree, %d rejected a valid mutant, %d crashed, %d mutants the reference rejects (of %d)'
          % (agree, len(differ), len(crashes), rejects, a.count))
    for p, rcx in differ[:5]:
        print('  rejects valid', p, 'port rc=%s' % rcx)
    for p, rcx in crashes[:5]:
        print('  crash        ', p, 'port rc=%s' % rcx)
    sys.exit(0 if not differ and not crashes else 1)

if __name__ == '__main__':
    main()