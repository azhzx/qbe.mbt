#!/usr/bin/env python3
"""Generate the homogeneous test series under test/core/ and test/fold/.

Each generated test is a small self-contained .ssa program that exercises one
specific operation/class/variant. The variants are:

  reg   : operands come from parameters, so the operation survives folding
          and reaches isel/emit (the primary coverage).
  const : operands are constants, so the operation is folded away by fold.c
          (covers constant folding).
  mix   : one constant, one register operand.
  jnz   : the comparison feeds a jnz, covering seljmp / conditional jumps.

Generated files are checked in; this script documents how they were produced.
Run:  python tools/gen_tests.py
"""
import os
import shutil

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TEST = os.path.join(ROOT, "test")

GEN_DIRS = [
    os.path.join(TEST, "core", "arith"),
    os.path.join(TEST, "core", "compare"),
    os.path.join(TEST, "core", "mem"),
    os.path.join(TEST, "core", "conv"),
    os.path.join(TEST, "core", "const"),
    os.path.join(TEST, "fold"),
    os.path.join(TEST, "abi"),
    os.path.join(TEST, "isel"),
    os.path.join(TEST, "regalloc"),
    os.path.join(TEST, "emit"),
]

INT_CMP = ["ceq", "cne", "csge", "csgt", "csle", "cslt", "cuge", "cugt", "cule", "cult"]
FLT_CMP = ["ceq", "cge", "cgt", "cle", "clt", "cne", "co", "cuo"]

ARITH = [
    ("add", "wlsd"),
    ("sub", "wlsd"),
    ("mul", "wlsd"),
    ("div", "wlsd"),
    ("rem", "wl"),
    ("udiv", "wl"),
    ("urem", "wl"),
    ("and", "wl"),
    ("or", "wl"),
    ("xor", "wl"),
    ("sar", "wl"),
    ("shr", "wl"),
    ("shl", "wl"),
]

EXTS = ["extsb", "extub", "extsh", "extuh", "extsw", "extuw"]

# An informative one-line comment describing what the test exercises.
INTENT = {
    "add": "integer/float addition",
    "sub": "integer/float subtraction",
    "mul": "integer/float multiplication",
    "div": "integer/float division",
    "rem": "integer remainder",
    "udiv": "unsigned division",
    "urem": "unsigned remainder",
    "and": "bitwise and",
    "or": "bitwise or",
    "xor": "bitwise xor",
    "sar": "arithmetic shift right",
    "shr": "logical shift right",
    "shl": "shift left",
}


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def func(export, retcls, name, params, body):
    s = ""
    if export:
        s += "export\n"
    s += f"function {retcls} ${name}("
    s += ", ".join(f"{c} %{p}" for c, p in params)
    s += ") {\n"
    s += body
    s += "}\n"
    return s


def op_body(op, cls, a, b):
    return f"@start\n\t%r ={cls} {op} {a}, {b}\n\tret %r\n"


def reg_arith(op, cls):
    return func(True, cls, f"{op}_{cls}_reg", [(cls, "a"), (cls, "b")],
                op_body(op, cls, f"%a", f"%b"))


def const_arith(op, cls, va, vb):
    return func(True, cls, f"{op}_{cls}_const", [],
                op_body(op, cls, str(va), str(vb)))


def mix_arith(op, cls, v):
    return func(True, cls, f"{op}_{cls}_mix", [(cls, "a")],
                op_body(op, cls, str(v), f"%a"))


def cmp_ret(op, cls):
    return func(True, "w", f"{op}_{cls}_ret", [(cls, "a"), (cls, "b")],
                f"@start\n\t%c =w {op} %a, %b\n\tret %c\n")


def cmp_jnz(op, cls):
    return func(True, "w", f"{op}_{cls}_jnz", [(cls, "a"), (cls, "b")],
                f"@start\n\t%c =w {op} %a, %b\n\tjnz %c, @t, @f\n@t\n\tret 1\n@f\n\tret 0\n")


def gen_arith():
    n = 0
    for op, classes in ARITH:
        for cls in classes:
            n += 1
            write(os.path.join(TEST, "core", "arith", f"{n:03d}_{op}_{cls}_reg.ssa"),
                  f"# {INTENT[op]}, class {cls}, register operands (reaches isel/emit)\n\n"
                  + reg_arith(op, cls) + "\n")
            n += 1
            # constant variant with interesting boundary-ish values
            if cls == "w":
                va, vb = 2000000000, 2000000000 if op not in ("div", "rem", "udiv", "urem") else (1000, 7)
            elif cls == "l":
                va, vb = 5000000000, 4000000000
            elif cls == "s":
                va, vb = "s_0.5", "s_1.5"
            else:
                va, vb = "d_0.5", "d_1.5"
            write(os.path.join(TEST, "core", "arith", f"{n:03d}_{op}_{cls}_const.ssa"),
                  f"# {INTENT[op]}, class {cls}, constant operands (constant folded)\n\n"
                  + const_arith(op, cls, va, vb) + "\n")
        # a couple of mixed variants for the common int ops
        if op in ("add", "sub", "mul", "and", "or", "xor", "sar", "shr", "shl"):
            for cls in ("w", "l"):
                n += 1
                v = 2147483647 if cls == "w" else 9223372036854775807
                write(os.path.join(TEST, "core", "arith", f"{n:03d}_{op}_{cls}_mix.ssa"),
                      f"# {INTENT[op]}, class {cls}, one constant one register operand\n\n"
                      + mix_arith(op, cls, v) + "\n")
    return n


def gen_compare():
    n = 0
    for op in INT_CMP:
        for cls in ("w", "l"):
            n += 1
            write(os.path.join(TEST, "core", "compare", f"{n:03d}_{op}_{cls}_ret.ssa"),
                  f"# comparison {op}, class {cls}, result returned (setcc path)\n\n"
                  + cmp_ret(op, cls) + "\n")
            n += 1
            write(os.path.join(TEST, "core", "compare", f"{n:03d}_{op}_{cls}_jnz.ssa"),
                  f"# comparison {op}, class {cls}, feeds jnz (seljmp path)\n\n"
                  + cmp_jnz(op, cls) + "\n")
    for op in FLT_CMP:
        for cls in ("s", "d"):
            n += 1
            write(os.path.join(TEST, "core", "compare", f"{n:03d}_{op}_{cls}_ret.ssa"),
                  f"# float comparison {op}, class {cls}, result returned\n\n"
                  + cmp_ret(op, cls) + "\n")
    return n


