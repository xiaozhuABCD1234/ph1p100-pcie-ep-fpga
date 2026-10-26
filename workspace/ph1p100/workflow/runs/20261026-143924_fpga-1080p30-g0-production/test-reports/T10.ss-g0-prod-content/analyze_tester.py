"""Independent re-derivation of the guide §3 metrics from the raw +EVT / +STAT files.

Tester-owned parser (does not import the developer's run_content.py). Works on the
frozen dev evidence and on the tester's own rerun.
"""
import json, os, re, zlib
import numpy as np

RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
SIM = os.path.join(OUT, "sim")
G0 = 6250000
G25 = 5000000


def parse_evt(p):
    t = {k: [None] * 5 for k in ("sof", "pub", "cam_end", "read", "enc", "exp")}
    stall = None
    pace = []
    for ln in open(p, encoding="utf-8", errors="replace"):
        m = re.search(r"t=(\d+) kind=(\w+) frame=(\d+)", ln)
        if m:
            tt, kind, fr = int(m.group(1)), m.group(2), int(m.group(3))
            if kind in t and 0 < fr <= 4:
                t[kind][fr] = tt
            continue
        m = re.search(r"SS_STALL frame=(\d+) cycles=(\d+) read=(\d+) enc=(\d+) exported=(\d+)", ln)
        if m:
            stall = dict(frame=int(m.group(1)), cycles=int(m.group(2)), read=int(m.group(3)),
                         enc=int(m.group(4)), exported=int(m.group(5)))
            continue
        m = re.search(r"SS_PACE (.*)", ln)
        if m:
            pace.append(m.group(1).strip())
    return t, stall, pace


def header(p):
    by = bytes(int(x, 16) for x in open(p).read().split())
    u32 = lambda o: int.from_bytes(by[o:o + 4], "little")
    h = dict(bytes=len(by), raw_len=u32(16), xform_len=u32(20), stream_len=u32(24),
             raw_crc=u32(28), xform_crc=u32(32), stream_crc=u32(36), header_crc=u32(40),
             header_crc_calc=zlib.crc32(by[:40]) & 0xFFFFFFFF)
    h["header_crc_ok"] = h["header_crc"] == h["header_crc_calc"]
    h["raw_crc_hex"] = "%08x" % h["raw_crc"]
    return h


def metrics(t, stall, hdr, bin_crc):
    out = dict()
    te = t["exp"]
    out["t_sof"], out["t_pub"], out["t_enc"], out["t_exp"] = t["sof"], t["pub"], t["enc"], te
    if all(te[k] is not None for k in (1, 2, 3, 4)):
        s2, s23, s34 = te[2] - te[1], te[3] - te[2], te[4] - te[3]
        ss = (s23 + s34) / 2
        tails = [te[k] - t["enc"][k] for k in (2, 3, 4)]
        tm = sum(tails) / 3
        out.update(S_2=s2, S_23=s23, S_34=s34, S_ss=ss, tail=tails, tail_mean=tm,
                   tail_frac=tm / ss, sink_limited=tm / ss >= 0.5,
                   margin_G0_pct=100 * (G0 / ss - 1), C_ss_MBps=2592000 * 187.5e6 / ss / 1e6)
    else:
        out.update(S_2=None, S_23=None, S_34=None, S_ss=None, tail=None, tail_mean=None,
                   tail_frac=None, sink_limited=None, margin_G0_pct=None, C_ss_MBps=None)
        out["why_null"] = "t_exp(1..4) incomplete -> S_ss/tail/sink_limited undefined"
    # first-frame cold-start arithmetic (exact, from the DUT header + t_enc)
    if t["enc"][1] is not None and hdr:
        exp_cycles = 2 * hdr["stream_len"]
        out["export_cycles_frame1_exact_2clk_per_B"] = exp_cycles
        out["t_exp1_lower_bound"] = t["enc"][1] + exp_cycles
        out["wd_limit"] = 12000000
        out["t_exp1_over_wd"] = out["t_exp1_lower_bound"] - 12000001
        out["t_exp1_over_wd_pct"] = 100.0 * out["t_exp1_over_wd"] / 12000001
        out["enc1_minus_t_pub1"] = t["enc"][1] - t["pub"][1]
        out["enc1_minus_1608000"] = t["enc"][1] - 1608000
        out["stream_len"] = hdr["stream_len"]
        out["compression_ratio"] = 2592000 / hdr["stream_len"]
        out["raw_crc_matches_content_bin"] = hdr["raw_crc"] == bin_crc
    out["stall"] = stall
    out["G0"] = ("G0_not_proven" if (out["S_ss"] is None or (stall and stall["exported"] < 4))
                 else ("G0_not_closed" if out["S_ss"] > G0 else
                       ("G0_not_proven" if out["sink_limited"] else "G0_feasible_for_scope")))
    return out


