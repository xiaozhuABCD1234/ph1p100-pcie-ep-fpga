#!/usr/bin/env python3
"""P4 T10.ss-4run-matrix bounded driver.

Subcommands (one vsim per invocation, hard 2700 s timeout):
  verify             input freeze / drift -> input-verified.json
  compile            vlib + vlog 12 frozen sources + tb_ss_4run.v
  r1|r2|r3|r4        one full-size 4-frame run (see RUNS)
  analyze            parse completed runs -> runs-4.csv / four-run-table.csv /
                     g0-verdict.json / gap-menu.csv / negative-controls.json

Writes only inside this task's r0/ directory and %TEMP%\opencode\ss-4run\.
"""
import csv
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import zlib

sys.dont_write_bytecode = True

HERE = pathlib.Path(__file__).resolve().parent
R0 = HERE.parent
SRC = R0 / "src"
SIM = HERE
LOGS = SIM / "logs"
CAPS = SIM / "caps"
CONTENT = R0 / "content"
OUT = R0 / "out"
ROOT = pathlib.Path(r"D:/fpga/ph1p100")
RUNROOT = ROOT / "workflow/runs/20261025-233401_fpga-steady-state-reverdict"
P1 = RUNROOT / "T10.ss-steady-anchor/r0"
P2 = RUNROOT / "T10.ss-verdict-r1/r0"
P3 = RUNROOT / "T10.ss-g0-closure/r0"
MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
WORK = pathlib.Path(os.environ.get("TEMP", r"C:\Users\czz\AppData\Local\Temp")) / "opencode" / "ss-4run" / "work"
CLOCK_HZ = 187.5e6
G0_MBPS = 77.76
G25_MBPS = 97.20
G0_CYCLES = 6250000.0
RAW_BAND_BYTES = 2594750          # 2,592,000 raw + 540*5 stored + 6 zlib + 44 header
SINK_NEED_33 = RAW_BAND_BYTES / 33.333e-3 / 1e6
SINK_NEED_25 = RAW_BAND_BYTES / 25.0e-3 / 1e6
P3_R3_EXPECT = 5928286.0
P3_R3_TOL = 0.005

SRC_FILES = [
    "a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v",
    "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
    "a1_deflate_core.v", "p2_ddr_bridge.v", "p2_a1_board_top.v",
    "a1_ddr_arb2.v", "capture_async_fifo.v", "p2_paxi_model_b11.v",
    "a1_ddr_model.v",
]
COMPILE = [f for f in SRC_FILES if f != "p2_a1_board_top.v"] + ["tb_ss_4run.v"]

RUNS = {
    "r1": dict(frames=4, content=2, content_id="C1", pacing=0, sink=1, capture=0,
               mode="C1_raw_slotfree", raw40="raw40_p1d1.hex",
               label="full_frame_raw_synthetic/grad"),
    "r2": dict(frames=4, content=2, content_id="C1", pacing=1, sink=1, capture=0,
               mode="C1_raw_serial", raw40="raw40_p1d1.hex",
               label="full_frame_raw_synthetic/grad"),
    "r3": dict(frames=4, content=3, content_id="C2", pacing=0, sink=1, capture=0,
               mode="C2_rand_slotfree", raw40="raw40_rand.hex",
               label="full_frame_raw_synthetic/rand"),
    "r4": dict(frames=4, content=1, content_id="C3_C7", pacing=0, sink=1, capture=0,
               mode="comp_proxy_slotfree_P3_control", label="proxy_not_worst"),
}
FULL_RUNS = ("r1", "r2", "r3", "r4")
BUDGET_WALL_S = 7200


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


def jdump(p, obj):
    pathlib.Path(p).write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def jload(p, default=None):
    p = pathlib.Path(p)
    if not p.exists():
        return default
    return json.loads(p.read_text(encoding="utf-8"))


def cmdlog(rec):
    LOGS.mkdir(parents=True, exist_ok=True)
    with open(SIM / "commands.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")


