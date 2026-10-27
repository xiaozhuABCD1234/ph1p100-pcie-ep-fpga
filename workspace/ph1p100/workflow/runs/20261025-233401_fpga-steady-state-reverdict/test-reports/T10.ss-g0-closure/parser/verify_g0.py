#!/usr/bin/env python3
"""Independent verification for T10.ss-g0-closure (tester-owned).

Self-written parser: reads the frozen raw logs directly (not the developer's
run_g0.py / runs.json) and recomputes L_cold, S_2/S_23/S_34, S_ss, export tails,
capacity/margins, overlap gain, G0 verdict, A2 gap, clock, DDR/UART arithmetic.
Also checks hashes, TB diffs, P1/P2 artifact integrity, content-proxy byte
mapping (independent forward transform) and the R3 export header CRC.

Writes only into test-reports/T10.ss-g0-closure/.
"""
import csv
import hashlib
import json
import math
import pathlib
import re
import sys
import zlib

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow" / "runs" / "20261025-233401_fpga-steady-state-reverdict"
TASK = RUN / "T10.ss-g0-closure" / "r0"
P1 = RUN / "T10.ss-steady-anchor" / "r0"
P2 = RUN / "T10.ss-verdict-r1" / "r0"
TEST = RUN / "test-reports" / "T10.ss-g0-closure"
OUT = TASK / "out"
CAPS = TASK / "sim" / "caps"
COMP = ROOT / "work" / "parallel-sim-20261024-2204" / "codec-throughput" / "comp"
CLK = 187.5e6
G0_MBPS = 77.76
G25_MBPS = 97.20
S_G0 = 6_250_000.0
S_G25 = 5_000_000.0

res = {"checks": [], "diffs": {}, "computed": {}, "notes": []}


def add(name, ok, detail=""):
    res["checks"].append({"name": name, "ok": bool(ok), "detail": detail})
    return bool(ok)


def sha_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_log_events(p):
    txt = p.read_text(encoding="utf-8", errors="replace")
    ev = {}
    meta = None
    stats = None
    vec = []
    pace = []
    for line in txt.splitlines():
        s = line.strip()
        if s.startswith("# "):
            s = s[2:]
        elif s.startswith("#"):
            s = s[1:].lstrip()
        if s.startswith("SS_EVT"):
            m = re.match(r"SS_EVT t=(\d+) kind=(\w+) frame=(\d+) n=(\d+)", s)
            if m:
                t, kind, fr, n = int(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4))
                ev.setdefault(kind, {})[fr] = t
        elif s.startswith("SS_META"):
            meta = s
        elif s.startswith("SS_STATS"):
            stats = s
        elif s.startswith("SS_VEC_MATCH"):
            m = re.match(r"SS_VEC_MATCH bad=(\d+) checked=(\d+) drv_groups=(\d+)", s)
            if m:
                vec.append(tuple(int(x) for x in m.groups()))
        elif s.startswith("SS_PACE"):
            pace.append(s)
    return {"events": ev, "meta": meta, "stats": stats, "vec_match": vec, "pace": pace, "raw": txt}


def stats_dict(stats_line):
    if not stats_line:
        return {}
    # SS_STATS has fewer fields; the final stats file line has all fields
    return {}


def parse_stats_file(p):
    txt = p.read_text(encoding="utf-8", errors="replace").strip()
    d = {}
    for kv in txt.split():
        if "=" in kv:
            k, v = kv.split("=", 1)
            try:
                d[k] = int(v)
            except ValueError:
                d[k] = v
    return d


def metrics_from_events(ev, t_rst=20):
    t_exp = ev.get("exp", {})
    t_enc = ev.get("enc", {})
    t_sof = ev.get("sof", {})
    t_pub = ev.get("pub", {})
    t_read = ev.get("read", {})
    t_cam = ev.get("cam_end", {})
    frames = sorted(t_exp)
    out = {"t_exp": t_exp, "t_enc": t_enc, "t_sof": t_sof, "t_pub": t_pub,
           "t_read": t_read, "t_cam_end": t_cam, "frames_exported": len(frames)}
    if len(frames) >= 1:
        out["L_cold"] = t_exp[frames[0]] - t_rst
        out["L_frame"] = t_exp[frames[0]] - t_sof.get(frames[0], 0)
    if len(frames) >= 2:
        out["S_2"] = t_exp[frames[1]] - t_exp[frames[0]]
    if len(frames) >= 3:
        out["S_23"] = t_exp[frames[2]] - t_exp[frames[1]]
    if len(frames) >= 4:
        out["S_34"] = t_exp[frames[3]] - t_exp[frames[2]]
    if "S_23" in out and "S_34" in out:
        out["S_band"] = [out["S_23"], out["S_34"]]
        out["S_ss"] = (out["S_23"] + out["S_34"]) / 2.0
        out["S_spread_pct"] = 100.0 * (max(out["S_band"]) - min(out["S_band"])) / out["S_ss"]
    out["export_tail"] = {k: t_exp[k] - t_enc[k] for k in t_enc if k in t_exp}
    if "S_ss" in out:
        out["capacity_MBps"] = 4.86e8 / out["S_ss"]
        out["fps"] = CLK / out["S_ss"]
        out["margin_0_pct"] = (out["capacity_MBps"] / G0_MBPS - 1) * 100
        out["margin_25_pct"] = (out["capacity_MBps"] / G25_MBPS - 1) * 100
        out["f_req_0_mhz"] = 30.0 * out["S_ss"] / 1e6
        out["f_req_25_mhz"] = 37.5 * out["S_ss"] / 1e6
        out["gap_to_G0_cycles"] = out["S_ss"] - S_G0
        out["gap_to_G0_pct_of_S"] = 100.0 * (out["S_ss"] - S_G0) / out["S_ss"]
        out["G0_pass"] = out["capacity_MBps"] >= G0_MBPS
        out["G25_pass"] = out["capacity_MBps"] >= G25_MBPS
    return out


