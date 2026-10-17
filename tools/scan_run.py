import os, re, subprocess, collections
ROOT = "/Users/Admin/Desktop/qbe.mbt"; BASE = ROOT + "/build/scan"; CC = "/usr/bin/clang"
rows = [l.rstrip(chr(10)).split(chr(9)) for l in open(BASE + "/detail_new.tsv")]
ok = {}
for p, f, s, res, d in rows: ok.setdefault(p, []).append((f, s))
MAIN = {"bzip2":"bzip2.c","dash":"main.c","farbfeld":"ff2pam.c","ii":"ii.c","lua":"lua.c",
        "sic":"sic.c","slstatus":"slstatus.c","lz4":"lz4cli.c","lchat":"lchat.c",
        "abduco":"abduco.c","smu":"smu.c"}
Q = chr(34)
LIB = {
 "cjson": ("cJSON.c", ["#include <stdio.h>", "#include " + Q + "cJSON.h" + Q, "int main(void){",
   "  cJSON *j = cJSON_Parse(" + Q + "{" + Q + "a" + Q + ":" + Q + "42}" + Q + ");",
   "  if (!j) return 1;", "  cJSON *a = cJSON_GetObjectItem(j, " + Q + "a" + Q + ");",
   "  printf(" + Q + "%d" + Q + ", a ? a->valueint : -1);", "  cJSON_Delete(j); return a ? 0 : 2; }"]),
 "yyjson": ("yyjson.c", ["#include <stdio.h>", "#include " + Q + "yyjson.h" + Q, "int main(void){",
   "  yyjson_doc *d = yyjson_read(" + Q + "{" + Q + "a" + Q + ":42}" + Q + ", 9, 0);",
   "  if (!d) return 1;", "  yyjson_val *v = yyjson_obj_get(yyjson_doc_get_root(d), " + Q + "a" + Q + ");",
   "  printf(" + Q + "%lld" + Q + ", (long long)yyjson_get_sint(v));", "  yyjson_doc_free(d); return 0; }"]),
 "zlib": ("crc32.c", ["#include <stdio.h>", "#include " + Q + "zlib.h" + Q, "int main(void){",
   "  unsigned char b[16]; int i; for (i = 0; i < 16; i++) b[i] = (unsigned char)i;",
   "  printf(" + Q + "%lu" + Q + ", (unsigned long)crc32(0L, b, 16)); return 0; }"]),
}
def path_of(p, f):
    for dp, dirs, files in os.walk(BASE + "/raw/" + p):
        dirs[:] = [d for d in dirs if d != ".git"]
        if f in files: return os.path.join(dp, f)
    return None
def obj(p, f): return BASE + "/o/" + p + "__" + f[:-2] + ".o"
def has_main(p, f):
    s = path_of(p, f)
    if not s: return False
    try: return bool(re.search(r"^\s*(int|void)\s+main\s*\(", open(s, errors="ignore").read(), re.M))
    except Exception: return False

res = []
for p in ["abduco","bzip2","cjson","dash","farbfeld","hiredis","ii","lchat","lua","lz4","miniz","sic","slstatus","smu","sqlite","yyjson","zlib"]:
    got = dict(ok.get(p, [])); names = list(got)
    if p in MAIN:
        m = MAIN[p]
        if got.get(m) != "OK":
            res.append((p, "NO-COMPILE", m, "")); continue
        objs = [obj(p, f) for f in names if got[f] == "OK" and f != m and os.path.exists(obj(p, f)) and not has_main(p, f)]
        exe = BASE + "/tmp/" + p + ".exe"
        r = subprocess.run([CC] + objs + [obj(p, m)] + ["-lm", "-o", exe], capture_output=True, text=True)
        if r.returncode:
            err = [l for l in r.stderr.splitlines() if "Undefined" in l or "duplicate" in l or "reference" in l]
            res.append((p, "LINK-FAIL", m, (err[0][:60] if err else "?"))); continue
        try:
            q = subprocess.run([exe], capture_output=True, text=True, timeout=20, input="")
            res.append((p, "RUNS" if q.returncode < 128 else "CRASH", m, "rc=%d %s" % (q.returncode, (q.stdout.strip().splitlines() or [""])[0][:28])))
        except subprocess.TimeoutExpired: res.append((p, "HANG", m, ""))
    elif p in LIB:
        base, src_lines = LIB[p]
        if got.get(base) != "OK":
            res.append((p, "NO-COMPILE", base, "")); continue
        d = BASE + "/tmp/drv_" + p + ".c"; open(d, "w").write(chr(10).join(src_lines))
        sd = os.path.dirname(path_of(p, base))
        objs = [obj(p, f) for f in names if got[f] == "OK" and not has_main(p, f) and os.path.exists(obj(p, f))]
        exe = BASE + "/tmp/" + p + ".exe"
        r = subprocess.run([CC, d, "-I", sd] + objs + ["-lm", "-o", exe], capture_output=True, text=True)
        if r.returncode:
            err = [l for l in r.stderr.splitlines() if "Undefined" in l or "reference" in l]
            res.append((p, "LIB-LINK-FAIL", base, (err[0][:60] if err else r.stderr.strip().splitlines()[-1][:60]))); continue
        q = subprocess.run([exe], capture_output=True, text=True, timeout=20)
        res.append((p, "RUNS-DRIVER" if q.returncode < 128 else "CRASH", base, "rc=%d %s" % (q.returncode, (q.stdout.strip().splitlines() or [""])[0][:28])))
    else:
        res.append((p, "NO-MAIN", "-", ""))
with open(BASE + "/run.tsv", "w") as fh:
    for r in res: fh.write(chr(9).join(r) + chr(10))
for r in res: print("  %-10s %-14s %-12s %s" % r)
print(); print(dict(collections.Counter(r[1] for r in res)))