def gen_mem():
    n = 0
    # loads
    loads = [("loadsb", "w"), ("loadub", "w"), ("loadsh", "w"), ("loaduh", "w"),
             ("loadsw", "l"), ("loaduw", "w")]
    for op, cls in loads:
        n += 1
        write(os.path.join(TEST, "core", "mem", f"{n:03d}_{op}_ssa"),
              f"# {op} from a parameter address\n\n"
              + func(True, cls, f"{op}", [("l", "a")],
                     f"@start\n\t%r ={cls} {op} %a\n\tret %r\n") + "\n")
    for cls in ("w", "l", "s", "d"):
        n += 1
        write(os.path.join(TEST, "core", "mem", f"{n:03d}_load_{cls}_ssa"),
              f"# generic load, class {cls}\n\n"
              + func(True, cls, f"load_{cls}", [("l", "a")],
                     f"@start\n\t%r ={cls} load %a\n\tret %r\n") + "\n")
    # stores: store then reload from a local alloc
    stores = [("storeb", "w"), ("storeh", "w"), ("storew", "w"), ("storel", "l"),
              ("stores", "s"), ("stored", "d")]
    for op, cls in stores:
        n += 1
        write(os.path.join(TEST, "core", "mem", f"{n:03d}_{op}_ssa"),
              f"# {op} then reload from a local alloc\n\n"
              + func(True, cls, f"{op}", [(cls, "v")],
                     f"@start\n\t%a =l alloc4 16\n\t{op} %v, %a\n\t%r ={cls} load %a\n\tret %r\n") + "\n")
    # addressing: base + constant offset, and base + index * scale
    n += 1
    write(os.path.join(TEST, "core", "mem", f"{n:03d}_addr_offset.ssa"),
          "# store through base + constant offset address\n\n"
          + func(True, "w", "addr_offset", [("w", "v")],
                 f"@start\n\t%a =l alloc4 16\n\t%b =l add 4, %a\n\tstorew %v, %b\n\t%r =w load %b\n\tret %r\n") + "\n")
    n += 1
    write(os.path.join(TEST, "core", "mem", f"{n:03d}_addr_index.ssa"),
          "# store through base + index * 4 address\n\n"
          + func(True, "w", "addr_index", [("w", "v"), ("l", "i")],
                 f"@start\n\t%a =l alloc4 16\n\t%s =l mul 4, %i\n\t%b =l add %a, %s\n\tstorew %v, %b\n\t%r =w load %b\n\tret %r\n") + "\n")
    return n


def gen_conv():
    n = 0
    # integer extensions: (w or l) source -> l result for extsw/extuw, w result otherwise
    for op in EXTS:
        n += 1
        src = "w" if op in ("extsb", "extub", "extsh", "extuh") else ("w" if op == "extsw" else "w")
        dst = "w" if op in ("extsb", "extub", "extsh", "extuh") else "l"
        write(os.path.join(TEST, "core", "conv", f"{n:03d}_{op}.ssa"),
              f"# {op} ({src} -> {dst})\n\n"
              + func(True, dst, f"{op}", [(src, "a")],
                     f"@start\n\t%r ={dst} {op} %a\n\tret %r\n") + "\n")
    convs = [
        ("exts", "s", "d"),
        ("truncd", "d", "s"),
        ("stosi", "s", "w"),
        ("dtosi", "d", "l"),
        ("swtof", "w", "s"),
        ("sltof", "l", "d"),
        ("cast", "d", "l"),
        ("cast", "l", "d"),
    ]
    for op, src, dst in convs:
        n += 1
        write(os.path.join(TEST, "core", "conv", f"{n:03d}_{op}_{src}{dst}.ssa"),
              f"# {op} ({src} -> {dst})\n\n"
              + func(True, dst, f"{op}_{src}{dst}", [(src, "a")],
                     f"@start\n\t%r ={dst} {op} %a\n\tret %r\n") + "\n")
    return n


def gen_const():
    n = 0
    ints = [
        (2147483647, "w"), (-2147483648, "w"),
        (4294967295, "l"), (2147483648, "l"), (-2147483649, "l"),
        (9223372036854775807, "l"), (-9223372036854775808, "l"),
        (2147483647, "l"), (-1, "l"),
    ]
    for v, cls in ints:
        n += 1
        write(os.path.join(TEST, "core", "const", f"{n:03d}_i_{v}_{cls}.ssa"),
              f"# large immediate {v} in class {cls} (noimm path)\n\n"
              + func(True, cls, f"const_{v}", [],
                     f"@start\n\t%r ={cls} copy {v}\n\tret %r\n") + "\n")
    fps = [
        ("d", "d_0.0"), ("d", "d_1.0"), ("d", "d_-1.0"), ("d", "d_0.5"),
        ("d", "d_-0.25"), ("d", "d_3.14159"), ("d", "d_1e9"), ("d", "d_-1e9"),
        ("s", "s_0.0"), ("s", "s_1.0"), ("s", "s_-1.5"), ("s", "s_0.5"),
        ("s", "s_2.71828"), ("s", "s_1e8"), ("s", "s_-1e8"),
    ]
    for cls, lit in fps:
        n += 1
        write(os.path.join(TEST, "core", "const", f"{n:03d}_f_{cls}_{n}.ssa"),
              f"# fp constant {lit} in class {cls}\n\n"
              + func(True, cls, f"fconst_{n}", [],
                     f"@start\n\t%r ={cls} copy {lit}\n\tret %r\n") + "\n")
    return n


