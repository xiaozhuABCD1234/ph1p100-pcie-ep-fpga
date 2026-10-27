"""Round1 tester metric re-derivation + dup-semantics reconstruction.

- parses sim/caps/{n,l}-r1.evt, .stats, .hdr (independent parser)
- recomputes guide section 3 metrics, L_cold, margins, bottleneck attribution
- compares with out/content-verdict-r1.json value-for-value
- predicts st_dup_words from the frozen raw_*.bin content itself (independent of the DUT)
"""
import json, os, re, zlib
import numpy as np

RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
G0, G25 = 6250000, 5000000


def parse_evt(p):
    t = {k: [None] * 5 for k in ("sof", "pub", "cam_end", "read", "enc", "exp")}
    expb = [None] * 5
    stall = []
    for ln in open(p, encoding="utf-8", errors="replace"):
        m = re.search(r"t=(\d+) kind=exp frame=(\d+) n=\d+ bytes=(\d+)", ln)
        if m:
            t["exp"][int(m.group(2))] = int(m.group(1))
            expb[int(m.group(2))] = int(m.group(3))
            continue
        m = re.search(r"t=(\d+) kind=(\w+) frame=(\d+)", ln)
        if m:
            k, fr = m.group(2), int(m.group(3))
            if k in t and 0 < fr <= 4:
                t[k][fr] = int(m.group(1))
            continue
        if "SS_STALL" in ln:
            stall.append(ln.strip())
    return t, expb, stall


def parse_stats(p):
    txt = open(p, encoding="utf-8", errors="replace").read().strip()
    if not txt:
        return {}
    return dict(re.findall(r"(\w+)=([-\d]+)", txt))


def header(p):
    by = bytes(int(x, 16) for x in open(p).read().split())
    u32 = lambda o: int.from_bytes(by[o:o + 4], "little")
    return dict(bytes=len(by), raw_len=u32(16), xform_len=u32(20), stream_len=u32(24),
                raw_crc=u32(28), header_crc=u32(40),
                header_crc_calc=zlib.crc32(by[:40]) & 0xFFFFFFFF,
                header_crc_ok=u32(40) == (zlib.crc32(by[:40]) & 0xFFFFFFFF),
                raw_crc_hex="%08x" % u32(28))


def crc32(p):
    return zlib.crc32(np.fromfile(p, dtype=np.uint8).tobytes()) & 0xFFFFFFFF


res = {}
for cls in ("N", "L"):
    tag = "n" if cls == "N" else "l"
    t, expb, stall = parse_evt(os.path.join(RUN, "sim", "caps", tag + "-r1.evt"))
    st = parse_stats(os.path.join(RUN, "sim", "caps", tag + "-r1.stats"))
    hd = header(os.path.join(RUN, "sim", "caps", tag + "-r1.hdr"))
    te, en = t["exp"], t["enc"]
    m = dict(t_sof=t["sof"], t_pub=t["pub"], t_enc=en, t_exp=te, exp_bytes=expb,
             stats=st, header=hd, stall=stall, stats_bytes=os.path.getsize(
                 os.path.join(RUN, "sim", "caps", tag + "-r1.stats")))
    if all(te[k] is not None for k in (1, 2, 3, 4)) and all(en[k] is not None for k in (1, 2, 3, 4)):
        s2, s23, s34 = te[2] - te[1], te[3] - te[2], te[4] - te[3]
        ss = (s23 + s34) / 2
        tail = {k: te[k] - en[k] for k in (1, 2, 3, 4)}
        tm = sum(tail[k] for k in (2, 3, 4)) / 3
        core = {k: (en[k] - en[k - 1]) if k >= 2 else en[1] for k in (1, 2, 3, 4)}
        m.update(S_2=s2, S_23=s23, S_34=s34, S_ss=ss, tail=tail, tail_mean=tm,
                 tail_frac=tm / ss, sink_limited=(tm / ss >= 0.5),
                 L_cold=te[1], margin_G0_pct=100 * (G0 / ss - 1),
                 margin_G25_pct_ref=100 * (G25 / ss - 1),
                 C_ss_MBps=2592000 * 187.5e6 / ss / 1e6,
                 fps=187.5e6 / ss, core_interval=core,
                 export_time={k: te[k] - en[k] for k in (1, 2, 3, 4)},
                 cycles_end=st.get("cycles"), read=st.get("read"),
                 dup=st.get("dup"), frames=st.get("frames"),
                 ss_pass=st.get("ss_pass"), wd=st.get("wd"),
                 raw_crc_matches_bin=(hd["raw_crc"] == crc32(os.path.join(RUN, "content", "raw_%s.bin" % tag))),
                 G0=("G0_not_proven" if (tm / ss >= 0.5) else
                     ("G0_not_closed" if ss > G0 else "G0_feasible_for_scope")))
    res[cls] = m

