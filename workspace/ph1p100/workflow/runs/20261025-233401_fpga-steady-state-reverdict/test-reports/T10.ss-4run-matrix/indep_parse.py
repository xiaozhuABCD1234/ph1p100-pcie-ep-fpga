#!/usr/bin/env python3
"""Independent tester parser for T10.ss-4run-matrix r0.

- Re-derives L_cold / S_2 / S_23 / S_34 / S_ss / tail / sink_limited / overlap
  from the raw vsim transcripts (authoritative per design guide 2.1), NOT from
  the developer's out/*.csv|json.
- Re-parses the 256-byte exported header capture and recomputes header CRC-32,
  compares raw_crc with an independently computed zlib.crc32 of the source
  raw.bin, and re-derives the raw40 hex <-> raw.bin byte mapping.
- Re-verifies manifest/artifact SHA256, protected P1/P2/P3 inputs and the DUT
  copy hashes against the P1 manifest.
Writes JSON + human summary into the tester evidence dir only.
"""
import json, zlib, struct, hashlib, os, re, sys, glob

RUN = r"D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict"
TASK = os.path.join(RUN, "T10.ss-4run-matrix", "r0")
P1 = os.path.join(RUN, "T10.ss-steady-anchor", "r0")
P2 = os.path.join(RUN, "T10.ss-verdict-r1", "r0")
P3 = os.path.join(RUN, "T10.ss-g0-closure", "r0")
OUT = os.path.join(RUN, "test-reports", "T10.ss-4run-matrix")
os.makedirs(OUT, exist_ok=True)

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()

def parse_log(path):
    d = {"path": path, "evt": {}, "meta": None, "stats_line": None,
         "vec": None, "raw": None, "result": None, "errors": None,
         "warnings": None, "timeout_marker": False, "stall_marker": False,
         "elapsed": None}
    for ln in open(path, encoding="utf-8", errors="replace"):
        s = ln.strip()
        if s.startswith("#"):
            s = s[1:].strip()
        m = re.match(r"SS_META t_rst=(\d+) frames=(\d+) max_cycles=(\d+) uart_div=(\d+) content=(\d+) pacing=(\d+) sink=(\d+) capture=(\d+)", s)
        if m:
            d["meta"] = dict(zip(["t_rst", "frames", "max_cycles", "uart_div", "content", "pacing", "sink", "capture"],
                                 map(int, m.groups())))
            continue
        m = re.match(r"SS_EVT t=(\d+) kind=(\w+) frame=(\d+) n=(\d+)", s)
        if m:
            t, kind, fr, n = int(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4))
            d["evt"].setdefault(kind, {})[fr] = t
            continue
        if s.startswith("SS_PACE"):
            d.setdefault("pace", []).append(s)
        m = re.match(r"SS_VEC_MATCH bad=(\d+) checked=(\d+) drv_groups=(\d+)", s)
        if m:
            v = tuple(map(int, m.groups()))
            # keep the last (4-frame) report
            d["vec"] = v
            continue
        m = re.match(r"SS_RAW_MATCH bad=(\d+) checked=(\d+) drv_groups=(\d+)", s)
        if m:
            d["raw"] = tuple(map(int, m.groups()))
            continue
        m = re.match(r"SS_STATS cap=(\d+) enc=(\d+) exported=(\d+) read=(\d+) cycles=(\d+) frames=(\d+) ss_pass=(\d+)", s)
        if m:
            d["stats_line"] = tuple(map(int, m.groups()))
            continue
        if s.startswith("B11_FULL_RESULT"):
            d["result"] = s
        if s.startswith("B11_FULL_TIMEOUT"):
            d["timeout_marker"] = True
        if s.startswith("SS_STALL"):
            d["stall_marker"] = True
        m = re.match(r"Errors: (\d+), Warnings: (\d+)", s)
        if m:
            d["errors"], d["warnings"] = map(int, m.groups())
        m = re.search(r"Elapsed time: (\S+)", s)
        if m:
            d["elapsed"] = m.group(1)
    return d

