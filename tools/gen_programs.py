#!/usr/bin/env python3
"""Hand-written realistic programs for test/programs/.

These are full programs (loops, recursion, arrays, strings, float math) that
exercise the compiler end to end. Each file is plain .ssa with correct SSA
(one definition per temporary, phi nodes at joins).

The generator is only a convenience for writing the files; the tests are
intended to be read and maintained by hand.
"""
import os
import re as _re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "test", "programs")

DEF_RE = _re.compile(r"^\s*(%[\w.]+)\s*=")
USE_RE = _re.compile(r"%[\w.]+")
JUMP_RE = _re.compile(r"jnz\s+%[\w.]+\s*,\s*@(\w+)\s*,\s*@(\w+)")
JMP_RE = _re.compile(r"jmp\s+@(\w+)")


def _rewrite_uses(rhs, latest):
    return USE_RE.sub(lambda m: latest.get(m.group(0), m.group(0)), rhs)


def fix_ssa(text):
    """Turn the hand-written (chain style) bodies into strict SSA:
    1. rename duplicate temp definitions (same-block chains and
       cross-block duplicates) and update uses,
    2. relabel phi arguments to real predecessors (fall-through aware)."""
    lines = text.splitlines()
    blocks = {}
    order = []
    cur = None
    for l in lines:
        if l.startswith("@"):
            cur = l[1:].strip()
            blocks[cur] = []
            order.append(cur)
        elif cur is not None:
            blocks[cur].append(l)

    succ = {}
    for i, name in enumerate(order):
        s = []
        for l in blocks[name]:
            m = JUMP_RE.search(l)
            if m:
                s = [m.group(1), m.group(2)]
            m = JMP_RE.search(l)
            if m:
                s = [m.group(1)]
        if not s and i + 1 < len(order):
            s = [order[i + 1]]
        succ[name] = s

    pred = {name: [] for name in order}
    for name, s in succ.items():
        for t in s:
            if t in pred:
                pred[t].append(name)

    defs = {}
    for name in order:
        d = set()
        for l in blocks[name]:
            m = DEF_RE.match(l)
            if m:
                d.add(m.group(1))
        defs[name] = d

    final = {}
    seen = {}
    for name in order:
        latest = {}
        out = []
        for l in blocks[name]:
            m = DEF_RE.match(l)
            if m:
                nm = m.group(1)
                if " phi " in l:
                    out.append(l)
                    continue
                seen[nm] = seen.get(nm, 0) + 1
                new = nm if seen[nm] == 1 else f"{nm}.{seen[nm]}"
                eq = l.index("=")
                l = l[:eq].replace(nm, new) + _rewrite_uses(l[eq:], latest)
                latest[nm] = new
                final.setdefault(name, {})[nm] = new
            else:
                l = _rewrite_uses(l, latest)
            out.append(l)
        blocks[name] = out

    for name in order:
        out = []
        for l in blocks[name]:
            if " phi " in l:
                args = _re.findall(r"@(\w+) (%[\w.]+)", l)
                new_parts = []
                used = set()
                for p, v in args:
                    if p in pred[name]:
                        if v in defs[p] or not any(v in defs[q] for q in pred[name]):
                            rp = p
                        else:
                            rp = next((q for q in pred[name] if v in defs[q]), None)
                    else:
                        rp = next((q for q in pred[name] if v in defs[q]), None)
                    if rp is None:
                        rp = next((q for q in pred[name] if q not in used), None)
                    if rp is None:
                        rp = p
                    nv = final.get(rp, {}).get(v, v)
                    new_parts.append(f"@{rp} {nv}")
                    used.add(rp)
                l = l.split("phi ")[0] + "phi " + ", ".join(new_parts)
            out.append(l)
        blocks[name] = out

    start = 0
    for i, l in enumerate(lines):
        if l.startswith("@"):
            start = i
            break
    result = []
    for name in order:
        result.append(f"@{name}")
        result.extend(blocks[name])
    return "\n".join(lines[:start] + result)