def gen_fold():
    n = 0
    # arithmetic fold with overflow wraparound
    cases = [
        ("w", "add", 2000000000, 2000000000),
        ("w", "sub", -2147483648, 1),
        ("w", "mul", 1000000, 1000000),
        ("l", "add", 9223372036854775807, 1),
        ("l", "mul", 3037000500, 3037000500),
        ("w", "and", 0xFFFFFFFF, 0xFFFF0000),
        ("w", "or", 0x0000FFFF, 0xFFFF0000),
        ("w", "xor", 0xAAAAAAAA, 0x55555555),
        ("w", "sar", -16, 2),
        ("w", "shr", -16, 2),
        ("w", "shl", 1, 31),
        ("w", "div", 100, 7),
        ("w", "rem", 100, 7),
        ("w", "udiv", -100, 7),
        ("w", "urem", -100, 7),
        ("d", "add", "d_0.5", "d_1.5"),
        ("d", "mul", "d_2.0", "d_3.0"),
        ("s", "add", "s_1.5", "s_2.5"),
    ]
    for cls, op, va, vb in cases:
        n += 1
        write(os.path.join(TEST, "fold", f"{n:03d}_{op}_{cls}.ssa"),
              f"# constant folding of {op} ({va} op {vb}) in class {cls}\n\n"
              + func(True, cls, f"fold_{op}_{cls}", [],
                     op_body(op, cls, str(va), str(vb))) + "\n")
    # comparison folding
    for op in ("ceqw", "cnew", "csgew", "cultl", "ceqd"):
        n += 1
        cls = "d" if op.endswith("d") else ("l" if op.endswith("l") else "w")
        a, b = ("d_1.0", "d_2.0") if cls == "d" else (1, 2)
        write(os.path.join(TEST, "fold", f"{n:03d}_{op}.ssa"),
              f"# constant folding of comparison {op}\n\n"
              + func(True, "w", f"fold_{op}", [],
                     f"@start\n\t%r =w {op} {a}, {b}\n\tret %r\n") + "\n")
    return n