# ---- dup prediction straight from the content (independent of any log) ----
mod = open(os.path.join(RUN, "src", "a1_ddr_slot_store.v"), encoding="utf-8").read().splitlines()
res["rd_port_lines"] = [f"{i+1}: {l.strip()}" for i, l in enumerate(mod)
                        if re.search(r"(input|output).*(rd_data|rd_words|rd_prev)|rd_prev\s*<=", l)][:12]
res["dup_prediction"] = {}
for cls, tag in (("N", "n"), ("L", "l")):
    buf = np.fromfile(os.path.join(RUN, "content", "raw_%s.bin" % tag), dtype=np.uint8).reshape(-1, 5)
    preds = {}
    for wbytes in (20, 32):
        g = buf.shape[0] * 5 // wbytes
        w = buf.reshape(g, wbytes)
        within = int(np.count_nonzero(np.all(w[1:] == w[:-1], axis=1)))
        words_per_frame = g // 4
        per = []
        for f in range(4):
            x = w[f * words_per_frame:(f + 1) * words_per_frame]
            per.append(int(np.count_nonzero(np.all(x[1:] == x[:-1], axis=1))))
        first_last = [bool(np.all(w[f * words_per_frame] == w[(f + 1) * words_per_frame - 1])) for f in range(3)]
        preds[wbytes] = dict(words_per_frame=words_per_frame, per_frame_adjacent_equal=per,
                             within_frame_total=sum(per), cross_frame_first_eq_prev_last=sum(first_last),
                             predicted_total=sum(per) + sum(first_last))
    res["dup_prediction"][cls] = preds

cv = json.load(open(os.path.join(RUN, "out", "content-verdict-r1.json")))
cmp = {}
for cls in ("N", "L"):
    j = cv.get("content_classes", {}).get(cls, {})
    c = {}
    for k in ("S_ss", "S_23", "S_34", "tail_mean", "tail_frac", "sink_limited", "G0", "L_cold",
              "frames_exported", "margin_G0_pct", "C_ss_MBps", "fps", "bottleneck_attribution"):
        jv = j.get(k)
        mv = res[cls].get(k, m.get("stats", {}).get("exported") if k == "frames_exported" else None)
        if k == "frames_exported":
            mv = res[cls]["stats"].get("exported")
        if isinstance(jv, (int, float)) and isinstance(mv, (int, float)):
            eq = abs(jv - mv) < 1e-9
        else:
            eq = (jv == mv)
        c[k] = dict(dev=jv, tester=mv, equal=eq)
    cmp[cls] = c
res["dev_json_vs_tester"] = cmp
res["dev_json_headline"] = cv.get("headline")

json.dump(res, open(os.path.join(OUT, "r1-metrics.json"), "w"), indent=2, default=str)
for cls in ("N", "L"):
    m = res[cls]
    print(cls, {k: m.get(k) for k in ("S_23", "S_34", "S_ss", "tail", "tail_mean", "tail_frac",
                                      "sink_limited", "L_cold", "margin_G0_pct", "C_ss_MBps", "fps",
                                      "G0", "core_interval", "export_time")})
    print(cls, "stats:", m["stats"])
    print(cls, "header:", m["header"], "raw_crc_ok:", m.get("raw_crc_matches_bin"), "stall:", m["stall"])
print("dup prediction:", json.dumps(res["dup_prediction"], indent=1))
print("dev json vs tester:", json.dumps(res["dev_json_vs_tester"], indent=1, default=str))
print("rd/prev port lines:", res["rd_port_lines"])