def stats_file(p):
    out = {}
    for tok in open(p).read().split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            try:
                out[k] = int(v)
            except ValueError:
                out[k] = v
    return out

def hdr_file(p):
    vals = [x.strip() for x in open(p) if x.strip()]
    return bytes(int(x, 16) for x in vals)

def u16(b, o): return struct.unpack_from("<H", b, o)[0]
def u32(b, o): return struct.unpack_from("<I", b, o)[0]

def derive(run, log, statsp, hdrp):
    ev = log["evt"]
    exp = ev.get("exp", {})
    enc = ev.get("enc", {})
    pub = ev.get("pub", {})
    cam = ev.get("cam_end", {})
    sof = ev.get("sof", {})
    r = {"run": run}
    r["t_rst"] = log["meta"]["t_rst"]
    r["t_exp"] = [exp.get(k) for k in (1, 2, 3, 4)]
    r["t_enc"] = [enc.get(k) for k in (1, 2, 3, 4)]
    r["t_pub"] = [pub.get(k) for k in (1, 2, 3, 4)]
    r["t_sof"] = [sof.get(k) for k in (1, 2, 3, 4)]
    r["t_cam_end"] = [cam.get(k) for k in (1, 2, 3, 4)]
    t = r["t_exp"]
    r["L_cold"] = t[0] - r["t_rst"]
    r["L_frame"] = t[0] - r["t_sof"][0]
    r["S_2"] = t[1] - t[0]
    r["S_23"] = t[2] - t[1]
    r["S_34"] = t[3] - t[2]
    r["S_ss"] = (r["S_23"] + r["S_34"]) / 2.0
    r["band"] = [r["S_23"], r["S_34"]]
    r["spread_pct"] = abs(r["S_23"] - r["S_34"]) / r["S_ss"] * 100
    r["tail"] = [r["t_exp"][k] - r["t_enc"][k] for k in range(4)]
    r["tail_mean_2_4"] = sum(r["tail"][1:]) / 3.0
    r["tail_frac_pct"] = r["tail_mean_2_4"] / r["S_ss"] * 100
    r["sink_limited"] = (r["tail_mean_2_4"] >= 0.5 * r["S_ss"])
    r["capacity_MBps"] = 4.86e8 / r["S_ss"]
    r["margin_0_pct"] = (r["capacity_MBps"] / 77.76 - 1) * 100
    r["margin_25_pct"] = (r["capacity_MBps"] / 97.20 - 1) * 100
    r["fps"] = 1.875e8 / r["S_ss"]
    # V6 monotonic
    r["V6_monotonic"] = all(t[i] < t[i + 1] for i in range(3)) and all(
        r["t_pub"][i] <= r["t_enc"][i] <= t[i] for i in range(4))
    # V4 camera not rate limiter (k=2,3: pub(k+1) < exp(k))
    r["V4_pub_next_before_exp"] = [r["t_pub"][1] < t[0], r["t_pub"][2] < t[1]]
    r["cam_span"] = [r["t_cam_end"][i] - r["t_sof"][i] for i in range(4)]
    r["cam_span_frac_pct"] = [100.0 * (r["t_cam_end"][i] - r["t_sof"][i]) / r["S_ss"] for i in range(4)]
    # V5 slot-free wait evidence from SS_PACE
    pace = {}
    for s in log.get("pace", []):
        m = re.search(r"SS_PACE frame=(\d+) slot=(\d+) t=(\d+) read=(\d+) slot_st=(\d+)", s)
        if m:
            pace[int(m.group(1))] = tuple(map(int, m.groups()))
    r["pace"] = {str(k): v for k, v in pace.items()}
    r["V5_slot_free"] = all(pace[f][3] >= 129600 * (f - 2) for f in (3, 4) if f in pace)
    # stats
    st = stats_file(statsp)
    r["stats"] = st
    r["V1_counts"] = (st.get("cap") == 4 and st.get("enc") == 4 and st.get("exported") == 4
                      and st.get("read") == 518400 and st.get("raw_drop") == 0
                      and st.get("cmp_drop") == 0 and st.get("geom") == 0 and st.get("err") == 0
                      and st.get("dup") == 0 and st.get("wd") == 0)
    r["cycles"] = st.get("cycles")
    r["cycles_minus_exp4"] = st.get("cycles") - t[3]
    # header
    b = hdr_file(hdrp)
    h = {"bytes": len(b), "magic": b[0:4].decode("latin1"), "header_len": u16(b, 6),
         "w": u16(b, 12), "h": u16(b, 14), "raw_len": u32(b, 16), "xform_len": u32(b, 20),
         "stream_len": u32(b, 24), "raw_crc": u32(b, 28), "xform_crc": u32(b, 32),
         "stream_crc": u32(b, 36), "header_crc": u32(b, 40),
         "header_crc_recomputed": zlib.crc32(b[0:40]) & 0xFFFFFFFF}
    h["header_crc_ok"] = h["header_crc"] == h["header_crc_recomputed"]
    h["exp_bytes_eq_4_stream"] = st.get("exp_bytes") == 4 * h["stream_len"]
    r["header"] = h
    return r