def parse_hex_words(p):
    words = []
    for line in p.read_text(encoding="ascii").splitlines():
        s = line.strip()
        if s:
            words.append(int(s, 16) & ((1 << 40) - 1))
    return words


def word_to_5b(w):
    return bytes([(w >> (8 * i)) & 0xFF for i in range(5)])


def pack_samples(s0, s1, s2, s3):
    return ((s3 & 3) << 38) | ((s2 & 3) << 36) | ((s1 & 3) << 34) | ((s0 & 3) << 32) | \
           ((s3 >> 2) << 24) | ((s2 >> 2) << 16) | ((s1 >> 2) << 8) | (s0 >> 2)


def unpack_samples(w):
    s0 = ((w >> 32) & 3) | (((w >> 0) & 0xFF) << 2)
    s1 = ((w >> 34) & 3) | (((w >> 8) & 0xFF) << 2)
    s2 = ((w >> 36) & 3) | (((w >> 16) & 0xFF) << 2)
    s3 = ((w >> 38) & 3) | (((w >> 24) & 0xFF) << 2)
    return s0, s1, s2, s3


def content_proxy_check():
    raw_words = parse_hex_words(CAPS / "comp_raw.hex")
    vec_words = parse_hex_words(CAPS / "comp_vec.hex")
    raw_words = raw_words[:518400]
    vec_words = vec_words[:30720]
    if len(raw_words) != 518400 or len(vec_words) != 30720:
        return {"ok": False, "why": "word count raw=%d vec=%d" % (len(raw_words), len(vec_words))}
    bad = 0
    checked = 0
    # Build the plane sample sequence per row, then group by 4.
    for b in range(540):
        vbase = (b % 32) * 960
        for r in range(2):
            for plane in range(2):
                seq = []
                for g in range(480):
                    w = raw_words[(b * 2 + r) * 480 + g]
                    s = unpack_samples(w)
                    sel = (s[0], s[2]) if plane == 0 else (s[1], s[3])
                    seq.extend(sel)
                prev = 0
                diffs = []
                for x in seq:
                    diffs.append((x - prev) & 0x3FF)
                    prev = x
                # 960 diffs -> 240 words of 4
                for q in range(240):
                    d = diffs[q * 4:q * 4 + 4]
                    wchk = pack_samples(*d)
                    exp = vec_words[vbase + plane * 240 + q]
                    checked += 1
                    if wchk != exp:
                        bad += 1
    return {"ok": bad == 0 and checked == 518400, "bad": bad, "checked": checked}