def gen_abi():
    """Argument passing, returns, aggregates, variadics."""
    n = 0

    # integer arguments 1..8 (6 GPR + stack beyond)
    def int_callee(k):
        params = ", ".join(f"w %a{i}" for i in range(k))
        body = "@start\n\t%r =w add %a0, 0\n"
        for i in range(1, k):
            body += f"\t%r =w add %r, %a{i}\n"
        body += "\tret %r\n"
        return f"export\nfunction w $callee{k}({params}) {{\n{body}}}\n"

    def int_caller(k):
        args = ", ".join(f"w {i+1}" for i in range(k))
        return f"function w $test() {{\n@start\n\t%r =w call $callee{k}({args})\n\tret %r\n}}\n"

    for k in range(1, 9):
        n += 1
        write(os.path.join(TEST, "abi", f"{n:03d}_arg{k}w.ssa"),
              f"# {k} word arguments (6 GPR, the rest on the stack)\n\n" + int_callee(k) + int_caller(k) + "\n")

    # long arguments 1..8
    for k in range(1, 9):
        n += 1
        params = ", ".join(f"l %a{i}" for i in range(k))
        body = "@start\n\t%r =l add %a0, 0\n"
        for i in range(1, k):
            body += f"\t%r =l add %r, %a{i}\n"
        body += "\tret %r\n"
        args = ", ".join(f"l {i+1}" for i in range(k))
        write(os.path.join(TEST, "abi", f"{n:03d}_arg{k}l.ssa"),
              f"# {k} long arguments\n\nexport\nfunction l $callee{k}({params}) {{\n{body}}}\n"
              f"function l $test() {{\n@start\n\t%r =l call $callee{k}({args})\n\tret %r\n}}\n\n")

    # float (double) arguments 1..9 (8 XMM + stack)
    for k in range(1, 10):
        n += 1
        params = ", ".join(f"d %f{i}" for i in range(k))
        body = "@start\n\t%r =d add %f0, d_0.0\n"
        for i in range(1, k):
            body += f"\t%r =d add %r, %f{i}\n"
        body += "\tret %r\n"
        args = ", ".join(f"d d_{i}.5" for i in range(k))
        write(os.path.join(TEST, "abi", f"{n:03d}_arg{k}d.ssa"),
              f"# {k} double arguments (8 XMM, the rest on the stack)\n\nexport\nfunction d $callee{k}({params}) {{\n{body}}}\n"
              f"function d $test() {{\n@start\n\t%r =d call $callee{k}({args})\n\tret %r\n}}\n\n")

    # single float arguments 1..9
    for k in range(1, 10):
        n += 1
        params = ", ".join(f"s %f{i}" for i in range(k))
        body = "@start\n\t%r =s add %f0, s_0.0\n"
        for i in range(1, k):
            body += f"\t%r =s add %r, %f{i}\n"
        body += "\tret %r\n"
        args = ", ".join(f"s s_{i}.5" for i in range(k))
        write(os.path.join(TEST, "abi", f"{n:03d}_arg{k}s.ssa"),
              f"# {k} single arguments\n\nexport\nfunction s $callee{k}({params}) {{\n{body}}}\n"
              f"function s $test() {{\n@start\n\t%r =s call $callee{k}({args})\n\tret %r\n}}\n\n")

    # mixed int/float arguments
    mixed = [
        [("w", "i0"), ("s", "f0")],
        [("d", "f0"), ("l", "i0")],
        [("w", "i0"), ("d", "f0"), ("w", "i1"), ("d", "f1")],
        [("l", "i0"), ("s", "f0"), ("l", "i1"), ("s", "f1"), ("l", "i2"), ("s", "f2")],
        [("d", "f0"), ("w", "i0"), ("d", "f1"), ("w", "i1"), ("d", "f2"), ("w", "i2"),
         ("d", "f3"), ("w", "i3"), ("d", "f4")],
    ]
    for mi in range(len(mixed)):
        n += 1
        sig = mixed[mi]
        params = ", ".join(f"{c} %{v}" for c, v in sig)
        argval = {"w": "1", "l": "2", "s": "s_1.5", "d": "d_2.5"}
        args = ", ".join(f"{c} {argval[c]}" for c, _ in sig)
        write(os.path.join(TEST, "abi", f"{n:03d}_mix{mi}.ssa"),
              f"# mixed int/float arguments: {', '.join(c for c, _ in sig)}\n\n"
              f"export\nfunction w $callee{mi}({params}) {{\n@start\n\t%r =w add 0, 0\n\tret %r\n}}\n"
              f"function w $test() {{\n@start\n\t%r =w call $callee{mi}({args})\n\tret %r\n}}\n\n")

    # aggregate by value (<= 16 bytes: register-passed)
    aggs = [
        ("t4", ":t4 = { w }", ["{ w }", "4"]),
        ("t8", ":t8 = { l }", None),
    ]
    # single-word struct
    n += 1
    write(os.path.join(TEST, "abi", f"{n:03d}_agg_w.ssa"),
          "# 4-byte aggregate passed by value\n\ntype :t4 = { w }\n"
          "export\nfunction w $callee(:t4 %p) {\n@start\n\t%r =w load %p\n\tret %r\n}\n"
          "function w $test() {\n@start\n\t%a =l alloc4 8\n\tstorew 42, %a\n"
          "\t%r =w call $callee(:t4 %a)\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "abi", f"{n:03d}_agg_l.ssa"),
          "# 8-byte aggregate passed by value\n\ntype :t8 = { l }\n"
          "export\nfunction l $callee(:t8 %p) {\n@start\n\t%r =l load %p\n\tret %r\n}\n"
          "function l $test() {\n@start\n\t%a =l alloc8 8\n\tstorel 43, %a\n"
          "\t%r =l call $callee(:t8 %a)\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "abi", f"{n:03d}_agg_w2.ssa"),
          "# two-word aggregate passed by value\n\ntype :t16 = { l, l }\n"
          "export\nfunction l $callee(:t16 %p) {\n@start\n\t%a =l load %p\n\t%b =l load 8(%p)\n"
          "\t%r =l add %a, %b\n\tret %r\n}\n"
          "function l $test() {\n@start\n\t%a =l alloc16 16\n\tstorel 20, %a\n"
          "\t%b =l add 8, %a\n\tstorel 22, %b\n"
          "\t%r =l call $callee(:t16 %a)\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "abi", f"{n:03d}_agg_2s.ssa"),
          "# two-single aggregate passed by value\n\ntype :t8s = { s, s }\n"
          "export\nfunction d $callee(:t8s %p) {\n@start\n\t%a =s load %p\n\t%b =s load 4(%p)\n"
          "\t%r =s add %a, %b\n\t%rd =d exts %r\n\tret %rd\n}\n"
          "function d $test() {\n@start\n\t%a =l alloc8 8\n\tstorew 1065353216, %a\n"
          "\t%b =l add 4, %a\n\tstorew 1073741824, %b\n"
          "\t%r =d call $callee(:t8s %a)\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "abi", f"{n:03d}_agg_2d.ssa"),
          "# two-double aggregate passed by value\n\ntype :t16d = { d, d }\n"
          "export\nfunction d $callee(:t16d %p) {\n@start\n\t%a =d load %p\n\t%b =d load 8(%p)\n"
          "\t%r =d add %a, %b\n\tret %r\n}\n"
          "function d $test() {\n@start\n\t%a =l alloc16 16\n\tstorel 0, %a\n\tstorel 1072693248, 8(%a)\n"
          "\t%r =d call $callee(:t16d %a)\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "abi", f"{n:03d}_agg_mem.ssa"),
          "# 17-byte aggregate passed on the stack\n\ntype :t17 = { b 17 }\n"
          "export\nfunction w $callee(:t17 %p) {\n@start\n\t%r =w loadub %p\n\tret %r\n}\n"
          "function w $test() {\n@start\n\t%a =l alloc4 24\n\tstoreb 77, %a\n"
          "\t%r =w call $callee(:t17 %a)\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "abi", f"{n:03d}_agg_ret_w.ssa"),
          "# 4-byte aggregate returned by value\n\ntype :t4 = { w }\n"
          "export\nfunction :t4 $callee() {\n@start\n\t%a =l alloc4 4\n\tstorew 123, %a\n"
          "\tret %a\n}\n"
          "function w $test() {\n@start\n\t%p =l call $callee()\n\t%r =w load %p\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "abi", f"{n:03d}_agg_ret_16.ssa"),
          "# 16-byte aggregate returned by value\n\ntype :t16 = { l, l }\n"
          "export\nfunction :t16 $callee() {\n@start\n\t%a =l alloc16 16\n\tstorel 10, %a\n"
          "\tstorel 20, 8(%a)\n\tret %a\n}\n"
          "function l $test() {\n@start\n\t%p =l call $callee()\n\t%r =l load 8(%p)\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "abi", f"{n:03d}_agg_ret_mem.ssa"),
          "# large aggregate returned via hidden pointer\n\ntype :t32 = { b 32 }\n"
          "export\nfunction :t32 $callee() {\n@start\n\t%a =l alloc4 40\n\tstoreb 1, %a\n"
          "\t%r =l add 31, %a\n\tstoreb 2, %r\n\tret %a\n}\n"
          "function w $test() {\n@start\n\t%p =l call $callee()\n\t%a =w loadub %p\n"
          "\t%r =l add 31, %p\n\t%b =w loadub %r\n\t%c =w add %a, %b\n\tret %c\n}\n\n")
    return n


