import hashlib, json, os, re, zlib
import numpy as np

RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
SIM = os.path.join(OUT, "sim")


def parse_evt(p):
    t = {k: [None] * 5 for k in ("sof", "enc", "exp")}
    b = [None] * 5
    for ln in open(p, encoding="utf-8", errors="replace"):
        m = re.search(r"t=(\d+) kind=exp frame=(\d+) n=\d+ bytes=(\d+)", ln)
        if m:
            t["exp"][int(m.group(2))] = int(m.group(1)); b[int(m.group(2))] = int(m.group(3)); continue
        m = re.search(r"t=(\d+) kind=(\w+) frame=(\d+)", ln)
        if m and m.group(2) in t:
            t[m.group(2)][int(m.group(3))] = int(m.group(1))
    return t, b


t, eb = parse_evt(os.path.join(SIM, "tester-n-r1.evt"))
stats = dict(re.findall(r"(\w+)=([-\d]+)", open(os.path.join(SIM, "tester-n-r1.stats")).read()))
by = bytes(int(x, 16) for x in open(os.path.join(SIM, "tester-n-r1.hdr")).read().split())
u32 = lambda o: int.from_bytes(by[o:o + 4], "little")
s23, s34 = t["exp"][3] - t["exp"][2], t["exp"][4] - t["exp"][3]
ss = (s23 + s34) / 2
tail = {k: t["exp"][k] - t["enc"][k] for k in (2, 3, 4)}
tm = sum(tail.values()) / 3
mine = dict(S_23=s23, S_34=s34, S_ss=ss, tail=tail, tail_mean=tm, tail_frac=tm / ss,
            sink_limited=(tm / ss >= 0.5), L_cold=t["exp"][1] - 20, L_cold_raw=t["exp"][1],
            margin_G0_pct=100 * (6250000 / ss - 1), exp_bytes=eb, stats=stats,
            hdr=dict(stream_len=u32(24), raw_crc=u32(28), header_crc=u32(40),
                     header_crc_calc=zlib.crc32(by[:40]) & 0xFFFFFFFF),
            raw_crc_bin=zlib.crc32(np.fromfile(os.path.join(RUN, "content", "raw_n.bin"),
                                               dtype=np.uint8).tobytes()) & 0xFFFFFFFF)
mine["G0"] = "G0_not_proven" if mine["sink_limited"] else ("G0_not_closed" if ss > 6250000 else "feasible")

dev = json.load(open(os.path.join(RUN, "out", "content-verdict-r1.json")))["content_classes"]["N"]
cmp = {k: dict(dev=dev.get(k), tester=mine.get(k),
               equal=(abs(dev[k] - mine[k]) < 1e-9 if isinstance(dev.get(k), (int, float)) and isinstance(mine.get(k), (int, float)) else dev.get(k) == mine.get(k)))
       for k in ("S_ss", "S_23", "S_34", "tail_frac", "sink_limited", "L_cold", "margin_G0_pct", "G0")}

# drift re-check after the tester rerun
out = dict(mine=mine, cmp=cmp)
for tag, p in (("r0", os.path.join(RUN, "manifest-r0.json")), ("r1", os.path.join(RUN, "manifest-r1.json"))):
    m = json.load(open(p))
    bad = []
    for a in m["artifacts"]:
        q = a["path"]
        if not os.path.exists(q):
            bad.append((a["rel"], "MISSING")); continue
        h = hashlib.sha256(open(q, "rb").read()).hexdigest()
        if h != a["sha256"] or os.path.getsize(q) != a["bytes"]:
            bad.append((a["rel"], "DRIFT"))
    out[tag] = dict(manifest_sha256=hashlib.sha256(open(p, "rb").read()).hexdigest(),
                    n=m["artifact_count"], bad=bad)
json.dump(out, open(os.path.join(OUT, "r1-tester-verify.json"), "w"), indent=2, default=str)
print(json.dumps({k: out[k] for k in ("mine", "cmp")}, indent=1, default=str))
print("r0:", out["r0"]["manifest_sha256"], out["r0"]["n"], "bad:", out["r0"]["bad"])
print("r1:", out["r1"]["manifest_sha256"], out["r1"]["n"], "bad:", out["r1"]["bad"])
print("note: tester evt/stats/hdr sha256 vs dev",
      [hashlib.sha256(open(os.path.join(SIM, "tester-n-r1." + e), "rb").read()).hexdigest()[:16]
       for e in ("evt", "stats", "hdr")])
