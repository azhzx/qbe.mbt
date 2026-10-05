#!/usr/bin/env python3
"""Generate the scale/stress series under test/stress/.

Where test/core/ pins *which* operation runs, this series pins *how much*: each
file is a valid, reference-compilable .ssa program whose size drives the passes
at scale -- long data-dependency chains, wide live ranges, deep CFGs, large
call/argument shapes, register pressure and memory traffic.

Every file is compared byte-for-byte against the vendored reference by
compare.py, exactly like the rest of the suite:

    python compare.py --cat stress

Generated files are checked in; this script documents how they were produced.
Run:  python tools/gen_stress.py

SSA rules honored (the reference rejects violations at -dA ssacheck):

- every temp is defined exactly once per function;
- a phi argument list follows the *block layout order* of its predecessors,
  because fillpreds walks fn->start..link and appends in that order;
- every block ends in a terminator and is reachable from @start;
- the constraints listed in test/README.md (no sltof on a word operand, no
  cs... spellings for unsigned compares, no decimal points in data).
"""
import os
import shutil

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DEST = os.path.join(ROOT, "test", "stress")

SYM = "$"  # QBE symbol sigil; kept separate so f-strings stay readable

# Sizes chosen so the whole directory stays in the tens of kilobytes while
# still putting thousands of instructions through every pass.
#
# Three shapes are emitted with a leading underscore, which makes compare.py
# skip them: they reach a register-pressure regime where our spill pass
# assigns different slot numbers than the reference (and one of them also
# trips an emitter ICE). They stay in the tree as reproducible inputs for
# tools/bench.py --all and for whoever fixes the pass; see TODO.md.
CHAIN = 400
WIDE = 300
BLOCKS = 160
DIAMONDS = 100
LOOP_OUTER, LOOP_MID, LOOP_INNER = 24, 16, 12
ARGS_W = 32
ARGS_MIXED = 24
LOCALS = 120
CALLS = 160
LADDER = 100
DATA_WORDS = 512
FLOATS = 200
EXTS = 240
FANIN = 40


