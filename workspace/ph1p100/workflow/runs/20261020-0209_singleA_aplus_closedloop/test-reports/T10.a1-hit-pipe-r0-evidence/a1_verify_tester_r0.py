import sys, os, json, hashlib, zlib, re, argparse

sys.dont_write_bytecode = True
ap = argparse.ArgumentParser()
ap.add_argument("--run", default=None)
ap.add_argument("--kind", default=None)
ap.add_argument("rest", nargs="*")
a = ap.parse_args()
RUN = a.run
if RUN is None:
    for x in a.rest:
        if os.path.isdir(x):
            RUN = x
if RUN is None:
    print("no run dir")
    sys.exit(2)
RUN = os.path.abspath(RUN)
KIND = a.kind or os.path.basename(RUN)


def find_root(p):
    cur = p
    while cur and cur != os.path.dirname(cur):
        if os.path.isdir(os.path.join(cur, "T10.a1-hit-pipe")) and os.path.isdir(os.path.join(cur, "T10.a1-htab-eram")):
            return cur
        cur = os.path.dirname(cur)
    return None


RUNROOT = find_root(RUN)
DEV = os.path.join(RUNROOT, "T10.a1-hit-pipe", "r0", KIND)
BASE = os.path.join(RUNROOT, "T10.a1-htab-eram", "r2", KIND)


def rd(p):
    with open(p, "rb") as f:
        return f.read()


def sha(b):
    return hashlib.sha256(b).hexdigest()


def hexbytes(p):
    toks = rd(p).decode("ascii", "ignore").split()
    out = bytearray()
    for w in toks:
        if len(w) == 2:
            out.append(int(w, 16))
        elif len(w) == 8:
            out += int(w, 16).to_bytes(4, "big")
        else:
            for i in range(0, len(w), 2):
                out.append(int(w[i:i + 2], 16))
    return bytes(out)


class BR:
    def __init__(s, d):
        s.d = d
        s.p = 0
        s.b = 0
        s.n = 0

    def bit(s):
        if s.n == 0:
            if s.p >= len(s.d):
                raise EOFError("eof")
            s.b = s.d[s.p]
            s.p += 1
            s.n = 8
        v = s.b & 1
        s.b >>= 1
        s.n -= 1
        return v

    def bits(s, k):
        v = 0
        for i in range(k):
            v |= s.bit() << i
        return v


LB = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
LE = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
DB = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
DE = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]


def make_fixed():
    lens = [8] * 144 + [9] * 112 + [7] * 24 + [8] * 8
    maxl = 15
    bl = [0] * (maxl + 1)
    for L in lens:
        bl[L] += 1
    code = 0
    nxt = [0] * (maxl + 2)
    for b in range(1, maxl + 1):
        code = (code + bl[b - 1]) << 1
        nxt[b] = code
    dec = {}
    for sym, L in enumerate(lens):
        dec[(L, nxt[L])] = sym
        nxt[L] += 1
    return dec


FIX = make_fixed()


def dec_sym(br, tab, maxl):
    c = 0
    for L in range(1, maxl + 1):
        c = (c << 1) | br.bit()
        if (L, c) in tab:
            return tab[(L, c)]
    raise ValueError("bad huffman code")


def strict_inflate(data):
    """Tester-written raw-deflate decoder (fixed + stored). Dynamic = unsupported."""
    br = BR(data)
    out = bytearray()
    nb = 0
    md = 0
    ml = 0
    bfinal = 0
    stored = 0
    fixed = 0
    while True:
        bfinal = br.bit()
        bt = br.bits(2)
        nb += 1
        if bt == 0:
            stored += 1
            br.n = 0
            L = br.bits(16)
            NL = br.bits(16)
            if (L ^ 0xFFFF) != NL:
                raise ValueError("stored nlen mismatch")
            for _ in range(L):
                out.append(br.bits(8))
        elif bt == 1:
            fixed += 1
            while True:
                s = dec_sym(br, FIX, 9)
                if s < 256:
                    out.append(s)
                elif s == 256:
                    break
                else:
                    i = s - 257
                    if i >= 29:
                        raise ValueError("bad length symbol %d" % s)
                    L = LB[i] + br.bits(LE[i])
                    j = br.bits(5)
                    if j >= 30:
                        raise ValueError("bad distance symbol %d" % j)
                    D = DB[j] + br.bits(DE[j])
                    if D > len(out):
                        raise ValueError("distance %d beyond output %d" % (D, len(out)))
                    md = max(md, D)
                    ml = max(ml, L)
                    for _ in range(L):
                        out.append(out[-D])
        elif bt == 2:
            raise ValueError("BTYPE_DYNAMIC_UNSUPPORTED")
        else:
            raise ValueError("btype 3")
        if bfinal:
            break
    return bytes(out), {"blocks": nb, "stored": stored, "fixed": fixed, "max_dist": md,
                        "max_len": ml, "bfinal": bfinal, "in_len": len(data), "out_len": len(out)}


prob = []


def chk(cond, msg):
    if not cond:
        prob.append(msg)


rep = {"run": RUN, "kind": KIND, "dev_result": DEV, "cases": []}
dev = json.loads(rd(os.path.join(DEV, "result.json")).decode("utf-8"))
base = json.loads(rd(os.path.join(BASE, "result.json")).decode("utf-8")) if os.path.exists(os.path.join(BASE, "result.json")) else None
dev_c = {c.get("name"): c for c in dev.get("cases", [])}