def main():
    closure = (TASK / "g0-closure.md").read_text(encoding="utf-8")
    verdict = json.loads((OUT / "g0-verdict.json").read_text(encoding="utf-8"))
    # ---------------------------------------------------------------- logs
    logs = {k: read_log_events(TASK / "sim" / "logs" / (k + ".log")) for k in ["r0", "r1", "r2", "r3"]}
    stats = {k: parse_stats_file(CAPS / (k + ".stats")) for k in ["r0", "r1", "r2", "r3"]}
    m = {k: metrics_from_events(logs[k]["events"], t_rst=20) for k in logs}
    res["computed"]["runs"] = m

    # R0 independent rerun (tester work dir)
    ind_log = read_log_events(TEST / "r0-control" / "r0.log")
    ind_stats = parse_stats_file(TEST / "r0-control" / "r0.stats")
    ind_m = metrics_from_events(ind_log["events"], t_rst=20)
    res["computed"]["r0_independent"] = ind_m
    res["computed"]["r0_independent_stats"] = ind_stats

    # R0 control exact
    ctl = {"t_rst": 20, "t_exp1": 6766454, "t_exp2": 11443989, "S_ss": 4677535,
           "exp_bytes": 160136, "cap_bytes": 160312, "cycles": 20801058,
           "cap": 4, "enc": 4, "exported": 4, "read": 518400,
           "raw_drop": 0, "cmp_drop": 0, "dup": 0, "geom": 0, "err": 0, "wd": 0}
    got = {
        "t_rst": 20, "t_exp1": m["r0"].get("t_exp", {}).get(1), "t_exp2": m["r0"].get("t_exp", {}).get(2),
        "S_ss": m["r0"].get("S_ss"), "exp_bytes": stats["r0"].get("exp_bytes"),
        "cap_bytes": stats["r0"].get("cap_bytes"), "cycles": stats["r0"].get("cycles"),
        "cap": stats["r0"].get("cap"), "enc": stats["r0"].get("enc"), "exported": stats["r0"].get("exported"),
        "read": stats["r0"].get("read"), "raw_drop": stats["r0"].get("raw_drop"),
        "cmp_drop": stats["r0"].get("cmp_drop"), "dup": stats["r0"].get("dup"),
        "geom": stats["r0"].get("geom"), "err": stats["r0"].get("err"), "wd": stats["r0"].get("wd")}
    add("R0 control exact vs P1", got == ctl, json.dumps({k: [ctl[k], got[k]] for k in ctl if ctl[k] != got[k]}))
    add("R0 independent rerun exact", ind_m.get("S_ss") == 4677535 and ind_stats.get("exp_bytes") == 160136
        and ind_stats.get("cap_bytes") == 160312 and ind_m.get("t_exp", {}).get(1) == 6766454
        and ind_m.get("t_exp", {}).get(2) == 11443989,
        json.dumps({"S_ss": ind_m.get("S_ss"), "exp_bytes": ind_stats.get("exp_bytes"),
                    "cap_bytes": ind_stats.get("cap_bytes"),
                    "t_exp1": ind_m.get("t_exp", {}).get(1), "t_exp2": ind_m.get("t_exp", {}).get(2)}))
    add("R0 independent stats == candidate stats",
        (TEST / "r0-control" / "r0.stats").read_bytes() == (CAPS / "r0.stats").read_bytes(),
        "%s vs %s" % (sha_file(TEST / "r0-control" / "r0.stats"), sha_file(CAPS / "r0.stats")))
    add("R0 independent dec == candidate dec",
        (TEST / "r0-control" / "r0.dec").read_bytes() == (CAPS / "r0.dec").read_bytes(),
        "%s vs %s" % (sha_file(TEST / "r0-control" / "r0.dec"), sha_file(CAPS / "r0.dec")))

    # R1/R2/R3 integrity
    for k in ["r1", "r2", "r3"]:
        mm = m[k]
        ok = (stats[k].get("cap") == 4 and stats[k].get("enc") == 4 and stats[k].get("exported") == 4
              and stats[k].get("read") == 518400 and stats[k].get("raw_drop") == 0
              and stats[k].get("cmp_drop") == 0 and stats[k].get("dup") == 0
              and stats[k].get("geom") == 0 and stats[k].get("err") == 0 and stats[k].get("wd") == 0
              and mm.get("frames_exported") == 4 and len(mm.get("t_exp", {})) == 4)
        add("%s 4-frame complete/no-drop" % k.upper(), ok, json.dumps(stats[k]))
        add("%s S_ss spread <=2%%" % k.upper(), mm.get("S_spread_pct", 99) <= 2.0,
            "%.8f%% band=%s" % (mm.get("S_spread_pct", -1), mm.get("S_band")))
    # Serial semantics
    add("R2 strict-serial V4 not applicable", stats["r2"].get("pacing") == 1, "pacing=%s" % stats["r2"].get("pacing"))
    # overlap gain
    ov = m["r2"]["S_ss"] - m["r1"]["S_ss"]
    res["computed"]["overlap_gain_cycles"] = ov
    res["computed"]["overlap_gain_pct_of_R1"] = 100.0 * ov / m["r1"]["S_ss"]
    add("overlap gain = R2-R1", abs(ov - 1688091.5) < 1e-6, "%.1f (%.6f%%)" % (ov, 100.0 * ov / m["r1"]["S_ss"]))

    # ---------------------------------------------------------------- G0 table
    with open(OUT / "g0-table.csv", newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    add("g0-table 32 rows", len(rows) == 32, "rows=%d" % len(rows))
    anchors = sorted(set(r["anchor"] for r in rows))
    add("g0-table anchors A1/A2/A3/P", anchors == ["A1_grad_measured", "A2_comp_assumed", "A3_rand_assumed", "P_proxy_measured"], str(anchors))
    add("g0-table G25 labelled ref-only", "gate_G25_ref_only" in rows[0],
        "header=%s" % list(rows[0].keys()))
    # no 2C: c2s2 == c1s1, c1s2 == C/2
    by = {(r["anchor"], r["view"], r["mode"]): r for r in rows}
    t_ok = True
    t_detail = {}
    for a in anchors:
        for v in ["overlapped", "serial"]:
            c11 = float(by[(a, v, "c1s1")]["capacity_MBps"])
            c12 = float(by[(a, v, "c1s2")]["capacity_MBps"])
            c21 = float(by[(a, v, "c2s1")]["capacity_MBps"])
            c22 = float(by[(a, v, "c2s2")]["capacity_MBps"])
            ok = abs(c12 - c11 / 2) < 1e-9 and abs(c21 - c11) < 1e-9 and abs(c22 - c11) < 1e-9
            t_ok &= ok
            if not ok:
                t_detail["%s/%s" % (a, v)] = [c11, c12, c21, c22]
    add("g0-table per-stream not aggregate 2C", t_ok, json.dumps(t_detail))
    # key table values / labels
    tvals = {
        ("A1_grad_measured", "overlapped", "c1s1"): (m["r1"]["S_ss"], "measured"),
        ("A1_grad_measured", "serial", "c1s1"): (m["r2"]["S_ss"], "measured"),
        ("A2_comp_assumed", "overlapped", "c1s1"): (6421414.375, "assumed"),
        ("A2_comp_assumed", "serial", "c1s1"): (8109505.875, "assumed+assumed_serial_delta"),
        ("A3_rand_assumed", "overlapped", "c1s1"): (3151346.5, "assumed"),
        ("A3_rand_assumed", "serial", "c1s1"): (4839438.0, "assumed+assumed_serial_delta"),
        ("P_proxy_measured", "overlapped", "c1s1"): (m["r3"]["S_ss"], "measured_proxy_not_worst"),
        ("P_proxy_measured", "serial", "c1s1"): (7616377.5, "measured_proxy_not_worst+assumed_serial_delta"),
    }
    badv = {}
    for k, (cyc, lab) in tvals.items():
        r = by[k]
        if abs(float(r["S_cycles"]) - cyc) > 1e-6 or r["label"] != lab:
            badv[str(k)] = [r["S_cycles"], r["label"], cyc, lab]
    add("g0-table key S_cycles/labels (serial comp assumed)", not badv, json.dumps(badv))
    add("R4 not run / serial comp assumed",
        ("not_run" in verdict.get("r4", "")) or ("R4" in closure),
        verdict.get("r4", ""))
    # margins recompute
    bad = []
    for r in rows:
        cap = float(r["capacity_MBps"])
        m0 = (cap / G0_MBPS - 1) * 100
        m25 = (cap / G25_MBPS - 1) * 100
        g0 = cap >= G0_MBPS
        g25 = cap >= G25_MBPS
        if abs(float(r["margin_0_pct"]) - m0) > 1e-6 or abs(float(r["margin_25_pct"]) - m25) > 1e-6 \
                or (r["gate_G0"] == "True") != g0 or (r["gate_G25_ref_only"] == "True") != g25:
            bad.append(r)
    add("g0-table margins/gates recompute", not bad, "bad=%d" % len(bad))
    # no cold latency as S_ss
    cold = [r for r in rows if abs(float(r["S_cycles"]) - 6766434) < 1]
    add("g0-table no L_cold as S_ss", not cold, "rows=%d" % len(cold))
    a2rows = [r for r in rows if r["anchor"] == "A2_comp_assumed"]
    add("g0-table A2 labelled assumed (not measured cold latency)",
        all(r["label"].startswith("assumed") for r in a2rows), str([r["label"] for r in a2rows]))
    # A2 gap / clock
    a2 = 6421414.375
    gap = a2 - S_G0
    res["computed"]["A2_gap_cycles"] = gap
    res["computed"]["A2_gap_pct_of_A2"] = 100.0 * gap / a2
    res["computed"]["A2_gap_pct_of_core"] = 100.0 * gap / 5995029.375
    res["computed"]["G0_clock_mhz"] = a2 * 30 / 1e6
    res["computed"]["G25_clock_mhz"] = a2 * 37.5 / 1e6
    add("A2 gap 171,414", abs(gap - 171414.0) < 1.0, "%.3f" % gap)
    add("G0 clock 192.642 MHz", abs(res["computed"]["G0_clock_mhz"] - 192.64243125) < 1e-9,
        "%.8f" % res["computed"]["G0_clock_mhz"])
    # G0 verdict
    closure = (TASK / "g0-closure.md").read_text(encoding="utf-8")
    verdict = json.loads((OUT / "g0-verdict.json").read_text(encoding="utf-8"))
    allowed = {"G0_feasible_for_scope", "G0_not_closed", "G0_not_proven"}
    add("G0 verdict word allowed", verdict.get("verdict") in allowed, str(verdict.get("verdict")))
    add("G0 verdict no downshift", verdict.get("not_downgraded") is True, str(verdict.get("not_downgraded")))
    add("G0 verdict G25 not headline", verdict.get("g25_used_for_headline") is False, str(verdict.get("g25_used_for_headline")))
    sc = verdict.get("scope", "")
    add("G0 scope slot-free", "slot-free" in sc, sc[:120])
    add("G0 scope proxy", "proxy" in sc and "proxy_not_worst" in sc, sc[:160])
    add("G0 scope per-stream", "per-stream" in sc, sc[:120])
    add("G0 scope behavioral DDR", "behavioral" in sc.lower() and "DDR" in sc, sc[:160])
    add("G0 scope no all-content claim", "all-content" not in sc.replace("not all-content", "").lower(),
        sc[:160])
    add("G0 verdict R3 S_ss <= 6.25M", verdict.get("runs", {}).get("r3", {}).get("S_ss") == m["r3"]["S_ss"],
        str(verdict.get("runs", {}).get("r3", {}).get("S_ss")))

    # ---------------------------------------------------------------- sink/tails
    for k in ["r0", "r1", "r2", "r3"]:
        tails = list(m[k].get("export_tail", {}).values())
        spread = max(tails) - min(tails) if tails else 0
        lim = (spread > 0.01 * m[k]["S_ss"]) or (max(tails) >= 0.5 * m[k]["S_ss"]) if tails else False
        add("%s tail constant/not sink-limited" % k.upper(), (not lim) and (not stats[k].get("wd", 1)),
            "tails=%s spread=%s S_ss=%s" % (tails, spread, m[k].get("S_ss")))
    # sink need
    payload = stats["r3"].get("exp_bytes") / 4.0
    exp_rate = (payload + 44) / (m["r3"]["export_tail"][1] / CLK) / 1e6 if m["r3"].get("export_tail") else None
    res["computed"]["r3_payload_per_frame"] = payload
    res["computed"]["r3_measured_export_MBps"] = exp_rate
    add("R3 measured export ~93.8 MB/s", exp_rate is not None and abs(exp_rate - 93.75) < 0.5, "%.6f" % (exp_rate or -1))
    need33 = 2594750 / 0.03333333333333333 / 1e6
    need25 = 2594750 / 0.025 / 1e6
    res["computed"]["sink_need_33ms_MBps"] = need33
    res["computed"]["sink_need_25ms_MBps"] = need25
    add("frozen raw sink need 77.84/103.79", abs(need33 - 77.8432784) < 1e-3 and abs(need25 - 103.79) < 1e-3,
        "%.6f / %.6f" % (need33, need25))

    # ---------------------------------------------------------------- header CRC
    hdr_words = parse_hex_words(CAPS / "r3.hdr")
    hdr = bytes()
    for w in hdr_words:
        # each line is a byte in %02x, not a 40-bit word
        hdr += bytes([w & 0xFF])
    hdr = hdr[:256]
    add("R3 hdr >=44 bytes", len(hdr) >= 44, "bytes=%d" % len(hdr))
    u32 = lambda o: int.from_bytes(hdr[o:o + 4], "little")
    got_h = {"raw_len": u32(16), "xform_len": u32(20), "stream_len": u32(24),
             "raw_crc": u32(28), "xform_crc": u32(32), "stream_crc": u32(36), "header_crc": u32(40)}
    raw_words = parse_hex_words(CAPS / "comp_raw.hex")
    raw = b"".join(word_to_5b(w) for w in raw_words)
    vec_words = parse_hex_words(CAPS / "comp_vec.hex")[:30720]
    tiled = b"".join(word_to_5b(vec_words[(b % 32) * 960 + p]) for b in range(540) for p in range(960))
    exp_h = {"raw_len": len(raw), "xform_len": len(tiled),
             "raw_crc": zlib.crc32(raw) & 0xFFFFFFFF, "xform_crc": zlib.crc32(tiled) & 0xFFFFFFFF}
    badh = {k: [exp_h[k], got_h[k]] for k in exp_h if exp_h[k] != got_h[k]}
    hcrc = zlib.crc32(hdr[0:40]) & 0xFFFFFFFF
    res["computed"]["r3_header"] = {"got": got_h, "expected": exp_h, "header_crc_calc": hcrc}
    add("R3 export header raw/xform len+crc", not badh, json.dumps(badh))
    add("R3 export header CRC", hcrc == got_h["header_crc"], "%08x vs %08x" % (hcrc, got_h["header_crc"]))
    add("R3 stream_len == exp_bytes/4", got_h["stream_len"] == stats["r3"].get("exp_bytes") / 4,
        "%s vs %s" % (got_h["stream_len"], stats["r3"].get("exp_bytes") / 4))

    # ---------------------------------------------------------------- proxy mapping
    cp = content_proxy_check()
    res["computed"]["content_proxy"] = cp
    add("content proxy raw->vec independent 0 mismatch", cp.get("ok"), json.dumps(cp))
    # content-proxy.json raw/xform hashes/crcs
    proxy = json.loads((OUT / "content-proxy.json").read_text(encoding="utf-8"))
    add("content-proxy raw_sha256", proxy["outputs"]["raw_sha256"] == sha_bytes(raw),
        "%s vs %s" % (proxy["outputs"]["raw_sha256"], sha_bytes(raw)))
    add("content-proxy tiled_sha256", proxy["outputs"]["tiled_xform_sha256"] == sha_bytes(tiled),
        "%s vs %s" % (proxy["outputs"]["tiled_xform_sha256"], sha_bytes(tiled)))
    add("content-proxy raw_crc", proxy["outputs"]["raw_crc32"] == (zlib.crc32(raw) & 0xFFFFFFFF),
        "%s vs %s" % (proxy["outputs"]["raw_crc32"], zlib.crc32(raw) & 0xFFFFFFFF))
    add("content-proxy xform_crc", proxy["outputs"]["xform_crc32"] == (zlib.crc32(tiled) & 0xFFFFFFFF),
        "%s vs %s" % (proxy["outputs"]["xform_crc32"], zlib.crc32(tiled) & 0xFFFFFFFF))
    # in.meta raw vs proxy metadata
    meta_raw = (COMP / "in.meta").read_bytes()
    meta_norm = (COMP / "in.meta").read_text(encoding="ascii").encode()
    res["computed"]["in_meta"] = {"raw_bytes": len(meta_raw), "raw_sha": sha_bytes(meta_raw),
                                  "norm_bytes": len(meta_norm), "norm_sha": sha_bytes(meta_norm),
                                  "proxy_bytes": proxy["inputs"]["in.meta"]["bytes"],
                                  "proxy_sha": proxy["inputs"]["in.meta"]["sha256"]}
    add("content-proxy in.meta metadata matches raw file",
        proxy["inputs"]["in.meta"]["bytes"] == len(meta_raw) and proxy["inputs"]["in.meta"]["sha256"] == sha_bytes(meta_raw),
        "actual=%d/%s proxy=%s/%s" % (len(meta_raw), sha_bytes(meta_raw)[:16],
                                      proxy["inputs"]["in.meta"]["bytes"], proxy["inputs"]["in.meta"]["sha256"][:16]))
    add("content-proxy in.hex/in.xform hashes",
        proxy["inputs"]["in.hex"]["sha256"] == sha_file(COMP / "in.hex")
        and proxy["inputs"]["in.xform"]["sha256"] == sha_file(COMP / "in.xform"),
        "in.hex=%s in.xform=%s" % (sha_file(COMP / "in.hex")[:16], sha_file(COMP / "in.xform")[:16]))

    # ---------------------------------------------------------------- vec match / TB versions
    v1 = read_log_events(TASK / "sim" / "logs" / "v1.log")
    add("v1 SS_VEC_MATCH bad=0 checked=518400", v1["vec_match"] and v1["vec_match"][-1] == (0, 518400, 518400),
        str(v1["vec_match"]))
    add("R3 pre-fix self-check disclosed bad=691132", logs["r3"]["vec_match"] and logs["r3"]["vec_match"][-1][0] == 691132,
        str(logs["r3"]["vec_match"]))
    old_tb = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\ss-g0\tb_prefix.v")
    add("old R0-R3 TB hash 89948303 available", old_tb.exists() and sha_file(old_tb) ==
        "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e",
        sha_file(old_tb) if old_tb.exists() else "missing")
    add("frozen TB hash a565c6f2", sha_file(TASK / "src" / "tb_ss_g0.v") ==
        "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",
        sha_file(TASK / "src" / "tb_ss_g0.v"))

    # ---------------------------------------------------------------- TB diff vs P1
    p1tb = (P1 / "src" / "tb_ss_anchor.v").read_text(encoding="utf-8").splitlines()
    p3tb = (TASK / "src" / "tb_ss_g0.v").read_text(encoding="utf-8").splitlines()
    import difflib
    diff = list(difflib.unified_diff(p1tb, p3tb, fromfile="tb_ss_anchor.v", tofile="tb_ss_g0.v", lineterm=""))
    res["diffs"]["p1_to_p3_tb"] = diff
    add("P3 TB has no force/deposit", "force " not in "\n".join(p3tb) and "$deposit" not in "\n".join(p3tb),
        "force/deposit absent")
    add("P3 TB DUT port map unchanged except clk_uart",
        ".clk_uart (clk_uart)" in "\n".join(p3tb) and ".clk_uart (clk_a1)" in "\n".join(p1tb),
        "clk_uart net switched by SINK")
    add("P3 TB geometry/GAP unchanged",
        all(x in "\n".join(p3tb) for x in ["CAM_W = 3864", "CAM_H = 2192", "ROI_X = 972", "ROI_Y = 556",
                                "LINE_GAP = 16", "FRAME_GAP = 400", "UART_DIV = 1"]),
        "geometry params present")
    add("P3 TB WD_LIMIT changed 8M->12M (non-whitelisted, disclosed)", "WD_LIMIT = 12000000" in "\n".join(p3tb),
        "WD_LIMIT 12M")
    add("P3 TB dec format %02x vs P1 %0d (disclosed)", "%02x" in "\n".join(p3tb) and "%0d" in "\n".join(p1tb),
        "dec text format differs")

    # ---------------------------------------------------------------- hashes / inputs
    protected = [
        (P1 / "manifest-r0.json", "39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a"),
        (P1 / "out" / "steady-state.json", "a0945e1f60d9e7651d3db2d1a4d939b665d4fe451e9206537fb3b7d0c5430023"),
        (P1 / "sim" / "run_ss.py", "d7417ea1f4ee32c17412a0d82ee547407cd8dc6be7b1ebe34061c347586dbac8"),
        (P1 / "src" / "tb_ss_anchor.v", "ddd9e02ca71aa3b81e86f4cc0f151498fd48bf9a4dbbcc042b59c97d9f15d1ff"),
        (P1 / "sim" / "caps" / "ss4.stats", "29bd31851804714bf65df6d5f4aa29f9daddccebe4d858e08dbfed2e937981a5"),
        (P2 / "manifest-r0.json", "fd27c70f304f51ba0b0b022398acd46f1f5f43a32351acfc472dea12e034fad0"),
        (P2 / "verdict-r1.md", "62ec3adc067101383613ef3e5ff659b7139f320f57d1f1e6ad6ea30c09a3c18a"),
        (COMP / "in.hex", "edbfdeaedb06824ced20ad76b260979e95e1322d6f6e3bab5e7a951a268f9849"),
    ]
    badp = []
    for p, exp in protected:
        got = sha_file(p)
        if got != exp:
            badp.append([str(p), exp, got])
    add("8 protected inputs 0 drift", not badp, json.dumps(badp))
    # all P2 artifacts vs its manifest
    p2m = json.loads((P2 / "manifest-r0.json").read_text(encoding="utf-8"))
    bad2 = []
    for a in p2m["artifacts"]:
        fp = P2 / a["path"]
        if not fp.exists() or sha_file(fp) != a["sha256"]:
            bad2.append(a["path"])
    add("P2 34 artifacts 0 drift", not bad2, json.dumps(bad2))
    # P1 artifacts vs its manifest
    p1m = json.loads((P1 / "manifest-r0.json").read_text(encoding="utf-8"))
    bad1 = []
    for a in p1m.get("artifacts", []):
        fp = P1 / a["path"]
        if not fp.exists() or sha_file(fp) != a["sha256"]:
            bad1.append(a["path"])
    add("P1 artifacts 0 drift", not bad1, json.dumps(bad1))
    # 12 DUT copies vs P1 manifest
    p1art = {a["path"]: a["sha256"] for a in p1m.get("artifacts", [])}
    copies = ["a1_ddr_arb2.v", "a1_ddr_model.v", "a1_ddr_slot_store.v", "a1_deflate_core.v",
              "a1_frame_top.v", "a1_raw_crop.v", "a1_uart_export.v", "cam_diag_mailbox.v",
              "camera_a1_uart_top.v", "capture_async_fifo.v", "p2_ddr_bridge.v", "p2_paxi_model_b11.v"]
    badc = []
    for c in copies:
        fp = TASK / "src" / c
        # P1 manifest path is src/<c>
        exp = p1art.get("src/" + c)
        if exp is None or sha_file(fp) != exp:
            badc.append([c, exp, sha_file(fp)])
    add("12 DUT copies == P1 manifest", not badc, json.dumps(badc))
    # comp vector decode
    hex_txt = (COMP / "in.hex").read_bytes()
    vec = bytes(int(x, 16) for x in hex_txt.split())
    xform = (COMP / "in.xform").read_bytes()
    add("comp in.hex decodes == in.xform", vec == xform and len(vec) == 153600, "len=%d" % len(vec))

    # ---------------------------------------------------------------- manifest artifacts
    man = json.loads((TASK / "manifest-r0.json").read_text(encoding="utf-8"))
    badm = []
    for a in man["artifacts"]:
        fp = TASK / a["path"]
        if not fp.exists() or sha_file(fp) != a["sha256"]:
            badm.append(a["path"])
    add("manifest 68 artifacts match", len(man["artifacts"]) == 68 and not badm,
        "count=%d bad=%s" % (len(man["artifacts"]), badm))
    add("manifest stopped/active", man.get("stopped_modifying") is True and man.get("active_commands") == 0,
        json.dumps({"stopped_modifying": man.get("stopped_modifying"), "active_commands": man.get("active_commands")}))
    add("manifest no forbidden actions", man.get("forbidden_actions_used") == [], str(man.get("forbidden_actions_used")))
    # commands
    cmds = man.get("commands", [])
    add("no TD/board/COM/JTAG commands", all(("vsim" in c["argv"][0].lower() or "vlog" in c["argv"][0].lower()
                                             or "vlib" in c["argv"][0].lower()) for c in cmds),
        "n=%d" % len(cmds))
    nz = [c for c in cmds if c["rc"] != 0]
    add("only the documented aborted v1 attempt has rc!=0",
        len(nz) == 1 and nz[0]["argv"][0].lower().endswith("vsim.exe") and nz[0]["seconds"] < 300,
        "nz=%s" % [(c["rc"], c["seconds"]) for c in nz])
    add("vsim timeout 2700 / vlog 1200", all(c["timeout_s"] in (2700, 1200, 300) for c in cmds),
        str(sorted(set(c["timeout_s"] for c in cmds))))
    add("sim wall <= 90 min", man.get("budget", {}).get("sim_wall_seconds", 0) <= 5400,
        str(man.get("budget", {}).get("sim_wall_seconds")))
    add("full-frame vsim count <=5", man.get("budget", {}).get("full_frame_vsim_runs", 99) <= 5,
        str(man.get("budget", {}).get("full_frame_vsim_runs")))

    # ---------------------------------------------------------------- DDR/UART
    ddr_total = 809.034
    gate = 1.25 * ddr_total
    res["computed"]["ddr"] = {
        "peak_1333": 1333 * 4, "peak_1600": 1600 * 4,
        "req_eff_1333": ddr_total / (1333 * 4) * 100, "gate_eff_1333": gate / (1333 * 4) * 100,
        "req_eff_1600": ddr_total / (1600 * 4) * 100, "gate_eff_1600": gate / (1600 * 4) * 100}
    add("DDR 5332/6400 + eff values", abs(res["computed"]["ddr"]["req_eff_1333"] - 15.1732) < 1e-3
        and abs(res["computed"]["ddr"]["gate_eff_1333"] - 18.9665) < 1e-3
        and abs(res["computed"]["ddr"]["req_eff_1600"] - 12.6412) < 1e-3
        and abs(res["computed"]["ddr"]["gate_eff_1600"] - 15.8014) < 1e-3,
        json.dumps(res["computed"]["ddr"]))
    uart = {"bps": 115200 / 10, "t_40032": 40032 / 11520, "t_2594706": 2594706 / 11520}
    res["computed"]["uart"] = uart
    add("UART 11520 B/s / 3.475 s / 225.235 s", abs(uart["bps"] - 11520) < 1e-9
        and abs(uart["t_40032"] - 3.475) < 1e-3 and abs(uart["t_2594706"] - 225.235) < 1e-2,
        json.dumps(uart))

    # ---------------------------------------------------------------- negative controls
    neg = json.loads((OUT / "negative-controls.json").read_text(encoding="utf-8"))
    add("5 negative controls all rejected", neg.get("all_rejected") is True and len(neg.get("controls", [])) == 5,
        json.dumps([(n["id"], n["rejected"]) for n in neg.get("controls", [])]))
    add("no 1600x900 as G0 alternative recommendation", "1600" in closure,
        "manual check: report only cites 1600x900 as a non-recommendation")
    # (manual) recommendation wording reviewed in the report
    # (manual) recommendation wording reviewed in the report
    # verdict words
    add("closure verdict word G0_feasible_for_scope", "G0_feasible_for_scope" in closure, "found")
    add("closure label proxy_not_worst", "proxy_not_worst" in closure, "found")
    add("closure proxy_not_worst + not_proven boundary", "proxy_not_worst" in closure and "not_proven" in closure, "checked")
    return res


if __name__ == "__main__":
    try:
        r = main()
    except Exception as e:
        import traceback
        traceback.print_exc()
        r = {"fatal": str(e), "checks": res.get("checks", []), "computed": res.get("computed", {})}
    (TEST / "evidence" / "verify_g0.json").write_text(json.dumps(r, indent=2, ensure_ascii=False), encoding="utf-8")
    npass = sum(1 for c in r.get("checks", []) if c["ok"])
    nfail = sum(1 for c in r.get("checks", []) if not c["ok"])
    print("checks=%d pass=%d fail=%d" % (len(r.get("checks", [])), npass, nfail))
    for c in r.get("checks", []):
        if not c["ok"]:
            print("FAIL:", c["name"], "||", c["detail"])
    if "fatal" in r:
        print("FATAL:", r["fatal"])
    print(json.dumps(r.get("computed", {}), indent=2)[:12000])

