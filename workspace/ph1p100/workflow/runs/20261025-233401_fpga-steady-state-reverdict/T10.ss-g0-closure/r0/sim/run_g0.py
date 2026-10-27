#!/usr/bin/env python3
"""P3 T10.ss-g0-closure bounded driver.

Subcommands (one vsim per invocation, hard 2700 s timeout):
  compile            vlib + vlog the 12 frozen sources + tb_ss_g0.v
  r0..r4             one 4-frame run (see RUNS)
  analyze            parse all completed runs -> G0 tables / gap menu / verdict

Writes only inside this task's r0/ directory and %TEMP%\opencode\ss-g0\.
"""
import csv
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
import zlib

sys.dont_write_bytecode = True

R0 = pathlib.Path(__file__).resolve().parent.parent
SRC = R0 / "src"
SIM = R0 / "sim"
LOGS = SIM / "logs"
CAPS = SIM / "caps"
OUT = R0 / "out"
MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
WORK = pathlib.Path(os.environ.get("TEMP", r"C:\Users\czz\AppData\Local\Temp")) / "opencode" / "ss-g0" / "work"
CLOCK_HZ = 187.5e6
G0_MBPS = 77.76
G25_MBPS = 97.20

SRC_FILES = [
    "a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v",
    "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
    "a1_deflate_core.v", "p2_ddr_bridge.v", "p2_a1_board_top.v",
    "a1_ddr_arb2.v", "capture_async_fifo.v", "p2_paxi_model_b11.v",
    "a1_ddr_model.v",
]
COMPILE = [f for f in SRC_FILES if f != "p2_a1_board_top.v"] + ["tb_ss_g0.v"]

RUNS = {
    "r0": dict(frames=4, content=0, pacing=0, sink=0, capture=1, mode="control"),
    "r1": dict(frames=4, content=0, pacing=0, sink=1, capture=1, mode="grad_fast_slotfree"),
    "r2": dict(frames=4, content=0, pacing=1, sink=1, capture=1, mode="grad_fast_serial"),
    "r3": dict(frames=4, content=1, pacing=0, sink=1, capture=0, mode="comp_fast_slotfree"),
    "r3f": dict(frames=4, content=1, pacing=0, sink=1, capture=0, mode="comp_fast_slotfree_frozen",
                tag="r3_frozen"),
    "r4": dict(frames=4, content=1, pacing=1, sink=1, capture=0, mode="comp_fast_serial"),
    # 1-frame verification only (not a G0 run): exercises the fixed byte-level
    # xform self check over the same comp content and must reproduce R3 t_exp(1).
    "v1": dict(frames=1, content=1, pacing=0, sink=1, capture=0, mode="comp_check_only", max_cycles=2000000),
}
CONTROL_EXPECT = {
    "cap": 4, "enc": 4, "exported": 4, "read": 518400, "exp_bytes": 160136,
    "cap_bytes": 160312, "cycles": 20801058, "raw_drop": 0, "cmp_drop": 0,
    "geom": 0, "err": 0, "dup": 0, "wd": 0, "raw_pub": 4,
}
CONTROL_EVENTS = {"t_rst": 20, "t_exp1": 6766454, "t_exp2": 11443989, "S_ss": 4677535}


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