def main():
    import shutil
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    n = 0
    for name in sorted(PROGRAMS):
        n += 1
        path = os.path.join(OUT, f"{n:03d}_{name}.ssa")
        os.makedirs(OUT, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(fix_ssa(PROGRAMS[name]))
    print(f"programs={n}")

PROGRAMS = {}


def wrap(desc, body):
    return f"# {desc}\n\n{body}"


# --- number theory ---

PROGRAMS["fact_rec"] = wrap(
    "recursive factorial: fact(5) = 120",
    """export
function w $fact(w %n) {
@start
	%c =w csgtw %n, 1
	jnz %c, @rec, @base
@base
	ret 1
@rec
	%m =w sub %n, 1
	%r =w call $fact(w %m)
	%res =w mul %n, %r
	ret %res
}
""")

PROGRAMS["fact_iter"] = wrap(
    "iterative factorial",
    """export
function l $fact(l %n) {
@start
	%r =l copy 1
	%i =l copy 2
@loop
	%i2 =l phi @start %i, @loop %i3
	%r2 =l phi @start %r, @loop %r3
	%c =l csgtl %i2, %n
	jnz %c, @end, @body
@body
	%r3 =l mul %r2, %i2
	%i3 =l add %i2, 1
	jmp @loop
@end
	ret %r2
}
""")

PROGRAMS["fib_rec"] = wrap(
    "recursive fibonacci: fib(10) = 55",
    """export
function w $fib(w %n) {
@start
	%c =w csgtw %n, 1
	jnz %c, @rec, @base
@base
	ret %n
@rec
	%a =w sub %n, 1
	%b =w sub %n, 2
	%r1 =w call $fib(w %a)
	%r2 =w call $fib(w %b)
	%res =w add %r1, %r2
	ret %res
}
""")

PROGRAMS["fib_iter"] = wrap(
    "iterative fibonacci",
    """export
function l $fib(l %n) {
@start
	%a =l copy 0
	%b =l copy 1
	%i =l copy 0
@loop
	%i2 =l phi @start %i, @loop %i3
	%a2 =l phi @start %a, @loop %a3
	%b2 =l phi @start %b, @loop %b3
	%c =l csltl %i2, %n
	jnz %c, @body, @end
@body
	%a3 =l copy %b2
	%b3 =l add %a2, %b2
	%i3 =l add %i2, 1
	jmp @loop
@end
	ret %a2
}
""")

PROGRAMS["gcd"] = wrap(
    "euclidean algorithm: gcd(1071, 462) = 21",
    """export
function w $gcd(w %a, w %b) {
@start
	%r =w rem %a, %b
	%c =w ceqw %r, 0
	jnz %c, @done, @again
@again
	%r1 =w call $gcd(w %b, w %r)
	ret %r1
@done
	ret %b
}
""")

PROGRAMS["pow"] = wrap(
    "exponentiation by squaring: pow(2, 10) = 1024",
    """export
function l $pow(l %b, w %e) {
@start
	%r =l copy 1
@loop
	%e2 =w phi @start %e, @loop %e4
	%r2 =l phi @start %r, @loop %r4
	%b2 =l phi @start %b, @loop %b4
	%c =w ceqw %e2, 0
	jnz %c, @done, @body
@body
	%odd =w and %e2, 1
	%c2 =w ceqw %odd, 0
	jnz %c2, @even, @odd
@odd
	%r3 =l mul %r2, %b2
	jmp @join
@even
	%r3 =l copy %r2
	jmp @join
@join
	%r4 =l phi @odd %r3, @even %r3
	%b4 =l mul %b2, %b2
	%e4 =w shr %e2, 1
	jmp @loop
@done
	ret %r2
}
""")

PROGRAMS["digit_sum"] = wrap(
    "sum of decimal digits: digit_sum(12345) = 15",
    """export
function w $ds(w %n) {
@start
	%s =w copy 0
@loop
	%n2 =w phi @start %n, @loop %n3
	%s2 =w phi @start %s, @loop %s3
	%c =w ceqw %n2, 0
	jnz %c, @done, @body
@body
	%d =w rem %n2, 10
	%s3 =w add %s2, %d
	%n3 =w div %n2, 10
	jmp @loop
@done
	ret %s2
}
""")

PROGRAMS["is_prime"] = wrap(
    "primality test: is_prime(97) = 1",
    """export
function w $prime(w %n) {
@start
	%c =w cslew %n, 1
	jnz %c, @no, @start2
@start2
	%i =w copy 2
@loop
	%i2 =w phi @start2 %i, @loop %i3
	%sq =w mul %i2, %i2
	%c2 =w csgtw %sq, %n
	jnz %c2, @yes, @body
@body
	%d =w rem %n, %i2
	%c3 =w ceqw %d, 0
	jnz %c3, @no, @cont
@cont
	%i3 =w add %i2, 1
	jmp @loop
@yes
	ret 1
@no
	ret 0
}
""")

# --- array / sorting ---

PROGRAMS["arr_sum"] = wrap(
    "sum of an array: 10+20+30+40 = 100",
    """data $arr = { l 10, l 20, l 30, l 40 }
export
function l $sum(w %n) {
@start
	%s =l copy 0
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%s2 =l phi @start %s, @loop %s3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%idx =l extsw %i2
	%off =l mul 8, %idx
	%p =l add $arr, %off
	%v =l load %p
	%s3 =l add %s2, %v
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %s2
}
""")

PROGRAMS["arr_max"] = wrap(
    "maximum of an array of words",
    """data $arr = { w 3, w 7, w 1, w 9, w 4 }
export
function w $max(w %n) {
@start
	%m =w copy 0
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%m2 =w phi @start %m, @loop %m3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%idx =l extsw %i2
	%off =l mul 4, %idx
	%p =l add $arr, %off
	%v =w load %p
	%c2 =w csgtw %v, %m2
	jnz %c2, @new, @keep
@new
	%mv =w copy %v
	jmp @join
@keep
	%mk =w copy %m2
	jmp @join
@join
	%m3 =w phi @new %mv, @keep %mk
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %m2
}
""")

PROGRAMS["arr_reverse"] = wrap(
    "reverse an array in place",
    """data $arr = { w 1, w 2, w 3, w 4, w 5 }
export
function w $rev(w %n) {
@start
	%lo =w copy 0
	%hi =w sub %n, 1
@loop
	%lo2 =w phi @start %lo, @loop %lo3
	%hi2 =w phi @start %hi, @loop %hi3
	%c =w csltw %lo2, %hi2
	jnz %c, @body, @end
@body
	%li =l extsw %lo2
	%loff =l mul 4, %li
	%lp =l add $arr, %loff
	%lv =w load %lp
	%hii =l extsw %hi2
	%hoff =l mul 4, %hii
	%hp =l add $arr, %hoff
	%hv =w load %hp
	storew %hv, %lp
	storew %lv, %hp
	%lo3 =w add %lo2, 1
	%hi3 =w sub %hi2, 1
	jmp @loop
@end
	ret 0
}
""")

PROGRAMS["bubble_sort"] = wrap(
    "bubble sort an array of words",
    """data $arr = { w 5, w 2, w 8, w 1, w 9, w 3 }
export
function w $sort(w %n) {
@start
	%i =w copy 0
	%j =w copy 0
@outer
	%i2 =w phi @start %i, @oend %i3
	%j2 =w phi @start %j, @oend %j3
	%c =w csltw %i2, %n
	jnz %c, @inner, @done
@inner
	%jm =w sub %n, %i2
	%jm2 =w sub %jm, 1
	%c2 =w csltw %j2, %jm2
	jnz %c2, @cmp, @oend
@cmp
	%ji =l extsw %j2
	%joff =l mul 4, %ji
	%jp =l add $arr, %joff
	%a =w load %jp
	%j1 =w add %j2, 1
	%j1i =l extsw %j1
	%j1off =l mul 4, %j1i
	%j1p =l add $arr, %j1off
	%b =w load %j1p
	%c3 =w csgtw %a, %b
	jnz %c3, @swap, @oend
@swap
	storew %b, %jp
	storew %a, %j1p
	jmp @oend
@oend
	%j3 =w add %j2, 1
	%i3 =w add %i2, 1
	jmp @outer
@done
	ret 0
}
""")

PROGRAMS["binary_search"] = wrap(
    "binary search in a sorted array of longs",
    """data $arr = { l 10, l 20, l 30, l 40, l 50, l 60 }
export
function w $search(l %key, w %n) {
@start
	%lo =w copy 0
	%hi =w sub %n, 1
@loop
	%lo2 =w phi @start %lo, @go_lo %lo3, @go_hi %lo4
	%hi2 =w phi @start %hi, @go_lo %hi3, @go_hi %hi4
	%c =w csgtw %lo2, %hi2
	jnz %c, @notfound, @body
@body
	%sum =w add %lo2, %hi2
	%mid =w shr %sum, 1
	%midi =l extsw %mid
	%moff =l mul 8, %midi
	%mp =l add $arr, %moff
	%mv =l load %mp
	%c2 =l ceql %mv, %key
	jnz %c2, @found, @less
@less
	%c3 =l csgtl %mv, %key
	jnz %c3, @go_lo, @go_hi
@go_lo
	%hi3 =w sub %mid, 1
	%lo3 =w copy %lo2
	jmp @loop
@go_hi
	%lo4 =w add %mid, 1
	%hi4 =w copy %hi2
	jmp @loop
@found
	ret %mid
@notfound
	ret -1
}
""")

PROGRAMS["count_bits"] = wrap(
    "population count (number of set bits)",
    """export
function w $pop(w %x) {
@start
	%c =w copy 0
	%v =w copy %x
@loop
	%c2 =w phi @start %c, @loop %c3
	%v2 =w phi @start %v, @loop %v3
	%test =w ceqw %v2, 0
	jnz %test, @done, @body
@body
	%bit =w and %v2, 1
	%c3 =w add %c2, %bit
	%v3 =w shr %v2, 1
	jmp @loop
@done
	ret %c2
}
""")

PROGRAMS["reverse_bits"] = wrap(
    "reverse the 32 bits of a word",
    """export
function w $revb(w %x) {
@start
	%r =w copy 0
	%i =w copy 0
	%xv =w copy %x
@loop
	%r2 =w phi @start %r, @loop %r3
	%i2 =w phi @start %i, @loop %i3
	%x2 =w phi @start %xv, @loop %x3
	%c =w csltw %i2, 32
	jnz %c, @body, @done
@body
	%r3 =w shl %r2, 1
	%bit =w and %x2, 1
	%r3 =w or %r3, %bit
	%x3 =w shr %x2, 1
	%i3 =w add %i2, 1
	jmp @loop
@done
	ret %r2
}
""")

PROGRAMS["lowbit"] = wrap(
    "isolate the lowest set bit: lowbit(12) = 4",
    """export
function w $lb(w %x) {
@start
	%n =w xor %x, -1
	%p =w add %n, 1
	%r =w and %x, %p
	ret %r
}
""")

PROGRAMS["ispow2"] = wrap(
    "test whether a word is a power of two",
    """export
function w $pow2(w %x) {
@start
	%c =w ceqw %x, 0
	jnz %c, @no, @chk
@chk
	%n =w sub %x, 1
	%a =w and %x, %n
	%c2 =w ceqw %a, 0
	jnz %c2, @yes, @no
@yes
	ret 1
@no
	ret 0
}
""")

# --- strings ---

PROGRAMS["str_len"] = wrap(
    "string length",
    """data $s = { b "hello", b 0 }
export
function w $len(l %s) {
@start
	%n =w copy 0
@loop
	%n2 =w phi @start %n, @loop %n3
	%p2 =l phi @start %s, @loop %p3
	%ch =w loadub %p2
	%c =w ceqw %ch, 0
	jnz %c, @done, @body
@body
	%n3 =w add %n2, 1
	%p3 =l add %p2, 1
	jmp @loop
@done
	ret %n2
}
""")

PROGRAMS["str_rev"] = wrap(
    "reverse a string in place",
    """data $s = { b "abcdef", b 0 }
export
function w $rev(l %s) {
@start
	%n =w call $len(l %s)
	%lo =w copy 0
	%hi =w sub %n, 1
@loop
	%lo2 =w phi @start %lo, @loop %lo3
	%hi2 =w phi @start %hi, @loop %hi3
	%c =w csltw %lo2, %hi2
	jnz %c, @body, @done
@body
	%loi =l extsw %lo2
	%lp =l add %s, %loi
	%a =w loadub %lp
	%hii =l extsw %hi2
	%hp =l add %s, %hii
	%b =w loadub %hp
	storeb %b, %lp
	storeb %a, %hp
	%lo3 =w add %lo2, 1
	%hi3 =w sub %hi2, 1
	jmp @loop
@done
	ret 0
}
""")

PROGRAMS["str_find"] = wrap(
    "find first occurrence of a byte in a string",
    """data $s = { b "hello world", b 0 }
export
function l $find(l %s, w %target) {
@start
	%i =l copy 0
@loop
	%i2 =l phi @start %i, @loop %i3
	%p2 =l phi @start %s, @loop %p3
	%ch =w loadub %p2
	%c =w ceqw %ch, 0
	jnz %c, @notfound, @chk
@chk
	%c2 =w ceqw %ch, %target
	jnz %c2, @found, @next
@next
	%i3 =l add %i2, 1
	%p3 =l add %p2, 1
	jmp @loop
@found
	ret %i2
@notfound
	ret -1
}
""")

# --- floats ---

PROGRAMS["fp_sum"] = wrap(
    "sum a run of doubles",
    """export
function d $fsum(w %n) {
@start
	%s =d copy d_0.0
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%s2 =d phi @start %s, @loop %s3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%f =d swtof %i2
	%s3 =d add %s2, %f
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %s2
}
""")

PROGRAMS["fp_avg"] = wrap(
    "average of doubles: (1.5 + 2.5 + 3.5) / 3",
    """export
function d $avg(d %a, d %b, d %c) {
@start
	%s =d add %a, %b
	%s =d add %s, %c
	%r =d div %s, d_3.0
	ret %r
}
""")

PROGRAMS["fp_poly"] = wrap(
    "evaluate a polynomial with float coefficients",
    """export
function d $poly(d %x) {
@start
	%x2 =d mul %x, %x
	%x3 =d mul %x2, %x
	%r =d mul %x3, d_2.0
	%r =d add %r, %x2
	%r =d sub %r, %x
	%r =d add %r, d_1.0
	ret %r
}
""")

PROGRAMS["fp_conv"] = wrap(
    "integer/float conversions mixed in a loop",
    """export
function w $conv(w %n) {
@start
	%sum =w copy 0
	%i =w copy 1
@loop
	%i2 =w phi @start %i, @loop %i3
	%sum2 =w phi @start %sum, @loop %sum3
	%c =w cslew %i2, %n
	jnz %c, @body, @end
@body
	%f =d swtof %i2
	%half =d div %f, d_2.0
	%ri =w dtosi %half
	%sum3 =w add %sum2, %ri
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %sum2
}
""")

# --- recursion / control flow ---

PROGRAMS["ackermann"] = wrap(
    "ackermann(2, 3) exercises deep recursion",
    """export
function w $ack(w %m, w %n) {
@start
	%c =w ceqw %m, 0
	jnz %c, @base, @chk
@base
	%r =w add %n, 1
	ret %r
@chk
	%c2 =w ceqw %n, 0
	jnz %c2, @m0, @both
@m0
	%m1 =w sub %m, 1
	%r1 =w call $ack(w %m1, w 1)
	ret %r1
@both
	%n1 =w sub %n, 1
	%r2 =w call $ack(w %m, w %n1)
	%m2 =w sub %m, 1
	%r3 =w call $ack(w %m2, w %r2)
	ret %r3
}
""")

PROGRAMS["nested_calls"] = wrap(
    "chain of calls with different argument counts",
    """export
function w $f1(w %x) {
@start
	%r =w add %x, 1
	ret %r
}
function w $f2(w %a, w %b) {
@start
	%r =w add %a, %b
	ret %r
}
function w $f3(w %a, w %b, w %c) {
@start
	%r =w add %a, %b
	%r =w add %r, %c
	ret %r
}
export
function w $test(w %n) {
@start
	%a =w call $f1(w %n)
	%b =w call $f2(w %a, w 2)
	%c =w call $f3(w %a, w %b, w 3)
	%r =w add %c, %b
	ret %r
}
""")

PROGRAMS["switch_like"] = wrap(
    "dispatch on a value (chain of comparisons)",
    """export
function w $dispatch(w %x) {
@start
	%c0 =w ceqw %x, 0
	jnz %c0, @zero, @c1
@c1
	%c1c =w ceqw %x, 1
	jnz %c1c, @one, @c2
@c2
	%c2c =w ceqw %x, 2
	jnz %c2c, @two, @many
@zero
	ret 0
@one
	ret 1
@two
	ret 2
@many
	%r =w mul %x, %x
	ret %r
}
""")

PROGRAMS["do_while"] = wrap(
    "do-while style loop (body executes at least once)",
    """export
function w $dowhile(w %n) {
@start
	%sum =w copy 0
	%i =w copy 0
@body
	%i2 =w phi @start %i, @loop %i3
	%sum2 =w phi @start %sum, @loop %sum3
	%sum3 =w add %sum2, %i2
	%i3 =w add %i2, 1
@loop
	%c =w csltw %i3, %n
	jnz %c, @body, @done
@done
	ret %sum3
}
""")

PROGRAMS["triple_nest"] = wrap(
    "three nested loops",
    """export
function w $triple(w %n) {
@start
	%i =w copy 0
	%total =w copy 0
@l1
	%i2 =w phi @start %i, @l1c %i3
	%t1 =w phi @start %total, @l1c %t1c
	%c1 =w csltw %i2, %n
	jnz %c1, @l2, @done
@l2
	%j =w phi @l1 0, @l2c %j3
	%t2 =w phi @l1 %t1, @l2c %t2c
	%c2 =w csltw %j, %n
	jnz %c2, @l3, @l1c
@l3
	%k =w phi @l2 0, @l3 %k3
	%t3 =w phi @l2 %t2, @l3 %t3c
	%c3 =w csltw %k, %n
	jnz %c3, @body, @l2c
@body
	%t3c =w add %t3, 1
	%k3 =w add %k, 1
	jmp @l3
@l2c
	%j3 =w add %j, 1
	%t2c =w copy %t3
	jmp @l2
@l1c
	%i3 =w add %i2, 1
	%t1c =w copy %t2
	jmp @l1
@done
	ret %t1
}
""")

# --- misc computations ---

PROGRAMS["collatz_len"] = wrap(
    "length of the collatz sequence for n",
    """export
function w $clen(w %n) {
@start
	%len =w copy 1
	%v =w copy %n
@loop
	%v2 =w phi @start %v, @join %v3
	%len2 =w phi @start %len, @join %len3
	%c =w ceqw %v2, 1
	jnz %c, @done, @body
@body
	%odd =w and %v2, 1
	%c2 =w ceqw %odd, 0
	jnz %c2, @even, @odd
@even
	%ve =w shr %v2, 1
	jmp @join
@odd
	%vo =w mul %v2, 3
	%vo =w add %vo, 1
	jmp @join
@join
	%v3 =w phi @even %ve, @odd %vo
	%len3 =w add %len2, 1
	jmp @loop
@done
	ret %len2
}
""")

PROGRAMS["collatz_max"] = wrap(
    "longest collatz sequence under n",
    """export
function w $cmax(w %n) {
@start
	%best =w copy 0
	%bestn =w copy 0
	%i =w copy 1
@loop
	%i2 =w phi @start %i, @loop %i3
	%best2 =w phi @start %best, @loop %best3
	%bestn2 =w phi @start %bestn, @loop %bestn3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%len =w call $clen(w %i2)
	%c2 =w csgtw %len, %best2
	jnz %c2, @new, @skip
@new
	%bn =w copy %len
	%bnn =w copy %i2
	jmp @join
@skip
	%bn =w copy %best2
	%bnn =w copy %bestn2
	jmp @join
@join
	%best3 =w phi @new %bn, @skip %bn
	%bestn3 =w phi @new %bnn, @skip %bnn
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %bestn2
}
""")

PROGRAMS["fizzbuzz"] = wrap(
    "sum of multiples of 3 or 5 below n",
    """export
function w $fizz(w %n) {
@start
	%sum =w copy 0
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%sum2 =w phi @start %sum, @loop %sum3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%m3 =w rem %i2, 3
	%m5 =w rem %i2, 5
	%c3 =w ceqw %m3, 0
	%c5 =w ceqw %m5, 0
	%m =w or %c3, %c5
	jnz %m, @add, @skip
@add
	%sa =w add %sum2, %i2
	jmp @join
@skip
	%ss =w copy %sum2
	jmp @join
@join
	%sum3 =w phi @add %sa, @skip %ss
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %sum2
}
""")

PROGRAMS["pi_approx"] = wrap(
    "approximate pi via a series: 4*(1 - 1/3 + 1/5 - ...)",
    """export
function d $pi(w %n) {
@start
	%s =d copy d_0.0
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%s2 =d phi @start %s, @loop %s3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%t =w shl %i2, 1
	%t =w add %t, 1
	%tf =d swtof %t
	%term =d div d_1.0, %tf
	%even =w and %i2, 1
	%c2 =w ceqw %even, 0
	jnz %c2, @add, @sub
@add
	%sa =d add %s2, %term
	jmp @join
@sub
	%sb =d sub %s2, %term
	jmp @join
@join
	%s3 =d phi @add %sa, @sub %sb
	%i3 =w add %i2, 1
	jmp @loop
@end
	%r =d mul %s2, d_4.0
	ret %r
}
""")

PROGRAMS["poly_eval"] = wrap(
    "evaluate an array as polynomial coefficients: 1 + 2x + 3x^2 at x=2 = 17",
    """data $c = { w 1, w 2, w 3 }
export
function w $peval(w %x, w %n) {
@start
	%acc =w copy 0
	%pow =w copy 1
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%acc2 =w phi @start %acc, @loop %acc3
	%pow2 =w phi @start %pow, @loop %pow3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%idx =l extsw %i2
	%off =l mul 4, %idx
	%p =l add $c, %off
	%coef =w load %p
	%term =w mul %coef, %pow2
	%acc3 =w add %acc2, %term
	%pow3 =w mul %pow2, %x
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %acc2
}
""")

PROGRAMS["rot13"] = wrap(
    "rot13 on a string in place",
    """data $s = { b "nopqrstuvwxyz", b 0 }
export
function w $rot13(l %s) {
@start
	%p =l copy %s
@loop
	%p2 =l phi @start %p, @next %p3
	%ch =w loadub %p2
	%c =w ceqw %ch, 0
	jnz %c, @done, @chk
@chk
	%c2 =w csgew %ch, 97
	jnz %c2, @islow, @next
@islow
	%c3 =w cslew %ch, 122
	jnz %c3, @rot, @next
@rot
	%nc =w add %ch, 13
	%c4 =w csgtw %nc, 122
	jnz %c4, @wrap, @store
@wrap
	%nw =w sub %nc, 26
	jmp @store
@store
	%ns =w phi @rot %nc, @wrap %nw
	storeb %ns, %p2
	jmp @next
@next
	%p3 =l add %p2, 1
	jmp @loop
@done
	ret 0
}
""")

PROGRAMS["bitcount_arr"] = wrap(
    "count total set bits across an array",
    """data $arr = { w 1, w 2, w 3, w 4, w 5, w 6, w 7 }
export
function w $total(w %n) {
@start
	%total =w copy 0
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%total2 =w phi @start %total, @loop %total3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%idx =l extsw %i2
	%off =l mul 4, %idx
	%p =l add $arr, %off
	%v =w load %p
	%b =w call $pop(w %v)
	%total3 =w add %total2, %b
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %total2
}
""")

PROGRAMS["mean_var"] = wrap(
    "mean of an array of doubles (truncated to int)",
    """data $arr = { d 4607182418800017408, d 4611686018427387904, d 4613937818241073152, d 4616189618054758400 }
export
function w $stats(w %n) {
@start
	%sum =d copy d_0.0
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%sum2 =d phi @start %sum, @loop %sum3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%idx =l extsw %i2
	%off =l mul 8, %idx
	%p =l add $arr, %off
	%v =d load %p
	%sum3 =d add %sum2, %v
	%i3 =w add %i2, 1
	jmp @loop
@end
	%mean =d div %sum2, d_4.0
	%mi =w dtosi %mean
	ret %mi
}
""")

PROGRAMS["conway"] = wrap(
    "next generation of a 1-d cellular automaton bitmask",
    """export
function w $next(w %x) {
@start
	%r =w copy 0
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%r2 =w phi @start %r, @loop %r3
	%c =w csltw %i2, 30
	jnz %c, @body, @end
@body
	%sh =w shl 1, %i2
	%l =w sub %i2, 1
	%rsh =w shl 1, %l
	%left =w and %x, %rsh
	%right =w and %x, %rsh
	%mid =w and %x, %sh
	%lr =w or %left, %mid
	%lr =w or %lr, %right
	%c2 =w ceqw %lr, %sh
	jnz %c2, @set, @no
@set
	%rs =w or %r2, %sh
	jmp @join
@no
	%rn =w copy %r2
	jmp @join
@join
	%r3 =w phi @set %rs, @no %rn
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %r2
}
""")

PROGRAMS["bound_check"] = wrap(
    "index bounds check helper then read",
    """data $arr = { w 10, w 20, w 30 }
export
function w $get(l %arr, w %idx, w %n) {
@start
	%c =w cugew %idx, %n
	jnz %c, @out, @ok
@ok
	%i =l extsw %idx
	%off =l mul 4, %i
	%p =l add %arr, %off
	%v =w load %p
	ret %v
@out
	ret -1
}
""")

PROGRAMS["sum_nat"] = wrap(
    "sum of naturals via a loop",
    """export
function l $sumnat(l %n) {
@start
	%sum =l copy 0
	%i =l copy 1
@loop
	%i2 =l phi @start %i, @loop %i3
	%sum2 =l phi @start %sum, @loop %sum3
	%c =l csgtl %i2, %n
	jnz %c, @done, @body
@body
	%sum3 =l add %sum2, %i2
	%i3 =l add %i2, 1
	jmp @loop
@done
	ret %sum2
}
""")

PROGRAMS["sqroot"] = wrap(
    "integer square root by Newton's method",
    """export
function w $isqrt(w %n) {
@start
	%x =w copy %n
	%y =w copy %n
@loop
	%x2 =w phi @start %x, @loop %x3
	%y2 =w phi @start %y, @loop %y3
	%c =w csgtw %x2, %y2
	jnz %c, @done, @body
@body
	%y3 =w copy %x2
	%q =w div %n, %x2
	%x3 =w add %x2, %q
	%x3 =w shr %x3, 1
	jmp @loop
@done
	ret %y2
}
""")

PROGRAMS["sum_odd_sq"] = wrap(
    "sum of odd squares up to n",
    """export
function l $sos(l %n) {
@start
	%sum =l copy 0
	%i =l copy 1
@loop
	%i2 =l phi @start %i, @loop %i3
	%sum2 =l phi @start %sum, @loop %sum3
	%c =l csgtl %i2, %n
	jnz %c, @done, @body
@body
	%sq =l mul %i2, %i2
	%sum3 =l add %sum2, %sq
	%i3 =l add %i2, 2
	jmp @loop
@done
	ret %sum2
}
""")

PROGRAMS["array2d"] = wrap(
    "index a 4x4 matrix stored as a flat array",
    """data $mat = { w 1, w 2, w 3, w 4, w 5, w 6, w 7, w 8, w 9, w 10, w 11, w 12, w 13, w 14, w 15, w 16 }
export
function w $at(w %r, w %c) {
@start
	%row =w mul %r, 4
	%idx =w add %row, %c
	%i =l extsw %idx
	%off =l mul 4, %i
	%p =l add $mat, %off
	%v =w load %p
	ret %v
}
""")

PROGRAMS["interleave"] = wrap(
    "merge two sorted runs (sum the smaller of each pair)",
    """data $a = { w 1, w 3, w 5 }
data $b = { w 2, w 4, w 6 }
export
function w $merge(w %n) {
@start
	%total =w copy 0
	%i =w copy 0
@loop
	%i2 =w phi @start %i, @loop %i3
	%t2 =w phi @start %total, @loop %t3
	%c =w csltw %i2, %n
	jnz %c, @body, @end
@body
	%ia =l extsw %i2
	%oa =l mul 4, %ia
	%pa =l add $a, %oa
	%va =w load %pa
	%ib =l extsw %i2
	%ob =l mul 4, %ib
	%pb =l add $b, %ob
	%vb =w load %pb
	%c2 =w csgtw %va, %vb
	jnz %c2, @b, @a
@a
	%ta =w add %t2, %va
	jmp @join
@b
	%tb =w add %t2, %vb
	jmp @join
@join
	%t3 =w phi @a %ta, @b %tb
	%i3 =w add %i2, 1
	jmp @loop
@end
	ret %t2
}
""")

PROGRAMS["mod_pow"] = wrap(
    "modular exponentiation: (base^exp) mod m",
    """export
function w $mpow(w %b, w %e, w %m) {
@start
	%r =w copy 1
	%be =w copy %b
	%ee =w copy %e
@loop
	%r2 =w phi @start %r, @join %r4
	%be2 =w phi @start %be, @join %be3
	%ee2 =w phi @start %ee, @join %ee3
	%c =w ceqw %ee2, 0
	jnz %c, @done, @body
@body
	%odd =w and %ee2, 1
	%c2 =w ceqw %odd, 0
	jnz %c2, @skip, @mul
@mul
	%rm =w mul %r2, %be2
	%rm =w rem %rm, %m
	%rm =w copy %rm
	jmp @join
@skip
	%rs =w copy %r2
	jmp @join
@join
	%r4 =w phi @mul %rm, @skip %rs
	%bm =w mul %be2, %be2
	%be3 =w rem %bm, %m
	%ee3 =w shr %ee2, 1
	jmp @loop
@done
	ret %r2
}
""")

PROGRAMS["is_palindrome_num"] = wrap(
    "palindrome test for a decimal number",
    """export
function w $palin(w %n) {
@start
	%rev =w copy 0
	%t =w copy %n
@loop
	%rev2 =w phi @start %rev, @loop %rev3
	%t2 =w phi @start %t, @loop %t3
	%c =w ceqw %t2, 0
	jnz %c, @chk, @body
@body
	%d =w rem %t2, 10
	%rev3 =w mul %rev2, 10
	%rev3 =w add %rev3, %d
	%t3 =w div %t2, 10
	jmp @loop
@chk
	%c2 =w ceqw %rev2, %n
	jnz %c2, @yes, @no
@yes
	ret 1
@no
	ret 0
}
""")

PROGRAMS["abs_diff"] = wrap(
    "absolute difference via branches",
    """export
function w $adiff(w %a, w %b) {
@start
	%c =w csgtw %a, %b
	jnz %c, @ab, @ba
@ab
	%r =w sub %a, %b
	ret %r
@ba
	%r =w sub %b, %a
	ret %r
}
""")

PROGRAMS["min_max"] = wrap(
    "return max*100 + min",
    """export
function w $minmax(w %a, w %b) {
@start
	%c =w csgtw %a, %b
	jnz %c, @ab, @ba
@ab
	%mx =w copy %a
	%mn =w copy %b
	jmp @join
@ba
	%mx =w copy %b
	%mn =w copy %a
	jmp @join
@join
	%max =w phi @ab %mx, @ba %mx
	%min =w phi @ab %mn, @ba %mn
	%m =w mul %max, 100
	%r =w add %m, %min
	ret %r
}
""")

PROGRAMS["clamp"] = wrap(
    "clamp a value to [lo, hi]",
    """export
function w $clamp(w %x, w %lo, w %hi) {
@start
	%c1 =w csltw %x, %lo
	jnz %c1, @lo, @c2
@c2
	%c2c =w csgtw %x, %hi
	jnz %c2c, @hi, @mid
@lo
	ret %lo
@hi
	ret %hi
@mid
	ret %x
}
""")

PROGRAMS["sign"] = wrap(
    "sign function: -1, 0, or 1",
    """export
function w $sign(w %x) {
@start
	%c0 =w ceqw %x, 0
	jnz %c0, @zero, @cpos
@cpos
	%c =w csgtw %x, 0
	jnz %c, @pos, @neg
@zero
	ret 0
@pos
	ret 1
@neg
	ret -1
}
""")

PROGRAMS["leap"] = wrap(
    "leap year test",
    """export
function w $leap(w %y) {
@start
	%m4 =w rem %y, 4
	%c4 =w ceqw %m4, 0
	jnz %c4, @by4, @no
@by4
	%m100 =w rem %y, 100
	%c100 =w ceqw %m100, 0
	jnz %c100, @by100, @yes
@by100
	%m400 =w rem %y, 400
	%c400 =w ceqw %m400, 0
	jnz %c400, @yes, @no
@yes
	ret 1
@no
	ret 0
}
""")

PROGRAMS["days_in_month"] = wrap(
    "days in a month (1-12)",
    """export
function w $days(w %m, w %y) {
@start
	%c =w ceqw %m, 2
	jnz %c, @feb, @big
@feb
	%le =w call $leap(w %y)
	%c2 =w ceqw %le, 1
	jnz %c2, @leap29, @feb28
@leap29
	ret 29
@feb28
	ret 28
@big
	%c30 =w ceqw %m, 4
	%c31 =w ceqw %m, 6
	%c32 =w ceqw %m, 9
	%c33 =w ceqw %m, 11
	%c30 =w or %c30, %c31
	%c30 =w or %c30, %c32
	%c30 =w or %c30, %c33
	jnz %c30, @ret30, @ret31
@ret30
	ret 30
@ret31
	ret 31
}
""")

PROGRAMS["byte_swap"] = wrap(
    "byte swap a 32-bit word",
    """export
function w $bswap(w %x) {
@start
	%b0 =w and %x, 255
	%sh0 =w shl %b0, 24
	%b1 =w shr %x, 8
	%b1 =w and %b1, 255
	%sh1 =w shl %b1, 16
	%b2 =w shr %x, 16
	%b2 =w and %b2, 255
	%sh2 =w shl %b2, 8
	%b3 =w shr %x, 24
	%r =w or %sh0, %sh1
	%r =w or %r, %sh2
	%r =w or %r, %b3
	ret %r
}
""")

PROGRAMS["gray"] = wrap(
    "gray code: n xor (n >> 1)",
    """export
function w $gray(w %n) {
@start
	%s =w shr %n, 1
	%r =w xor %n, %s
	ret %r
}
""")

PROGRAMS["tower"] = wrap(
    "tower of hanoi move count: 2^d - 1",
    """export
function w $hanoi(w %d) {
@start
	%r =w shl 1, %d
	%r =w sub %r, 1
	ret %r
}
""")

PROGRAMS["byte_swap"] = PROGRAMS["byte_swap"]

PROGRAMS["abs_diff"] = PROGRAMS["abs_diff"]


if __name__ == "__main__":
    main()