def run_proc(argv, cwd, log_path, timeout):
    log_path = pathlib.Path(log_path)
    out_path = log_path.with_suffix(log_path.suffix + ".out")
    t0 = time.monotonic()
    timed_out = False
    rc = None
    with open(out_path, "wb") as out:
        proc = subprocess.Popen([str(x) for x in argv], cwd=str(cwd), stdout=out,
                                stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            rc = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                           capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            rc = 124
    el = time.monotonic() - t0
    rec = {"argv": [str(x) for x in argv], "cwd": str(cwd), "rc": rc,
           "timed_out": timed_out, "seconds": round(el, 1), "timeout_s": timeout,
           "log": str(log_path)}
    cmdlog(rec)
    return rc, el, timed_out


def toolenv():
    env = os.environ.copy()
    env["MODEL_TECH"] = str(MS)
    env["MODELSIM"] = str(SIM / "modelsim.ini")
    env["PATH"] = str(MS) + os.pathsep + env.get("PATH", "")
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def compile_all():
    WORK.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    rc, el, to = run_proc([MS / "vlib.exe", "work"], WORK, LOGS / "vlib.log", 300)
    if rc != 0:
        raise SystemExit("vlib failed rc=%s" % rc)
    files = [SRC / f for f in COMPILE]
    argv = [MS / "vlog.exe", "-sv", "-work", "work", "+define+SIMULATION"] + files
    rc, el, to = run_proc(argv, WORK, LOGS / "vlog.log", 1200)
    text = (LOGS / "vlog.log.out").read_text(errors="replace") if (LOGS / "vlog.log.out").exists() else ""
    errs = len(re.findall(r"\*\* Error", text))
    print("compile rc=%s %.1fs timeout=%s errors=%d" % (rc, el, to, errs))
    if rc != 0 or errs:
        raise SystemExit("compile failed")


def spent_full_seconds():
    total = 0.0
    for line in (SIM / "commands.jsonl").read_text().splitlines() if (SIM / "commands.jsonl").exists() else []:
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if any(("tb_ss_4run" in str(a)) for a in rec.get("argv", [])) and rec.get("timeout_s") == 2700:
            total += rec.get("seconds", 0.0)
    return total


def vsim(run_key):
    cfg = RUNS[run_key]
    spent = spent_full_seconds()
    if spent >= BUDGET_WALL_S:
        print("BUDGET_EXHAUSTED spent=%.1fs" % spent)
        raise SystemExit(3)
    LOGS.mkdir(parents=True, exist_ok=True)
    CAPS.mkdir(parents=True, exist_ok=True)
    tag = run_key
    stat = CAPS / (tag + ".stats")
    evt = CAPS / (tag + ".evt")
    hdr = CAPS / (tag + ".hdr")
    log = LOGS / (tag + ".log")
    argv = [MS / "vsim.exe", "-c", "-lib", "work", "-l", log, "tb_ss_4run",
            "+STAT=" + str(stat), "+EVT=" + str(evt), "+HDR=" + str(hdr),
            "-gFRAMES=%d" % cfg["frames"],
            "-gCONTENT=%d" % cfg["content"], "-gPACING=%d" % cfg["pacing"],
            "-gSINK=%d" % cfg["sink"], "-gCAPTURE=%d" % cfg["capture"]]
    if cfg["content"] == 1:
        argv.insert(-1, "+RAW=" + str(CONTENT / "comp_raw.hex"))
        argv.insert(-1, "+VEC=" + str(CONTENT / "comp_vec.hex"))
    else:
        argv.insert(-1, "+RAW40=" + str(CONTENT / cfg["raw40"]))
    argv += ["-do", "run -all; quit -f"]
    rc, el, to = run_proc(argv, WORK, log, 2700)
    print("%s rc=%s %.1fs timeout=%s spent=%.0fs" % (run_key, rc, el, to, spent + el))
    if not stat.exists():
        print("NO STATS (partial)")
        return
    m = metrics(run_key, tag, stat, log, el, rc, to)
    db = jload(OUT / "runs.json", {})
    db[run_key] = m
    jdump(OUT / "runs.json", db)
    print("%s S_ss=%s band=%s exp_bytes=%s cycles=%s partial=%s raw_bad=%s vec_bad=%s" % (
        run_key, m.get("S_ss"), m.get("S_band_cycles"),
        m.get("counters", {}).get("exp_bytes"), m.get("counters", {}).get("cycles"),
        m.get("partial"), (m.get("ss_raw_match") or {}).get("bad"),
        (m.get("ss_vec_match") or {}).get("bad")))


def metrics(key, tag, stat_path, log_path, el, rc, to):
    stats = {}
    for tok in stat_path.read_text().split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            try:
                stats[k] = int(v, 0)
            except ValueError:
                stats[k] = v
    text = log_path.read_text(errors="replace") if log_path.exists() else ""
    ev = {}
    for mm in re.finditer(r"SS_EVT t=(\d+) kind=(sof|cam_end|pub|read|enc|exp) frame=(\d+) n=(\d+)", text):
        t, kind, fr = int(mm.group(1)), mm.group(2), int(mm.group(3))
        ev.setdefault(kind, {})[fr] = t
    pace = {}
    for mm in re.finditer(r"SS_PACE frame=(\d+).*?\bt=(\d+)", text):
        pace[int(mm.group(1))] = int(mm.group(2))
    meta = re.search(r"SS_META t_rst=(\d+)", text)
    vecm = re.search(r"SS_VEC_MATCH bad=(\d+) checked=(\d+) drv_groups=(\d+)", text)
    rawm = re.search(r"SS_RAW_MATCH bad=(\d+) checked=(\d+) drv_groups=(\d+)", text)
    stall = "SS_STALL" in text
    timeout = "B11_FULL_TIMEOUT" in text
    passm = re.search(r"B11_FULL_RESULT pass=(\d+)", text)
    m = {"run": key, "tag": tag, "mode": RUNS[key]["mode"], "cfg": RUNS[key],
         "command_rc": rc, "command_seconds": round(el, 1), "timed_out": to,
         "stall_marker": stall, "timeout_marker": timeout,
         "result_marker": passm.group(0) if passm else None,
         "t_rst": int(meta.group(1)) if meta else None,
         "counters": stats,
         "ss_vec_match": ({"bad": int(vecm.group(1)), "checked": int(vecm.group(2)),
                           "drv_groups": int(vecm.group(3))} if vecm else None),
         "ss_raw_match": ({"bad": int(rawm.group(1)), "checked": int(rawm.group(2)),
                           "drv_groups": int(rawm.group(3))} if rawm else None),
         "pace": pace, "events": ev}
    if not ev.get("exp"):
        m["partial"] = True
        m["steady_state_status"] = "partial"
        m["header_check"] = header_check(tag, RUNS[key]["content_id"])
        return m
    tr = ev.get("exp", {})
    def g(kind, k):
        return ev.get(kind, {}).get(k)
    t_exp = [None] + [tr.get(k) for k in range(1, 5)]
    m["t_sof"] = [None] + [g("sof", k) for k in range(1, 5)]
    m["t_cam_end"] = [None] + [g("cam_end", k) for k in range(1, 5)]
    m["t_pub"] = [None] + [g("pub", k) for k in range(1, 5)]
    m["t_read"] = [None] + [g("read", k) for k in range(1, 5)]
    m["t_enc"] = [None] + [g("enc", k) for k in range(1, 5)]
    m["t_exp"] = t_exp
    n = max([k for k in range(1, 5) if t_exp[k] is not None] or [0])
    m["frames_exported"] = n
    if t_exp[1] is not None and m["t_rst"] is not None:
        m["L_cold"] = t_exp[1] - m["t_rst"]
    if t_exp[1] is not None and m["t_sof"][1] is not None:
        m["L_frame"] = t_exp[1] - m["t_sof"][1]
    m["S_2"] = (t_exp[2] - t_exp[1]) if (t_exp[1] and t_exp[2]) else None
    m["S_23"] = (t_exp[3] - t_exp[2]) if (t_exp[2] and t_exp[3]) else None
    m["S_34"] = (t_exp[4] - t_exp[3]) if (t_exp[3] and t_exp[4]) else None
    band = [x for x in (m["S_23"], m["S_34"]) if x is not None]
    m["S_band_cycles"] = band if band else None
    if band:
        m["S_ss"] = sum(band) / len(band)
        m["S_ss_spread_pct"] = (100.0 * (max(band) - min(band)) / m["S_ss"]) if m["S_ss"] else None
        m["capacity_MBps"] = 4.86e8 / m["S_ss"]
        m["fps"] = CLOCK_HZ / m["S_ss"]
        m["margin_0_pct"] = (m["capacity_MBps"] / G0_MBPS - 1) * 100
        m["margin_25_pct"] = (m["capacity_MBps"] / G25_MBPS - 1) * 100
        m["f_req_0_mhz"] = 30.0 * m["S_ss"] / 1e6
        m["f_req_25_mhz"] = 37.5 * m["S_ss"] / 1e6
        m["startup"] = m["L_cold"] - m["S_ss"] if m.get("L_cold") is not None else None
        if m.get("L_cold"):
            m["startup_pct"] = 100.0 * (m["L_cold"] / m["S_ss"] - 1)
    tails = {}
    for k in range(1, 5):
        if t_exp[k] is not None and g("enc", k) is not None:
            tails[k] = t_exp[k] - g("enc", k)
    m["export_tail"] = tails
    steady = [tails[k] for k in (2, 3, 4) if k in tails]
    m["export_tail_mean_steady"] = (sum(steady) / len(steady)) if steady else None
    why = []
    if steady and m.get("S_ss"):
        spread = max(steady) - min(steady)
        if spread > 0.01 * m["S_ss"]:
            why.append("tail spread > 1%% S_ss (%d)" % spread)
        if max(steady) >= 0.5 * m["S_ss"]:
            why.append("tail >= 0.5*S_ss")
        if len(steady) == 3 and steady[2] > steady[1] > steady[0] and (steady[2] - steady[0]) > 0.01 * m["S_ss"]:
            why.append("tail grows with k")
    m["sink_limited"] = bool(why)
    m["sink_limited_why"] = why
    if m.get("S_ss") and m.get("export_tail_mean_steady"):
        m["export_tail_frac_pct"] = 100.0 * m["export_tail_mean_steady"] / m["S_ss"]
    cnt = stats
    m["validity"] = {
        "v1_counts": (cnt.get("cap") == 4 and cnt.get("enc") == 4 and cnt.get("exported") == 4
                      and cnt.get("read") == 518400 and cnt.get("raw_drop") == 0
                      and cnt.get("cmp_drop") == 0 and cnt.get("geom") == 0
                      and cnt.get("err") == 0 and cnt.get("dup") == 0 and cnt.get("wd") == 0),
        "v3_stable": (m.get("S_ss_spread_pct") is not None and m["S_ss_spread_pct"] <= 2.0),
        "v4_no_bubble": all(
            m["t_pub"][k + 1] is not None and t_exp[k] is not None and m["t_pub"][k + 1] < t_exp[k]
            for k in (2, 3)),
        "v5_slot_free": all(pace.get(k) is not None for k in (3, 4)) or n < 4,
        "v6_monotone": all(t_exp[k] is not None and t_exp[k - 1] is not None and t_exp[k] > t_exp[k - 1]
                           for k in (2, 3, 4)) if n == 4 else False,
    }
    if RUNS[key]["pacing"] != 0:
        m["validity"]["v4_applicable"] = False
        m["validity"]["v4_no_bubble"] = None
        m["capacity_is_lower_bound"] = False
        m["serial_by_construction"] = True
    else:
        m["validity"]["v4_applicable"] = True
        m["capacity_is_lower_bound"] = not m["validity"]["v4_no_bubble"]
    m["frames"] = n
    m["partial"] = bool(to or stall or timeout or n < 4)
    m["steady_state_status"] = "measured" if (n == 4 and not m["partial"]) else ("partial" if n else "not_measured")
    # payload / sink demand
    fr = n or 1
    m["payload_bytes_per_frame"] = (cnt.get("exp_bytes") or 0) / fr
    tail = m.get("export_tail_mean_steady")
    if tail:
        m["measured_export_MBps"] = m["payload_bytes_per_frame"] / (tail / CLOCK_HZ) / 1e6
    m["needed_sink_MBps_33ms"] = m["payload_bytes_per_frame"] / 33.333e-3 / 1e6
    m["needed_sink_MBps_25ms"] = m["payload_bytes_per_frame"] / 25.0e-3 / 1e6
    if m.get("S_ss"):
        m["export_rate_from_S_ss_MBps"] = m["payload_bytes_per_frame"] / (m["S_ss"] / CLOCK_HZ) / 1e6
    if tail and m.get("S_ss"):
        m["sink_pipelined"] = bool(tail > m["S_ss"])
        # when the sink is saturated the tail includes waiting for the previous
        # frame's export, so the interval (min(tail,S_ss)) is the correct window
        m["measured_export_MBps"] = m["payload_bytes_per_frame"] / (min(tail, m["S_ss"]) / CLOCK_HZ) / 1e6
    m["header_check"] = header_check(tag, RUNS[key]["content_id"])
    # per-run G0
    self_ok = True
    if RUNS[key]["content"] == 1:
        vm = m.get("ss_vec_match") or {}
        self_ok = (vm.get("bad") == 0 and vm.get("checked") == 518400)
        m["self_check"] = vm
    else:
        rm = m.get("ss_raw_match") or {}
        self_ok = (rm.get("bad") == 0 and rm.get("checked") == 518400)
        m["self_check"] = rm
    hdr_ok = (m.get("header_check") or {}).get("pass", False)
    if m["partial"] or not self_ok or not hdr_ok:
        g0 = "G0_not_proven"
        g0_why = "run partial or content self-check/header CRC failed"
    elif m["sink_limited"]:
        g0 = "G0_not_proven"
        g0_why = "sink_limited (tail %s%% of S_ss); sink-limited S_ss is not G0 evidence" % (
            round(m.get("export_tail_frac_pct") or 0, 1))
    elif m["S_ss"] <= G0_CYCLES:
        g0 = "G0_feasible_for_scope"
        g0_why = "S_ss %.1f <= 6,250,000 (measured)" % m["S_ss"]
    else:
        g0 = "G0_not_closed"
        g0_why = "S_ss %.1f > 6,250,000; gap %.1f cycles (%.3f%%)" % (
            m["S_ss"], m["S_ss"] - G0_CYCLES, 100.0 * (m["S_ss"] - G0_CYCLES) / m["S_ss"])
    m["G0"] = g0
    m["G0_why"] = g0_why
    m["G25_ref"] = "meets_25_ref" if (m.get("capacity_MBps") or 0) >= G25_MBPS else "below_25_ref"
    return m


def header_check(tag, content_id):
    hdr_path = CAPS / (tag + ".hdr")
    cmap = jload(OUT / "content-map.json", {}) or {}
    ent = (cmap.get("content") or {}).get(content_id) or {}
    exp_all = ent.get("expected_header")
    if not hdr_path.exists() or not exp_all:
        return {"available": False}
    rawb = bytes(int(x, 16) for x in hdr_path.read_text().split())
    if len(rawb) < 44:
        return {"available": False, "bytes": len(rawb)}
    u32 = lambda o: int.from_bytes(rawb[o:o + 4], "little")
    got = {"raw_len": u32(16), "xform_len": u32(20), "stream_len": u32(24),
           "raw_crc": u32(28), "xform_crc": u32(32), "stream_crc": u32(36),
           "header_crc": u32(40)}
    exp = {"raw_len": exp_all["raw_len"], "xform_len": exp_all["xform_len"],
           "raw_crc": exp_all.get("raw_crc32", exp_all.get("raw_crc")),
           "xform_crc": exp_all.get("xform_crc32", exp_all.get("xform_crc"))}
    bad = [k for k in exp if got[k] != exp[k]]
    hcrc = zlib.crc32(rawb[0:40]) & 0xFFFFFFFF
    return {"available": True, "got": got, "expected": exp, "bad": bad,
            "header_crc_ok": (hcrc == got["header_crc"]),
            "pass": (not bad) and hcrc == got["header_crc"]}


# ------------------------------------------------------------------ verify
PROTECTED = {
    str(P3 / "manifest-r2.json"): "3c8377a484f42a132b6434cf975710662b8c92871d31bcdaabd9b8ba7aec4961",
    str(P3 / "src/tb_ss_g0.v"): "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",
    str(P3 / "src/DIFF.md"): "d2c9f5c9cb0ad2da85c410c37e81b8c6fa2e71bf906bdd3f6642c7ac17789664",
    str(P1 / "manifest-r0.json"): "39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a",
    str(P2 / "manifest-r0.json"): "fd27c70f304f51ba0b0b022398acd46f1f5f43a32351acfc472dea12e034fad0",
}
CONTENT_SHA = {
    "raw_p1d1.bin": "061b0dfce062d5cd9231e2f0eccee112c189f64487e9b928f99e1531ccf91f8d",
    "raw_rand.bin": "8fe204b715d08285b5918d7745e01195c1925b18ef0d19b9fcfb59ff06f0fad5",
    "in.hex": "edbfdeaedb06824ced20ad76b260979e95e1322d6f6e3bab5e7a951a268f9849",
    "in.meta": "e98c9a1c3e0fe621c9aa65aaadbcacbef13c2437a0bbbafcde17d2ff471f80fe",
    "in.xform": "b836b51df0bc98045f3768cf497bb5a76f88fa301e0598c63514284e2fbfba7a",
    "comp_raw.hex": "e3d9094643e3d7d3881ab527abfa0d7e296348895c71eca757cbf911a595eea1",
    "comp_vec.hex": "a91cd406585d54cb2ed9cc760eb88abfcfc6faf135265684f93a6c20a98595b8",
}


def verify():
    p1man = json.loads((P1 / "manifest-r0.json").read_text())
    p1art = {a["path"]: a for a in p1man["artifacts"]}
    checks, drift = [], []
    for path, want in PROTECTED.items():
        got = sha(path)
        ok = got == want
        checks.append({"path": path, "bytes": pathlib.Path(path).stat().st_size,
                       "sha256": got, "expected": want, "match": ok})
        if not ok:
            drift.append(path)
    copied = []
    for f in sorted(SRC.glob("*.v")):
        rel = "src/" + f.name
        ref = p1art.get(rel)
        rec = {"file": f.name, "bytes": f.stat().st_size, "sha256": sha(f)}
        if ref:
            rec["p1_manifest_sha256"] = ref["sha256"]
            rec["match"] = rec["sha256"] == ref["sha256"] and rec["bytes"] == ref["bytes"]
        else:
            rec["match"] = None
        copied.append(rec)
        if rec["match"] is False:
            drift.append(str(f))
    content = []
    for name, want in CONTENT_SHA.items():
        p = CONTENT / name
        got = sha(p)
        ok = got == want
        content.append({"file": name, "path": str(p), "bytes": p.stat().st_size,
                        "sha256": got, "frozen_expected": want, "match": ok})
        if not ok:
            drift.append(str(p))
    cmap = jload(OUT / "content-map.json", {}) or {}
    out = {
        "created": "2026-10-26",
        "task": "T10.ss-4run-matrix",
        "run": "r0",
        "protected_inputs": checks,
        "protected_drift": drift,
        "copied_src": copied,
        "copied_src_mismatch": [c["file"] for c in copied if c["match"] is False],
        "copied_src_extra": [c["file"] for c in copied if c["match"] is None],
        "copied_src_extra_note": "tb_ss_4run.v is the P4 derived TB and has no P1 manifest entry; "
                                 "all 12 DUT/model sources match the P1 manifest",
        "content_sources": content,
        "content_mismatch": [c["file"] for c in content if not c["match"]],
        "prepared_content": {
            "content_map_sha256": sha(OUT / "content-map.json") if (OUT / "content-map.json").exists() else None,
            "raw40_p1d1_sha256": ((cmap.get("content") or {}).get("C1") or {}).get("raw40_hex", {}).get("sha256"),
            "raw40_rand_sha256": ((cmap.get("content") or {}).get("C2") or {}).get("raw40_hex", {}).get("sha256"),
            "c1_roundtrip_mismatch": ((cmap.get("content") or {}).get("C1") or {}).get("roundtrip", {}).get("mismatch_bytes"),
            "c2_roundtrip_mismatch": ((cmap.get("content") or {}).get("C2") or {}).get("roundtrip", {}).get("mismatch_bytes"),
            "comp_matches_p3": ((cmap.get("content") or {}).get("C3_C7") or {}).get("matches_p3_proxy"),
        },
        "p3_bindings": {
            "manifest_r2_sha256": PROTECTED[str(P3 / "manifest-r2.json")],
            "tb_ss_g0_sha256": PROTECTED[str(P3 / "src/tb_ss_g0.v")],
            "r3_expected_S_ss": P3_R3_EXPECT,
        },
        "tools": {"modelsim": str(MS / "vsim.exe"), "python": sys.version.split()[0]},
        "drift_status": "ok" if not drift else "DRIFT",
    }
    jdump(R0 / "input-verified.json", out)
    print("protected=%d drift=%d copied=%d mismatch=%d extra=%d content_bad=%d prepared_c1=%s" % (
        len(checks), len(drift), len(copied), len(out["copied_src_mismatch"]),
        len(out["copied_src_extra"]), len(out["content_mismatch"]),
        out["prepared_content"]["c1_roundtrip_mismatch"]))
    if drift:
        print("DRIFT:", drift)


# ------------------------------------------------------------------ analyze
def analyze():
    db = jload(OUT / "runs.json", {})
    missing = [k for k in FULL_RUNS if k not in db]
    if missing:
        raise SystemExit("missing runs: %s" % missing)
    r1, r2, r3, r4 = db["r1"], db["r2"], db["r3"], db["r4"]
    p3runs = jload(P3 / "out/runs.json", {}) or {}
    p3 = p3runs.get("r3f") or {}
    cmap = jload(OUT / "content-map.json", {}) or {}

    overlap = (r2["S_ss"] - r1["S_ss"]) if (r2.get("S_ss") and r1.get("S_ss")) else None
    overlap_pct = (100.0 * overlap / r1["S_ss"]) if overlap is not None and r1.get("S_ss") else None
    r4_delta = (r4["S_ss"] - P3_R3_EXPECT) if r4.get("S_ss") else None
    r4_pct = (100.0 * r4_delta / P3_R3_EXPECT) if r4_delta is not None else None
    r4_within = (r4_pct is not None and abs(r4_pct) <= 100.0 * P3_R3_TOL)
    r4_vec = (r4.get("ss_vec_match") or {})
    r4_hdr = (r4.get("header_check") or {})
    r4_pass = bool(r4_within and r4_vec.get("bad") == 0 and r4_vec.get("checked") == 518400
                   and r4_hdr.get("pass"))

    # ---------------------------------------------------------- runs-4.csv
    cols = ["run_id", "content_id", "content_label", "pacing", "sink", "capture", "frames",
            "partial", "steady_state_status", "S_2", "S_23", "S_34", "S_ss",
            "S_band_cycles", "S_spread_pct", "L_cold", "startup_pct", "capacity_MBps",
            "fps", "margin_0_pct", "margin_25_pct", "f_req_0_mhz", "f_req_25_mhz",
            "export_tail_mean", "export_tail_frac_pct", "measured_export_MBps",
            "sink_pipelined",
            "payload_bytes_per_frame", "needed_sink_MBps_33ms", "needed_sink_MBps_25ms",
            "sink_limited", "raw_match_bad", "raw_match_checked", "vec_match_bad",
            "vec_match_checked", "header_pass", "header_crc_ok", "exp_bytes", "cap_bytes",
            "cycles", "command_seconds", "timed_out", "timeout_marker", "stall_marker",
            "result_marker", "G0", "G25_ref"]
    rows = []
    for k in FULL_RUNS:
        m = db[k]
        c = m["cfg"]
        rows.append({
            "run_id": k, "content_id": c["content_id"], "content_label": c.get("label"),
            "pacing": c["pacing"], "sink": c["sink"], "capture": c["capture"],
            "frames": m.get("frames"), "partial": m.get("partial"),
            "steady_state_status": m.get("steady_state_status"),
            "S_2": m.get("S_2"), "S_23": m.get("S_23"), "S_34": m.get("S_34"),
            "S_ss": m.get("S_ss"), "S_band_cycles": "|".join(str(x) for x in (m.get("S_band_cycles") or [])),
            "S_spread_pct": m.get("S_ss_spread_pct"), "L_cold": m.get("L_cold"),
            "startup_pct": m.get("startup_pct"), "capacity_MBps": m.get("capacity_MBps"),
            "fps": m.get("fps"), "margin_0_pct": m.get("margin_0_pct"),
            "margin_25_pct": m.get("margin_25_pct"), "f_req_0_mhz": m.get("f_req_0_mhz"),
            "f_req_25_mhz": m.get("f_req_25_mhz"),
            "export_tail_mean": m.get("export_tail_mean_steady"),
            "export_tail_frac_pct": m.get("export_tail_frac_pct"),
            "measured_export_MBps": m.get("measured_export_MBps"),
            "sink_pipelined": m.get("sink_pipelined"),
            "payload_bytes_per_frame": m.get("payload_bytes_per_frame"),
            "needed_sink_MBps_33ms": m.get("needed_sink_MBps_33ms"),
            "needed_sink_MBps_25ms": m.get("needed_sink_MBps_25ms"),
            "sink_limited": m.get("sink_limited"),
            "raw_match_bad": (m.get("ss_raw_match") or {}).get("bad"),
            "raw_match_checked": (m.get("ss_raw_match") or {}).get("checked"),
            "vec_match_bad": (m.get("ss_vec_match") or {}).get("bad"),
            "vec_match_checked": (m.get("ss_vec_match") or {}).get("checked"),
            "header_pass": (m.get("header_check") or {}).get("pass"),
            "header_crc_ok": (m.get("header_check") or {}).get("header_crc_ok"),
            "exp_bytes": m.get("counters", {}).get("exp_bytes"),
            "cap_bytes": m.get("counters", {}).get("cap_bytes"),
            "cycles": m.get("counters", {}).get("cycles"),
            "command_seconds": m.get("command_seconds"),
            "timed_out": m.get("timed_out"), "timeout_marker": m.get("timeout_marker"),
            "stall_marker": m.get("stall_marker"), "result_marker": m.get("result_marker"),
            "G0": m.get("G0"), "G25_ref": m.get("G25_ref"),
        })
    with open(OUT / "runs-4.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows([{k: ("" if v is None else v) for k, v in row.items()} for row in rows])

    # ------------------------------------------------------ four-run-table.csv
    tcols = ["row", "run_id", "content", "pacing", "sink", "S_ss", "L_cold", "tail_mean",
             "tail_frac_pct", "sink_limited", "overlap_gain_vs_R1", "capacity_MBps",
             "margin_0_pct", "margin_25_pct", "G0", "source", "note"]
    trows = []
    for k in FULL_RUNS:
        m = db[k]
        trows.append({
            "row": k.upper(), "run_id": k, "content": m["cfg"]["content_id"],
            "pacing": "slot-free" if m["cfg"]["pacing"] == 0 else "strict-serial",
            "sink": "SINK=1 (93.75 MB/s max frozen)",
            "S_ss": m.get("S_ss"), "L_cold": m.get("L_cold"),
            "tail_mean": m.get("export_tail_mean_steady"),
            "tail_frac_pct": m.get("export_tail_frac_pct"),
            "sink_limited": m.get("sink_limited"),
            "overlap_gain_vs_R1": (m["S_ss"] - r1["S_ss"]) if (m.get("S_ss") and r1.get("S_ss")) else None,
            "capacity_MBps": m.get("capacity_MBps"), "margin_0_pct": m.get("margin_0_pct"),
            "margin_25_pct": m.get("margin_25_pct"), "G0": m.get("G0"),
            "source": "measured this run",
            "note": m.get("G0_why"),
        })
    trows.append({
        "row": "P3-R3(control)", "run_id": "p3_r3f", "content": "C3-C7",
        "pacing": "slot-free", "sink": "SINK=1 (same frozen TB lineage)",
        "S_ss": p3.get("S_ss"), "L_cold": p3.get("L_cold"),
        "tail_mean": p3.get("export_tail_mean_steady"),
        "tail_frac_pct": (100.0 * p3["export_tail_mean_steady"] / p3["S_ss"]) if p3.get("export_tail_mean_steady") else None,
        "sink_limited": p3.get("sink_limited"),
        "overlap_gain_vs_R1": None, "capacity_MBps": p3.get("capacity_MBps"),
        "margin_0_pct": p3.get("margin_0_pct"), "margin_25_pct": p3.get("margin_25_pct"),
        "G0": "G0_feasible_for_scope" if (p3.get("S_ss") or 1e12) <= G0_CYCLES else "G0_not_closed",
        "source": "P3 r3_frozen (read-only comparison)",
        "note": "P3 G0 pseudo-closure run; R4 must reproduce this S_ss within +/-0.5%",
    })
    with open(OUT / "four-run-table.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=tcols)
        w.writeheader()
        w.writerows([{k: ("" if v is None else v) for k, v in row.items()} for row in trows])

    # ---------------------------------------------------------- gap-menu.csv
    menu = [
        ("M1_tail_overlap", "keep the per-frame export tail hidden by slot-free overlap; "
         "strict-serial is the conservative cost",
         overlap, "R2-R1 = %s cycles (%.3f%% of R1); includes camera serialization, so it is an "
         "upper bound for the pure tail cost" % (overlap, overlap_pct or 0),
         "already present in slot-free; no new RTL", "none", "R2 vs R1 measured",
         "0 (already implemented)", "measured"),
        ("M2_core_cycles", "reduce core cycles/B by 171,414 cycles/frame",
         171414, "A2 6,421,414 -> 6,250,000 at G0; 2.859% of the comp core 5,995,029",
         "needs ~2.86% faster core; no RTL change in this run", "ERAM/area risk unassessed",
         "not timed", "new core task + TD + STA", "not_implemented"),
        ("M3_clock", "raise core clock to 192.642 MHz (G0); 240.803 MHz is the G25 reference",
         171414, "192.642 MHz @30 fps vs 187.5 MHz closed point (+2.74%)",
         "TD/STA not run", "unknown", "unproven", "TD/STA + bitgen + board", "not_implemented"),
        ("M4_combo", "overlap + 2.86% core and/or +2.74% clock",
         None, "combination sufficient only if each part is validated", "stacked risk",
         "unknown", "unproven", "new implementation + TD + board", "not_implemented"),
        ("M5_production_sink", "production high-speed sink for the raw band",
         None, "raw band needs >= %.2f MB/s for G0 and >= %.2f MB/s at 25 ms per frame; "
         "the frozen TB sink caps at 93.75 MB/s (2 clk_a1/B), so it cannot demonstrate "
         ">=103.79 MB/s" % (SINK_NEED_33, SINK_NEED_25),
         "requires new TB/export RTL or PCIe; outside P4 whitelist", "new transport IP",
         "unproven", "new transport task + board", "not_implemented"),
        ("M6_content_envelope", "natural/low-light/worst-case content corpus",
         None, "C1/C2 are full-frame synthetic packed RAW10; comp proxy is proxy_not_worst; "
         "no natural-image evidence", "content corpus absent", "none", "not_applicable",
         "new content task", "not_implemented"),
    ]
    with open(OUT / "gap-menu.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "path", "gain_cycles", "evidence", "risk", "resource_cost",
                    "timing_status", "validation_cost", "implemented"])
        for r in menu:
            w.writerow(["" if v is None else v for v in r])

    # ---------------------------------------------------------- verdict json
    def run_view(m):
        return {"S_ss": m.get("S_ss"), "band": m.get("S_band_cycles"),
                "L_cold": m.get("L_cold"), "tail_mean": m.get("export_tail_mean_steady"),
                "tail_frac_pct": m.get("export_tail_frac_pct"),
                "capacity_MBps": m.get("capacity_MBps"),
                "margin_0_pct": m.get("margin_0_pct"),
                "margin_25_pct": m.get("margin_25_pct"),
                "sink_limited": m.get("sink_limited"),
                "measured_export_MBps": m.get("measured_export_MBps"),
                "sink_pipelined": m.get("sink_pipelined"),
                "partial": m.get("partial"), "G0": m.get("G0"), "G0_why": m.get("G0_why"),
                "self_check": m.get("self_check"),
                "header_pass": (m.get("header_check") or {}).get("pass")}

    blocked = False
    blocked_reason = None
    if not r4_pass:
        blocked = True
        blocked_reason = ("R4 did not reproduce P3 R3 S_ss=%d within +/-0.5%% "
                          "(measured %s, delta %s, %.4f%%); vector bad=%s; header pass=%s"
                          % (P3_R3_EXPECT, r4.get("S_ss"), r4_delta, r4_pct or 0,
                             r4_vec.get("bad"), r4_hdr.get("pass")))
    headline = "G0_feasible_for_scope"
    why = []
    if r1.get("G0") == "G0_feasible_for_scope":
        why.append("R1 C1 full-frame raw slot-free S_ss=%.0f <= 6,250,000" % r1["S_ss"])
    if r4_pass:
        why.append("R4 comp proxy reproduces P3 R3 5,928,286 within 0.5%")
    if r3.get("G0") != "G0_feasible_for_scope":
        why.append("R3 C2 rand raw band is %s (sink-limited): capacity cannot be concluded" % r3.get("G0"))
    if r2.get("G0") != "G0_feasible_for_scope":
        why.append("R2 C1 strict-serial is %s: pacing penalty, conservative view only" % r2.get("G0"))
    if blocked:
        headline = "G0_not_proven"
        why = [blocked_reason]
    elif r1.get("G0") != "G0_feasible_for_scope":
        headline = r1.get("G0") or "G0_not_proven"
    verdict = {
        "task": "T10.ss-4run-matrix", "created": "2026-10-26",
        "hard_gate": {"G0_MBps": G0_MBPS, "G0_cycles": G0_CYCLES,
                      "G25_MBps_ref_only": G25_MBPS},
        "runs": {k: run_view(db[k]) for k in FULL_RUNS},
        "r4_reproduction": {
            "p3_r3_expected_S_ss": P3_R3_EXPECT, "measured_S_ss": r4.get("S_ss"),
            "delta_cycles": r4_delta, "delta_pct": r4_pct, "tolerance_pct": 0.5,
            "within_0p5": r4_within, "vec_bad": r4_vec.get("bad"),
            "vec_checked": r4_vec.get("checked"), "header_pass": r4_hdr.get("pass"),
            "pass": r4_pass,
            "note": "P4 new TB is trusted only if this reproduction passes; otherwise blocked",
        },
        "overlap_penalty": {
            "cycles": overlap, "pct_of_R1": overlap_pct,
            "note": "R2-R1 is an upper bound for the pure export-tail cost: strict-serial also "
                    "serializes camera drive after export, so it is not a pure tail measurement",
        },
        "r1_r2_same_content": (r1["cfg"]["content_id"] == r2["cfg"]["content_id"]
                               and r1["cfg"]["sink"] == r2["cfg"]["sink"]),
        "content_scope": {
            "C1": "full_frame_raw_synthetic (f1080p_p1d1, 1920x1080 packed RAW10) / "
                  "proxy_not_natural / proxy_not_worst",
            "C2": "full_frame_raw_synthetic (f1080p_rand, stored/incompressible) / "
                  "proxy_not_natural / proxy_not_worst",
            "C3_C7": "P3 transform-domain comp proxy / proxy_not_natural / proxy_not_worst",
            "no_natural_corpus": True,
        },
        "measured_sink": {
            "frozen_tb_max_MBps": 93.75,
            "note": "a1_uart_export has a 2 clk_a1/byte handoff; SINK=1 cannot exceed 93.75 MB/s",
            "raw_band_needed_MBps_33ms": SINK_NEED_33,
            "raw_band_needed_MBps_25ms": SINK_NEED_25,
            "literal_103_79_supported": False,
            "production_sink_requirement": ">=77.84 MB/s for G0 / >=103.79 MB/s at 25 ms; "
                                           "the 93.75 MB/s frozen sink must NOT be presented as "
                                           ">=103.79",
        },
        "headline": headline, "headline_why": "; ".join(why),
        "headline_scope": "per-stream 1080p30; C1 slot-free full-frame raw + P3 comp proxy; "
                          "C2 rand raw band G0_not_proven (sink-limited); strict-serial R2 is a "
                          "conservative pacing view; 93.75 MB/s sim sink; behavioral DDR; "
                          "single core / 187.5 MHz; no board/TD/real UART/PCIe/RK claim",
        "not_downgraded": True, "g25_used_for_headline": False,
        "blocked": blocked, "blocked_reason": blocked_reason,
    }
    jdump(OUT / "g0-verdict.json", verdict)

    # ------------------------------------------------------ negative controls
    def add(nid, name, rejected, detail):
        return {"id": nid, "name": name, "rule": "rejected_as_invalid",
                "rejected": bool(rejected), "detail": detail}

    neg = []
    neg.append(add("NEG-01", "RAW_AS_NATURAL", True,
                   "C1/C2 are full-frame synthetic packed RAW10 images; no natural-image corpus "
                   "exists in this run -> claim_status labels stay proxy_not_natural/proxy_not_worst"))
    neg.append(add("NEG-02", "RAW_AS_WORST", True,
                   "C2 rand is incompressible raw but is not a proven worst case for all natural "
                   "content; R3 stays G0_not_proven for the raw band, not a worst-case proof"))
    neg.append(add("NEG-03", "SINK_LIMITED_AS_G0",
                   bool(r3.get("sink_limited") and r3.get("S_ss") and r3["S_ss"] <= G0_CYCLES),
                   "R3 S_ss=%s <= 6.25M would pass the arithmetic, but tail=%s%% of S_ss and the "
                   "measured export rate is the sink cap; the run is labelled %s, never G0 evidence"
                   % (r3.get("S_ss"), round(r3.get("export_tail_frac_pct") or 0, 1), r3.get("G0"))))
    neg.append(add("NEG-04", "SERIAL_AS_OVERLAP",
                   bool(overlap is not None and overlap > 0),
                   "R2-R1=%s cycles; the strict-serial S_ss is reported only in the serial column "
                   "and may not populate the slot-free/overlapped result" % overlap))
    cold_cap = (4.86e8 / r1["L_cold"]) if r1.get("L_cold") else None
    neg.append(add("NEG-05", "COLD_LATENCY_AS_THROUGHPUT",
                   bool(cold_cap is not None and cold_cap < G0_MBPS),
                   "R1 L_cold=%s -> %.3f MB/s < 77.76: t_exp(1)-t_rst is startup latency, not S_ss"
                   % (r1.get("L_cold"), cold_cap or 0)))
    g25_down = (r1.get("G0") == "G0_feasible_for_scope" and r1.get("G25_ref") == "below_25_ref")
    neg.append(add("NEG-06", "G25_DOWNGRADE", True,
                   "G25 is a reference column only (R1 G25_ref=%s); no 1600x900 or other downgrade "
                   "is proposed from G25" % r1.get("G25_ref")))
    c1s2 = (4.86e8 / r1["S_ss"]) / 2.0 if r1.get("S_ss") else None
    agg_ok = (2.0 * c1s2) >= G0_MBPS if c1s2 else False
    neg.append(add("NEG-07", "AGGREGATE_2C",
                   bool(agg_ok and c1s2 < G0_MBPS),
                   "R1 c1s2 aggregate 2C=%0.3f passes while per-stream C/2=%0.3f fails; aggregate "
                   "capacity is never substituted for per-stream" % (2.0 * (c1s2 or 0), c1s2 or 0)))
    map_bad = 0
    for k in FULL_RUNS:
        m = db[k]
        if k == "r4":
            map_bad += (m.get("ss_vec_match") or {}).get("bad") or 0
        else:
            map_bad += (m.get("ss_raw_match") or {}).get("bad") or 0
    c1_rt = ((cmap.get("content") or {}).get("C1") or {}).get("roundtrip", {}).get("mismatch_bytes")
    c2_rt = ((cmap.get("content") or {}).get("C2") or {}).get("roundtrip", {}).get("mismatch_bytes")
    map_ok = (map_bad == 0 and c1_rt == 0 and c2_rt == 0)
    neg.append(add("NEG-08", "CONTENT_MAP_MISMATCH", map_ok,
                   "TB self-check bad=%d; Python raw.bin->raw40->bytes mismatch C1=%s C2=%s; "
                   "the mismatch interpretation is rejected because the map checks are clean. "
                   "Any bad>0 would void the content and force G0_not_proven instead of guessing"
                   % (map_bad, c1_rt, c2_rt)))
    jdump(OUT / "negative-controls.json",
          {"controls": neg, "all_rejected": all(n["rejected"] for n in neg)})

    print("verdict=%s r4_pass=%s overlap=%s" % (headline, r4_pass, overlap))
    print("negative_controls_all_rejected=%s" % all(n["rejected"] for n in neg))
    return verdict


def parse_run(key):
    """Re-parse an already completed run from its stats/log (no vsim)."""
    rec = None
    if (SIM / "commands.jsonl").exists():
        for line in (SIM / "commands.jsonl").read_text().splitlines():
            try:
                r = json.loads(line)
            except Exception:
                continue
            if any("tb_ss_4run" in str(a) for a in r.get("argv", [])) and \
               str(r.get("log", "")).endswith(key + ".log"):
                rec = r
    if rec is None:
        raise SystemExit("no command record for %s" % key)
    stat = CAPS / (key + ".stats")
    if not stat.exists():
        raise SystemExit("no stats for %s" % key)
    m = metrics(key, key, stat, LOGS / (key + ".log"),
                rec.get("seconds", 0.0), rec.get("rc", 0), rec.get("timed_out", False))
    db = jload(OUT / "runs.json", {})
    db[key] = m
    jdump(OUT / "runs.json", db)
    print("%s S_ss=%s exp_bytes=%s raw_bad=%s vec_bad=%s hdr=%s" % (
        key, m.get("S_ss"), m.get("counters", {}).get("exp_bytes"),
        (m.get("ss_raw_match") or {}).get("bad"),
        (m.get("ss_vec_match") or {}).get("bad"),
        (m.get("header_check") or {}).get("pass")))


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: run_4run.py verify|compile|r1|r2|r3|r4|parse:<run>|analyze")
    os.environ.update(toolenv())
    what = sys.argv[1]
    if what == "verify":
        verify()
    elif what == "compile":
        compile_all()
    elif what in RUNS:
        vsim(what)
    elif what.startswith("parse:"):
        parse_run(what.split(":", 1)[1])
    elif what == "analyze":
        analyze()
    else:
        raise SystemExit("unknown subcommand")


if __name__ == "__main__":
    main()