def vsim(run_key):
    cfg = RUNS[run_key]
    LOGS.mkdir(parents=True, exist_ok=True)
    CAPS.mkdir(parents=True, exist_ok=True)
    tag = cfg.get("tag", run_key)
    stat = CAPS / (tag + ".stats")
    evt = CAPS / (tag + ".evt")
    log = LOGS / (tag + ".log")
    argv = [MS / "vsim.exe", "-c", "-lib", "work", "-l", log, "tb_ss_g0",
            "+STAT=" + str(stat), "+EVT=" + str(evt),
            "-gFRAMES=%d" % cfg["frames"],
            "-gCONTENT=%d" % cfg["content"], "-gPACING=%d" % cfg["pacing"],
            "-gSINK=%d" % cfg["sink"], "-gCAPTURE=%d" % cfg["capture"]]
    if cfg["capture"]:
        argv.insert(-1, "+DEC=" + str(CAPS / (tag + ".dec")))
    else:
        argv.insert(-1, "+HDR=" + str(CAPS / (tag + ".hdr")))
    if cfg["content"]:
        argv.insert(-1, "+RAW=" + str(CAPS / "comp_raw.hex"))
        argv.insert(-1, "+VEC=" + str(CAPS / "comp_vec.hex"))
    if cfg.get("max_cycles"):
        argv.insert(-1, "-gMAX_CYCLES=%d" % cfg["max_cycles"])
    argv += ["-do", "run -all; quit -f"]
    rc, el, to = run_proc(argv, WORK, log, 2700)
    print("%s rc=%s %.1fs timeout=%s" % (run_key, rc, el, to))
    if not stat.exists():
        print("NO STATS (partial)")
        return
    m = metrics(run_key, tag, stat, log, el, rc, to)
    db = jload(OUT / "runs.json", {})
    db[run_key] = m
    jdump(OUT / "runs.json", db)
    write_runs_csv(db)
    print("%s S_ss=%s band=%s exp_bytes=%s cycles=%s partial=%s" % (
        run_key, m.get("S_ss"), m.get("S_band_cycles"), m.get("counters", {}).get("exp_bytes"),
        m.get("counters", {}).get("cycles"), m.get("partial")))


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
    for mm in re.finditer(r"SS_PACE frame=(\d+).*?t=(\d+)", text):
        pace[int(mm.group(1))] = int(mm.group(2))
    meta = re.search(r"SS_META t_rst=(\d+)", text)
    vecm = re.search(r"SS_VEC_MATCH bad=(\d+) checked=(\d+) drv_groups=(\d+)", text)
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
         "pace": pace, "events": ev}
    if not ev.get("exp"):
        m["partial"] = True
        m["steady_state_status"] = "partial"
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
        # strict-serial deliberately starts frame k+1 after exp(k): V4 as
        # written (camera runs ahead) is not applicable, not a bubble.
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
    if key == "r0":
        cm = {}
        for k, v in CONTROL_EXPECT.items():
            got = stats.get(k)
            if got != v:
                cm[k] = {"expected": v, "got": got}
        for k, v in CONTROL_EVENTS.items():
            if k == "t_rst":
                got = m.get("t_rst")
            elif k == "t_exp1":
                got = t_exp[1]
            elif k == "t_exp2":
                got = t_exp[2]
            else:
                got = m.get("S_ss")
            if got != v:
                cm[k] = {"expected": v, "got": got}
        m["control_mismatches"] = cm
        m["control_pass"] = not cm
    if RUNS[key]["content"]:
        m["header_check"] = header_check(tag)
    return m


def header_check(tag):
    hdr_path = CAPS / (tag + ".hdr")
    proxy = jload(OUT / "content-proxy.json", {})
    if not hdr_path.exists() or not proxy:
        return {"available": False}
    rawb = bytes(int(x, 16) for x in hdr_path.read_text().split())
    if len(rawb) < 44:
        return {"available": False, "bytes": len(rawb)}
    u32 = lambda o: int.from_bytes(rawb[o:o + 4], "little")
    got = {"raw_len": u32(16), "xform_len": u32(20), "stream_len": u32(24),
           "raw_crc": u32(28), "xform_crc": u32(32), "stream_crc": u32(36),
           "header_crc": u32(40)}
    exp = {"raw_len": proxy["outputs"]["raw_bytes"],
           "xform_len": proxy["outputs"]["tiled_xform_bytes"],
           "raw_crc": proxy["outputs"]["raw_crc32"],
           "xform_crc": proxy["outputs"]["xform_crc32"]}
    bad = [k for k in exp if got[k] != exp[k]]
    hcrc = zlib.crc32(rawb[0:40]) & 0xFFFFFFFF
    return {"available": True, "got": got, "expected": exp, "bad": bad,
            "header_crc_ok": (hcrc == got["header_crc"]),
            "pass": (not bad) and hcrc == got["header_crc"]}


