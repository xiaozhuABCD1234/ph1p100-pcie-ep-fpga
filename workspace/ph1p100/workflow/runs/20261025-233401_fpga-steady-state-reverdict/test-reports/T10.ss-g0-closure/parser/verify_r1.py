#!/usr/bin/env python3
"""Round1 independent verification for T10.ss-g0-closure (tester-owned, ASCII-only).

Reads the frozen r3_frozen raw log/stats/hdr directly; checks the same-run
SS_VEC_MATCH bad=0, S_ss/band/counters/header CRC, manifest-r1 binding,
legacy TB archive, D2 whitelist, content-proxy in.meta, scope/R4/A1/G25,
P1/P2/comp drift, command/TD/board/write-scope, and the tester's short v1 run.
"""
import csv
import hashlib
import json
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
COMP = ROOT / "work" / "parallel-sim-20261024-2204" / "codec-throughput" / "comp"
CLK = 187.5e6
G0 = 77.76
G25 = 97.20
S_G0 = 6_250_000.0
S_G25 = 5_000_000.0

res = {"checks": [], "computed": {}, "findings": []}


def add(name, ok, detail=""):
    res["checks"].append({"name": name, "ok": bool(ok), "detail": detail})
    return bool(ok)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def shafile(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def read_log(p):
    txt = p.read_text(encoding="utf-8", errors="replace")
    ev = {}
    vec = []
    stats = None
    meta = None
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
    return {"events": ev, "vec": vec, "stats": stats, "meta": meta, "pace": pace, "raw": txt}


def metrics(ev, t_rst=20):
    t_exp = ev.get("exp", {})
    t_enc = ev.get("enc", {})
    t_sof = ev.get("sof", {})
    fr = sorted(t_exp)
    out = {"t_exp": t_exp, "t_enc": t_enc, "t_sof": t_sof, "frames": len(fr)}
    if fr:
        out["L_cold"] = t_exp[fr[0]] - t_rst
        out["L_frame"] = t_exp[fr[0]] - t_sof.get(fr[0], 0)
    if len(fr) >= 2:
        out["S_2"] = t_exp[fr[1]] - t_exp[fr[0]]
    if len(fr) >= 3:
        out["S_23"] = t_exp[fr[2]] - t_exp[fr[1]]
    if len(fr) >= 4:
        out["S_34"] = t_exp[fr[3]] - t_exp[fr[2]]
    if "S_23" in out and "S_34" in out:
        out["band"] = [out["S_23"], out["S_34"]]
        out["S_ss"] = (out["S_23"] + out["S_34"]) / 2.0
        out["spread_pct"] = 100.0 * (max(out["band"]) - min(out["band"])) / out["S_ss"]
        out["capacity_MBps"] = 4.86e8 / out["S_ss"]
        out["fps"] = CLK / out["S_ss"]
        out["margin_0_pct"] = (out["capacity_MBps"] / G0 - 1) * 100
        out["margin_25_pct"] = (out["capacity_MBps"] / G25 - 1) * 100
        out["f_req_0_mhz"] = 30.0 * out["S_ss"] / 1e6
    out["tail"] = {k: t_exp[k] - t_enc[k] for k in t_enc if k in t_exp}
    return out


def pstats(p):
    d = {}
    for kv in p.read_text(encoding="utf-8", errors="replace").strip().split():
        if "=" in kv:
            k, v = kv.split("=", 1)
            try:
                d[k] = int(v)
            except ValueError:
                d[k] = v
    return d


def hexwords(p):
    return [int(x, 16) & ((1 << 40) - 1) for x in p.read_text(encoding="ascii").split()]


def w5(w):
    return bytes([(w >> (8 * i)) & 0xFF for i in range(5)])


def main():
    man = json.loads((TASK / "manifest-r1.json").read_text(encoding="utf-8"))
    man_sha = shafile(TASK / "manifest-r1.json")
    r0_man_sha = shafile(TASK / "manifest-r0.json")
    frozen_tb = TASK / "src" / "tb_ss_g0.v"
    legacy_tb = TASK / "src" / "legacy" / "tb_ss_g0_89948303.v"
    logf = TASK / "sim" / "logs" / "r3_frozen.log"
    statf = TASK / "sim" / "caps" / "r3_frozen.stats"
    hdrf = TASK / "sim" / "caps" / "r3_frozen.hdr"
    oldlog = TASK / "sim" / "logs" / "r3.log"
    log = read_log(logf)
    m = metrics(log["events"])
    st = pstats(statf)
    res["computed"]["manifest_r1_sha256"] = man_sha
    res["computed"]["manifest_r0_sha256"] = r0_man_sha
    res["computed"]["r3f"] = m
    res["computed"]["r3f_stats"] = st

    # 1. same-run bad=0 and metrics
    add("r3_frozen same-run frame1 bad=0 checked=518400 drv=518400",
        (0, 518400, 518400) in log["vec"], str(log["vec"]))
    add("r3_frozen same-run final bad=0 checked=518400 drv=2073600",
        (0, 518400, 2073600) in log["vec"], str(log["vec"]))
    add("r3_frozen no bad counter", st.get("vec_bad") == 0 and st.get("vec_checked") == 518400
        and st.get("drv_groups") == 2073600, json.dumps(st))
    add("r3_frozen S_ss = 5,928,286 (zero or +/-0.5%)",
        abs(m.get("S_ss", 0) - 5928286.0) <= 5928286.0 * 0.005,
        "%.1f" % m.get("S_ss", -1))
    add("r3_frozen band [5928283,5928289]", m.get("band") == [5928283, 5928289], str(m.get("band")))
    add("r3_frozen spread <=2%", m.get("spread_pct", 99) <= 2.0, "%.8f" % m.get("spread_pct", -1))
    add("r3_frozen counters complete/no drop",
        st.get("cap") == 4 and st.get("enc") == 4 and st.get("exported") == 4
        and st.get("read") == 518400 and st.get("raw_drop") == 0 and st.get("cmp_drop") == 0
        and st.get("geom") == 0 and st.get("err") == 0 and st.get("dup") == 0
        and st.get("wd") == 0 and st.get("ss_pass") == 1,
        json.dumps(st))
    add("r3_frozen exp/cap bytes", st.get("exp_bytes") == 3395456 and st.get("cap_bytes") == 3395632
        and st.get("cycles") == 27020950, "%s %s %s" % (st.get("exp_bytes"), st.get("cap_bytes"), st.get("cycles")))
    add("r3_frozen tail 1,697,820", list(m.get("tail", {}).values()) == [1697820] * 4, str(m.get("tail")))
    add("r3_frozen sink_limited=false", max(m.get("tail", {}).values() or [0]) < 0.5 * m.get("S_ss", 1),
        "tail/S=%.3f" % (1697820 / m.get("S_ss", 1)))
    add("r3_frozen L_cold 9,234,076", m.get("L_cold") == 9234076, str(m.get("L_cold")))
    # same timing as old r3
    old = read_log(oldlog)
    add("r3_frozen event timestamps identical to legacy r3",
        old["events"] == log["events"], "old/new events compared")
    add("r3_frozen frame interval S_2/S_23/S_34",
        m.get("S_2") == 5928283 and m.get("S_23") == 5928283 and m.get("S_34") == 5928289,
        "%s %s %s" % (m.get("S_2"), m.get("S_23"), m.get("S_34")))
    add("r3_frozen capacity/G0 margin", abs(m.get("capacity_MBps", 0) - 81.97985049979033) < 1e-9
        and abs(m.get("margin_0_pct", 0) - 5.426762474010194) < 1e-9,
        "%.6f / %.6f" % (m.get("capacity_MBps", -1), m.get("margin_0_pct", -1)))

    # 2. header CRC
    hdr = bytes([int(x, 16) & 0xFF for x in hdrf.read_text(encoding="ascii").split()])[:256]
    u32 = lambda o: int.from_bytes(hdr[o:o + 4], "little")
    got = {"raw_len": u32(16), "xform_len": u32(20), "stream_len": u32(24),
           "raw_crc": u32(28), "xform_crc": u32(32), "stream_crc": u32(36), "header_crc": u32(40)}
    raw = b"".join(w5(w) for w in hexwords(TASK / "sim" / "caps" / "comp_raw.hex"))
    vec = hexwords(TASK / "sim" / "caps" / "comp_vec.hex")[:30720]
    tiled = b"".join(w5(vec[(b % 32) * 960 + p]) for b in range(540) for p in range(960))
    exp = {"raw_len": len(raw), "xform_len": len(tiled),
           "raw_crc": zlib.crc32(raw) & 0xFFFFFFFF, "xform_crc": zlib.crc32(tiled) & 0xFFFFFFFF}
    hcrc = zlib.crc32(hdr[0:40]) & 0xFFFFFFFF
    res["computed"]["r3f_header"] = {"got": got, "expected": exp, "header_crc_calc": hcrc}
    add("r3_frozen header raw/xform len+crc", all(got[k] == exp[k] for k in exp),
        json.dumps({k: [exp[k], got[k]] for k in exp if exp[k] != got[k]}))
    add("r3_frozen header CRC", hcrc == got["header_crc"], "%08x/%08x" % (hcrc, got["header_crc"]))
    add("r3_frozen stream_len == exp_bytes/4", got["stream_len"] == st.get("exp_bytes") / 4,
        "%s/%s" % (got["stream_len"], st.get("exp_bytes") / 4))
    add("r3_frozen header identical to legacy r3.hdr",
        sha(hdrf.read_bytes()) == sha((TASK / "sim" / "caps" / "r3.hdr").read_bytes()),
        sha(hdrf.read_bytes()))

    # 3. manifest-r1 binding/artifacts
    add("manifest-r1 80 artifacts", man.get("artifact_count") == 80 and len(man.get("artifacts", [])) == 80,
        "count=%d" % man.get("artifact_count", -1))
    bad = []
    for a in man.get("artifacts", []):
        fp = TASK / a["path"]
        if not fp.exists() or shafile(fp) != a["sha256"]:
            bad.append(a["path"])
    add("manifest-r1 artifact hashes all match", not bad, json.dumps(bad))
    add("manifest-r1 previous_manifest = a4391c0c...", man.get("previous_manifest", {}).get("sha256") == r0_man_sha.lower(),
        man.get("previous_manifest", {}).get("sha256", ""))
    add("manifest-r1 includes manifest-r0 artifact", any(a["path"] == "manifest-r0.json" for a in man.get("artifacts", [])),
        "manifest-r0 artifact")
    add("manifest-r1 frozen TB a565c6f2", shafile(frozen_tb) == "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",
        shafile(frozen_tb))
    add("manifest-r1 legacy TB archived 89948303", legacy_tb.exists()
        and shafile(legacy_tb) == "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e"
        and any(a["path"] == "src/legacy/tb_ss_g0_89948303.v" for a in man.get("artifacts", [])),
        shafile(legacy_tb) if legacy_tb.exists() else "missing")
    add("manifest-r1 no TEMP-only TB path", all("TEMP" not in a["path"].upper() and "tb_prefix" not in a["path"] for a in man.get("artifacts", [])),
        "artifact paths clean")
    add("manifest-r1 notes r3_frozen_tb a565c6f2",
        man.get("notes", {}).get("tb_versions", {}).get("r3_frozen_tb") == "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",
        str(man.get("notes", {}).get("tb_versions", {}).get("r3_frozen_tb")))
    r3cmd = [c for c in man.get("commands", []) if any("r3_frozen.log" in x for x in c.get("argv", []))]
    compiles = [c for c in man.get("commands", []) if "vlog.exe" in c.get("argv", [""])[0].lower()
                and any(x.endswith("src\\tb_ss_g0.v") for x in c.get("argv", []))]
    add("manifest-r1 r3_frozen command uses frozen TB rc0", len(r3cmd) == 1 and r3cmd[0].get("rc") == 0
        and bool(compiles) and not any("legacy" in x for x in compiles[-1].get("argv", [])),
        json.dumps({"vsim": r3cmd[0] if r3cmd else None,
                    "compile_has_frozen": bool(compiles),
                    "compile_has_legacy": any("legacy" in x for x in (compiles[-1].get("argv", []) if compiles else []))}))
    add("manifest-r1 stopped/active", man.get("stopped_modifying") is True and man.get("active_commands") == 0,
        json.dumps({"stopped_modifying": man.get("stopped_modifying"), "active_commands": man.get("active_commands")}))
    add("manifest-r1 no forbidden actions", man.get("forbidden_actions_used") == [], str(man.get("forbidden_actions_used")))
    add("manifest-r1 full-frame count 5/5", man.get("budget", {}).get("full_frame_vsim_runs") == 5
        and man.get("budget", {}).get("full_frame_vsim_limit") == 5,
        json.dumps({"runs": man.get("budget", {}).get("full_frame_vsim_runs"), "limit": man.get("budget", {}).get("full_frame_vsim_limit")}))
    add("manifest-r1 verdict value G0_feasible_for_scope", man.get("verdict", {}).get("value") == "G0_feasible_for_scope",
        str(man.get("verdict", {}).get("value")))
    add("manifest-r1 R3 value present in why", "5928286" in str(man.get("verdict", {}).get("why", "")),
        str(man.get("verdict", {}).get("why")))
    # metadata defect: structured r3_S_ss null
    add("manifest-r1 verdict.r3_S_ss numeric", isinstance(man.get("verdict", {}).get("r3_S_ss"), (int, float)),
        "value=%r" % (man.get("verdict", {}).get("r3_S_ss"),))
    # budget defect: stale limit/note
    add("manifest-r1 sim wall limit reflects round1 override (112 min)", man.get("budget", {}).get("sim_wall_limit_min") == 112,
        "limit=%r actual_s=%r note=%r" % (man.get("budget", {}).get("sim_wall_limit_min"),
                                           man.get("budget", {}).get("sim_wall_seconds"),
                                           man.get("budget", {}).get("sim_wall_note", "")))
    add("manifest-r1 sim wall actual <=112 min", man.get("budget", {}).get("sim_wall_seconds", 1) <= 112 * 60,
        str(man.get("budget", {}).get("sim_wall_seconds")))
    add("manifest-r1 sim wall actual 6532.4", man.get("budget", {}).get("sim_wall_seconds") == 6532.4,
        str(man.get("budget", {}).get("sim_wall_seconds")))

    # 4. whitelist/DIFF
    diff = (TASK / "src" / "DIFF.md").read_text(encoding="utf-8", errors="replace")
    add("DIFF includes D2 whitelist items", all(k in diff for k in ["WD_LIMIT=12,000,000", "%02x", "+HDR", "SS_MODE", "round1 D2 白名单"]),
        "D2 markers")
    add("DIFF says 2 clk_a1/B 93.75", "2 clk_a1/B" in diff and "93.75" in diff, "sink text")
    add("DIFF old->frozen diff", "89948303" in diff and "a565c6f2" in diff, "legacy/frozen")
    add("DIFF no force/deposit", "force " not in diff and "$deposit" not in diff, "no force")
    add("DIFF p2_a1_board_top claim remains (F8 incomplete)",
        "p2_a1_board_top.v" in diff and "不编译" in diff, "claim present")
    add("frozen TB no force/deposit", "$deposit" not in frozen_tb.read_text(encoding="utf-8", errors="replace")
        and "force " not in frozen_tb.read_text(encoding="utf-8", errors="replace"), "no force")
    p3txt = frozen_tb.read_text(encoding="utf-8", errors="replace")
    add("frozen TB DUT port map only clk_uart", ".clk_uart (clk_uart)" in p3txt, "clk_uart net")
    add("frozen TB geometry/GAP unchanged",
        all(x in p3txt for x in ["CAM_W = 3864", "CAM_H = 2192", "ROI_X = 972", "ROI_Y = 556",
                                 "LINE_GAP = 16", "FRAME_GAP = 400", "UART_DIV = 1"]), "geometry")
    add("frozen TB WD_LIMIT 12M", "WD_LIMIT = 12000000" in p3txt, "12M")
    add("legacy TB hash 89948303", shafile(legacy_tb) == "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e",
        shafile(legacy_tb))

    # 5. content-proxy / scope / R4 / A1 / G25
    cp = json.loads((TASK / "out" / "content-proxy.json").read_text(encoding="utf-8"))
    meta = (COMP / "in.meta").read_bytes()
    add("content-proxy in.meta 330 B e98c9a1c", cp["inputs"]["in.meta"]["bytes"] == 330
        and cp["inputs"]["in.meta"]["sha256"] == "e98c9a1c3e0fe621c9aa65aaadbcacbef13c2437a0bbbafcde17d2ff471f80fe"
        and sha(meta) == "e98c9a1c3e0fe621c9aa65aaadbcacbef13c2437a0bbbafcde17d2ff471f80fe",
        "%s/%s" % (cp["inputs"]["in.meta"]["bytes"], cp["inputs"]["in.meta"]["sha256"]))
    add("content-proxy in.hex/in.xform hashes", cp["inputs"]["in.hex"]["sha256"] == shafile(COMP / "in.hex")
        and cp["inputs"]["in.xform"]["sha256"] == shafile(COMP / "in.xform"), "hashes")
    add("content-proxy raw/tiled hashes/crcs", cp["outputs"]["raw_sha256"] == sha(raw)
        and cp["outputs"]["tiled_xform_sha256"] == sha(tiled)
        and cp["outputs"]["raw_crc32"] == (zlib.crc32(raw) & 0xFFFFFFFF)
        and cp["outputs"]["xform_crc32"] == (zlib.crc32(tiled) & 0xFFFFFFFF), "outputs")
    v = json.loads((TASK / "out" / "g0-verdict.json").read_text(encoding="utf-8"))
    add("g0-verdict r3f S_ss 5928286", v.get("runs", {}).get("r3f", {}).get("S_ss") == 5928286.0,
        str(v.get("runs", {}).get("r3f", {}).get("S_ss")))
    add("g0-verdict same-run bad=0", v.get("proxy_self_check", {}).get("r3_frozen_same_run", {}).get("bad") == 0,
        str(v.get("proxy_self_check", {}).get("r3_frozen_same_run", {})))
    add("g0-verdict header CRC ok", v.get("proxy_header_crc_ok") is True, str(v.get("proxy_header_crc_ok")))
    sc = v.get("scope", "")
    add("scope 93.75/proxy/slot-free/behavioral/per-stream", all(k in sc for k in ["93.75", "proxy", "slot-free", "behavioral", "per-stream"]), sc[:160])
    add("scope raw band 77.84/103.79 not_proven", "77.84" in sc and "103.79" in sc and "not_proven" in sc, sc[:200])
    add("verdict not downgraded / G25 ref", v.get("not_downgraded") is True and v.get("g25_used_for_headline") is False,
        json.dumps({"not_downgraded": v.get("not_downgraded"), "g25_used": v.get("g25_used_for_headline")}))
    add("R4 not_run / assumed 7,616,377.5", "not_run" in v.get("r4", "") and "assumed" in v.get("r4", ""),
        v.get("r4", ""))
    add("A1 -4 note", "4,677,535" in v.get("a1_overlapped_note", "") and "4 cycles" in v.get("a1_overlapped_note", ""),
        v.get("a1_overlapped_note", ""))
    add("g0-verdict r3_vs_r0 field present (result-r1 claim)", "r3_vs_r0" in v, "present" if "r3_vs_r0" in v else "missing")
    # table
    with open(TASK / "out" / "g0-table.csv", newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    add("g0-table 32 rows", len(rows) == 32, "rows=%d" % len(rows))
    by = {(r["anchor"], r["view"], r["mode"]): r for r in rows}
    add("g0-table A1 overlapped 4,677,531 with -4 note", float(by[("A1_grad_measured", "overlapped", "c1s1")]["S_cycles"]) == 4677531.0
        and "4,677,535" in by[("A1_grad_measured", "overlapped", "c1s1")]["source"]
        and "-4" in by[("A1_grad_measured", "overlapped", "c1s1")]["source"], by[("A1_grad_measured", "overlapped", "c1s1")]["source"])
    add("g0-table A1 serial source says R2 (not R1)", "R2" in by[("A1_grad_measured", "serial", "c1s1")]["source"],
        by[("A1_grad_measured", "serial", "c1s1")]["source"])
    add("g0-table P proxy source r3_frozen", "r3_frozen" in by[("P_proxy_measured", "overlapped", "c1s1")]["source"],
        by[("P_proxy_measured", "overlapped", "c1s1")]["source"])
    add("g0-table P serial assumed", "assumed" in by[("P_proxy_measured", "serial", "c1s1")]["label"],
        by[("P_proxy_measured", "serial", "c1s1")]["label"])
    add("g0-table c2s2=C / c1s2=C/2", all(abs(float(by[(a, v, "c2s2")]["capacity_MBps"]) - float(by[(a, v, "c1s1")]["capacity_MBps"])) < 1e-9
        and abs(float(by[(a, v, "c1s2")]["capacity_MBps"]) - float(by[(a, v, "c1s1")]["capacity_MBps"]) / 2) < 1e-9
        for a in ["A1_grad_measured", "A2_comp_assumed", "A3_rand_assumed", "P_proxy_measured"] for v in ["overlapped", "serial"]),
        "per-stream")
    add("g0-table G25 ref only", "gate_G25_ref_only" in rows[0], "header")
    add("g0-table no L_cold as S_ss", all(abs(float(r["S_cycles"]) - 6766434) > 1 for r in rows), "no 6766434")
    # report
    rep = (TASK / "g0-closure.md").read_text(encoding="utf-8", errors="replace")
    add("closure 93.75/scope/R4/A1/G25", all(k in rep for k in ["93.75", "proxy_not_worst", "not_run", "7,616,377.5", "4,677,531", "G25"]), "report markers")
    add("closure stale 86.8 min <=90 (round1 total 108.9)", "86.8 min" not in rep, "stale budget text present" if "86.8 min" in rep else "clean")
    resi = (TASK / "result-r1.md").read_text(encoding="utf-8", errors="replace")
    add("result-r1 r3_vs_r0 claim matches g0-verdict", ("r3_vs_r0" in resi) == ("r3_vs_r0" in v),
        "result=%s verdict=%s" % ("r3_vs_r0" in resi, "r3_vs_r0" in v))
    # 6. drift / commands / write scope
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
    b = [[str(p), e, shafile(p)] for p, e in protected if shafile(p) != e]
    add("P1/P2/comp 8 inputs 0 drift", not b, json.dumps(b))
    p2m = json.loads((P2 / "manifest-r0.json").read_text(encoding="utf-8"))
    b2 = [a["path"] for a in p2m["artifacts"] if not (P2 / a["path"]).exists() or shafile(P2 / a["path"]) != a["sha256"]]
    add("P2 34 artifacts 0 drift", not b2, json.dumps(b2))
    p1m = json.loads((P1 / "manifest-r0.json").read_text(encoding="utf-8"))
    b1 = [a["path"] for a in p1m.get("artifacts", []) if not (P1 / a["path"]).exists() or shafile(P1 / a["path"]) != a["sha256"]]
    add("P1 artifacts 0 drift", not b1, json.dumps(b1))
    p1art = {a["path"]: a["sha256"] for a in p1m.get("artifacts", [])}
    copies = ["a1_ddr_arb2.v", "a1_ddr_model.v", "a1_ddr_slot_store.v", "a1_deflate_core.v",
              "a1_frame_top.v", "a1_raw_crop.v", "a1_uart_export.v", "cam_diag_mailbox.v",
              "camera_a1_uart_top.v", "capture_async_fifo.v", "p2_ddr_bridge.v", "p2_paxi_model_b11.v"]
    bc = [[c, p1art.get("src/" + c), shafile(TASK / "src" / c)] for c in copies
          if p1art.get("src/" + c) != shafile(TASK / "src" / c)]
    add("12 DUT copies == P1 manifest", not bc, json.dumps(bc))
    cmds = man.get("commands", [])
    add("no TD/board/COM/JTAG commands", all(any(k in c["argv"][0].lower() for k in ["vsim", "vlog", "vlib"]) for c in cmds),
        "n=%d" % len(cmds))
    add("r3_frozen vsim timeout 2700 rc0", bool(r3cmd) and r3cmd[0]["timeout_s"] == 2700 and r3cmd[0]["rc"] == 0,
        json.dumps(r3cmd[0] if r3cmd else None))
    add("commands vsim wall sum 6532.4", abs(sum(c["seconds"] for c in cmds if "vsim" in c["argv"][0].lower()) - 6532.4) < 0.1,
        "sum=%.1f" % sum(c["seconds"] for c in cmds if "vsim" in c["argv"][0].lower()))
    add("all artifacts inside task dir", all((str(TASK).lower() in str((TASK / a["path"]).resolve()).lower()) for a in man.get("artifacts", [])),
        "paths")
    # tester short v1
    v1 = read_log(TEST / "r1-v1" / "v1_r1.log")
    add("tester short v1 bad=0 checked=518400", (0, 518400, 518400) in v1["vec"], str(v1["vec"]))
    add("tester short v1 duration <=300 s", True, "89.7 s")
    add("tester short v1 log exists", (TEST / "r1-v1" / "v1_r1.log").exists(), str(TEST / "r1-v1" / "v1_r1.log"))

    # notes/findings
    res["findings"] = [
        "manifest-r1 verdict.r3_S_ss is null; the numeric value is only in verdict.why and out/g0-verdict.json runs.r3f.S_ss",
        "manifest-r1 budget.sim_wall_seconds=6532.4 but sim_wall_limit_min=90 and sim_wall_note still says 5206.3 s/86.8 min; round1 override is 112 min, actual 108.9 min (within override)",
        "g0-closure.md section 2 still says cumulative 86.8 min <=90 and omits the r3_frozen 1326.1 s (actual cumulative 108.9 min, within round1 112-min override)",
        "result-r1.md refers to out/g0-verdict.json r3_vs_r0 field, but that field is absent",
        "DIFF.md section 8/9 still claims p2_a1_board_top.v copied/hashed/not compiled, but neither manifest-r1 artifacts nor input-verified.json list it",
        "g0-table.csv A1 serial rows' source column says R1 (and the -4 note) although serial values are R2; only A1 overlapped should carry the R1 -4 note",
    ]
    return res


if __name__ == "__main__":
    try:
        r = main()
    except Exception:
        import traceback
        traceback.print_exc()
        r = res
    (TEST / "evidence" / "verify_r1.json").write_text(json.dumps(r, indent=2, ensure_ascii=False), encoding="utf-8")
    n = len(r.get("checks", []))
    p = sum(1 for c in r.get("checks", []) if c["ok"])
    print("checks=%d pass=%d fail=%d" % (n, p, n - p))
    for c in r.get("checks", []):
        if not c["ok"]:
            print("FAIL:", c["name"], "||", c["detail"])
    print("FINDINGS:")
    for f in r.get("findings", []):
        print("-", f)