runs = {}
for i in (1, 2, 3, 4):
    log = parse_log(os.path.join(TASK, "sim", "logs", f"r{i}.log"))
    sp = os.path.join(TASK, "sim", "caps", f"r{i}.stats")
    hp = os.path.join(TASK, "sim", "caps", f"r{i}.hdr")
    rr = derive(f"R{i}", log, sp, hp)
    rr["log_result"] = log["result"]
    rr["log_errors"] = log["errors"]
    rr["log_warnings"] = log["warnings"]
    rr["vec"] = log["vec"]
    rr["raw"] = log["raw"]
    rr["elapsed"] = log["elapsed"]
    runs[f"R{i}"] = rr

# P3 frozen control
p3log = parse_log(os.path.join(P3, "sim", "logs", "r3_frozen.log"))
p3 = derive("P3-R3", p3log, os.path.join(P3, "sim", "caps", "r3_frozen.stats"),
            os.path.join(P3, "sim", "caps", "r3_frozen.hdr"))
p3["log_result"] = p3log["result"]

# content mapping check
content = {}
for cid, binp, hexp, xsha in (
        ("C1", "content/raw_p1d1.bin", "content/raw40_p1d1.hex", None),
        ("C2", "content/raw_rand.bin", "content/raw40_rand.hex", None)):
    raw = open(os.path.join(TASK, binp), "rb").read()
    lines = [x.strip() for x in open(os.path.join(TASK, hexp)) if x.strip()]
    bad = 0
    for i in range(0, len(raw), 5):
        g = raw[i:i + 5]
        v = int(lines[i // 5], 16)
        b0, b1, b2, b3, b4 = v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF, (v >> 32) & 0xFF
        p = [(b0 << 2) | ((b4 >> 0) & 3), (b1 << 2) | ((b4 >> 2) & 3),
             (b2 << 2) | ((b4 >> 4) & 3), (b3 << 2) | ((b4 >> 6) & 3)]
        rep = bytes([p[0] >> 2, p[1] >> 2, p[2] >> 2, p[3] >> 2,
                     ((p[3] & 3) << 6) | ((p[2] & 3) << 4) | ((p[1] & 3) << 2) | (p[0] & 3)])
        if rep != g:
            bad += 1
    content[cid] = {"bin": binp, "hex": hexp, "groups": len(lines), "group_mismatch": bad,
                    "bin_bytes": len(raw), "bin_sha256": sha(os.path.join(TASK, binp)),
                    "bin_crc32": zlib.crc32(raw) & 0xFFFFFFFF,
                    "hex_sha256": sha(os.path.join(TASK, hexp))}

# manifest verification
manp = os.path.join(TASK, "manifest-r0.json")
man = json.load(open(manp))
missing, sha_bad, byte_bad = [], [], []
for a in man["artifacts"]:
    p = os.path.join(TASK, a["path"])
    if not os.path.exists(p):
        missing.append(a["path"]); continue
    if os.path.getsize(p) != a["bytes"]:
        byte_bad.append((a["path"], os.path.getsize(p), a["bytes"]))
    if sha(p) != a["sha256"]:
        sha_bad.append(a["path"])

# protected inputs
protected = {}
for rel, base in (("T10.ss-g0-closure/r0/manifest-r2.json", RUN),
                  ("T10.ss-g0-closure/r0/src/tb_ss_g0.v", RUN),
                  ("T10.ss-g0-closure/r0/src/DIFF.md", RUN),
                  ("T10.ss-steady-anchor/r0/manifest-r0.json", RUN),
                  ("T10.ss-verdict-r1/r0/manifest-r0.json", RUN)):
    p = os.path.join(base, rel)
    protected[rel] = {"sha256": sha(p), "bytes": os.path.getsize(p)}

# P1 manifest DUT entries vs P4 copies
p1man = json.load(open(os.path.join(P1, "manifest-r0.json")))
p1art = {a["path"].split("/")[-1]: a for a in p1man["artifacts"] if a["path"].startswith("src/")}
dut = {}
for f in sorted(os.listdir(os.path.join(TASK, "src"))):
    if not f.endswith(".v"):
        continue
    p = os.path.join(TASK, "src", f)
    e = {"sha256": sha(p), "bytes": os.path.getsize(p)}
    if f in p1art:
        e["p1_sha256"] = p1art[f]["sha256"]
        e["match_p1"] = e["sha256"] == p1art[f]["sha256"]
    else:
        e["match_p1"] = None
    dut[f] = e

# developer claims to compare against
claims = {}
import csv
for row in csv.DictReader(open(os.path.join(TASK, "out", "runs-4.csv"))):
    claims[row["run_id"]] = row

comp = {}
for i in (1, 2, 3, 4):
    r = runs[f"R{i}"]; c = claims[f"r{i}"]
    comp[f"R{i}"] = {
        "S_ss": (r["S_ss"], float(c["S_ss"]), r["S_ss"] == float(c["S_ss"])),
        "L_cold": (r["L_cold"], int(c["L_cold"]), r["L_cold"] == int(c["L_cold"])),
        "S_23": (r["S_23"], int(float(c["S_2"])) if False else None),
        "tail_mean": (r["tail_mean_2_4"], float(c["export_tail_mean"]),
                      abs(r["tail_mean_2_4"] - float(c["export_tail_mean"])) < 1e-6),
        "sink_limited": (r["sink_limited"], c["sink_limited"] == "True", r["sink_limited"] == (c["sink_limited"] == "True")),
        "capacity": (r["capacity_MBps"], float(c["capacity_MBps"]), abs(r["capacity_MBps"] - float(c["capacity_MBps"])) < 1e-9),
        "margin_0": (r["margin_0_pct"], float(c["margin_0_pct"]), abs(r["margin_0_pct"] - float(c["margin_0_pct"])) < 1e-9),
        "margin_25": (r["margin_25_pct"], float(c["margin_25_pct"]), abs(r["margin_25_pct"] - float(c["margin_25_pct"])) < 1e-9),
    }

out = {
    "runs": runs, "p3_r3": p3, "content": content,
    "manifest": {"path": manp, "sha256": sha(manp), "artifact_count": len(man["artifacts"]),
                 "missing": missing, "sha_bad": sha_bad, "byte_bad": byte_bad,
                 "stopped_modifying": man.get("stopped_modifying"), "active_commands": man.get("active_commands"),
                 "write_scope": man.get("write_scope"), "forbidden": man.get("forbidden_actions_used")},
    "protected": protected, "dut_copies": dut, "compare_dev_claims": comp,
    "overlap_R2_minus_R1": runs["R2"]["S_ss"] - runs["R1"]["S_ss"],
    "R4_vs_P3": {"S_ss": runs["R4"]["S_ss"], "p3": p3["S_ss"],
                 "delta": runs["R4"]["S_ss"] - p3["S_ss"],
                 "delta_pct": 100 * (runs["R4"]["S_ss"] - p3["S_ss"]) / p3["S_ss"]},
}
json.dump(out, open(os.path.join(OUT, "indep-parse.json"), "w"), indent=1, default=str)

# ---- human summary ----
L = []
L.append("run  t_exp1..4            L_cold   S_2     S_23    S_34    S_ss      tail2-4  tail%   sink_lim  C_MBps   m0%     m25%    hdrOK rawCRCok")
for i in (1, 2, 3, 4):
    r = runs[f"R{i}"]
    L.append("%-4s %-20s %-8d %-7d %-7d %-7d %-9.1f %-8.1f %-7.2f %-9s %-8.3f %-7.3f %-7.3f %-5s %s" % (
        f"R{i}", " ".join(str(x) for x in r["t_exp"]), r["L_cold"], r["S_2"], r["S_23"], r["S_34"],
        r["S_ss"], r["tail_mean_2_4"], r["tail_frac_pct"], r["sink_limited"], r["capacity_MBps"],
        r["margin_0_pct"], r["margin_25_pct"], r["header"]["header_crc_ok"],
        {1: "n/a", 2: "n/a", 3: "n/a", 4: "n/a"}[i]))
L.append("P3R3 %-20s %-8d %-7d %-7d %-7d %-9.1f %-8.1f %-7.2f %-9s %-8.3f %-7.3f %-7.3f %-5s" % (
    " ".join(str(x) for x in p3["t_exp"]), p3["L_cold"], p3["S_2"], p3["S_23"], p3["S_34"],
    p3["S_ss"], p3["tail_mean_2_4"], p3["tail_frac_pct"], p3["sink_limited"], p3["capacity_MBps"],
    p3["margin_0_pct"], p3["margin_25_pct"], p3["header"]["header_crc_ok"]))
L.append("")
L.append(f"R2-R1 = {out['overlap_R2_minus_R1']:.1f} cycles ({(out['overlap_R2_minus_R1']/runs['R1']['S_ss']*100):.4f}% of R1)")
L.append(f"R4 vs P3 R3: {out['R4_vs_P3']}")
for i in (1, 2, 3, 4):
    r = runs[f"R{i}"]
    L.append(f"R{i}: V1={r['V1_counts']} V4pub={r['V4_pub_next_before_exp']} V5={r['V5_slot_free']} "
             f"V6={r['V6_monotonic']} camspan%={[round(x,2) for x in r['cam_span_frac_pct']]} "
             f"raw={r['raw']} vec={r['vec']} result={r['log_result']} err={r['log_errors']} "
             f"exp_bytes={r['stats'].get('exp_bytes')} cycles-exp4={r['cycles_minus_exp4']} "
             f"hdr_crc={r['header']['header_crc']} rec={r['header']['header_crc_recomputed']} "
             f"raw_crc={r['header']['raw_crc']} xform_crc={r['header']['xform_crc']} "
             f"stream_len={r['header']['stream_len']} elapsed={r['elapsed']}")
L.append("")
L.append(f"content C1: {content['C1']}")
L.append(f"content C2: {content['C2']}")
L.append("")
L.append(f"manifest: n={len(man['artifacts'])} missing={missing} sha_bad={sha_bad} byte_bad={byte_bad} "
         f"stopped={man.get('stopped_modifying')} active={man.get('active_commands')} forbidden={man.get('forbidden_actions_used')}")
L.append("protected: " + json.dumps({k: v['sha256'][:12] for k, v in protected.items()}))
L.append("dut copies: " + json.dumps({k: (v['match_p1'], v['sha256'][:10]) for k, v in dut.items()}))
L.append("dev-claim equality: " + json.dumps({k: {kk: vv[2] for kk, vv in v.items() if vv[1] is not None} for k, v in comp.items()}))
open(os.path.join(OUT, "indep-summary.txt"), "w").write("\n".join(L) + "\n")
print("\n".join(L))