def gen_isel():
    """Instruction selection: immediates, addressing, div/shift/alloc cases."""
    n = 0
    # large immediates in arithmetic
    bigs = [
        ("w", "add", 2147483647, 1),
        ("w", "sub", 0, 2147483648),
        ("w", "and", 2147483647, -2147483648),
        ("l", "add", 4294967295, 1),
        ("l", "add", 2147483648, -1),
        ("l", "or", 9223372036854775807, -1),
        ("l", "xor", -2147483648, 9223372036854775807),
        ("w", "mul", 100000, 100000),
        ("l", "mul", 2147483647, 2147483647),
    ]
    for cls, op, a, b in bigs:
        n += 1
        write(os.path.join(TEST, "isel", f"{n:03d}_imm_{op}_{cls}.ssa"),
              f"# large immediate operands in {op} (class {cls})\n\n"
              f"export\nfunction {cls} $test({cls} %x) {{\n@start\n\t%r ={cls} {op} {a}, %x\n\tret %r\n}}\n\n")

    # addressing: base + index * scale with each scale factor
    for scale in (1, 2, 4, 8):
        n += 1
        write(os.path.join(TEST, "isel", f"{n:03d}_addr_scale{scale}.ssa"),
              f"# base + index * {scale} addressing\n\n"
              f"export\nfunction w $test(w %v, l %i) {{\n@start\n\t%a =l alloc16 64\n"
              f"\t%s =l mul {scale}, %i\n\t%b =l add %a, %s\n\tstorew %v, %b\n"
              f"\t%r =w load %b\n\tret %r\n}}\n\n")
    n += 1
    write(os.path.join(TEST, "isel", f"{n:03d}_addr_2d.ssa"),
          "# two-level addressing: base + i*8 + j*4\n\n"
          "export\nfunction w $test(w %v, l %i, l %j) {\n@start\n\t%a =l alloc16 128\n"
          "\t%s =l mul 8, %i\n\t%b =l add %a, %s\n\t%t =l mul 4, %j\n\t%c =l add %b, %t\n"
          "\tstorew %v, %c\n\t%r =w load %c\n\tret %r\n}\n\n")

    # division patterns: constant divisor (fits / large)
    for cls in ("w", "l"):
        for d in (7, 1000000, 2147483648 if cls == "l" else 3):
            n += 1
            write(os.path.join(TEST, "isel", f"{n:03d}_div_c_{cls}_{d}.ssa"),
                  f"# division by constant {d} (class {cls})\n\n"
                  f"export\nfunction {cls} $test({cls} %x) {{\n@start\n\t%r ={cls} div %x, {d}\n\tret %r\n}}\n\n")
    # rem and unsigned
    for cls in ("w", "l"):
        n += 1
        write(os.path.join(TEST, "isel", f"{n:03d}_rem_c_{cls}.ssa"),
              f"# remainder by constant (class {cls})\n\n"
              f"export\nfunction {cls} $test({cls} %x) {{\n@start\n\t%r ={cls} rem %x, 10\n\tret %r\n}}\n\n")
        n += 1
        write(os.path.join(TEST, "isel", f"{n:03d}_udiv_c_{cls}.ssa"),
              f"# unsigned division by constant (class {cls})\n\n"
              f"export\nfunction {cls} $test({cls} %x) {{\n@start\n\t%r ={cls} udiv %x, 3\n\tret %r\n}}\n\n")

    # shift by variable
    for op in ("shl", "shr", "sar"):
        n += 1
        write(os.path.join(TEST, "isel", f"{n:03d}_{op}_var.ssa"),
              f"# {op} by a variable count (routed through rcx)\n\n"
              f"export\nfunction w $test(w %x, w %c) {{\n@start\n\t%r =w {op} %x, %c\n\tret %r\n}}\n\n")

    # allocs: constant sizes (fast allocs)
    for sz in (4, 8, 16, 24, 100):
        n += 1
        write(os.path.join(TEST, "isel", f"{n:03d}_alloc_{sz}.ssa"),
              f"# alloc with constant size {sz}\n\n"
              f"export\nfunction w $test() {{\n@start\n\t%a =l alloc4 {sz}\n\tstorew 9, %a\n"
              f"\t%r =w load %a\n\tret %r\n}}\n\n")

    # dynamic alloc
    n += 1
    write(os.path.join(TEST, "isel", f"{n:03d}_alloc_dyn.ssa"),
          "# alloc with a runtime size (dynamic stack frame)\n\n"
          "export\nfunction l $test(l %n) {\n@start\n\t%a =l alloc4 %n\n\tstorel 9, %a\n"
          "\t%r =l load %a\n\tret %r\n}\n\n")

    # copy of a large immediate into a register (movl trick vs movq)
    n += 1
    write(os.path.join(TEST, "isel", f"{n:03d}_copy_imm_l.ssa"),
          "# copy of long immediates into registers (movl trick for small values)\n\n"
          "export\nfunction l $test() {\n@start\n\t%a =l copy 100\n\t%b =l copy 2147483648\n"
          "\t%c =l copy -1\n\t%r =l add %a, %b\n\t%r =l add %r, %c\n\tret %r\n}\n\n")
    return n