def crc32(p):
    return zlib.crc32(np.fromfile(p, dtype=np.uint8).tobytes()) & 0xFFFFFFFF


res = {}
for cls in ("N", "L"):
    tag = cls.lower()
    t, stall, pace = parse_evt(os.path.join(RUN, "sim", "caps", tag + ".evt"))
    hdr = header(os.path.join(RUN, "sim", "caps", tag + ".hdr"))
    res[cls] = dict(events=t, pace=pace, header=hdr,
                    metrics=metrics(t, stall, hdr, crc32(os.path.join(RUN, "content", "raw_%s.bin" % tag))))
    res[cls]["stats_bytes"] = os.path.getsize(os.path.join(RUN, "sim", "caps", tag + ".stats"))

# tester rerun
mine = None
mp = os.path.join(SIM, "tester-n.evt")
if os.path.exists(mp):
    t, stall, pace = parse_evt(mp)
    hh = header(os.path.join(SIM, "tester-n.hdr")) if os.path.exists(os.path.join(SIM, "tester-n.hdr")) else None
    mine = dict(events=t, pace=pace, header=hh,
                metrics=metrics(t, stall, hh, crc32(os.path.join(RUN, "content", "raw_n.bin"))))
    mine["log"] = {}
    lp = os.path.join(SIM, "vsim-tester-n.log")
    if os.path.exists(lp):
        txt = open(lp, encoding="utf-8", errors="replace").read()
        mine["log"] = dict(bytes=len(txt),
                           errors=re.findall(r"# Errors: (\d+), Warnings: (\d+)", txt),
                           has_stats="SS_STATS" in txt, has_stall="SS_STALL" in txt,
                           result=re.findall(r"B11_FULL_RESULT pass=\d", txt))
res["tester_rerun_N"] = mine

# compare with the developer's JSON
cv = json.load(open(os.path.join(RUN, "out", "content-verdict.json")))
cmp = {}
for cls in ("N", "L"):
    j = cv["content_classes"][cls]
    c = {}
    for k in ("S_ss", "tail_mean", "tail_frac", "sink_limited", "G0", "frames_exported",
              "t_sof", "t_pub", "t_enc", "t_exp", "self_check_pass"):
        jv = j.get(k)
        mv = res[cls]["metrics"].get(k)
        c[k] = dict(dev=jv, tester=mv, equal=(jv == mv))
    cmp[cls] = c
res["dev_json_vs_tester"] = cmp

# event-by-event compare tester vs dev (N)
if mine:
    enum = ("sof", "pub", "enc", "exp", "read")
    res["tester_vs_dev_N_events"] = {k: dict(dev=res["N"]["events"][k], tester=mine["events"][k],
                                             equal=res["N"]["events"][k] == mine["events"][k])
                                     for k in enum}

json.dump(res, open(os.path.join(OUT, "evidence-metrics-recompute.json"), "w"), indent=2)
print(json.dumps({k: res[k] for k in ("N", "L")}, indent=2, default=str))
print("--- dev json vs tester ---")
print(json.dumps(res["dev_json_vs_tester"], indent=1))
if mine:
    print("--- tester rerun N ---")
    print(json.dumps({k: mine[k] for k in ("metrics", "log", "header")}, indent=1, default=str))
    print("tester_vs_dev_N_events:", json.dumps(res["tester_vs_dev_N_events"], indent=1))