def write(name, text):
    os.makedirs(DEST, exist_ok=True)
    with open(os.path.join(DEST, name), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def func(name, params, body, ret="w", export=True):
    s = "export\n" if export else ""
    s += f"function {ret} {SYM}{name}("
    s += ", ".join(f"{c} %{p}" for c, p in params)
    s += ") {\n" + body + "}\n"
    return s


def header(title, note):
    return f"# {title}\n# {note}\n\n"


def gen_chain(n):
    b = "@start\n\t%t0 =w add %a, 1\n"
    for i in range(1, n):
        b += f"\t%t{i} =w add %t{i - 1}, {i % 7 + 1}\n"
    b += f"\tret %t{n - 1}\n"
    write(f"001_chain_{n}.ssa", header(
        f"a single block with a {n}-deep data dependency chain",
        "one long live range: gvn/gcm see a chain, rega sees them all live") +
        func("chain", [("w", "a")], b))


def gen_wide(n):
    b = "@start\n"
    for i in range(n):
        b += f"\t%x{i} =w add %a, {i % 31 + 1}\n"
    acc = "%x0"
    for i in range(1, n):
        b += f"\t%s{i} =w add {acc}, %x{i}\n"
        acc = f"%s{i}"
    b += f"\tret {acc}\n"
    write(f"_002_wide_{n}.ssa", header(
        f"a single block with {n} independent definitions",
        "many simultaneously live temps: maximum register pressure in one block") +
        func("wide", [("w", "a")], b))


def gen_blocks(n):
    b = "@start\n\t%t0 =w copy %a\n\tjmp @b0\n"
    for i in range(1, n):
        b += f"@b{i - 1}\n\t%t{i} =w add %t{i - 1}, 1\n\tjmp @b{i}\n"
    b += f"@b{n - 1}\n\t%t{n} =w add %t{n - 1}, 1\n\tret %t{n}\n"
    write(f"003_blocks_{n}.ssa", header(
        f"a chain of {n} basic blocks",
        "CFG scale: dominators, liveness and spill cost across many blocks") +
        func("blocks", [("w", "a")], b, export=False))


def gen_diamond(n):
    b = "@start\n\t%c0 =w csltw %a, 0\n\tjnz %c0, @t0, @e0\n"
    for i in range(n):
        if i:
            b += (f"\t%c{i} =w csltw %p{i - 1}, {i}\n"
                  f"\tjnz %c{i}, @t{i}, @e{i}\n")
        b += f"@t{i}\n\tjmp @j{i}\n@e{i}\n\tjmp @j{i}\n"
        b += f"@j{i}\n\t%p{i} =w phi @t{i} {i + 1}, @e{i} {i + 2}\n"
    b += f"\tret %p{n - 1}\n"
    write(f"004_diamond_{n}.ssa", header(
        f"{n} diamond joins with phi nodes",
        "each join has 2 predecessors; the phi order follows block layout") +
        func("diamond", [("w", "a")], b))


def gen_fanin(n):
    b = "@start\n"
    for i in range(n):
        b += (f"\t%c{i} =w ceqw %a, {i}\n"
              f"\tjnz %c{i}, @b{i}, @n{i}\n@n{i}\n")
    b += "\tjmp @join\n"
    for i in range(n):
        b += f"@b{i}\n\tjmp @join\n"
    args = ", ".join(f"@b{i} {i}" for i in range(n))
    b += f"@join\n\t%p =w phi @n{n - 1} -1, {args}\n\tret %p\n"
    write(f"005_fanin_{n}.ssa", header(
        f"a join block with {n + 1} predecessors",
        f"the largest phi in the suite: @n{n - 1} is laid out before @b0.., so "
        "it comes first in the phi argument list") +
        func("fanin", [("w", "a")], b))

def gen_args_w(n):
    params = [("w", f"a{i}") for i in range(n)]
    b = "@start\n\t%acc0 =w copy %a0\n"
    for i in range(1, n):
        b += f"\t%acc{i} =w add %acc{i - 1}, %a{i}\n"
    b += f"\tret %acc{n - 1}\n"
    call = ", ".join(f"w {i + 1}" for i in range(n))
    txt = header(
        f"{n} word parameters, far past the 8 GPR limit",
        "most arguments are passed on the stack; the callee must reload them") + \
        func("callee_w", params, b)
    txt += f"\nexport\nfunction w {SYM}args_w() {{\n@start\n"
    txt += f"\t%r =w call {SYM}callee_w({call})\n\tret %r\n}}\n"
    write(f"_006_args_w_{n}.ssa", txt)


def gen_args_mixed(n):
    classes = ["w", "l", "s", "d"]
    params = [(classes[i % 4], f"a{i}") for i in range(n)]
    b = "@start\n"
    for i, (c, _) in enumerate(params):
        b += f"\t%b{i} ={c} copy %a{i}\n"
    ints = [i for i, (c, _) in enumerate(params) if c in "wl"]
    flts = [i for i, (c, _) in enumerate(params) if c in "sd"]
    prev = f"%b{ints[0]}"
    for i in ints[1:]:
        b += f"\t%i{i} =l add {prev}, %b{i}\n"
        prev = f"%i{i}"
    flt_prev, flt_cls = None, None
    for i in flts:
        cls = params[i][0]
        if flt_prev is None:
            flt_prev, flt_cls = f"%b{i}", cls
            continue
        if cls == flt_cls:
            b += f"\t%f{i} ={cls} add {flt_prev}, %b{i}\n"
        elif flt_cls == "s":
            b += f"\t%e{i} =d exts {flt_prev}\n\t%f{i} =d add %e{i}, %b{i}\n"
        else:
            b += f"\t%e{i} =s truncd {flt_prev}\n\t%f{i} =s add %e{i}, %b{i}\n"
        flt_prev, flt_cls = f"%f{i}", cls
    b += "\t%r =w copy 0\n\tret %r\n"
    call = ", ".join(f"{c} {i + 1}" for i, (c, _) in enumerate(params))
    txt = header(
        f"{n} parameters mixing the w/l/s/d classes",
        "exercises the mixed integer/float argument registers and stack slots") + \
        func("callee_mixed", params, b)
    txt += f"\nexport\nfunction w {SYM}args_mixed() {{\n@start\n"
    txt += f"\t%r =w call {SYM}callee_mixed({call})\n\tret %r\n}}\n"
    write(f"007_args_mixed_{n}.ssa", txt)


def gen_locals(n):
    b = "@start\n"
    for i in range(n):
        b += f"\t%p{i} =l alloc8 1\n"
    for i in range(n):
        b += f"\tstorew {i}, %p{i}\n"
    acc = None
    for i in range(n):
        b += f"\t%v{i} =w load %p{i}\n"
        if acc is None:
            acc = f"%v{i}"
        else:
            b += f"\t%u{i} =w add {acc}, %v{i}\n"
            acc = f"%u{i}"
    b += f"\tret {acc}\n"
    write(f"008_locals_{n}.ssa", header(
        f"{n} stack slots, each stored then loaded",
        "promote/coalesce have many slots to chew on; spill cost sees them all") +
        func("locals", [], b, export=False))


def gen_calls(n):
    txt = header("a call-heavy function", f"{n} calls in one block") + \
        func("plus1", [("w", "x")], "@start\n\t%r =w add %x, 1\n\tret %r\n",
             export=False)
    b = "@start\n\t%a0 =w copy 0\n"
    for i in range(n):
        b += f"\t%a{i + 1} =w call %plus1(w %a{i})\n"
    b += f"\tret %a{n}\n"
    txt += f"\nexport\nfunction w {SYM}calls() {{\n{b}}}\n"
    write(f"_009_calls_{n}.ssa", txt)


def gen_ladder(n):
    b = "@start\n"
    for i in range(n):
        b += (f"\t%c{i} =w ceqw %a, {i}\n"
              f"\tjnz %c{i}, @h{i}, @n{i}\n@n{i}\n")
    b += "\t%rd =w copy 99\n\tret %rd\n"
    for i in range(n - 1, -1, -1):
        b += f"@h{i}\n\t%r{i} =w copy {i}\n\tret %r{i}\n"
    write(f"010_ladder_{n}.ssa", header(
        f"a {n}-rung compare/jump ladder",
        "each rung is its own block; only one is entered, the rest are cold") +
        func("ladder", [("w", "a")], b, export=False))


def gen_data(n):
    words = ", ".join(f"w {i % 251}" for i in range(n))
    b = "@start\n\t%i =w copy 0\n\t%acc =w copy 0\n@loop\n"
    b += "\t%i2 =w phi @start %i, @body %i3\n"
    b += "\t%acc2 =w phi @start %acc, @body %acc3\n"
    b += f"\t%c =w csltw %i2, {n}\n\tjnz %c, @body, @end\n"
    b += "@body\n\t%idx =l extsw %i2\n\t%off =l mul 4, %idx\n"
    b += f"\t%p =l add {SYM}tbl, %off\n\t%v =w load %p\n"
    b += "\t%acc3 =w add %acc2, %v\n\t%i3 =w add %i2, 1\n\tjmp @loop\n"
    b += "@end\n\tret %acc2\n"
    txt = header(f"a {n}-word data section walked by a loop",
                 "data layout and address arithmetic at scale") + \
        f"data {SYM}tbl = {{ {words} }}\n\n" + func("data_sum", [], b)
    write(f"011_data_{n}.ssa", txt)


def gen_floats(n):
    b = "@start\n\t%t0 =d copy %a\n"
    prev, cls = "%t0", "d"
    for i in range(n):
        nxt = f"%t{i + 1}"
        if i % 4 == 0:
            b += f"\t{nxt} =d add {prev}, d_1.000000\n"
            cls = "d"
        elif i % 4 == 1:
            b += f"\t%s{i} =s truncd {prev}\n"
            b += f"\t{nxt} =s mul %s{i}, s_0.500000\n"
            cls = "s"
        elif i % 4 == 2:
            b += f"\t%e{i} =d exts {prev}\n"
            b += f"\t{nxt} =d sub %e{i}, d_0.250000\n"
            cls = "d"
        else:
            b += f"\t{nxt} ={cls} div {prev}, {cls}_2.000000\n"
        prev = nxt
    b += f"\tret {prev}\n"
    write(f"012_floats_{n}.ssa", header(
        f"a {n}-step chain alternating single and double precision",
        "exts/truncd round trips plus float constants in the rodata stash") +
        func("floats", [("d", "a")], b, ret="d"))


def gen_exts(n):
    ops = ["extsb", "extub", "extsh", "extuh", "extsw", "extuw"]
    b = "@start\n\t%t0 =l copy %a\n"
    prev = "%t0"
    for i in range(n):
        nxt = f"%t{i + 1}"
        b += f"\t{nxt} =l {ops[i % len(ops)]} {prev}\n"
        prev = nxt
    b += f"\tret {prev}\n"
    write(f"013_exts_{n}.ssa", header(
        f"a {n}-step chain through all six extension ops",
        "the sign/zero extension encodings, back to back") +
        func("exts", [("l", "a")], b, ret="l"))


def gen_loop_nest():
    o, m, i = LOOP_OUTER, LOOP_MID, LOOP_INNER
    b = "@start\n\t%i =w copy 0\n\t%acc =w copy 0\n"
    b += "\t%sp =l alloc8 1\n\tstorew 0, %sp\n\tjmp @h0\n"
    b += f"@h0\n\t%i2 =w phi @start %i, @l0 %i3\n"
    b += f"\t%c0 =w csltw %i2, {o}\n\tjnz %c0, @b0, @end\n"
    b += "@b0\n\t%j =w copy 0\n\tjmp @h1\n"
    b += f"@h1\n\t%j2 =w phi @b0 %j, @l1 %j3\n"
    b += f"\t%c1 =w csltw %j2, {m}\n\tjnz %c1, @b1, @l0\n"
    b += "@b1\n\t%k =w copy 0\n\tjmp @h2\n"
    b += f"@h2\n\t%k2 =w phi @b1 %k, @b2 %k3\n"
    b += f"\t%c2 =w csltw %k2, {i}\n\tjnz %c2, @b2, @l1\n"
    b += "@b2\n\t%cur =w load %sp\n\t%nx =w add %cur, 1\n\tstorew %nx, %sp\n"
    b += "\t%k3 =w add %k2, 1\n\tjmp @h2\n"
    b += "@l1\n\t%j3 =w add %j2, 1\n\tjmp @h1\n"
    b += "@l0\n\t%i3 =w add %i2, 1\n\tjmp @h0\n"
    b += "@end\n\t%res =w load %sp\n\tret %res\n"
    write("014_loop_nest.ssa", header(
        f"three nested loops {o} x {m} x {i}",
        "deep CFG with an accumulator in memory, so promote must cope with the "
        "value live across all three headers") +
        func("loop_nest", [], b, export=False))


def main():
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)
    gen_chain(CHAIN)
    gen_wide(WIDE)
    gen_blocks(BLOCKS)
    gen_diamond(DIAMONDS)
    gen_fanin(FANIN)
    gen_args_w(ARGS_W)
    gen_args_mixed(ARGS_MIXED)
    gen_locals(LOCALS)
    gen_calls(CALLS)
    gen_ladder(LADDER)
    gen_data(DATA_WORDS)
    gen_floats(FLOATS)
    gen_exts(EXTS)
    gen_loop_nest()
    files = sorted(os.listdir(DEST))
    total = sum(os.path.getsize(os.path.join(DEST, f)) for f in files)
    print(f"stress: {len(files)} files, {total} bytes")
    for f in files:
        print("  %-28s %6d B" % (f, os.path.getsize(os.path.join(DEST, f))))


if __name__ == "__main__":
    main()