def gen_regalloc():
    """Register allocation: pressure, live ranges, loops, phis, copies."""
    n = 0

    # register pressure: many simultaneously live int temps
    # (qbe's rega dies with "no more regs" above ~12, so stay under it)
    for k in (8, 12):
        n += 1
        body = "@start\n"
        for i in range(k):
            body += f"\t%t{i} =w add %x{i}, 0\n"
        body += "\t%r =w add %t0, %t1\n"
        for i in range(2, k):
            body += f"\t%r =w add %r, %t{i}\n"
        body += "\tret %r\n"
        params = ", ".join(f"w %x{i}" for i in range(k))
        write(os.path.join(TEST, "regalloc", f"{n:03d}_press_w{k}.ssa"),
              f"# {k} simultaneously live word temporaries\n\n"
              f"export\nfunction w $test({params}) {{\n{body}}}\n\n")

    # float pressure
    for k in (8, 12, 14):
        n += 1
        body = "@start\n"
        for i in range(k):
            body += f"\t%t{i} =d add %x{i}, d_0.0\n"
        body += "\t%r =d add %t0, %t1\n"
        for i in range(2, k):
            body += f"\t%r =d add %r, %t{i}\n"
        body += "\tret %r\n"
        params = ", ".join(f"d %x{i}" for i in range(k))
        write(os.path.join(TEST, "regalloc", f"{n:03d}_press_d{k}.ssa"),
              f"# {k} simultaneously live double temporaries\n\n"
              f"export\nfunction d $test({params}) {{\n{body}}}\n\n")

    # long live range across a call (caller-save)
    n += 1
    write(os.path.join(TEST, "regalloc", f"{n:03d}_callersave.ssa"),
          "# values live across a call must survive in callee-save registers\n\n"
          "export\nfunction w $callee(w %x) {\n@start\n\t%r =w add 1, %x\n\tret %r\n}\n"
          "function w $test(w %a, w %b) {\n@start\n\t%x =w add %a, 1\n\t%y =w call $callee(w %b)\n"
          "\t%z =w add %x, %y\n\tret %z\n}\n\n")

    # loop-carried values
    n += 1
    write(os.path.join(TEST, "regalloc", f"{n:03d}_loopcarry.ssa"),
          "# loop-carried values across several live temporaries\n\n"
          "export\nfunction w $test(w %n) {\n@start\n\t%a =w copy 0\n\t%b =w copy 1\n\t%c =w copy 2\n"
          "\t%d =w copy 3\n\t%i =w copy 0\n@loop\n\t%i2 =w phi @start %i, @loop %i3\n"
          "\t%a2 =w phi @start %a, @loop %a3\n\t%b2 =w phi @start %b, @loop %b3\n"
          "\t%c2 =w phi @start %c, @loop %c3\n\t%d2 =w phi @start %d, @loop %d3\n"
          "\t%a3 =w add %a2, %b2\n\t%b3 =w add %b2, %c2\n\t%c3 =w add %c2, %d2\n\t%d3 =w add %d2, 1\n"
          "\t%i3 =w add %i2, 1\n\t%cmp =w csltw %i3, %n\n\tjnz %cmp, @loop, @end\n@end\n"
          "\t%r =w add %a3, %d3\n\tret %r\n}\n\n")

    # dense phis
    n += 1
    write(os.path.join(TEST, "regalloc", f"{n:03d}_phi_many.ssa"),
          "# many phi nodes joining two predecessors\n\n"
          "export\nfunction w $test(w %a, w %b, w %c, w %d) {\n@start\n\t%t =w add %a, 1\n"
          "\tjnz %t, @l, @r\n@l\n\t%la =w add %a, 1\n\t%lb =w add %b, 2\n\t%lc =w add %c, 3\n\t%ld =w add %d, 4\n"
          "\tjmp @join\n@r\n\t%ra =w sub %a, 1\n\t%rb =w sub %b, 2\n\t%rc =w sub %c, 3\n\t%rd =w sub %d, 4\n"
          "\tjmp @join\n@join\n\t%pa =w phi @l %la, @r %ra\n\t%pb =w phi @l %lb, @r %rb\n"
          "\t%pc =w phi @l %lc, @r %rc\n\t%pd =w phi @l %ld, @r %rd\n"
          "\t%r =w add %pa, %pb\n\t%r =w add %r, %pc\n\t%r =w add %r, %pd\n\tret %r\n}\n\n")

    # copy-heavy (parallel moves)
    n += 1
    write(os.path.join(TEST, "regalloc", f"{n:03d}_copy_chain.ssa"),
          "# a chain of copies at a block boundary (parallel move resolution)\n\n"
          "export\nfunction w $test(w %a, w %b, w %c) {\n@start\n\t%x =w add %a, 1\n\t%y =w add %b, 2\n"
          "\t%z =w add %c, 3\n\t%t =w add %x, %y\n\tjnz %t, @l, @r\n@l\n\t%l1 =w copy %x\n\t%l2 =w copy %y\n"
          "\t%l3 =w copy %z\n\t%l4 =w copy %x\n\t%l5 =w copy %y\n\t%l6 =w copy %z\n"
          "\t%l7 =w copy %x\n\t%l8 =w copy %y\n\t%l9 =w copy %z\n\tjmp @join\n@r\n"
          "\t%r1 =w copy %z\n\t%r2 =w copy %y\n\t%r3 =w copy %x\n\t%r4 =w copy %z\n\t%r5 =w copy %y\n"
          "\t%r6 =w copy %x\n\t%r7 =w copy %z\n\t%r8 =w copy %y\n\t%r9 =w copy %x\n\tjmp @join\n@join\n"
          "\t%p1 =w phi @l %l1, @r %r1\n\t%p2 =w phi @l %l2, @r %r2\n\t%p3 =w phi @l %l3, @r %r3\n"
          "\t%p4 =w phi @l %l4, @r %r4\n\t%p5 =w phi @l %l5, @r %r5\n\t%p6 =w phi @l %l6, @r %r6\n"
          "\t%p7 =w phi @l %l7, @r %r7\n\t%p8 =w phi @l %l8, @r %r8\n\t%p9 =w phi @l %l9, @r %r9\n"
          "\t%sum =w add %p1, %p2\n\t%sum =w add %sum, %p3\n\t%sum =w add %sum, %p4\n"
          "\t%sum =w add %sum, %p5\n\t%sum =w add %sum, %p6\n\t%sum =w add %sum, %p7\n"
          "\t%sum =w add %sum, %p8\n\t%sum =w add %sum, %p9\n\tret %sum\n}\n\n")

    # several calls in sequence (caller-save results kept in registers)
    n += 1
    write(os.path.join(TEST, "regalloc", f"{n:03d}_calleesave.ssa"),
          "# several calls in sequence, results kept in registers\n\n"
          "export\nfunction w $callee(w %x) {\n@start\n\t%r =w add 1, %x\n\tret %r\n}\n"
          "function w $test(w %a0, w %a1, w %a2, w %a3) {\n@start\n"
          "\t%r0 =w call $callee(w %a0)\n\t%r1 =w call $callee(w %a1)\n\t%r2 =w call $callee(w %a2)\n"
          "\t%r3 =w call $callee(w %a3)\n"
          "\t%r =w add %r0, %r1\n\t%r =w add %r, %r2\n\t%r =w add %r, %r3\n\tret %r\n}\n\n")

    # mixed int/float pressure
    for k in (6, 10, 14):
        n += 1
        body = "@start\n"
        for i in range(k):
            body += f"\t%ti{i} =w add %xi{i}, 0\n\t%tf{i} =d add %xf{i}, d_0.0\n"
        body += "\t%r =w add %ti0, %ti1\n"
        for i in range(2, k):
            body += f"\t%r =w add %r, %ti{i}\n"
        body += "\t%rd =d add %tf0, %tf1\n"
        for i in range(2, k):
            body += f"\t%rd =d add %rd, %tf{i}\n"
        body += "\t%ri =w dtosi %rd\n\t%r =w add %r, %ri\n\tret %r\n"
        params = ", ".join(f"w %xi{i}" for i in range(k)) + ", " + \
            ", ".join(f"d %xf{i}" for i in range(k))
        write(os.path.join(TEST, "regalloc", f"{n:03d}_press_mix{k}.ssa"),
              f"# {k} words and {k} doubles simultaneously live\n\n"
              f"export\nfunction w $test({params}) {{\n{body}}}\n\n")

    # nested loops
    n += 1
    write(os.path.join(TEST, "regalloc", f"{n:03d}_nest_loop.ssa"),
          "# nested loops with loop-carried accumulators\n\n"
          "export\nfunction w $test(w %n, w %m) {\n@start\n\t%acc =w copy 0\n\t%i =w copy 0\n"
          "@outer\n\t%i2 =w phi @start %i, @outer2 %i4\n\t%ao =w phi @start %acc, @outer2 %ao4\n"
          "\t%j =w copy 0\n@inner\n\t%j2 =w phi @outer %j, @inner %j3\n\t%ai =w phi @outer %ao, @inner %ai3\n"
          "\t%ai3 =w add %ai, 1\n\t%j3 =w add %j2, 1\n\t%jc =w csltw %j3, %m\n\tjnz %jc, @inner, @outer2\n"
          "@outer2\n\t%ao4 =w phi @inner %ai3\n\t%i4 =w add %i2, 1\n"
          "\t%ic =w csltw %i4, %n\n\tjnz %ic, @outer, @end\n@end\n\tret %ao4\n}\n\n")

    # long chain of dependent computations (deep live range)
    n += 1
    write(os.path.join(TEST, "regalloc", f"{n:03d}_chain.ssa"),
          "# a long chain of dependent temporaries\n\n"
          "export\nfunction w $test(w %a, w %b, w %c, w %d) {\n@start\n"
          "\t%t0 =w add %a, %b\n\t%t1 =w mul %c, %d\n\t%t2 =w xor %t0, %t1\n"
          "\t%t3 =w shl %t2, 3\n\t%t4 =w shr %t3, 1\n\t%t5 =w sar %t4, 2\n"
          "\t%t6 =w and %t5, 65535\n\t%t7 =w or %t6, %t1\n\t%t8 =w sub %t7, %t0\n"
          "\t%t9 =w add %t8, %t2\n\t%t10 =w mul %t9, %t4\n\t%t11 =w rem %t10, 1000\n"
          "\t%t12 =w udiv %t11, 7\n\t%t13 =w urem %t12, 13\n\t%t14 =w xor %t13, %t5\n"
          "\t%t15 =w add %t14, %t3\n\t%t16 =w sub %t15, %t1\n\t%t17 =w mul %t16, %t0\n"
          "\tret %t17\n}\n\n")

    # spill stress: values live across many intervening definitions
    for k in (8, 12):
        n += 1
        body = "@start\n"
        for i in range(k):
            body += f"\t%v{i} =w add %x{i}, 0\n"
        # use each value at the very end, interleaving many dead computations
        for i in range(k):
            body += f"\t%t =w add %v{i}, 1\n\t%t =w mul %t, 2\n\t%t =w sub %t, 1\n"
        body += "\t%r =w add %v0, %v1\n"
        for i in range(2, k):
            body += f"\t%r =w add %r, %v{i}\n"
        body += "\tret %r\n"
        params = ", ".join(f"w %x{i}" for i in range(k))
        write(os.path.join(TEST, "regalloc", f"{n:03d}_spill{k}.ssa"),
              f"# {k} values live across many instructions (spill stress)\n\n"
              f"export\nfunction w $test({params}) {{\n{body}}}\n\n")
    return n