def write_runs_csv(db):
    cols = ["run", "mode", "content", "pacing", "sink", "capture", "frames", "command_rc",
            "command_seconds", "timed_out", "partial", "steady_state_status",
            "L_cold", "L_frame", "S_2", "S_23", "S_34", "S_ss", "S_ss_spread_pct",
            "capacity_MBps", "fps", "margin_0_pct", "margin_25_pct", "f_req_0_mhz",
            "f_req_25_mhz", "export_tail_mean_steady", "sink_limited",
            "exp_bytes", "cap_bytes", "cycles", "ss_vec_match", "control_pass"]
    with open(OUT / "runs.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for key in sorted(db):
            m = db[key]
            c = m.get("cfg", {})
            row = [key, m.get("mode"), c.get("content"), c.get("pacing"), c.get("sink"), c.get("capture"),
                   m.get("frames"), m.get("command_rc"), m.get("command_seconds"), m.get("timed_out"),
                   m.get("partial"), m.get("steady_state_status"), m.get("L_cold"), m.get("L_frame"),
                   m.get("S_2"), m.get("S_23"), m.get("S_34"), m.get("S_ss"), m.get("S_ss_spread_pct"),
                   m.get("capacity_MBps"), m.get("fps"), m.get("margin_0_pct"), m.get("margin_25_pct"),
                   m.get("f_req_0_mhz"), m.get("f_req_25_mhz"), m.get("export_tail_mean_steady"),
                   m.get("sink_limited"), m.get("counters", {}).get("exp_bytes"),
                   m.get("counters", {}).get("cap_bytes"), m.get("counters", {}).get("cycles"),
                   (m.get("ss_vec_match") or {}).get("bad"), m.get("control_pass")]
            w.writerow(["" if v is None else v for v in row])


# ------------------------------------------------------------------ analyze
ANCHORS = {
    "A1_grad_measured": {"cycles": 4677535.0, "label": "measured", "src": "R1 fast-sink S_ss (P1 4,677,535 -4 cycles)"},
    "A2_comp_assumed": {"cycles": 6421414.375, "label": "assumed", "src": "P2 A2 = 5,995,029.375 + 426,385"},
    "A3_rand_assumed": {"cycles": 3151346.5, "label": "assumed", "src": "P2 A3 = 2,724,961.5 + 426,385"},
    "P_proxy_measured": {"cycles": None, "label": "measured_proxy_not_worst", "src": "r3_frozen S_ss (frozen TB a565c6f2)"},
}
MODES = {"c1s1": 1.0, "c1s2": 0.5, "c2s1": 1.0, "c2s2": 1.0}


def cap_for(cycles, mode):
    return (4.86e8 / cycles) * MODES[mode]


def analyze():
    db = jload(OUT / "runs.json", {})
    proxy = jload(OUT / "content-proxy.json", {})
    need = [k for k in ("r0", "r1", "r2") if k not in db]
    if "r3f" not in db:
        need.append("r3f")
    if need:
        raise SystemExit("missing runs: %s" % need)
    r0, r1, r2, r3 = db["r0"], db["r1"], db["r2"], db["r3f"]
    r4 = db.get("r4")
    overlap_gain = (r2["S_ss"] - r1["S_ss"]) if (r1.get("S_ss") and r2.get("S_ss")) else None
    serial_frac = (100.0 * overlap_gain / r1["S_ss"]) if overlap_gain and r1.get("S_ss") else None
    ANCHORS["A1_grad_measured"]["cycles"] = r1.get("S_ss") or 4677535.0
    ANCHORS["P_proxy_measured"]["cycles"] = r3.get("S_ss")
    delta_serial = overlap_gain if overlap_gain is not None else 0.0

    rows = []
    for aid, a in ANCHORS.items():
        if a["cycles"] is None:
            continue
        for view in ("overlapped", "serial"):
            if view == "serial":
                if aid.startswith("P") and r4 and r4.get("S_ss"):
                    cyc = r4["S_ss"]
                    lbl = "measured"
                elif aid.startswith("A1") and r2.get("S_ss"):
                    cyc = r2["S_ss"]
                    lbl = "measured"
                else:
                    cyc = a["cycles"] + delta_serial
                    lbl = a["label"] + "+assumed_serial_delta"
            else:
                cyc = a["cycles"]
                lbl = a["label"]
            for mode in ("c1s1", "c1s2", "c2s1", "c2s2"):
                cap = cap_for(cyc, mode)
                rows.append({
                    "anchor": aid, "view": view, "mode": mode, "S_cycles": cyc,
                    "capacity_MBps": cap, "demand_MBps": G0_MBPS,
                    "margin_0_pct": (cap / G0_MBPS - 1) * 100,
                    "gate_G0": cap >= G0_MBPS,
                    "margin_25_pct": (cap / G25_MBPS - 1) * 100,
                    "gate_G25_ref_only": cap >= G25_MBPS,
                    "f_req_0_mhz": 30.0 * cyc / 1e6,
                    "label": lbl,
                    "source": a["src"],
                })
    for row in rows:
        if row["anchor"] == "A1_grad_measured" and row["view"] == "serial":
            row["source"] = "R2 strict-serial (measured)"
    cols = list(rows[0].keys())
    with open(OUT / "g0-table.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    # ------------------------------------------------ proxy / tail / sink
    needed_sink_333 = 2594750 / 33.333e-3 / 1e6
    needed_sink_25 = 2594750 / 25.0e-3 / 1e6
    measured_sink = None
    if r3.get("S_ss") and r3.get("counters", {}).get("exp_bytes") and r3.get("frames"):
        bpf = r3["counters"]["exp_bytes"] / r3["frames"]
        if bpf > 0 and r3.get("export_tail_mean_steady"):
            measured_sink = bpf / (r3["export_tail_mean_steady"] / CLOCK_HZ) / 1e6

    # ------------------------------------------------ sink demand table
    sink_rows = []
    for key in ("r0", "r1", "r2", "r3f"):
        m = db[key]
        fr = m.get("frames") or 0
        bpf = (m.get("counters", {}).get("exp_bytes") / fr) if fr else None
        tail = m.get("export_tail_mean_steady")
        rate = (bpf / (tail / CLOCK_HZ) / 1e6) if (bpf and tail) else None
        sink_rows.append({
            "run": key, "mode": m.get("mode"), "payload_bytes_per_frame": bpf,
            "export_tail_cycles": tail, "measured_export_rate_MBps": rate,
            "needed_rate_MBps_at_33.333ms": (bpf / 33.333e-3 / 1e6) if bpf else None,
            "needed_rate_MBps_at_25ms": (bpf / 25.0e-3 / 1e6) if bpf else None,
            "sink_limited": m.get("sink_limited"),
        })
    sink_rows.append({
        "run": "frozen_raw_band", "mode": "2,594,750 B/frame raw+overhead",
        "payload_bytes_per_frame": 2594750, "export_tail_cycles": None,
        "measured_export_rate_MBps": None,
        "needed_rate_MBps_at_33.333ms": needed_sink_333,
        "needed_rate_MBps_at_25ms": needed_sink_25, "sink_limited": None,
    })
    with open(OUT / "sink-needs.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(sink_rows[0].keys()))
        w.writeheader()
        w.writerows(sink_rows)

    # ------------------------------------------------ gap menu
    gap = {
        "A2_cycles": 6421414.0, "G0_cycles": 6250000.0,
        "gap_cycles": 6421414.0 - 6250000.0,
        "gap_pct_of_A2": 100.0 * (6421414.0 - 6250000.0) / 6421414.0,
        "gap_pct_of_core": 100.0 * (6421414.0 - 6250000.0) / 5995029.375,
        "A2_clock_0_mhz": 6421414.0 * 30 / 1e6,
        "A2_clock_25_mhz": 6421414.0 * 37.5 / 1e6,
        "G0_clock_mhz": 187.5, "G25_clock_mhz": 187.5 * 1.25,
        "proxy_gap_cycles": (r3["S_ss"] - 6250000.0) if r3.get("S_ss") else None,
        "proxy_gap_pct": (100.0 * (r3["S_ss"] - 6250000.0) / r3["S_ss"]) if r3.get("S_ss") else None,
        "overlap_gain_cycles": overlap_gain,
        "overlap_gain_pct_of_R1": serial_frac,
        "export_tail_cycles": r1.get("export_tail_mean_steady"),
        "needed_sink_MBps_33ms": needed_sink_333,
        "needed_sink_MBps_25ms": needed_sink_25,
        "measured_export_rate_MBps": measured_sink,
    }
    menu = [
        ("M1_tail_overlap", "hide the per-frame export tail by slot-free overlap",
         "0..%d cycles/frame (P1 slow-sink tail); fast-sink tail %s" % (
             r0.get("export_tail_mean_steady") or 480930, r1.get("export_tail_mean_steady")),
         "measured: slot-free S_ss=R1=%s; strict-serial penalty R2-R1=%s cycles (%s%%), "
         "which also includes camera serialization and is therefore an upper bound for "
         "what strict-serial loses" % (r1.get("S_ss"), overlap_gain,
                                      None if serial_frac is None else round(serial_frac, 3)),
         "already present in the P1/current slot-free pipeline; strict-serial loses it",
         "no new RTL; 2 RAW + 2 CMP slots already exist", "none", "R2 vs R1 measured",
         "0 (already implemented)"),
        ("M2_core_cycles", "reduce core cycles/B by 171,414 (2.859% of 5,995,029)",
         "171,414 cycles/frame", "A2 6,421,414 -> 6,250,000 exactly at G0",
         "requires ~2.86% faster core; no RTL change allowed in this run",
         "ERAM/area risk unassessed", "not timed; mod==0", "needs a new core task + TD + STA",
         "not implemented"),
        ("M3_clock", "raise core clock to 192.642 MHz (G0); 240.803 MHz is the G25 reference",
         "192.642 MHz @ 30 fps", "meets 30 fps at A2 cycles; 187.5 MHz gives 29.199 fps",
         "TD/STA not run; 192.642 MHz is +2.74% over the 187.5 MHz closed point",
         "unknown (no TD in this run)", "unproven", "TD/STA + bitgen + board", "not implemented"),
        ("M4_combo", "MASTER: overlap + 2.86% core cycles and/or +2.74% clock",
         "up to 171,414 + tail", "combination is sufficient only if each part is validated",
         "stacked risk; core and clock changes interact", "unknown", "unproven",
         "new implementation + TD + board", "not implemented"),
    ]
    with open(OUT / "gap-menu.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "path", "gain_cycles", "evidence", "risk", "resource_cost",
                    "timing_status", "validation_cost", "implemented"])
        w.writerows(menu)

    # ------------------------------------------------ G0 verdict
    v1 = db.get("v1") or {}
    v1_vec = v1.get("ss_vec_match") or {}
    r3_vec = r3.get("ss_vec_match") or {}
    hdr_ok = (r3.get("header_check") or {}).get("pass", False)
    proxy_vec_ok = (r3_vec.get("bad") == 0 and r3_vec.get("checked") == 518400
                    and r3_vec.get("drv_groups") in (518400, 2073600))
    proxy_ok = bool(proxy_vec_ok and hdr_ok)
    scope = ("per-stream 1080p30; content = comp-vector proxy (transform-domain "
             "1920x64 vector tiled b mod 32 over 1080p; proxy_not_worst, not all-content); "
             "pacing/sink = slot-free (overlapped) + measured 93.75 MB/s sim sink (proxy not limited; "
             "raw band still needs >=77.84 MB/s for G0 / >=103.79 MB/s at 25 ms, not_proven); "
             "DDR = behavioral 256-bit PAXI (no MC/refresh/contention model); "
             "single core per stream; no board/TD/real UART/PCIe claim")
    verdict = {"task": "T10.ss-g0-closure", "created": "2026-10-26",
               "hard_gate": {"G0_MBps": G0_MBPS, "G0_cycles": 6250000, "G0_clock_mhz": 187.5,
                             "G25_MBps_ref_only": G25_MBPS},
               "runs": {k: {"S_ss": db[k].get("S_ss"), "partial": db[k].get("partial"),
                            "sink_limited": db[k].get("sink_limited"),
                            "steady_state_status": db[k].get("steady_state_status")}
                        for k in ("r0", "r1", "r2", "r3f") if k in db},
               "v1_check_only": {"frames": 1, "max_cycles": 2000000,
                                 "note": "check-only run stopped before export; proves the fixed "
                                         "byte-level xform check, not a timing run",
                                 "ss_vec_match": v1_vec or None},
               "overlap_gain_cycles": overlap_gain, "overlap_gain_pct": serial_frac,
               "proxy_gap_cycles": gap["proxy_gap_cycles"], "proxy_gap_pct": gap["proxy_gap_pct"],
               "proxy_self_check": {
                   "r3_frozen_same_run": r3_vec or None,
                   "legacy_tb_r3_counter": (db.get("r3") or {}).get("ss_vec_match"),
                   "note": "R3 re-run with frozen TB a565c6f2: SS_VEC_MATCH bad=0 in the same run; "
                           "the r0 legacy-TB counter (bad=691132) is kept only as history",
                   "v1_check_only": v1_vec or None,
                   "dut_export_header_crc": (r3.get("header_check") or {}).get("pass"),
                   "proxy_ok": proxy_ok,
               },
               "a1_overlapped_note": "R1 4,677,531 is 4 cycles below P1 A1 4,677,535 (0.0001%)",
               "raw_band_sink_needs_MBps": {"G0": needed_sink_333, "25ms": needed_sink_25},
               "scope": scope,
               "not_downgraded": True, "g25_used_for_headline": False,
               "r4": "not_run_budget_cap; comp strict-serial view is assumed = R3 + (R2-R1)",
               "sink": {
                   "frozen_raw_band_needed_MBps_33ms": needed_sink_333,
                   "frozen_raw_band_needed_MBps_25ms": needed_sink_25,
                   "measured_export_rate_MBps_r3": measured_sink,
                   "r3_payload_bytes_per_frame": (r3.get("counters", {}).get("exp_bytes") or 0) / 4.0,
               }}
    if not r0.get("control_pass"):
        v = "G0_not_proven"
        why = "R0 control did not reproduce P1 by value: %s" % r0.get("control_mismatches")
    elif not proxy_ok or r3.get("partial") or not r3.get("S_ss"):
        v = "G0_not_proven"
        why = ("proxy byte-level self check failed (r3_frozen bad=%s), DUT header CRC failed, "
               "run partial, or no S_ss" % r3_vec.get("bad"))
    elif r3["S_ss"] <= 6250000:
        v = "G0_feasible_for_scope"
        why = "R3 S_ss %.1f <= 6,250,000 cycles (measured, comp proxy content, slot-free)" % r3["S_ss"]
    else:
        v = "G0_not_closed"
        why = "R3 S_ss %.1f > 6,250,000 cycles; gap %.1f cycles (%.3f%%)" % (
            r3["S_ss"], gap["proxy_gap_cycles"], gap["proxy_gap_pct"])
    verdict["verdict"] = v
    verdict["why"] = why
    verdict["proxy_header_crc_ok"] = hdr_ok
    verdict["proxy_vec_match"] = r3_vec
    legacy = db.get("r3") or {}
    verdict["r3_vs_r0"] = {
        "legacy_S_ss": legacy.get("S_ss"), "frozen_S_ss": r3.get("S_ss"),
        "delta_cycles": (r3["S_ss"] - legacy["S_ss"]) if (legacy.get("S_ss") and r3.get("S_ss")) else None,
        "note": "round1 r3_frozen vs round0 legacy-TB r3; same timing, frozen TB is the G0 binding",
    }
    verdict["label_scope"] = "measured-for-proxy-content only; not all-content, not worst-case"
    jdump(OUT / "g0-verdict.json", verdict)

    # ------------------------------------------------ negative controls
    neg = []
    def add(nid, name, rejected, detail):
        neg.append({"id": nid, "name": name, "rule": "rejected_as_invalid", "rejected": rejected, "detail": detail})
    # NEG-1 G25-driven downgrade
    g25_row = [r for r in rows if r["anchor"] == "A2_comp_assumed" and r["mode"] == "c1s1" and r["view"] == "overlapped"][0]
    add("NEG-01", "G25_DOWNGRADE",
        (not g25_row["gate_G0"]) or g25_row["gate_G0"] and not g25_row["gate_G25_ref_only"],
        "A2 c1s1 overlapped: G0=%s G25=%s; must not turn below_25 into a 1600x900 recommendation"
        % (g25_row["gate_G0"], g25_row["gate_G25_ref_only"]))
    # NEG-2 cold latency as S_ss
    cold = r0.get("L_cold")
    cold_cap = 4.86e8 / cold if cold else None
    add("NEG-02", "COLD_LATENCY_AS_THROUGHPUT",
        cold_cap is not None and cold_cap < G0_MBPS,
        "L_cold=%.0f -> %.3f MB/s < 77.76: using t_exp(1)-t_rst as S_ss fails G0; S_ss must be the frame-to-frame interval"
        % (cold, cold_cap))
    # NEG-3 proxy as worst/all-content
    add("NEG-03", "PROXY_AS_WORST_ALL_CONTENT",
        True, "proxy is a tiled synthetic comp ramp; claim_status=proxy_not_worst; no all-content proof")
    # NEG-4 serial as overlap
    add("NEG-04", "SERIAL_AS_OVERLAP",
        (overlap_gain is not None and overlap_gain > 0),
        "R2-R1=%s cycles: strict-serial S_ss must not populate the overlapped column" % overlap_gain)
    # NEG-5 aggregate 2C as per-stream
    c1s2 = [r for r in rows if r["anchor"] == "A1_grad_measured" and r["view"] == "overlapped" and r["mode"] == "c1s2"][0]
    agg_ok = (2.0 * (4.86e8 / c1s2["S_cycles"])) >= G0_MBPS
    add("NEG-05", "AGGREGATE_CAPACITY_FOR_PER_STREAM",
        agg_ok and (c1s2["capacity_MBps"] < G0_MBPS),
        "c1s2 aggregate 2C=%0.3f passes while per-stream C/2=%0.3f fails: aggregate may not replace per-stream"
        % (2.0 * (4.86e8 / c1s2["S_cycles"]), c1s2["capacity_MBps"]))
    jdump(OUT / "negative-controls.json", {"controls": neg,
                                           "all_rejected": all(n["rejected"] for n in neg)})

    # ------------------------------------------------ content proxy doc
    lines = ["# P3 content proxy (comp-like full-frame)", "",
             "- label: **proxy_not_worst** (proxy content; not a worst/all-content proof).",
             "- input: frozen comp vector 32x4800 B (SHA `%s`), tiled over 1920x1080 by 2-ROI-row block b mod 32 (540 blocks)."
             % proxy.get("inputs", {}).get("in.hex", {}).get("sha256", "?"),
             "- domain: in.hex is transform-domain; the chain has PREP/PRED=1, so the TB inverts with a1_ref.inverse_frame to packed RAW10 and the DUT re-applies the transform; the core consumes the vector byte for byte.",
             "- Python check: forward(inverse(tiled)) == tiled, mismatch=%d." % proxy.get("transform", {}).get("mismatch_bytes"),
             "- fixed-TB check (v1, check-only run stopped at 2,000,000 cycles): SS_VEC_MATCH bad=%s checked=%s drv_groups=%s."
             % (v1_vec.get("bad"), v1_vec.get("checked"), v1_vec.get("drv_groups")),
             "- R3 pre-fix TB counter printed bad=691132: a TB-only grouping off-by-one (compared every 3rd sample); it does not touch DUT inputs.",
             "- DUT end-to-end: R3 exported frame header raw_crc/xform_crc/lengths equal the Python expectation; header_crc self-consistent; pass=%s." % hdr_ok,
             "- cross-band: identical blocks are 153,600 B apart, far beyond the core 13-bit (8,192 B) match window; adjacent blocks differ.",
             "- limits: synthetic ramp, single content class; no natural/low-light/noise corpus; real images remain not_proven.",
             "- local codec-throughput rerun (different core.v 79,788 B) gives 374,461 cycles/153,600 B = 2.438 c/B vs frozen 355,261 (2.313 c/B), +5.1%; A2 stays assumed and R3 is the direct measurement."]
    (OUT / "content-proxy.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


    # ------------------------------------------------ console summary
    print("verdict=%s why=%s" % (v, why))
    print("overlap_gain=%s (%s%%) proxy_gap=%s" % (overlap_gain, serial_frac, gap["proxy_gap_cycles"]))
    print("negative_controls_all_rejected=%s" % all(n["rejected"] for n in neg))
    return verdict


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: run_g0.py compile|r0|r1|r2|r3|r4|analyze")
    os.environ.update(toolenv())
    what = sys.argv[1]
    if what == "compile":
        compile_all()
    elif what in RUNS:
        vsim(what)
    elif what == "reparse":
        db = jload(OUT / "runs.json", {})
        for key in list(db):
            stat = CAPS / (key + ".stats")
            log = LOGS / (key + ".log")
            if stat.exists():
                old = db[key]
                db[key] = metrics(key, stat, log, old.get("command_seconds", 0.0),
                                  old.get("command_rc", 0), old.get("timed_out", False))
        jdump(OUT / "runs.json", db)
        write_runs_csv(db)
        print("reparsed %d runs" % len(db))
    elif what == "analyze":
        analyze()
    else:
        raise SystemExit("unknown subcommand")


if __name__ == "__main__":
    main()