def bmap(res, kind):
    m = {}
    if not res:
        return m
    for c in res.get("cases", []):
        n = c.get("name")
        if kind == "p2":
            m[n] = {"sha": c.get("stream_sha256"), "len": c.get("stream_len"),
                    "cyc": (c.get("stats") or {}).get("run_cycles"),
                    "raw": c.get("raw_sha256"),
                    "out_len": (c.get("strict_stats") or {}).get("out_len")}
        else:
            p1 = c.get("p1") or {}
            m[n] = {"sha": p1.get("sha256_stream"), "len": p1.get("stream_len"),
                    "cyc": c.get("cycles"), "xform": p1.get("sha256_xform")}
    return m


D = bmap(dev, KIND)
B = bmap(base, KIND)
names = [c.get("name") for c in dev.get("cases", [])]
for n in names:
    od = os.path.join(RUN, "runs", n, "out.hex")
    if not os.path.exists(od):
        prob.append("%s: out.hex missing" % n)
        rep["cases"].append({"name": n, "ok": False})
        continue
    st = hexbytes(od)
    sh = sha(st)
    stt = rd(os.path.join(RUN, "runs", n, "stats.txt")).decode("utf-8", "ignore")
    kv = {}
    for k, v in re.findall(r"(?m)^\s*([A-Za-z_]+)\s*[:=\s]\s*(-?\d+)\s*$", stt):
        kv[k] = int(v)
    cyc = kv.get("run_cycles") or kv.get("cycles") or kv.get("total_cycles")
    d = D.get(n, {})
    o = {"name": n, "sha": sh, "len": len(st), "cycles": cyc, "stats_keys": sorted(kv.keys())[:6],
         "dev_sha": d.get("sha"), "dev_len": d.get("len"), "dev_cyc": d.get("cyc"),
         "base_sha": B.get(n, {}).get("sha"), "base_cyc": B.get(n, {}).get("cyc")}
    chk(sh == d.get("sha"), "%s: stream sha differs from r0 (%s vs %s)" % (n, sh[:16], str(d.get("sha"))[:16]))
    chk(len(st) == d.get("len"), "%s: stream len %d vs r0 %s" % (n, len(st), d.get("len")))
    chk(cyc is not None and cyc == d.get("cyc"), "%s: cycles %s vs r0 %s" % (n, cyc, d.get("cyc")))
    if n in B:
        chk(cyc == B[n]["cyc"], "%s: cycles differ vs r2 baseline" % n)
        chk(sh == B[n]["sha"], "%s: sha differs vs r2 baseline" % n)
    try:
        try:
            dz = zlib.decompress(st)
            o["wrapped"] = "zlib"
        except Exception:
            dz = zlib.decompress(st, -15)
            o["wrapped"] = "raw"
        o["zlib_len"] = len(dz)
        if KIND == "p2":
            xl = d.get("out_len")
            chk(xl is None or len(dz) == xl, "%s: decoded len %d != r0 strict out_len %s" % (n, len(dz), xl))
            if "flat" in n:
                chk(sha(dz) == d.get("raw"), "%s: zlib decoded sha != r0 raw_sha" % n)
        else:
            chk(sha(dz) == d.get("xform"), "%s: zlib decoded sha != r0 xform_sha" % n)
        if len(st) <= 200000:
            off = 2 if o["wrapped"] == "zlib" else 0
            sd, info = strict_inflate(st[off:])
            o["strict"] = info
            chk(sd == dz, "%s: tester strict inflate output != zlib" % n)
            chk(info["max_dist"] <= 2048, "%s: distance %d > 2048" % (n, info["max_dist"]))
            chk(info["max_len"] <= 258, "%s: match len %d > 258" % (n, info["max_len"]))
        else:
            o["strict"] = "skipped_large"
        o["ok"] = True
    except Exception as e:
        o["ok"] = False
        o["err"] = str(e)
        prob.append("%s: decode error %s" % (n, e))
    rep["cases"].append(o)

if KIND == "p2":
    for n in ("abort_midblock", "reset_midblock"):
        sp = os.path.join(RUN, "runs", n, "stats.txt")
        kv = {}
        if os.path.exists(sp):
            stt = rd(sp).decode("utf-8", "ignore")
            for k, v in re.findall(r"(?m)^\s*([A-Za-z_]+)\s*[:=\s]\s*(-?\d+)\s*$", stt):
                kv[k] = int(v)
        od = os.path.join(RUN, "runs", n, "out.hex")
        ol = len(hexbytes(od)) if os.path.exists(od) else 0
        rep.setdefault("neg", []).append({"name": n, "stats": kv, "out_bytes": ol})
        chk(kv.get("done", 0) == 0, "%s: done set on aborted/reset run" % n)
    for n in ("p2_frame_16x8_bp", "p2_frame_16x8_gapbp"):
        od = os.path.join(RUN, "runs", n, "out.hex")
        if os.path.exists(od):
            sh = sha(hexbytes(od))
            chk(sh == D.get("p2_frame_16x8", {}).get("sha"), "%s: stream differs from p2_frame_16x8" % n)
            rep.setdefault("bp", []).append({"name": n, "sha": sh})

rep["problems"] = prob
rep["verdict"] = "PASS" if not prob else "FAIL"
with open(os.path.join(RUN, "result_tester.json"), "w", encoding="utf-8") as f:
    json.dump(rep, f, indent=1)
with open(os.path.join(RUN, "result.json"), "w", encoding="utf-8") as f:
    json.dump({"verdict": rep["verdict"],
               "cases": [{"name": c["name"], "pass": c.get("ok", False)} for c in rep["cases"]],
               "tester": True}, f, indent=1)
print(json.dumps({"verdict": rep["verdict"], "cases": len(rep["cases"]), "nprob": len(prob), "problems": prob[:6]}, indent=1))