def gen_emit():
    """Emission: vararg prologue, dynalloc frame, data sections, -G m."""
    n = 0
    # vararg function prologue (saves arg registers to the frame)
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_vararg_scan.ssa"),
          "# variadic function using vaarg to scan fixed + variadic args\n\n"
          "function w $vf(w %n, ...) {\n@start\n\t%ap =l alloc8 40\n\tvastart %ap\n\t%r =w copy 0\n"
          "\t%i =w copy 0\n@loop\n\t%i2 =w phi @start %i, @body %i3\n\t%r2 =w phi @start %r, @body %r3\n"
          "\t%cmp =w csltw %i2, %n\n\tjnz %cmp, @body, @end\n@body\n\t%v =w vaarg %ap\n"
          "\t%r3 =w add %r2, %v\n\t%i3 =w add %i2, 1\n\tjmp @loop\n@end\n\tret %r2\n}\n"
          "function w $test() {\n@start\n\t%r =w call $vf(w 3, w 1, w 2, w 3)\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_vararg_mixed.ssa"),
          "# variadic with mixed float and int varargs\n\n"
          "function d $vf(w %n, ...) {\n@start\n\t%ap =l alloc8 40\n\tvastart %ap\n\t%r =d copy d_0.0\n"
          "\t%i =w copy 0\n@loop\n\t%i2 =w phi @start %i, @body %i3\n\t%r2 =d phi @start %r, @body %r3\n"
          "\t%cmp =w csltw %i2, %n\n\tjnz %cmp, @body, @end\n@body\n\t%v =d vaarg %ap\n"
          "\t%r3 =d add %r2, %v\n\t%i3 =w add %i2, 1\n\tjmp @loop\n@end\n\tret %r2\n}\n"
          "function d $test() {\n@start\n\t%r =d call $vf(w 2, d d_1.0, d d_2.0)\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_vararg_empty.ssa"),
          "# variadic function with no varargs passed\n\n"
          "function w $vf(w %n, ...) {\n@start\n\t%ap =l alloc8 40\n\tvastart %ap\n\tret %n\n}\n"
          "function w $test() {\n@start\n\t%r =w call $vf(w 7)\n\tret %r\n}\n\n")

    # dynamic alloc frame (mov rbp,rsp + sub)
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_dynalloc.ssa"),
          "# dynamic alloc requires a runtime frame adjustment on return\n\n"
          "export\nfunction l $test(l %n) {\n@start\n\t%a =l alloc4 %n\n\tstorel 1, %a\n"
          "\t%b =l add 8, %a\n\tstorel 2, %b\n\t%r =l load %b\n\tret %r\n}\n\n")

    # data sections: strings, alignment, references
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_data_str.ssa"),
          "# data section with strings and a newline escape\n\n"
          "data $s = { b \"hello\\n\", b 0 }\n"
          "data $s2 = { b \"tab\\there\", b 0 }\n"
          "export\nfunction w $test() {\n@start\n\tret 0\n}\n\n")
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_data_num.ssa"),
          "# data section with numeric constants and zero fill\n\n"
          "data $d = { w 1, w 2, l 3, b 4, h 5 }\n"
          "data $big = { z 16, l 6, l 7 }\n"
          "export\nfunction w $test() {\n@start\n\tret 0\n}\n\n")
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_data_ref.ssa"),
          "# data section referencing another symbol\n\n"
          "data $t = { b 5 }\n"
          "data $r = { l $t, b 0 }\n"
          "export\nfunction w $test() {\n@start\n\tret 0\n}\n\n")
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_data_zero.ssa"),
          "# data section with zero fill\n\n"
          "data $z = { b 1, z 64, b 2 }\n"
          "export\nfunction w $test() {\n@start\n\tret 0\n}\n\n")

    # global variables read/written (rip-relative addressing)
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_global_io.ssa"),
          "# read and write globals (rip-relative addressing)\n\n"
          "data $g1 = { w 1 }\n"
          "data $g2 = { w 0 }\n"
          "export\nfunction w $test() {\n@start\n\t%a =w loadw $g1\n\t%a =w add %a, 1\n"
          "\tstorew %a, $g2\n\t%r =w loadw $g2\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_global_arr.ssa"),
          "# indexing into a global array\n\n"
          "data $arr = { l 10, l 20, l 30, l 40 }\n"
          "export\nfunction l $test(l %i) {\n@start\n\t%s =l mul 8, %i\n\t%p =l add $arr, %s\n"
          "\t%r =l load %p\n\tret %r\n}\n\n")

    # fp constants table (labels, alignment, int words)
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_fp_table.ssa"),
          "# fp constants emitted in the table at the end\n\n"
          "export\nfunction d $test(w %n) {\n@start\n\t%r =d copy d_0.5\n"
          "\t%r =d add %r, d_1.5\n\t%r =d mul %r, d_-2.25\n"
          "\t%i =l extsw %n\n\t%rd =d sltof %i\n\t%r =d add %r, %rd\n\tret %r\n}\n\n")
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_fp_single.ssa"),
          "# single-precision fp constants\n\n"
          "export\nfunction s $test(w %n) {\n@start\n\t%r =s copy s_0.5\n"
          "\t%r =s add %r, s_1.5\n\t%r =s mul %r, s_3.25\n\tret %r\n}\n\n")

    # multiple functions: label id0 counter advances across functions
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_two_funcs.ssa"),
          "# two functions in one file (block labels keep a global counter)\n\n"
          "function w $f1(w %a) {\n@start\n\t%r =w add %a, 1\n\tret %r\n}\n"
          "export\nfunction w $f2(w %a, w %b) {\n@start\n\t%x =w add %a, %b\n"
          "\t%y =w call $f1(w %x)\n\tret %y\n}\n\n")

    # a function with many blocks (label numbering, fall-through jumps)
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_many_blocks.ssa"),
          "# a function with several blocks exercising label/fall-through logic\n\n"
          "export\nfunction w $test(w %n) {\n@start\n\t%i =w copy 0\n"
          "@b0\n\t%i1 =w phi @start %i, @b3 %i2\n\t%a1 =w phi @start 0, @b3 %a3\n"
          "\t%c0 =w ceqw %i1, 0\n\tjnz %c0, @b1, @b2\n@b1\n\t%a2 =w add %a1, 1\n\tjmp @b3\n@b2\n"
          "\t%c1 =w csgtw %i1, %n\n\tjnz %c1, @b4, @b5\n@b4\n\t%a4 =w sub %a1, 1\n\tjmp @b3\n@b5\n"
          "\t%a5 =w add %a1, %n\n\tjmp @b3\n@b3\n\t%a3 =w phi @b1 %a2, @b4 %a4, @b5 %a5\n"
          "\t%i2 =w add %i1, 1\n\t%c2 =w csltw %i2, 10\n\tjnz %c2, @b0, @end\n@end\n\tret %a3\n}\n\n")

    # no export: the symbol is local
    n += 1
    write(os.path.join(TEST, "emit", f"{n:03d}_local_fn.ssa"),
          "# a non-exported function (no .globl)\n\n"
          "function w $helper(w %a) {\n@start\n\t%r =w mul %a, 3\n\tret %r\n}\n"
          "function w $test(w %a) {\n@start\n\t%r =w call $helper(w %a)\n\tret %r\n}\n\n")
    return n


def main():
    # clean the generated directories so renames never leave stale files
    for d in GEN_DIRS:
        if os.path.isdir(d):
            shutil.rmtree(d)
    a = gen_arith()
    c = gen_compare()
    m = gen_mem()
    v = gen_conv()
    k = gen_const()
    f = gen_fold()
    ab = gen_abi()
    i = gen_isel()
    r = gen_regalloc()
    e = gen_emit()
    total = a + c + m + v + k + f + ab + i + r + e
    print(f"arith={a} compare={c} mem={m} conv={v} const={k} fold={f} "
          f"abi={ab} isel={i} regalloc={r} emit={e} total={total}")


if __name__ == "__main__":
    main()
