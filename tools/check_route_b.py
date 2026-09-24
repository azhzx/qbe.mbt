#!/usr/bin/env python3
"""Route B differential: compare the *machine code* emitted by qbe.mbt's
self-contained arm64 object writer (compile_arm64_object) with clang's
assembly of the route A text emitter (which is byte-identical to the frozen
reference QBE). Only intra-__text BRANCH26 relocations are applied, because
clang resolves same-section calls while route B records them as relocations;
everything else (global addresses, external calls) is left at 0 by both.

Usage: python tools/check_route_b.py [--limit N] [file.ssa ...]
"""
import glob, os, struct, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MINE = os.path.join(ROOT, "_build/native/debug/build/cmd/main/main.exe")
TESTDIR = os.path.join(ROOT, "test")

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2


def parse_macho(path):
    data = open(path, "rb").read()
    (magic,) = struct.unpack_from("<I", data, 0)
    if magic != MH_MAGIC_64:
        raise ValueError("not Mach-O 64: %s" % path)
    (ncmds,) = struct.unpack_from("<I", data, 16)
    off = 32
    sections = []
    symtab = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == LC_SEGMENT_64:
            (nsects,) = struct.unpack_from("<I", data, off + 64)
            so = off + 72
            for _ in range(nsects):
                name = data[so : so + 16].split(b"\0")[0].decode()
                (size,) = struct.unpack_from("<Q", data, so + 40)
                (secoff,) = struct.unpack_from("<I", data, so + 48)
                (reloff,) = struct.unpack_from("<I", data, so + 56)
                (nreloc,) = struct.unpack_from("<I", data, so + 60)
                sections.append(
                    dict(
                        name=name,
                        size=size,
                        offset=secoff,
                        reloff=reloff,
                        nreloc=nreloc,
                        index=len(sections) + 1,
                    )
                )
                so += 80
        elif cmd == LC_SYMTAB:
            symoff, nsyms, stroff, _ = struct.unpack_from("<IIII", data, off + 8)
            symtab = (symoff, nsyms, stroff)
        off += cmdsize
    syms = []
    if symtab:
        symoff, nsyms, stroff = symtab
        for i in range(nsyms):
            base = symoff + i * 16
            (n_strx,) = struct.unpack_from("<I", data, base)
            n_type = data[base + 4]
            n_sect = data[base + 5]
            (n_value,) = struct.unpack_from("<Q", data, base + 8)
            end = data.index(b"\0", stroff + n_strx)
            name = data[stroff + n_strx : end].decode()
            syms.append(dict(name=name, type=n_type, sect=n_sect, value=n_value))
    for s in sections:
        s["data"] = bytearray(data[s["offset"] : s["offset"] + s["size"]])
        s["relocs"] = []
        for i in range(s["nreloc"]):
            base = s["reloff"] + i * 8
            (r_address,) = struct.unpack_from("<i", data, base)
            (r_info,) = struct.unpack_from("<I", data, base + 4)
            s["relocs"].append(
                dict(
                    address=r_address,
                    sym=r_info & 0xFFFFFF,
                    pcrel=(r_info >> 24) & 1,
                    length=(r_info >> 25) & 3,
                    extern=(r_info >> 27) & 1,
                    rtype=(r_info >> 28) & 0xF,
                )
            )
    return sections, syms


def apply_intra_text_branches(sections, syms):
    text = next(s for s in sections if s["name"] == "__text")
    for r in text["relocs"]:
        if r["rtype"] != 2 or not r["extern"] or r["sym"] >= len(syms):
            continue
        sym = syms[r["sym"]]
        if sym["sect"] != text["index"]:
            continue
        off = r["address"]
        target = sym["value"]
        pc = off
        (word,) = struct.unpack_from("<I", text["data"], off)
        imm = (target - pc) >> 2
        word = (word & 0xFC000000) | (imm & 0x03FFFFFF)
        struct.pack_into("<I", text["data"], off, word)


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, **kw)


def main():
    args = sys.argv[1:]
    limit = None
    if "--limit" in args:
        i = args.index("--limit")
        limit = int(args[i + 1])
        args = args[:i] + args[i + 2:]
    files = args or sorted(
        f
        for f in glob.glob(os.path.join(TESTDIR, "**", "*.ssa"), recursive=True)
        if not os.path.basename(f).startswith("_")
    )
    if limit:
        files = files[:limit]
    passed = skipped = b_err = mism = 0
    errors = []
    for f in files:
        rel = os.path.relpath(f, ROOT)
        ra = run([MINE, "-t", "arm64", "-G", "m", f])
        if ra.returncode != 0 or not ra.stdout:
            skipped += 1
            continue
        with tempfile.TemporaryDirectory() as d:
            s = os.path.join(d, "a.s")
            ao = os.path.join(d, "a.o")
            bo = os.path.join(d, "b.o")
            open(s, "wb").write(ra.stdout)
            if run(["clang", "-c", s, "-o", ao]).returncode != 0:
                skipped += 1
                continue
            rb = run([MINE, "--emit", "obj", "-o", bo, f])
            if rb.returncode != 0 or not os.path.exists(bo):
                b_err += 1
                errors.append((rel, "route B: " + rb.stderr.decode()[:120]))
                continue
            try:
                a_secs, _ = parse_macho(ao)
                b_secs, b_syms = parse_macho(bo)
                apply_intra_text_branches(b_secs, b_syms)
                at = next(s["data"] for s in a_secs if s["name"] == "__text")
                bt = next(s["data"] for s in b_secs if s["name"] == "__text")
            except Exception as e:  # noqa
                b_err += 1
                errors.append((rel, "parse: %s" % e))
                continue
            if bytes(at) == bytes(bt):
                passed += 1
            else:
                mism += 1
                if len(errors) < 12:
                    diff = next(
                        (i for i in range(min(len(at), len(bt))) if at[i] != bt[i]),
                        min(len(at), len(bt)),
                    )
                    errors.append(
                        (
                            rel,
                            "text differs at byte %d/%d (A=%d B=%d)"
                            % (diff, len(at), len(at), len(bt)),
                        )
                    )
    print("route B vs clang __text: pass=%d mismatch=%d routeB-error=%d skipped=%d"
          % (passed, mism, b_err, skipped))
    for rel, msg in errors:
        print("  %-52s %s" % (rel, msg))


if __name__ == "__main__":
    main()
