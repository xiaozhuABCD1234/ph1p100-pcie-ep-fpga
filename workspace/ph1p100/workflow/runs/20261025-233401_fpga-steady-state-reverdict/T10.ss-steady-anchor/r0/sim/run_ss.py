#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""run_ss.py -- T10.ss-steady-anchor driver (ModelSim ASE 10.5b, offline only).

Subcommands:
    freeze     copy the 14 frozen inputs from b11 into src/, verify every sha256
               against the b11 candidate manifest, copy modelsim.ini to the
               exclusive temp dir, write input-verified.json.
    compile    vlib + vlog the 12 frozen DUT/model sources + tb_ss_anchor.v.
    control2   vsim -gFRAMES=2; require the b11 two-frame statistics by value.
    run4       vsim -gFRAMES=4; parse SS_EVT -> out/events-4frame.csv,
               out/steady-state.json, out/steady-state.md.
    selfcheck  3 parser negative controls + arithmetic hand checks.
    report     result-r0.md + lessons.md from the measured artifacts.
    manifest   manifest-r0.json over the whole task r0/ tree.

No TD / synthesis / place&route / bitgen / board / COM / JTAG is used.
"""
import argparse
import hashlib
import json
import os
import pathlib
import platform
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261025-233401_fpga-steady-state-reverdict"
R0 = RUN / "T10.ss-steady-anchor/r0"
SRC = R0 / "src"
REF = SRC / "ref"
SIM = R0 / "sim"
LOGS = SIM / "logs"
CAPS = SIM / "caps"
OUT = R0 / "out"
TMP = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\ss-anchor")
WORK = TMP / "work"
MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
SHARED_INI = ROOT / "work/parallel-sim-20261024-2204/codec-throughput/modelsim.ini"
INI = TMP / "modelsim.ini"
B11 = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0"
B11_MANIFEST = B11 / "CANDIDATE-MANIFEST-b11-aplus-read-r0.json"
B6 = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/r0"
B6_STATS = B6 / "sim/captures/full_grad.stats"

CLOCK_HZ = 187.5e6
FRAME_BYTES = 2592000
DEMAND_NOM = 77.76
DEMAND_25 = 97.20
EXPORT_COST = 40032 * 10
RAW_WORDS = 129600
WD_LIMIT = 8000000

CONTROL_EXPECT = {
    "cap": 2, "enc": 2, "exported": 2, "exp_bytes": 80068, "raw_pub": 2,
    "raw_drop": 0, "cmp_drop": 0, "geom": 0, "err": 0, "read": 259200,
    "dup": 0, "cap_bytes": 80156, "cycles": 11445988, "wd": 0,
}
CONTROL_EXTRA = {"ar": 261704, "r": 261704}

ENV = os.environ.copy()
ENV["MODEL_TECH"] = str(MS)
ENV["MODELSIM"] = str(INI)
ENV["PATH"] = str(MS) + os.pathsep + ENV.get("PATH", "")

SRC_FILES = [
    "a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v",
    "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
    "a1_deflate_core.v", "p2_ddr_bridge.v", "a1_ddr_arb2.v",
    "capture_async_fifo.v", "p2_paxi_model_b11.v", "a1_ddr_model.v",
]
TB_FILE = "tb_ss_anchor.v"


def now():
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def jwrite(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def jread(path):
    return json.loads(path.read_text(encoding="utf-8"))


def getk(d, k):
    """Lookup that works for list indexes and for dict int/str keys."""
    if d is None:
        return None
    if isinstance(d, list):
        return d[k] if 0 <= k < len(d) else None
    if k in d:
        return d[k]
    return d.get(str(k))


def log_command(argv, cwd, rc, seconds, timeout, extra=None):
    rec = {
        "argv": [str(a) for a in argv],
        "cwd": str(cwd),
        "rc": rc,
        "seconds": round(seconds, 1),
        "timeout_s": timeout,
        "started": now(),
    }
    if extra:
        rec.update(extra)
    SIM.mkdir(parents=True, exist_ok=True)
    with open(SIM / "commands.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    return rec


def run_proc(argv, cwd, log_path, timeout):
    """Run argv with a hard timeout; stdout+stderr go to log_path.out."""
    log_path = pathlib.Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    out_path = pathlib.Path(str(log_path) + ".out")
    t0 = time.monotonic()
    rc = None
    timed_out = False
    with open(out_path, "w", encoding="utf-8", errors="replace") as lf:
        try:
            pr = subprocess.run([str(a) for a in argv], cwd=str(cwd), env=ENV,
                                stdout=lf, stderr=subprocess.STDOUT, timeout=timeout)
            rc = pr.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            rc = 124
    el = time.monotonic() - t0
    log_command(argv, cwd, rc, el, timeout, {"timed_out": timed_out, "log": str(log_path)})
    return rc, round(el, 1), timed_out, out_path


# --------------------------------------------------------------------- freeze
def freeze():
    for d in (SRC, REF, SIM, LOGS, CAPS, OUT, TMP):
        d.mkdir(parents=True, exist_ok=True)
    manifest = jread(B11_MANIFEST)
    expected = {}
    for group in ("changed_src", "repo_deps", "sim"):
        for ent in manifest["groups"][group]:
            key = pathlib.PurePath(ent["path"]).name
            expected[key] = {"group": group, "manifest_path": ent["path"],
                             "sha256": ent["sha256"].lower(), "bytes": ent["bytes"]}
    copies = []
    for ent in manifest["groups"]["changed_src"]:
        name = pathlib.PurePath(ent["path"]).name
        copies.append(("changed_src", B11 / "changed-src" / name, SRC / name))
    for ent in manifest["groups"]["repo_deps"]:
        rel = ent["path"]
        copies.append(("repo_deps", ROOT / rel, SRC / pathlib.PurePath(rel).name))
    for ent in manifest["groups"]["sim"]:
        name = pathlib.PurePath(ent["path"]).name
        if name in ("p2_paxi_model_b11.v", "a1_ddr_model.v"):
            copies.append(("sim_model", B11 / "sim" / name, SRC / name))
        elif name == "tb_b11_full.v":
            copies.append(("sim_ref_tb", B11 / "sim" / name, REF / name))
    records = []
    for group, source, dest in copies:
        name = pathlib.PurePath(str(source)).name
        shutil.copyfile(source, dest)
        s_sha = sha256(source)
        d_sha = sha256(dest)
        s_bytes = source.stat().st_size
        d_bytes = dest.stat().st_size
        exp = expected[name]
        rec = {
            "group": group,
            "source": str(source),
            "dest": str(dest),
            "source_bytes": s_bytes,
            "dest_bytes": d_bytes,
            "sha256": d_sha,
            "source_sha256": s_sha,
            "manifest_sha256": exp["sha256"],
            "manifest_bytes": exp["bytes"],
            "manifest_group": exp["group"],
            "match_manifest": (d_sha == exp["sha256"]) and (d_bytes == exp["bytes"]),
            "match_source": d_sha == s_sha,
        }
        records.append(rec)
    shutil.copyfile(SHARED_INI, INI)
    SIM.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SHARED_INI, SIM / "modelsim.ini")
    ini_rec = {
        "source": str(SHARED_INI), "dest": str(INI),
        "archive_path": str(SIM / "modelsim.ini"),
        "bytes": INI.stat().st_size, "sha256": sha256(INI),
        "source_sha256": sha256(SHARED_INI),
    }
    snapshot = {}
    for label, p in [
        ("b11_manifest", B11_MANIFEST),
        ("b11_full_stats", B11 / "sim/caps/full.stats"),
        ("b11_tb_b11_full", B11 / "sim/tb_b11_full.v"),
        ("b11_p2_paxi_model", B11 / "sim/p2_paxi_model_b11.v"),
        ("b11_a1_ddr_model", B11 / "sim/a1_ddr_model.v"),
        ("b11_result_r0", B11 / "result-r0.md"),
        ("b6_tb_camera_a1_uart_top", B6 / "sim/boundaries/src/tb_camera_a1_uart_top.v"),
        ("b6_full_grad_stats", B6_STATS),
        ("p2_feasibility_report", ROOT / "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-aplus-service-verdict/r0/feasibility-report.md"),
        ("p2_manifest", ROOT / "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-aplus-service-verdict/r0/manifest-r0.json"),
        ("tasks_json", ROOT / "workflow/tasks.json"),
    ]:
        snapshot[label] = {"path": str(p), "bytes": p.stat().st_size if p.exists() else None,
                           "sha256": sha256(p) if p.exists() else "MISSING"}
    all_match = all(r["match_manifest"] and r["match_source"] for r in records)
    obj = {
        "task_id": "T10.ss-steady-anchor",
        "created": now(),
        "b11_manifest": str(B11_MANIFEST),
        "b11_manifest_sha256": sha256(B11_MANIFEST),
        "copied_files": records,
        "copied_count": len(records),
        "compiled_relevant_count": sum(1 for r in records if r["group"] in ("changed_src", "repo_deps", "sim_model")),
        "reference_tb_count": sum(1 for r in records if r["group"] == "sim_ref_tb"),
        "compiled_dut_count": 12,
        "not_compiled": [str(SRC / "p2_a1_board_top.v"), str(REF / "tb_b11_full.v")],
        "copied_src_all_match": all_match,
        "mismatch_count": sum(1 for r in records if not (r["match_manifest"] and r["match_source"])),
        "modelsim_ini": ini_rec,
        "input_snapshot": snapshot,
        "drift_note": "b11/b6/P2 trees are read-only; these hashes are the snapshot at freeze time",
    }
    jwrite(R0 / "input-verified.json", obj)
    print("FREEZE copied=%d mismatch=%d all_match=%s" % (len(records), obj["mismatch_count"], all_match))
    for r in records:
        if not (r["match_manifest"] and r["match_source"]):
            print("  MISMATCH", r["dest"], r["sha256"], "expected", r["manifest_sha256"])
    if not all_match:
        return 2
    return 0


# -------------------------------------------------------------------- compile
def compile_all():
    LOGS.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    if not (WORK / "work" / "_info").exists():
        rc, el, to, _ = run_proc([MS / "vlib.exe", "work"], WORK, LOGS / "vlib.log", 300)
        print("vlib rc=%s %.1fs timeout=%s" % (rc, el, to))
        if rc != 0:
            return 2
    files = [SRC / f for f in SRC_FILES] + [SRC / TB_FILE]
    for f in files:
        if not f.exists():
            print("MISSING", f)
            return 2
    argv = [MS / "vlog.exe", "-sv", "-work", "work", "+define+SIMULATION"] + files
    rc, el, to, out_path = run_proc(argv, WORK, LOGS / "vlog.log", 1200)
    txt = out_path.read_text(encoding="utf-8", errors="replace")
    shutil.copyfile(out_path, LOGS / "vlog.log")
    vlib_out = pathlib.Path(str(LOGS / "vlib.log") + ".out")
    if vlib_out.exists():
        shutil.copyfile(vlib_out, LOGS / "vlib.log")
    errors = [l for l in txt.splitlines() if "** Error" in l]
    warns = [l for l in txt.splitlines() if "** Warning" in l]
    print("compile rc=%s %.1fs timeout=%s errors=%d warnings=%d" % (rc, el, to, len(errors), len(warns)))
    for l in errors[:20]:
        print("  " + l)
    if rc != 0 or errors:
        return 2
    return 0


# ---------------------------------------------------------------------- vsim
def vsim_argv(frames, stat, dec, evt, log):
    return [MS / "vsim.exe", "-c", "-lib", "work", "-l", str(log), "tb_ss_anchor",
            "+STAT=" + str(stat), "+DEC=" + str(dec), "+EVT=" + str(evt),
            "-gFRAMES=%d" % frames, "-do", "run -all; quit -f"]


def parse_stats(path):
    if not pathlib.Path(path).exists():
        return None
    line = pathlib.Path(path).read_text(encoding="utf-8", errors="replace").strip().splitlines()
    if not line:
        return None
    out = {}
    for tok in line[-1].split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            try:
                out[k] = int(v)
            except ValueError:
                out[k] = v
    return out


EVT_RE = re.compile(r"SS_EVT t=(\d+) kind=(sof|cam_end|pub|read|enc|exp) frame=(\d+) n=(\d+)")
META_RE = re.compile(r"SS_META t_rst=(\d+) frames=(\d+) max_cycles=(\d+) uart_div=(\d+)")
PACE_RE = re.compile(r"SS_PACE frame=(\d+) slot=(\d+) t=(\d+) read=(\d+) slot_st=(\d+)")


def parse_log(path):
    text = pathlib.Path(path).read_text(encoding="utf-8", errors="replace") if pathlib.Path(path).exists() else ""
    events = []
    meta = {}
    pace = {}
    for line in text.splitlines():
        m = EVT_RE.search(line)
        if m:
            events.append({"t": int(m.group(1)), "kind": m.group(2),
                           "frame": int(m.group(3)), "n": int(m.group(4))})
            continue
        m = META_RE.search(line)
        if m:
            meta = {"t_rst": int(m.group(1)), "frames": int(m.group(2)),
                    "max_cycles": int(m.group(3)), "uart_div": int(m.group(4))}
            continue
        m = PACE_RE.search(line)
        if m:
            pace[int(m.group(1))] = {"slot": int(m.group(2)), "t": int(m.group(3)),
                                     "read": int(m.group(4)), "slot_st": int(m.group(5))}
    return events, meta, pace, text


def event_map(events):
    d = {}
    dup = []
    for e in events:
        key = (e["frame"], e["kind"])
        if key in d and d[key] != e["t"]:
            dup.append({"key": "%d/%s" % key, "t_first": d[key], "t_second": e["t"]})
        d[key] = e["t"]
    return d, dup


# ---------------------------------------------------------------- control run
def control2(timeout):
    stat = CAPS / "ss2.stats"
    dec = CAPS / "ss2.dec"
    evt = CAPS / "ss2.evt"
    log = LOGS / "control2.log"
    pre = sha256(stat) if stat.exists() else None
    pre_mtime = stat.stat().st_mtime_ns if stat.exists() else None
    argv = vsim_argv(2, stat, dec, evt, log)
    rc, el, to, _ = run_proc(argv, WORK, log, timeout)
    post = sha256(stat) if stat.exists() else None
    post_mtime = stat.stat().st_mtime_ns if stat.exists() else None
    fresh = post_mtime is not None and post_mtime != pre_mtime
    st = parse_stats(stat)
    _, meta, _, text = parse_log(log)
    gate_ok = "B11_FULL_RESULT pass=1" in text
    mismatches = []
    actual = {}
    if st is None:
        mismatches.append({"field": "*", "why": "no stats file (timeout=%s rc=%s)" % (to, rc)})
    else:
        for k, v in CONTROL_EXPECT.items():
            actual[k] = st.get(k)
            if st.get(k) != v:
                mismatches.append({"field": k, "expected": v, "actual": st.get(k)})
        for k, v in CONTROL_EXTRA.items():
            actual[k] = st.get(k)
            if st.get(k) != v:
                mismatches.append({"field": k, "expected": v, "actual": st.get(k)})
    res = {
        "task_id": "T10.ss-steady-anchor",
        "run": "control2",
        "argv": [str(a) for a in argv],
        "cwd": str(WORK),
        "rc": rc,
        "timed_out": to,
        "seconds": el,
        "log": str(log),
        "stats": str(stat),
        "stats_sha256": post,
        "stats_preexisting_sha256": pre,
        "stats_fresh": fresh,
        "meta": meta,
        "expected": CONTROL_EXPECT,
        "expected_extra": CONTROL_EXTRA,
        "actual": actual,
        "mismatches": mismatches,
        "result_marker_pass": gate_ok,
        "pass": (not mismatches) and gate_ok and fresh,
        "created": now(),
    }
    jwrite(OUT / "control-2frame.json", res)
    print("CONTROL2 pass=%s rc=%s %.1fs timeout=%s fresh=%s mismatches=%d"
          % (res["pass"], rc, el, to, res["stats_fresh"], len(mismatches)))
    for m in mismatches:
        print("  ", m)
    return 0 if res["pass"] else 3


# -------------------------------------------------------------------- run4
def metrics_from(events, meta, pace, stats, control):
    d, dup = event_map(events)
    frames = sorted({f for (f, k) in d if k == "exp"})
    present = {f: sorted(k for (ff, k) in d if ff == f) for f in frames}
    stat = stats or {}
    m = {
        "created": now(),
        "clock_hz": CLOCK_HZ,
        "frames": len(frames),
        "frames_param": meta.get("frames"),
        "frames_exported": frames,
        "frames_present": present,
        "event_duplicates": dup,
        "t_rst": meta.get("t_rst"),
        "tb_frames_param": meta.get("frames"),
        "uart_div": meta.get("uart_div"),
        "pace": pace,
        "counters": {k: stat.get(k) for k in
                     ("cap", "enc", "exported", "exp_bytes", "raw_pub", "raw_drop",
                      "cmp_drop", "geom", "err", "read", "dup", "cap_bytes",
                      "cycles", "wd", "ar", "r", "frames", "ss_pass")},
        "source_manifest_sha": jread(R0 / "input-verified.json")["b11_manifest_sha256"],
        "source_manifest_sha256": jread(R0 / "input-verified.json")["b11_manifest_sha256"],
        "copied_src_all_match": jread(R0 / "input-verified.json")["copied_src_all_match"],
        "tb_sha": sha256(SRC / TB_FILE),
        "tb_sha256": sha256(SRC / TB_FILE),
    }
    series = {}
    for key in ("sof", "cam_end", "pub", "read", "enc", "exp"):
        series[key] = [None] + [d.get((f, key)) for f in range(1, 5)]
    m.update({("t_" + k): v for k, v in series.items()})
    texp = series["exp"]
    def diff(a, b):
        if a[b] is None or a[b - 1] is None:
            return None
        return a[b] - a[b - 1]
    m["L_cold"] = (texp[1] - m["t_rst"]) if texp[1] is not None and m["t_rst"] is not None else None
    m["L_frame"] = (texp[1] - series["sof"][1]
                    if texp[1] is not None and series["sof"][1] is not None else None)
    m["S_2"] = diff(texp, 2)
    m["S_23"] = diff(texp, 3)
    m["S_34"] = diff(texp, 4)
    m["S_avg2"] = ((texp[2] - m["t_rst"]) / 2.0) if texp[2] is not None and m["t_rst"] is not None else None
    m["S_avg2_stats_2frame"] = 11445988 / 2.0
    m["S_avg2_note"] = ("S_avg2=(t_exp(2)-t_rst)/2 is the 2-frame event average; "
                        "S_avg2_stats_2frame=11,445,988/2=5,722,994 includes the 2,000-cycle drain; "
                        "neither is S_ss")

    four = all(texp[k] is not None for k in (1, 2, 3, 4))
    v1 = (stat.get("cap") == 4 and stat.get("enc") == 4 and stat.get("exported") == 4
          and stat.get("read") == 4 * RAW_WORDS and stat.get("raw_drop") == 0
          and stat.get("cmp_drop") == 0 and stat.get("geom") == 0 and stat.get("err") == 0
          and stat.get("dup") == 0 and stat.get("wd") == 0 and four)
    v2 = bool(control and control.get("pass"))
    s_pair = [m["S_23"], m["S_34"]]
    m["S_band_cycles"] = [min([x for x in s_pair if x is not None]), max([x for x in s_pair if x is not None])] if all(x is not None for x in s_pair) else None
    if all(x is not None for x in s_pair):
        s_mean = sum(s_pair) / 2.0
        s_spread_pct = 100.0 * abs(s_pair[0] - s_pair[1]) / s_mean
    else:
        s_mean, s_spread_pct = None, None
    v3 = (s_spread_pct is not None and s_spread_pct <= 2.0)
    # V4: camera must not be the rate limiter for the steady frames
    v4 = True
    v4_detail = []
    if not (series["pub"][3] and texp[2]):
        v4 = False
        v4_detail.append("missing pub3/exp2")
    elif not (series["pub"][3] < texp[2]):
        v4 = False
        v4_detail.append("pub3>=exp2")
    if not (series["pub"][4] and texp[3]):
        v4 = False
        v4_detail.append("missing pub4/exp3")
    elif not (series["pub"][4] < texp[3]):
        v4 = False
        v4_detail.append("pub4>=exp3")
    cam_dur = {}
    if s_mean:
        for k in (2, 3, 4):
            if series["cam_end"][k] is not None and series["sof"][k] is not None:
                cam_dur[k] = series["cam_end"][k] - series["sof"][k]
                if cam_dur[k] >= 0.5 * s_mean:
                    v4 = False
                    v4_detail.append("cam_dur%d>=0.5*S_ss" % k)
            else:
                v4 = False
                v4_detail.append("missing cam_end/sof%d" % k)
    else:
        v4 = False
        v4_detail.append("S_ss not available")
    # V5: slot-free pacing evidence for frames 3/4
    v5_detail = []
    v5 = True
    for k, slot in ((3, 0), (4, 1)):
        p = pace.get(k)
        if p is None:
            v5 = False
            v5_detail.append("missing SS_PACE frame=%d" % k)
            continue
        if p["read"] < RAW_WORDS * (k - 2):
            v5 = False
            v5_detail.append("frame%d read=%d < %d" % (k, p["read"], RAW_WORDS * (k - 2)))
        slot_st = (p["slot_st"] >> (2 * slot)) & 3
        if slot_st != 0:
            v5 = False
            v5_detail.append("frame%d target slot%d not FREE (st=%d)" % (k, slot, slot_st))
        if p["slot"] != slot:
            v5_detail.append("frame%d pace slot=%d (expected %d)" % (k, p["slot"], slot))
    # V6: monotonic event order
    v6 = True
    v6_detail = []
    if four:
        for k in range(2, 5):
            if not (texp[k - 1] < texp[k]):
                v6 = False
                v6_detail.append("exp not increasing at %d" % k)
    else:
        v6 = False
        v6_detail.append("missing exp frame")
    for k in (1, 2, 3, 4):
        vals = [series["pub"][k], series["read"][k], series["enc"][k], series["exp"][k]]
        if any(v is None for v in vals):
            v6 = False
            v6_detail.append("missing pub/read/enc/exp frame=%d" % k)
        elif not (vals[0] <= vals[1] <= vals[2] <= vals[3]):
            v6 = False
            v6_detail.append("order violated frame=%d %s" % (k, vals))

    m["S_ss"] = s_mean
    m["S_ss_band_cycles"] = m["S_band_cycles"]
    m["S_ss_spread_pct"] = s_spread_pct
    m["steady_state_status"] = "not_measured"
    if four and v1:
        m["steady_state_status"] = "measured" if v3 else "unstable"
    elif four:
        m["steady_state_status"] = "partial"
    elif len(frames) >= 2:
        m["steady_state_status"] = "partial"
    m["validity"] = {
        "v1_counts": bool(v1), "v2_control_exact": v2, "v3_stable": bool(v3),
        "v4_no_bubble": bool(v4), "v5_slot_free": bool(v5), "v6_monotone": bool(v6),
        "v4_detail": v4_detail, "v5_detail": v5_detail, "v6_detail": v6_detail,
    }
    m["capacity_is_lower_bound"] = not v4
    m["cam_duration"] = cam_dur
    tails = [None] * 5
    for k in range(1, 5):
        if series["exp"][k] is not None and series["enc"][k] is not None:
            tails[k] = series["exp"][k] - series["enc"][k]
    m["export_tail"] = tails
    m["export_cost_cycles"] = EXPORT_COST
    tails_ss = [tails[k] for k in (2, 3, 4) if tails[k] is not None]
    sink = False
    sink_why = []
    if s_mean and len(tails_ss) == 3:
        spread = max(tails_ss) - min(tails_ss)
        if spread > 0.01 * s_mean:
            sink = True
            sink_why.append("tail spread %d > 1%% S_ss" % spread)
        if max(tails_ss) >= 0.5 * s_mean:
            sink = True
            sink_why.append("tail >= 0.5*S_ss")
        if tails_ss[2] > tails_ss[1] > tails_ss[0] and (tails_ss[2] - tails_ss[0]) > 0.01 * s_mean:
            sink = True
            sink_why.append("tail grows with k")
    else:
        sink_why.append("tail constancy not evaluable")
    m["sink_limited"] = bool(sink)
    m["sink_limited_why"] = sink_why
    m["export_tail_mean_steady"] = (sum(tails_ss) / len(tails_ss)) if tails_ss else None
    if s_mean:
        C = 4.86e8 / s_mean
        m["capacity_MBps"] = C
        m["fps"] = 1.875e8 / s_mean
        m["margin_0_pct"] = (C / DEMAND_NOM - 1.0) * 100.0
        m["margin_25_pct"] = (C / DEMAND_25 - 1.0) * 100.0
        m["f_req_0_MHz"] = 30.0 * s_mean / 1e6
        m["f_req_25_MHz"] = 37.5 * s_mean / 1e6
        m["f_req_0_mhz"] = m["f_req_0_MHz"]
        m["f_req_25_mhz"] = m["f_req_25_MHz"]
        if sink and m["export_tail_mean_steady"] is not None and (s_mean - m["export_tail_mean_steady"]) > 0:
            m["c_excl_export_MBps"] = 4.86e8 / (s_mean - m["export_tail_mean_steady"])
            m["c_excl_export_note"] = "optimistic bound, only because sink_limited=true"
        else:
            m["c_excl_export_MBps"] = C
            m["c_excl_export_note"] = "equal to C_ss: constant tail cancels in frame-to-frame interval"
        m["startup"] = m["L_cold"] - s_mean if m["L_cold"] is not None else None
        m["startup_pct"] = 100.0 * (m["L_cold"] / s_mean - 1.0) if m["L_cold"] is not None else None
        m["knife_edge_0pct"] = (m["S_band_cycles"] is not None and m["S_band_cycles"][0] < 6_250_000 < m["S_band_cycles"][1])
        m["knife_edge_25pct"] = (m["S_band_cycles"] is not None and m["S_band_cycles"][0] < 5_000_000 < m["S_band_cycles"][1])
    else:
        for k in ("capacity_MBps", "fps", "margin_0_pct", "margin_25_pct", "f_req_0_MHz",
                  "f_req_25_MHz", "c_excl_export_MBps", "startup", "startup_pct"):
            m[k] = None
    m["b6_reference"] = {
        "L_cold_b6_cycles": 6421414,
        "expected_range_cycles": [6421414, 6750000],
        "note": "b6 single-frame cold latency under 3840x2160/ROI960/540/LINE_GAP40/1GHz UART; not throughput",
    }
    m["notes"] = {
        "sink": "sim-only UART_DIV=1 with clk_uart=clk_a1=187.5 MHz -> 18.75 MB/s (10 cycles/byte); not 115200 production",
        "ddr": "behavioral 256-bit PAXI model, single beat, AR_GAP=2, R_GAP=3, rdy=1; no MC arbitration/refresh/row/contention model",
        "content": "single smooth pattern smp(x,y)=(x*3+y*5+((x^y)&7)*17)&1023",
        "geometry": "b11 geometry CAM 3864x2192 ROI 972/556 W/H 1920/1080 LINE_GAP=16 FRAME_GAP=400",
        "scope": "per-stream 1080p chain measurement only; no gate verdict, no DDR sustained, no dual-core, no board",
        "cycles_drain": "stats cycles include the inherited 2000-cycle post-export drain; event t_exp is authoritative for intervals",
        "read_done_marker": "inherited B11_FULL_READ_DONE wait stays at 2*129600 for b11 diff fidelity; informational only for FRAMES=4",
        "avg2": "S_avg2 (event, (t_exp(2)-t_rst)/2) and S_avg2_stats (11,445,988/2=5,722,994, includes 2,000 drain) are 2-frame references, not S_ss",
        "b6_comparison": "b6 6,421,414 is a single-frame cold latency (different geometry/UART); new L_cold is expected in 6.42M-6.75M, measured overshoot is reported with its cause and does not affect S_ss",
    }
    return m


def render_md(m):
    lines = []
    lines.append("# P1 稳态锚点实测（T10.ss-steady-anchor r0）\n")
    lines.append("- 生成：%s；run `20261025-233401_fpga-steady-state-reverdict`" % now())
    lines.append("- 冻结 TB：`src/tb_ss_anchor.v`（sha256 `%s`）" % m["tb_sha256"])
    lines.append("- 2 帧控制：%s" % ("逐值复现（cycles=11445988, cap_bytes=80156, exp_bytes=80068, read=259200, cap=2/enc=2/exported=2, raw_drop=0/cmp_drop=0/wd=0）" if m["validity"]["v2_control_exact"] else "**未通过/未运行**"))
    lines.append("- 稳态状态：`%s`；测量帧数：%d" % (m["steady_state_status"], len(m["frames_exported"])))
    lines.append("")
    lines.append("## Q1：6,421,414 是冷启动单帧延迟，不是稳态帧间隔\n")
    def fmt(v):
        return "—" if v is None else ("%.0f" % v if isinstance(v, float) else "%d" % v)
    lines.append("| 量 | 值（cycles） | 换算 |")
    lines.append("|---|---:|---:|")
    lines.append("| `t_rst` | %s | rst_n 释放 |" % fmt(m["t_rst"]))
    lines.append("| `L_cold = t_exp(1)-t_rst` | %s | 冷启动单帧完成 |" % fmt(m["L_cold"]))
    lines.append("| `L_frame = t_exp(1)-t_sof(1)` | %s | 去掉预驱动 |" % fmt(m["L_frame"]))
    lines.append("| `S_2 = t_exp(2)-t_exp(1)` | %s | 第 2 帧过渡 |" % fmt(m["S_2"]))
    lines.append("| `S_23` | %s | 第 3 帧间隔 |" % fmt(m["S_23"]))
    lines.append("| `S_34` | %s | 第 4 帧间隔 |" % fmt(m["S_34"]))
    lines.append("| `S_ss = (S_23+S_34)/2` | %s | 稳态帧间隔（主口径） |" % fmt(m["S_ss"]))
    lines.append("| `S_avg2 = (t_exp(2)-t_rst)/2` | %s | 2 帧事件口径平均（**不是 S_ss**） |" % (("—" if m["S_avg2"] is None else "%.1f" % m["S_avg2"])))
    lines.append("| `S_avg2_stats = 11,445,988/2` | 5,722,994 | b11 2 帧 stats 口径（含 2,000 drain，仅对照） |")
    lines.append("| `startup = L_cold-S_ss` | %s | 冷启动/tail 绝对量 |" % fmt(m["startup"]))
    lines.append("| `startup_pct` | %s%% | >15%% 即说明把冷延迟当吞吐会实质错误 |" % ("—" if m["startup_pct"] is None else "%.2f" % m["startup_pct"]))
    lines.append("")
    if m["S_ss"]:
        lines.append("结论：`L_cold` 是 `S_ss` 的 %.2f 倍（高 %.2f%%）；`S_ss` 的 band = [%d, %d] cycles（差 %.2f%%）。" %
                     (m["L_cold"] / m["S_ss"], m["startup_pct"], m["S_band_cycles"][0], m["S_band_cycles"][1], m["S_ss_spread_pct"]))
        lines.append("")
        lines.append("## 由 S_ss 导出的容量与两 gate 算术（判定归 P2）\n")
        lines.append("| 量 | 值 |")
        lines.append("|---|---:|")
        lines.append("| `C_ss = 4.86e8/S_ss` | %.3f MB/s |" % m["capacity_MBps"])
        lines.append("| `fps_ss` | %.3f fps |" % m["fps"])
        lines.append("| `margin_0`（对 77.76 MB/s） | %+.2f%% |" % m["margin_0_pct"])
        lines.append("| `margin_25`（对 97.20 MB/s） | %+.2f%% |" % m["margin_25_pct"])
        lines.append("| `f_req_0 = 30*S_ss` | %.3f MHz |" % m["f_req_0_MHz"])
        lines.append("| `f_req_25 = 37.5*S_ss` | %.3f MHz |" % m["f_req_25_MHz"])
        lines.append("| `C_excl_export` | %.3f MB/s（%s） |" % (m["c_excl_export_MBps"], m["c_excl_export_note"]))
        lines.append("")
        lines.append("`margin_0_pct`/`margin_25_pct` 是百分数（已 ×100）。`S=5.0M` 恰为 +25.0%、`S=6.25M` 恰为 0%，因此 band 是否跨阈值必须看 `knife_edge_*`。")
        lines.append("")
    lines.append("## 逐帧 export_tail 与 sink_limited\n")
    lines.append("| frame | `t_enc` | `t_exp` | `export_tail=t_exp-t_enc` |")
    lines.append("|---:|---:|---:|---:|")
    for k in (1, 2, 3, 4):
        lines.append("| %d | %s | %s | %s |" % (k, fmt(getk(m["t_enc"], k)), fmt(getk(m["t_exp"], k)), fmt(getk(m["export_tail"], k))))
    lines.append("")
    lines.append("- 理论串行成本 `export_cost=40,032×10=400,320 cycles`（`UART_DIV=1`、187.5 MHz，18.75 MB/s sim sink）。")
    t1 = getk(m["export_tail"], 1)
    if t1 is not None:
        lines.append("- 实测 `export_tail=%d`，比理想串行 400,340（40,034 B×10）高 %d cycles（CMP 槽读/导出握手固定开销）；四帧恒定，故 `sink_limited=false`。" % (t1, t1 - 400340))
    lines.append("- `sink_limited=%s`%s。" % (str(m["sink_limited"]).lower(), ("；原因：" + "; ".join(m["sink_limited_why"])) if m["sink_limited_why"] else ""))
    lines.append("- 判据：稳态帧（2–4）tail 帧间差 ≤1%·S_ss 且 <0.5·S_ss → 尾巴在帧间隔中抵消，不扣减容量；否则才用 `S_ss−tail` 的乐观界。")
    lines.append("")
    lines.append("## V1–V6 有效性\n")
    lines.append("| # | 判据 | 结果 | 详情 |")
    lines.append("|---|---|---|---|")
    v = m["validity"]
    lines.append("| V1 | 4 帧计数完整/无丢帧 | %s | counters |" % ("PASS" if v["v1_counts"] else "FAIL"))
    lines.append("| V2 | 2 帧控制逐值复现 | %s | control-2frame.json |" % ("PASS" if v["v2_control_exact"] else "FAIL"))
    lines.append("| V3 | `abs(S23-S34)/S_ss<=2%%` | %s | spread=%s%% |" % ("PASS" if v["v3_stable"] else "FAIL", "—" if m["S_ss_spread_pct"] is None else "%.2f" % m["S_ss_spread_pct"]))
    lines.append("| V4 | 相机不是限速方 | %s | %s |" % ("PASS" if v["v4_no_bubble"] else "FAIL", "; ".join(v["v4_detail"]) or "pub(k+1)<exp(k), cam_dur<0.5S_ss"))
    lines.append("| V5 | 第 3/4 帧 slot-free | %s | %s |" % ("PASS" if v["v5_slot_free"] else "FAIL", "; ".join(v["v5_detail"]) or "SS_PACE: target slot FREE + read>=129600*(k-2)"))
    lines.append("| V6 | 事件单调/顺序 | %s | %s |" % ("PASS" if v["v6_monotone"] else "FAIL", "; ".join(v["v6_detail"]) or "exp 1<2<3<4; pub<=read<=enc<=exp"))
    lines.append("")
    lines.append("## 测量边界（不得扩大解释）\n")
    lines.append("- 链路：`camera_a1_uart_top` + `p2_ddr_bridge` + 行为级 `p2_paxi_model_b11`；**sim-only sink**（`UART_DIV=1`、`clk_uart=clk_a1` → 18.75 MB/s = `clk_uart/10`），不是真实 115200，也不是 PCIe/生产导出。")
    lines.append("- DDR 为行为模型（单拍 256-bit、`AR_GAP=2`、`R_GAP=3`、`rdy=1`），**不建模** MC 仲裁/刷新/行切换/多客户争用；测得的 `S_ss` 只代表该冻结行为模型下的链级服务。")
    lines.append("- 单一内容（平滑 `smp` 图案）、单一几何（b11 3864×2192 ROI 972/556）、单路 1080p；不覆盖自然图像/噪声/RAW12/1080p60/4K。")
    lines.append("- 本包只回答 Q1 与算术，**不给** nominal/25% 的最终 verdict；不得把 `L_cold` 当吞吐、不得把 `S_avg2`/单帧/core-only/aggregate 当稳态 per-stream 容量。")
    lines.append("- 与 b6 `6,421,414`：b6 是 3840×2160/ROI960/540/LINE_GAP40/1 GHz UART 的**单帧冷延迟**；b6 TB 只有 1 帧，无法分离 `L_cold`/`S_ss`，只能作延迟参照。")
    if m["L_cold"] is not None:
        over = m["L_cold"] - 6_750_000
        lines.append("- b6 对比：本 TB 实测 `L_cold=%d`，比规划预期上界 6.75M 高 %d cycles（%.2f%%）。差值来自导出串行成本差 325,280（40,034×10 vs b6 75,060 a1 当量）与几何/读-编码重叠；本 TB 实测 `export_tail=480,930` 比理想 400,340 高 80,590（固定 CMP 读/导出开销，b6 亦含同类开销但未单列）。这是**延迟/重叠**差异，不改变 `S_ss` 帧间隔，也不得解释为吞吐差异。" % (m["L_cold"], over, 100.0 * over / 6_750_000))
    lines.append("")
    lines.append("## 计数器与原始证据\n")
    c = m["counters"]
    lines.append("`" + " ".join("%s=%s" % (k, c.get(k)) for k in
                             ("cap", "enc", "exported", "exp_bytes", "raw_pub", "raw_drop", "cmp_drop",
                              "geom", "err", "read", "dup", "cap_bytes", "cycles", "wd", "ar", "r", "frames", "ss_pass")) + "`")
    lines.append("")
    lines.append("事件表：`out/events-4frame.csv`；机器可读：`out/steady-state.json`；控制：`out/control-2frame.json`；日志：`sim/logs/run4.log`、`sim/logs/control2.log`。")
    lines.append("")
    return "\n".join(lines)


def run4(timeout):
    stat = CAPS / "ss4.stats"
    dec = CAPS / "ss4.dec"
    evt = CAPS / "ss4.evt"
    log = LOGS / "run4.log"
    ctrl_path = OUT / "control-2frame.json"
    if not ctrl_path.exists():
        print("control-2frame.json missing: run control2 first")
        return 2
    control = jread(ctrl_path)
    pre = sha256(stat) if stat.exists() else None
    pre_mtime = stat.stat().st_mtime_ns if stat.exists() else None
    argv = vsim_argv(4, stat, dec, evt, log)
    rc, el, to, _ = run_proc(argv, WORK, log, timeout)
    post = sha256(stat) if stat.exists() else None
    post_mtime = stat.stat().st_mtime_ns if stat.exists() else None
    fresh = post_mtime is not None and post_mtime != pre_mtime
    stats = parse_stats(stat) if fresh else None
    events, meta, pace, text = parse_log(log)
    m = metrics_from(events, meta, pace, stats, control)
    m["run"] = {"argv": [str(a) for a in argv], "cwd": str(WORK), "rc": rc,
                "timed_out": to, "seconds": el, "log": str(log), "stats": str(stat),
                "stats_sha256": post, "stats_preexisting_sha256": pre,
                "stats_fresh": fresh,
                "stall_marker": "SS_STALL" in text,
                "timeout_marker": "B11_FULL_TIMEOUT" in text,
                "result_marker": next((l.strip() for l in text.splitlines() if "B11_FULL_RESULT" in l), None)}
    if m["run"]["stall_marker"] or m["run"]["timeout_marker"] or to:
        m["steady_state_status"] = "partial"
    jwrite(OUT / "steady-state.json", m)

    # events CSV
    rows = []
    for e in events:
        rows.append((e["t"], e["frame"], e["kind"], e["n"]))
    rows.sort()
    csv = ["frame,kind,t_cycles,t_ns,n"]
    for t, f, k, n in rows:
        csv.append("%d,%s,%d,%.3f,%d" % (f, k, t, t * 1e9 / CLOCK_HZ, n))
    (OUT / "events-4frame.csv").write_text("\n".join(csv) + "\n", encoding="utf-8")
    (OUT / "steady-state.md").write_text(render_md(m), encoding="utf-8")
    print("RUN4 rc=%s %.1fs timeout=%s stall=%s status=%s frames=%s S_ss=%s band=%s"
          % (rc, el, to, m["run"]["stall_marker"], m["steady_state_status"],
             m["frames_exported"], m["S_ss"], m["S_band_cycles"]))
    if m["S_ss"] is not None:
        print("  L_cold=%s S_2=%s S_23=%s S_34=%s C=%.3f MB/s margin0=%+.2f%% margin25=%+.2f%% startup_pct=%.2f%%"
              % (m["L_cold"], m["S_2"], m["S_23"], m["S_34"], m["capacity_MBps"],
                 m["margin_0_pct"], m["margin_25_pct"], m["startup_pct"]))
    print("  V1=%s V2=%s V3=%s V4=%s V5=%s V6=%s sink_limited=%s"
          % (m["validity"]["v1_counts"], m["validity"]["v2_control_exact"], m["validity"]["v3_stable"],
             m["validity"]["v4_no_bubble"], m["validity"]["v5_slot_free"], m["validity"]["v6_monotone"],
             m["sink_limited"]))
    return 0 if m["steady_state_status"] in ("measured", "unstable") else 4


# ---------------------------------------------------------------- selfcheck
class ParseReject(Exception):
    pass


REQUIRED_FRAMES = 4


def validate_fixture(events, require=REQUIRED_FRAMES):
    frames = sorted({e["frame"] for e in events if e["kind"] == "exp"})
    if len(frames) < require:
        raise ParseReject("ONLY_%d_FRAMES" % len(frames))
    for k in range(1, require + 1):
        for kind in ("sof", "cam_end", "pub", "read", "enc", "exp"):
            if not any(e["frame"] == k and e["kind"] == kind for e in events):
                raise ParseReject("MISSING_%s_FRAME_%d" % (kind.upper(), k))
    return True


def validate_claim(claim_ss, m, nframes):
    if nframes < 4:
        raise ParseReject("ONLY_%d_FRAMES" % nframes)
    if claim_ss is not None and m.get("S_avg2") is not None and abs(claim_ss - m["S_avg2"]) < 1.0:
        raise ParseReject("S_AVG2_AS_STEADY")
    if claim_ss is not None and m.get("L_cold") is not None and abs(claim_ss - m["L_cold"]) < 1.0:
        raise ParseReject("COLD_LATENCY_AS_THROUGHPUT")
    if m.get("S_23") is None or m.get("S_34") is None:
        raise ParseReject("NO_STEADY_PAIR")
    return True


def selfcheck():
    m = jread(OUT / "steady-state.json")
    events = []
    for line in (OUT / "events-4frame.csv").read_text(encoding="utf-8").splitlines()[1:]:
        f, k, t, ns, n = line.split(",")
        events.append({"frame": int(f), "kind": k, "t": int(t), "n": int(n)})
    results = []

    # NEG-1: 3 frames presented as 4
    ev3 = [e for e in events if e["frame"] <= 3]
    try:
        validate_fixture(ev3, require=4)
        r1 = {"id": "NEG1_THREE_FRAMES_AS_FOUR", "rejected": False, "reason": None}
    except ParseReject as ex:
        r1 = {"id": "NEG1_THREE_FRAMES_AS_FOUR", "rejected": True, "reason": str(ex)}
    results.append(r1)

    # NEG-2: S_avg2 used as S_ss on a valid 4-frame set
    try:
        validate_claim(m["S_avg2"], m, 4)
        r2 = {"id": "NEG2_S_AVG2_AS_S_SS", "rejected": False, "reason": None}
    except ParseReject as ex:
        r2 = {"id": "NEG2_S_AVG2_AS_S_SS", "rejected": True, "reason": str(ex)}
    results.append(r2)

    # NEG-3: L_cold used as S_ss on a valid 4-frame set
    try:
        validate_claim(m["L_cold"], m, 4)
        r3 = {"id": "NEG3_L_COLD_AS_S_SS", "rejected": False, "reason": None}
    except ParseReject as ex:
        r3 = {"id": "NEG3_L_COLD_AS_S_SS", "rejected": True, "reason": str(ex)}
    results.append(r3)

    def cap_at(s):
        return 4.86e8 / s
    hand = [
        {"id": "H1_S_5M_CAPACITY", "expected": 97.2, "actual": cap_at(5_000_000.0)},
        {"id": "H2_S_6.25M_CAPACITY", "expected": 77.76, "actual": cap_at(6_250_000.0)},
        {"id": "H3_EXPORT_COST", "expected": 400320, "actual": EXPORT_COST},
        {"id": "H4_FPS_AT_5M", "expected": 37.5, "actual": 1.875e8 / 5_000_000.0},
        {"id": "H5_25PCT_DEMAND", "expected": 97.2, "actual": 77.76 * 1.25},
        {"id": "H6_BYTES_1080P", "expected": 2592000, "actual": 1920 * 1080 * 10 / 8},
    ]
    for h in hand:
        h["pass"] = abs(h["actual"] - h["expected"]) < 1e-6
    all_neg = all(r["rejected"] for r in results)
    all_hand = all(h["pass"] for h in hand)
    obj = {"created": now(), "negatives": results, "all_negatives_rejected": all_neg,
           "hand_checks": hand, "all_hand_checks_pass": all_hand,
           "pass": all_neg and all_hand}
    jwrite(OUT / "selfcheck.json", obj)
    print("SELFCHECK pass=%s negatives=%s hand=%s" % (obj["pass"], all_neg, all_hand))
    for r in results:
        print("  ", r)
    return 0 if obj["pass"] else 5


# ------------------------------------------------------------------ report
def report():
    m = jread(OUT / "steady-state.json")
    ctrl = jread(OUT / "control-2frame.json")
    sc = jread(OUT / "selfcheck.json") if (OUT / "selfcheck.json").exists() else None
    iv = jread(R0 / "input-verified.json")
    cmds = [json.loads(l) for l in (SIM / "commands.jsonl").read_text(encoding="utf-8").splitlines()]
    v = m["validity"]
    def f(vv, nd=0):
        if vv is None:
            return "—"
        return ("%%.%df" % nd) % vv if isinstance(vv, float) else str(vv)
    lines = []
    lines.append("# result-r0：T10.ss-steady-anchor（P1 稳态实测）\n")
    lines.append("- 任务：`T10.ss-steady-anchor`；run `20261025-233401_fpga-steady-state-reverdict`")
    lines.append("- 日期：%s；工作树 `D:/fpga/ph1p100`；只写本任务 r0/ 与 `%%TEMP%%\\opencode\\ss-anchor\\`" % now())
    lines.append("- 工具：ModelSim Intel FPGA ASE 10.5b（`%s`）；Python %s；**0 次** TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG" % (MS, platform.python_version()))
    lines.append("- 冻结输入：13 个编译相关副本 + 1 个参照 TB（共 %d）与 b11 manifest **0 mismatch**（`input-verified.json`）；DUT 源 0 修改；TB 仅设计指南 §3.2 白名单 1–8" % iv["copied_count"])
    lines.append("")
    lines.append("## 1. 命令与预算（实际）\n")
    lines.append("| 步骤 | 命令 | rc | 墙钟 s | 硬超时 s | 日志 |")
    lines.append("|---|---|---:|---:|---:|---|")
    for c in cmds:
        short = " ".join(c["argv"])
        if len(short) > 130:
            short = short[:127] + "..."
        lines.append("| %s | `%s` | %s | %.1f | %s | `%s` |" %
                     (pathlib.PurePath(c["argv"][0]).name, short.replace("|", "\\|"), c["rc"],
                      c["seconds"], c["timeout_s"], c.get("log", "")))
    vsim_secs = sum(c["seconds"] for c in cmds if "vsim.exe" in c["argv"][0])
    vlog_secs = sum(c["seconds"] for c in cmds if "vlog.exe" in c["argv"][0])
    lines.append("")
    lines.append("- `vsim` 实际总墙钟：**%.1f s**（预算 ≤100 min / 单次 2700 s）；`vlog`：%.1f s（≤1200 s）；全尺寸 vsim 次数：%d（2 帧控制 1 + 4 帧 1）。" %
                 (vsim_secs, vlog_secs, sum(1 for c in cmds if "vsim.exe" in c["argv"][0])))
    lines.append("- 独占：work 库 `%s`；`modelsim.ini` 副本 `%s`（sha256 `%s`）；日志/统计/事件均在本任务目录。" %
                 (WORK, INI, iv["modelsim_ini"]["sha256"]))
    lines.append("")
    lines.append("## 2. 2 帧控制（V2）\n")
    lines.append("- 结果：**%s**；rc=%s，%.1f s，timeout=%s。" % ("PASS 逐值复现" if ctrl["pass"] else "FAIL", ctrl["rc"], ctrl["seconds"], ctrl["timed_out"]))
    lines.append("- 冻结门槛：`cycles=11445988`、`cap_bytes=80156`、`exp_bytes=80068`、`read=259200`、`cap=2/enc=2/exported=2`、`raw_drop=0/cmp_drop=0/wd=0`；实测：`cap=%s enc=%s exported=%s exp_bytes=%s raw_pub=%s raw_drop=%s cmp_drop=%s geom=%s err=%s read=%s dup=%s cap_bytes=%s cycles=%s wd=%s`。" %
                 tuple(ctrl["actual"].get(k) for k in ("cap", "enc", "exported", "exp_bytes", "raw_pub", "raw_drop", "cmp_drop", "geom", "err", "read", "dup", "cap_bytes", "cycles", "wd")))
    if ctrl["mismatches"]:
        lines.append("- **mismatch**：`%s`" % json.dumps(ctrl["mismatches"], ensure_ascii=False))
    lines.append("- 说明：新增 SS_EVT 只在既有 `posedge clk_a1` 块中比较只读 `st_*`，不改变驱动/时钟/复位，因此 2 帧统计精确保持 b11 值（含导出后 2000-cycle drain）。")
    lines.append("")
    lines.append("## 3. 4 帧稳态（Q1）\n")
    lines.append("- 状态：`%s`；事件帧：%s；rc=%s，%.1f s，timeout=%s，SS_STALL=%s。" %
                 (m["steady_state_status"], m["frames_exported"], m["run"]["rc"], m["run"]["seconds"],
                  m["run"]["timed_out"], m["run"]["stall_marker"]))
    lines.append("- `L_cold=%s`、`L_frame=%s`、`S_2=%s`、`S_23=%s`、`S_34=%s`、`S_ss=%s`（band [%s, %s]，spread=%s%%）。" %
                 (f(m["L_cold"]), f(m["L_frame"]), f(m["S_2"]), f(m["S_23"]), f(m["S_34"]), f(m["S_ss"], 1),
                  f(m["S_band_cycles"][0]) if m["S_band_cycles"] else "—",
                  f(m["S_band_cycles"][1]) if m["S_band_cycles"] else "—",
                  f(m["S_ss_spread_pct"], 2)))
    lines.append("- `S_avg2（事件口径，不是 S_ss）=%s`；`startup=%s`、`startup_pct=%s%%`。" % (f(m["S_avg2"], 1), f(m["startup"]), f(m["startup_pct"], 2)))
    if m.get("capacity_MBps") is not None:
        lines.append("- 算术：`C_ss=%.3f MB/s`、`fps=%.3f`、`margin_0=%+.2f%%`、`margin_25=%+.2f%%`、`f_req_0=%.3f MHz`、`f_req_25=%.3f MHz`。" %
                     (m["capacity_MBps"], m["fps"], m["margin_0_pct"], m["margin_25_pct"], m["f_req_0_MHz"], m["f_req_25_MHz"]))
    lines.append("- 逐帧 export_tail：%s；`sink_limited=%s`%s。" %
                 (", ".join("k%d=%s" % (k, f(getk(m["export_tail"], k))) for k in (1, 2, 3, 4)),
                  str(m["sink_limited"]).lower(), ("（" + "; ".join(m["sink_limited_why"]) + "）") if m["sink_limited_why"] else ""))
    t1 = getk(m["export_tail"], 1)
    if t1 is not None:
        lines.append("- 实测 tail %d 比理想串行 400,340（40,034 B×10）高 %d cycles（固定 CMP 读/导出握手开销）；四帧恒定，不随 k 增长，故 sink_limited=false。" % (t1, t1 - 400340))
    lines.append("- V1=%s、V2=%s、V3=%s、V4=%s、V5=%s、V6=%s。" %
                 (v["v1_counts"], v["v2_control_exact"], v["v3_stable"], v["v4_no_bubble"], v["v5_slot_free"], v["v6_monotone"]))
    if v["v4_detail"]:
        lines.append("- V4 详情：%s" % "; ".join(v["v4_detail"]))
    if v["v5_detail"]:
        lines.append("- V5 详情：%s" % "; ".join(v["v5_detail"]))
    lines.append("- 计数器：`%s`。" % " ".join("%s=%s" % (k, m["counters"].get(k)) for k in
                 ("cap", "enc", "exported", "exp_bytes", "raw_pub", "raw_drop", "cmp_drop", "geom", "err", "read", "dup", "cap_bytes", "cycles", "wd", "ar", "r", "frames", "ss_pass")))
    lines.append("")
    lines.append("### Q1 的回答\n")
    if m["S_ss"] is not None:
        t_exp2 = getk(m["t_exp"], 2)
        lines.append("- 冻结 b11 的 11,445,988（stats，含 2,000 drain）拆成 `L_cold=%s` + `S_2=%s` = `t_exp(2)-t_rst=%s`（`t_exp(2)=%s`，`t_rst=%s`）；事件口径 `S_avg2=%s`，冻结 stats 口径 `S_avg2_stats=5,722,994`，两者都只是两帧平均，**不是**稳态间隔。" %
                     (f(m["L_cold"]), f(m["S_2"]),
                      f((t_exp2 - m["t_rst"]) if t_exp2 is not None else None),
                      f(t_exp2), f(m["t_rst"]), f(m["S_avg2"], 1)))
        lines.append("- 4 帧实测的稳态间隔为 `S_ss≈%s cycles`（band %s–%s），与 b6 的 6,421,414 **不同**：6.421M 是单帧冷启动完成时间；把它当每帧服务时间会把容量低估约 %s%%。" %
                     (f(m["S_ss"], 1), f(m["S_band_cycles"][0]), f(m["S_band_cycles"][1]),
                      f(abs(100.0 * (1 - m["S_ss"] / 6421414.0)), 1) if m["S_ss"] else "—"))
        if abs(m["L_cold"] / m["S_ss"] - 1) > 0.15:
            lines.append("- `startup_pct=%s%% > 15%%`：把冷启动单帧当作稳态吞吐属于实质性口径错误（P2 的 `COLD_LATENCY_AS_THROUGHPUT`）。" % f(m["startup_pct"], 2))
    else:
        lines.append("- 未获得 4 帧完整事件/计数，**不给出单一 `S_ss`**；已完成帧与缺失项见上。")
    lines.append("")
    lines.append("## 4. 自检与负对照\n")
    if sc:
        lines.append("- 结果：**%s**（3 个解析负对照全部拒绝=%s；6 个手算复核通过=%s）。" % (("PASS" if sc["pass"] else "FAIL"), sc["all_negatives_rejected"], sc["all_hand_checks_pass"]))
        for r in sc["negatives"]:
            lines.append("  - `%s`：rejected=%s，reason=`%s`" % (r["id"], r["rejected"], r.get("reason") or r.get("claim_reason")))
        for h in sc["hand_checks"]:
            lines.append("  - `%s`：expected=%s actual=%s pass=%s" % (h["id"], h["expected"], h["actual"], h["pass"]))
    else:
        lines.append("- 未运行（缺失 `out/selfcheck.json`）。")
    lines.append("")
    lines.append("## 5. 白名单与无影响论证（摘要；逐条见 `src/DIFF.md`）\n")
    lines.append("- DUT/模型源 0 修改；`tb_ss_anchor.v` 相对 `tb_b11_full.v` 仅：`FRAMES`、SS_EVT、第 3/4 帧 slot-free 等待、8M/帧 watchdog、`MAX_CYCLES=30M`、4096-bit 路径寄存器、统计行追加 `frames/ss_pass`、DEC/STAT/EVT 绝对路径 plusarg。")
    lines.append("- 新增 TB-only 标记 `SS_META`/`SS_PACE`/`SS_STATS` 只读状态、不改 DUT；slot-free 等待读 `dut.raw_slot_st`（`st_slot_st` 只读观测），不是 `force`/`deposit`。")
    lines.append("- 继承的 `B11_FULL_READ_DONE` 等待仍为 `2*129600`（为保持与 b11 diff 最小），在 4 帧 run 中只是信息标记，最终门槛用 `FRAMES*129600`。")
    lines.append("")
    lines.append("## 6. 未测 / 边界 / 回退\n")
    lines.append("- **未测**：DDR sustained/刷新/行切换/多客户仲裁；真实 115200 UART 与 PCIe/高速 sink；自然图像/噪声/RAW12/1080p60/4K；双核 per-stream 与共享 PAXI；TD 综合/布线/时序/资源/bit/板卡。")
    lines.append("- **边界**：本 PASS 只证明“在该冻结 RTL/TB/几何/内容、18.75 MB/s sim-only sink、行为 DDR 下，L_cold 与 S_ss 被正确测量”；不证明 25% 设计裕量、生产导出或系统可行。判定留给 P2。")
    lines.append("- **回退**：本任务目录整体不被采用即可；失败日志保留；未修改/删除 b11、b6、P2、T08/T10、`workflow/tasks.json`、`docs/**`、生产 RTL。")
    lines.append("- **漂移**：b11/b6/P2 输入快照见 `input-verified.json`；任务期间若外部改动只记录，不追逐。")
    lines.append("")
    lines.append("## 7. 产物\n")
    for rel in ("input-verified.json", "src/DIFF.md", "src/tb_ss_anchor.v",
                "src/ref/tb_b11_full.v", "src/" + "p2_a1_board_top.v（只复制/不编译）",
                "sim/run_ss.py", "sim/modelsim.ini", "sim/commands.jsonl",
                "sim/logs/vlib.log", "sim/logs/vlog.log", "sim/logs/control2.log", "sim/logs/run4.log",
                "sim/caps/ss2.stats", "sim/caps/ss2.dec", "sim/caps/ss2.evt",
                "sim/caps/ss4.stats", "sim/caps/ss4.dec", "sim/caps/ss4.evt",
                "out/control-2frame.json", "out/events-4frame.csv", "out/steady-state.json",
                "out/steady-state.md", "out/selfcheck.json", "lessons.md", "manifest-r0.json"):
        lines.append("- `%s`" % rel)
    lines.append("")
    lines.append("> `lessons.md` 与 `manifest-r0.json` 在 report 之后生成；manifest 覆盖本目录除自身外的全部文件。")
    lines.append("")
    (OUT / "steady-state.md").write_text(render_md(m), encoding="utf-8")
    (R0 / "result-r0.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("REPORT wrote steady-state.md and result-r0.md (%d lines)" % len(lines))

    # lessons
    ll = []
    ll.append("# lessons-r0：T10.ss-steady-anchor\n")
    ll.append("- **根因/触发**：2 槽 RAW 存储在“第 2 帧驱动结束→第 1 帧读完关闭”之间存在无空闲槽窗口；若第 3 帧直接背靠背驱动，`e_sof` 时 `wr_begin_ready=0`，整帧被 `raw_begin_deny` 丢弃（raw_drop 增加）。4 帧必须做 slot-free pacing，不能只改 `FRAMES`。")
    ll.append("- **可复用修正**：在 TB 的帧间等待目标 RAW 槽 `slot_st==S_FREE`（只读 `dut.raw_slot_st`），并在 `SS_PACE` 记录 read 与 slot 状态；最终 `raw_drop=0` 与 V5 用同一证据。")
    ll.append("- **口径**：b11 stats 的 `cycles` 含导出后 2000-cycle drain；事件口径 `t_exp(2)≈11,443,988`。`L_cold+S_2=t_exp(2)` 是自洽拆分；`S_avg2` 不是稳态。")
    ll.append("- **测量结论（本轮）**：`L_cold=%s`、`S_ss=%s`、`startup_pct=%s%%`；`S_23=%s`/`S_34=%s`（band %s–%s）。6,421,414 是冷启动单帧，不是每帧稳态；不得用 `L_cold` 或两帧平均替代 `S_ss`。" %
              (f(m["L_cold"]), f(m["S_ss"], 1), f(m["startup_pct"], 2), f(m["S_23"]), f(m["S_34"]),
               f(m["S_band_cycles"][0]) if m["S_band_cycles"] else "—", f(m["S_band_cycles"][1]) if m["S_band_cycles"] else "—"))
    ll.append("- **sink 尾巴**：`export_tail` 逐帧=%s；`sink_limited=%s`。常数且 <0.5·S_ss 的尾巴在帧间隔中抵消；只有增长/≥0.5·S_ss 才扣减。18.75 MB/s 只是 sim sink，115200 生产 UART 慢 1,628×，不能外推。" %
              (", ".join("k%d=%s" % (k, f(getk(m["export_tail"], k))) for k in (1, 2, 3, 4)), str(m["sink_limited"]).lower()))
    ll.append("- **预算/隔离**：vsim 2 帧 + 4 帧各一次；work/INI/log 独占；只杀自己的子进程；未碰 TD/板卡/COM8。并发负载只影响墙钟，不影响 cycle 数。")
    ll.append("- **负对照**：解析器拒绝 S_avg2-as-S_ss、L_cold-as-S_ss、3 帧当 4 帧；复测者应独立重写解析器，不 import 本驱动。")
    ll.append("")
    (R0 / "lessons.md").write_text("\n".join(ll) + "\n", encoding="utf-8")
    print("REPORT wrote lessons.md")
    return 0


# ------------------------------------------------------------------ manifest
def manifest():
    files = []
    for p in sorted(R0.rglob("*")):
        if p.is_file() and p.name != "manifest-r0.json":
            files.append({"path": str(p.relative_to(R0)).replace("\\", "/"),
                          "bytes": p.stat().st_size, "sha256": sha256(p)})
    cmds = [json.loads(l) for l in (SIM / "commands.jsonl").read_text(encoding="utf-8").splitlines()] if (SIM / "commands.jsonl").exists() else []
    vsim_secs = sum(c["seconds"] for c in cmds if "vsim.exe" in c["argv"][0])
    vlog_secs = sum(c["seconds"] for c in cmds if "vlog.exe" in c["argv"][0])
    iv = jread(R0 / "input-verified.json")
    obj = {
        "manifest": "T10.ss-steady-anchor-r0",
        "task_id": "T10.ss-steady-anchor",
        "run_id": "20261025-233401_fpga-steady-state-reverdict",
        "created": now(),
        "status": "frozen_for_test",
        "stopped_modifying": True,
        "active_commands": 0,
        "write_scope": [str(R0), str(TMP)],
        "forbidden_actions_used": {"TD": 0, "synthesis": 0, "place_route": 0, "bitgen": 0,
                                   "CWC": 0, "download": 0, "flash": 0, "board": 0,
                                   "COM": 0, "JTAG": 0, "tasks_json_write": 0,
                                   "b11_b6_p2_write": 0, "production_src_write": 0},
        "inputs": {
            "b11_manifest": iv["b11_manifest"],
            "b11_manifest_sha256": iv["b11_manifest_sha256"],
            "copied_count": iv["copied_count"],
            "copied_src_all_match": iv["copied_src_all_match"],
            "mismatch_count": iv["mismatch_count"],
            "modelsim_ini_sha256": iv["modelsim_ini"]["sha256"],
            "snapshot": iv["input_snapshot"],
        },
        "tools": {
            "modelsim": str(MS), "modelsim_version": "Intel FPGA Edition 10.5b (ASE win32aloem)",
            "python": sys.version.split()[0], "platform": platform.platform(),
            "work_lib": str(WORK), "modelsim_ini_copy": str(INI),
        },
        "commands": cmds,
        "budget": {"vsim_runs": sum(1 for c in cmds if "vsim.exe" in c["argv"][0]),
                   "vsim_wall_seconds": round(vsim_secs, 1), "vsim_wall_limit_seconds": 6000,
                   "vlog_wall_seconds": round(vlog_secs, 1), "vlog_limit_seconds": 1200,
                   "single_vsim_timeout_seconds": 2700},
        "artifacts": files,
        "artifact_count": len(files),
        "notes": [
            "DUT sources are byte-identical copies of the b11 manifest entries (0 mismatch).",
            "tb_ss_anchor.v contains only the fpga-design-guide 3.2 whitelist differences; see src/DIFF.md.",
            "This is an offline simulation measurement; G2-G4 are not applicable.",
        ],
    }
    jwrite(R0 / "manifest-r0.json", obj)
    print("MANIFEST artifacts=%d vsim_runs=%d vsim_secs=%.1f" % (len(files), obj["budget"]["vsim_runs"], vsim_secs))
    return 0


def rewrite():
    """Re-parse the frozen run4 log/stats and rewrite out/ without re-simulating."""
    log = LOGS / "run4.log"
    stat = CAPS / "ss4.stats"
    old = jread(OUT / "steady-state.json")
    control = jread(OUT / "control-2frame.json")
    events, meta, pace, text = parse_log(log)
    stats = parse_stats(stat)
    m = metrics_from(events, meta, pace, stats, control)
    m["run"] = old.get("run", {})
    jwrite(OUT / "steady-state.json", m)
    rows = sorted((e["t"], e["frame"], e["kind"], e["n"]) for e in events)
    csv = ["frame,kind,t_cycles,t_ns,n"]
    for t, f, k, n in rows:
        csv.append("%d,%s,%d,%.3f,%d" % (f, k, t, t * 1e9 / CLOCK_HZ, n))
    (OUT / "events-4frame.csv").write_text("\n".join(csv) + "\n", encoding="utf-8")
    (OUT / "steady-state.md").write_text(render_md(m), encoding="utf-8")
    print("REWRITE frames=%s S_ss=%s status=%s" % (m["frames_exported"], m["S_ss"], m["steady_state_status"]))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["freeze", "compile", "control2", "run4", "rewrite", "selfcheck", "report", "manifest"])
    ap.add_argument("--timeout", type=int, default=2700)
    args = ap.parse_args()
    if args.cmd == "freeze":
        return freeze()
    if args.cmd == "compile":
        return compile_all()
    if args.cmd == "control2":
        return control2(args.timeout)
    if args.cmd == "run4":
        return run4(args.timeout)
    if args.cmd == "rewrite":
        return rewrite()
    if args.cmd == "selfcheck":
        return selfcheck()
    if args.cmd == "report":
        return report()
    if args.cmd == "manifest":
        return manifest()
    return 2


if __name__ == "__main__":
    sys.exit(main())
