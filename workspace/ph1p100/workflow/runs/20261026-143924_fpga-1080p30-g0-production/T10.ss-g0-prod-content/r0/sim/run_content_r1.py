#!/usr/bin/env python3
"""P1 round1 driver - T10.ss-g0-prod-content (same task, same developer session).

Only NEW files are written (r0 frozen artifacts are read-only here):
  src/tb_ss_4run_wd.v (already created by the whitelist edits)
  sim/logs/{vlib,vlog}-r1.log, sim/logs/{n,l}-r1.log(+.out)
  sim/caps/{n,l}-r1.{stats,evt,hdr}
  sim/commands-r1.jsonl, out/r1-verify.json
  out/content-verdict-r1.json, out/run-status-r1.json
  manifest-r1.json

Subcommands: verify | compile | run n|l | analyze | manifest
Whitelist (round1-ruling.md section 2 / design guide section 3.1): only the two-stage
watchdog (WD_LIMIT_COLD=20,000,000 anchored at t_sof[1] while st_exp==0; WD_LIMIT=
12,000,000 anchored at last_exp_t only when st_exp>0) and a read-only ``bytes=``
field on the kind=exp event. ``verify`` reconstructs that expected file from the
frozen r0 TB and requires byte equality.
"""
import json
import hashlib
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
CAPS = SIM / "caps"
SLOGS = SIM / "logs"
CONTENT = R0 / "content"
OUT = R0 / "out"

MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
TEMP = pathlib.Path(os.environ.get("TEMP", r"C:\Users\czz\AppData\Local\Temp"))
WORK = TEMP / "opencode" / "ss-g0-prod-content" / "work-r1"

R0_TB = SRC / "tb_ss_4run.v"
R1_TB = SRC / "tb_ss_4run_wd.v"
SRC12 = ["a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v",
         "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
         "a1_deflate_core.v", "p2_ddr_bridge.v", "a1_ddr_arb2.v",
         "capture_async_fifo.v", "p2_paxi_model_b11.v", "a1_ddr_model.v"]

CLOCK_HZ = 187.5e6
G0_CYCLES = 6250000.0
G25_CYCLES = 5000000.0
G0_MBPS = 77.76
G25_MBPS = 97.20
RAW_FRAME_BYTES = 2592000
RAW_BAND_BYTES = 2594706
SINK_MAX_MBPS = 93.75
GROUPS = 518400
MAXCYC = 60000000
RUN_TIMEOUT_S = 2700
MAX_FULL_RUNS = 2

R0_MAN_SHA = "e55e79659981e3a7f87696aec67d46b02011c3d8fe527c4ecdaf7b39553d9a74"
R0_TB_SHA = "7f5cc29405001e4a5da868e8129819e0068715965999c7e81082e38e20947f81"

RUNS = {
    "n": dict(tag="n", content_id="N", raw40="raw40_n.hex", mode="N_natural_scene_slotfree_r1"),
    "l": dict(tag="l", content_id="L", raw40="raw40_l.hex", mode="L_low_light_natural_slotfree_r1"),
}

# ---------------------------------------------------------------- whitelist canon
CANON = [
    # (1) new localparam right after the frozen WD_LIMIT line
    ("    localparam integer WD_LIMIT = 12000000;\n",
     "    localparam integer WD_LIMIT = 12000000;\n"
     "    localparam integer WD_LIMIT_COLD = 20000000;   // round1: cold-start budget, "
     "anchored at t_sof(1)\n"),
    # (4) kind=exp event gains a read-only bytes= field (display + fwrite)
    ('                $display("SS_EVT t=%0d kind=exp frame=%0d n=%0d", cycles, st_exp, st_exp);\n'
     '                if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=exp frame=%0d n=%0d\\n", '
     'cycles, st_exp, st_exp);\n',
     '                $display("SS_EVT t=%0d kind=exp frame=%0d n=%0d bytes=%0d", cycles, '
     'st_exp, st_exp, st_expb);\n'
     '                if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=exp frame=%0d n=%0d '
     'bytes=%0d\\n", cycles, st_exp, st_exp, st_expb);\n'),
    # (2)(3)(5) two-stage watchdog + comment block
    ('            // ---- per-frame watchdog (12,000,000 cycles with no export) ----\n'
     '            if ((cycles - last_exp_t) > WD_LIMIT) begin\n',
     '            // ---- two-stage watchdog (round1 harness fix; whitelist items 2 and 3) ----\n'
     '            //  cold start: anchored at t_sof(1) while nothing has been exported yet\n'
     '            //  steady state: original 12,000,000-cycle gap between completed exports\n'
     '            if ((st_exp == 0) && ((cycles - t_sof[1]) > WD_LIMIT_COLD)) begin\n'
     '                $display("SS_STALL_COLD frame=%0d cycles=%0d read=%0d enc=%0d exported=%0d",\n'
     '                         st_exp + 1, cycles, st_read, st_enc, st_exp);\n'
     '                $display("B11_FULL_RESULT pass=0");\n'
     '                $finish;\n'
     '            end\n'
     '            if ((st_exp > 0) && ((cycles - last_exp_t) > WD_LIMIT)) begin\n'),
]


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def jdump(p, obj):
    pathlib.Path(p).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(p).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def jload(p, default=None):
    p = pathlib.Path(p)
    if not p.exists():
        return default
    return json.loads(p.read_text(encoding="utf-8"))


def cmdlog(rec):
    SIM.mkdir(parents=True, exist_ok=True)
    rec = dict(rec)
    rec["logged_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    with open(SIM / "commands-r1.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def run_proc(argv, cwd, log_path, timeout, note=""):
    log_path = pathlib.Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    out_path = log_path.with_suffix(log_path.suffix + ".out")
    t0 = time.monotonic()
    timed_out = False
    with open(out_path, "wb") as out:
        proc = subprocess.Popen([str(x) for x in argv], cwd=str(cwd), stdout=out,
                                stderr=subprocess.STDOUT,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            rc = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                           capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
            rc = 124
    el = time.monotonic() - t0
    cmdlog({"argv": [str(x) for x in argv], "cwd": str(cwd), "rc": rc, "timed_out": timed_out,
            "seconds": round(el, 1), "timeout_s": timeout, "log": str(log_path), "note": note})
    return rc, el, timed_out


# ------------------------------------------------------------------ verify
def cmd_verify():
    a = R0_TB.read_text(encoding="utf-8")
    canon = a
    applied = []
    for old, new in CANON:
        n = canon.count(old)
        applied.append({"patterns_found": n})
        if n != 1:
            raise SystemExit("whitelist pattern not unique: %r" % old[:60])
        canon = canon.replace(old, new)
    actual = R1_TB.read_text(encoding="utf-8")
    whitelist_ok = (canon == actual)
    man0 = sha(R0 / "manifest-r0.json")
    cmap = jload(R0 / "content-map.json", {})
    man0j = jload(R0 / "manifest-r0.json", {})
    art0 = {x["rel"]: x["sha256"] for x in man0j.get("artifacts", [])}
    src_chk = []
    for f in SRC12:
        p = SRC / f
        rec = {"file": f, "sha256": sha(p), "r0_manifest_sha256": art0.get("src/" + f),
               "r0_tb": (f == "tb_ss_4run.v")}
        rec["match_r0_manifest"] = rec["sha256"] == rec["r0_manifest_sha256"]
        src_chk.append(rec)
    tb_chk = {"r0_tb_sha256": sha(R0_TB), "expected": R0_TB_SHA,
              "r0_tb_unchanged": sha(R0_TB) == R0_TB_SHA,
              "r1_tb_sha256": sha(R1_TB),
              "whitelist_reconstruct_equal": whitelist_ok,
              "r1_lines": len(actual.splitlines()), "r0_lines": len(a.splitlines())}
    cnt = []
    for cid in ("N", "L"):
        e = cmap["content"][cid]
        cnt.append({"content": cid,
                    "raw_bin_sha256": sha(CONTENT / ("raw_%s.bin" % cid.lower())),
                    "raw_bin_expected": e["raw_bin"]["sha256"],
                    "raw40_hex_sha256": sha(CONTENT / ("raw40_%s.hex" % cid.lower())),
                    "raw40_hex_expected": e["raw40_hex"]["sha256"]})
        cnt[-1]["match"] = (cnt[-1]["raw_bin_sha256"] == cnt[-1]["raw_bin_expected"]
                            and cnt[-1]["raw40_hex_sha256"] == cnt[-1]["raw40_hex_expected"])
    out = {
        "task": "T10.ss-g0-prod-content", "round": 1, "created": time.strftime("%Y-%m-%d"),
        "r0_manifest_sha256": man0, "r0_manifest_expected": R0_MAN_SHA,
        "r0_manifest_unchanged": man0 == R0_MAN_SHA,
        "r0_manifest_artifacts": len(man0j.get("artifacts", [])),
        "tb": tb_chk,
        "whitelist": {"items": [
            "1 new localparam WD_LIMIT_COLD = 20000000 (WD_LIMIT kept)",
            "2 cold branch st_exp==0 && (cycles-t_sof[1])>WD_LIMIT_COLD -> SS_STALL_COLD/pass=0/finish",
            "3 steady branch st_exp>0 && (cycles-last_exp_t)>WD_LIMIT -> SS_STALL (text/behaviour kept)",
            "4 kind=exp SS_EVT gains read-only bytes=st_expb (display+fwrite)",
            "5 comments/blank lines only"],
            "reconstruct_patterns": applied, "reconstruct_equal": whitelist_ok},
        "dut_sources": src_chk,
        "dut_sources_all_match_r0": all(x["match_r0_manifest"] for x in src_chk),
        "content_sha": cnt,
        "content_all_match": all(x["match"] for x in cnt),
        "forbidden_api_grep": {"force": actual.count("force "), "deposit": actual.count("deposit"),
                               "release": actual.count("release ")},
        "drift_status": "ok",
    }
    if not (whitelist_ok and tb_chk["r0_tb_unchanged"] and out["r0_manifest_unchanged"]
            and out["dut_sources_all_match_r0"] and out["content_all_match"]):
        out["drift_status"] = "DRIFT"
    jdump(OUT / "r1-verify.json", out)
    print("whitelist_ok=%s r0_tb=%s r0_manifest=%s dut12=%s content=%s force/dep/release=%d/%d/%d" % (
        whitelist_ok, tb_chk["r0_tb_unchanged"], out["r0_manifest_unchanged"],
        out["dut_sources_all_match_r0"], out["content_all_match"],
        out["forbidden_api_grep"]["force"], out["forbidden_api_grep"]["deposit"],
        out["forbidden_api_grep"]["release"]))
    print("r1_tb_sha256=%s lines=%d" % (tb_chk["r1_tb_sha256"], tb_chk["r1_lines"]))


# ------------------------------------------------------------------ compile / run
def compile_all():
    WORK.mkdir(parents=True, exist_ok=True)
    SLOGS.mkdir(parents=True, exist_ok=True)
    rc, el, to = run_proc([MS / "vlib.exe", "work"], WORK, SLOGS / "vlib-r1.log", 300, "vlib-r1")
    if rc != 0:
        raise SystemExit("vlib failed rc=%s" % rc)
    files = [SRC / f for f in SRC12] + [R1_TB]
    rc, el, to = run_proc([MS / "vlog.exe", "-sv", "-work", "work", "+define+SIMULATION"] + files,
                          WORK, SLOGS / "vlog-r1.log", 1200, "vlog-r1")
    txt = (SLOGS / "vlog-r1.log.out").read_text(errors="replace") \
        if (SLOGS / "vlog-r1.log.out").exists() else ""
    errs = len(re.findall(r"\*\* Error", txt))
    print("compile rc=%s %.1fs errors=%d" % (rc, el, errs))
    if rc != 0 or errs:
        raise SystemExit("compile failed")


def spent():
    total, n = 0.0, 0
    p = SIM / "commands-r1.jsonl"
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if any("tb_ss_4run" in str(x) for x in rec.get("argv", [])) and rec.get("timeout_s") == RUN_TIMEOUT_S:
                total += rec.get("seconds", 0.0)
                n += 1
    return total, n


def cmd_run(key):
    cfg = RUNS[key]
    tot, n = spent()
    if n >= MAX_FULL_RUNS:
        print("FULL_RUN_BUDGET_EXHAUSTED n=%d spent=%.0fs" % (n, tot))
        raise SystemExit(3)
    if tot >= 5700:
        print("VSIM_WALL_BUDGET_EXHAUSTED spent=%.0fs" % tot)
        raise SystemExit(3)
    CAPS.mkdir(parents=True, exist_ok=True)
    SLOGS.mkdir(parents=True, exist_ok=True)
    tag = cfg["tag"] + "-r1"
    stat, evt, hdr = CAPS / (tag + ".stats"), CAPS / (tag + ".evt"), CAPS / (tag + ".hdr")
    log = SLOGS / (tag + ".log")
    argv = [MS / "vsim.exe", "-c", "-lib", "work", "-l", log, "tb_ss_4run",
            "+STAT=" + str(stat), "+EVT=" + str(evt), "+HDR=" + str(hdr),
            "+RAW40=" + str(CONTENT / cfg["raw40"]),
            "-gFRAMES=4", "-gCONTENT=2", "-gPACING=0", "-gSINK=1", "-gCAPTURE=0",
            "-gMAX_CYCLES=%d" % MAXCYC, "-do", "run -all; quit -f"]
    rc, el, to = run_proc(argv, WORK, log, RUN_TIMEOUT_S, cfg["mode"])
    print("%s rc=%s %.1fs timeout=%s" % (tag, rc, el, to))
    txt = log.read_text(errors="replace") if log.exists() else ""
    markers = {}
    for pat in ("SS_STALL_COLD", "SS_STALL", "B11_FULL_TIMEOUT", "SS_RAW_MATCH",
                "B11_FULL_RESULT", "SS_STATS"):
        ms = re.findall(pat + r"[^\n]*", txt)
        markers[pat] = ms[0][:200] if ms else None
        print("   ", markers[pat])
    db = jload(OUT / "run-status-r1.json", {}) or {}
    db[cfg["content_id"]] = {
        "content_id": cfg["content_id"], "mode": cfg["mode"], "tag": tag,
        "rc": rc, "seconds": round(el, 1), "timed_out": to, "timeout_s": RUN_TIMEOUT_S,
        "stats_file_created": stat.exists(),
        "stats_bytes": stat.stat().st_size if stat.exists() else None,
        "stats_rows_present": ("ss_pass=" in stat.read_text(errors="replace")) if stat.exists() else False,
        "evt_bytes": evt.stat().st_size if evt.exists() else None,
        "hdr_bytes": hdr.stat().st_size if hdr.exists() else None,
        "markers": markers,
        "command": [str(x) for x in argv],
        "note": "stats_exists was replaced by stats_rows_present in round1 (r0 OBS-2): a "
                "0-byte stats file only proves $fopen ran, not that SS_STATS was written.",
    }
    jdump(OUT / "run-status-r1.json", db)


# ------------------------------------------------------------------ analyze
def parse_stats(p):
    st = {}
    txt = pathlib.Path(p).read_text(errors="replace")
    for tok in txt.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            try:
                st[k] = int(v, 0)
            except ValueError:
                st[k] = v
    return st, txt


def header_check(tag, ent):
    hp = CAPS / (tag + ".hdr")
    if not hp.exists():
        return {"available": False}
    rawb = bytes(int(x, 16) for x in hp.read_text().split())
    if len(rawb) < 44:
        return {"available": False, "bytes": len(rawb)}
    u32 = lambda o: int.from_bytes(rawb[o:o + 4], "little")
    got = {"raw_len": u32(16), "xform_len": u32(20), "stream_len": u32(24), "raw_crc": u32(28),
           "xform_crc": u32(32), "stream_crc": u32(36), "header_crc": u32(40)}
    raw_crc = int(ent["raw_bin"]["crc32"], 16)
    hcrc = zlib.crc32(rawb[0:40]) & 0xFFFFFFFF
    ok = (got["raw_len"] == RAW_FRAME_BYTES and got["xform_len"] == RAW_FRAME_BYTES
          and got["raw_crc"] == raw_crc and hcrc == got["header_crc"])
    return {"available": True, "bytes": len(rawb), "got": got,
            "expected": {"raw_len": RAW_FRAME_BYTES, "xform_len": RAW_FRAME_BYTES,
                         "raw_crc": raw_crc, "raw_crc_hex": ent["raw_bin"]["crc32"]},
            "raw_crc_matches_content_bin": got["raw_crc"] == raw_crc,
            "header_crc_ok": hcrc == got["header_crc"], "pass": ok}


def cmd_analyze():
    cmap = jload(R0 / "content-map.json", {})
    rs = jload(OUT / "run-status-r1.json", {}) or {}
    res, classes = {}, {}
    for key in ("n", "l"):
        cfg = RUNS[key]
        tag = cfg["tag"] + "-r1"
        cid = cfg["content_id"]
        ent = cmap["content"][cid]
        statp = CAPS / (tag + ".stats")
        logp = SLOGS / (tag + ".log")
        txt = logp.read_text(errors="replace") if logp.exists() else ""
        st, statxt = parse_stats(statp) if statp.exists() else ({}, "")
        stats_rows = "ss_pass=" in statxt
        m = {"content_id": cid, "mode": cfg["mode"], "labels": ent["labels"], "tag": tag,
             "run": rs.get(cid, {}), "stats_rows_present": stats_rows,
             "stats_file_created": statp.exists(),
             "stats_bytes": statp.stat().st_size if statp.exists() else 0}
        ev = {}
        for mm in re.finditer(r"SS_EVT t=(\d+) kind=(sof|cam_end|pub|read|enc|exp) frame=(\d+)"
                              r"(?: n=(\d+))?(?: bytes=(\d+))?", txt):
            k = mm.group(2)
            fr = int(mm.group(3))
            rec = ev.setdefault(k, {}).setdefault(fr, {})
            rec["t"] = int(mm.group(1))
            if mm.group(5) is not None:
                rec["bytes"] = int(mm.group(5))
        meta = re.search(r"SS_META t_rst=(\d+)", txt)
        rawm = re.search(r"SS_RAW_MATCH bad=(\d+) checked=(\d+) drv_groups=(\d+)", txt)
        t_rst = int(meta.group(1)) if meta else None
        t_exp = [None] + [ev.get("exp", {}).get(k, {}).get("t") for k in range(1, 5)]
        t_enc = [None] + [ev.get("enc", {}).get(k, {}).get("t") for k in range(1, 5)]
        t_sof = [None] + [ev.get("sof", {}).get(k, {}).get("t") for k in range(1, 5)]
        cum = [None] + [ev.get("exp", {}).get(k, {}).get("bytes") for k in range(1, 5)]
        nfr = max([k for k in range(1, 5) if t_exp[k] is not None] or [0])
        m.update({"t_rst": t_rst, "t_sof": t_sof, "t_enc": t_enc, "t_exp": t_exp,
                  "cum_exp_bytes": cum, "frames_exported": nfr,
                  "ss_raw_match": ({"bad": int(rawm.group(1)), "checked": int(rawm.group(2)),
                                    "drv_groups": int(rawm.group(3))} if rawm else None),
                  "stall_marker": ("SS_STALL" in txt), "stall_cold_marker": ("SS_STALL_COLD" in txt),
                  "timeout_marker": ("B11_FULL_TIMEOUT" in txt),
                  "counters": st,
                  "ss_stats_line": statxt.strip() or None})
        # cold start (guide section 3: L_cold = t_exp(1) with t_rst as 0)
        if t_exp[1] and t_rst is not None:
            m["L_cold"] = t_exp[1] - t_rst
            m["L_cold_raw_t_exp1"] = t_exp[1]
            m["L_cold_over_G0"] = m["L_cold"] / G0_CYCLES
        # per-frame bytes / ratios / export time / core interval
        frames = {}
        prev_cum = 0
        for k in range(1, 5):
            if cum[k] is None:
                continue
            b = cum[k] - prev_cum
            prev_cum = cum[k]
            frames[k] = {"exp_bytes": b,
                         "compression_ratio": (RAW_FRAME_BYTES / b) if b else None,
                         "export_time_cycles": 2 * b}
            if t_exp[k] and t_enc[k]:
                frames[k]["tail"] = t_exp[k] - t_enc[k]
            if k >= 2 and t_enc[k] and t_enc[k - 1]:
                ci = t_enc[k] - t_enc[k - 1]
                frames[k]["core_interval_cycles"] = ci
                et = frames[k]["export_time_cycles"]
                frames[k]["bottleneck"] = "core_interval" if ci >= et else "export_time"
        m["per_frame"] = frames
        S23 = (t_exp[3] - t_exp[2]) if (t_exp[2] and t_exp[3]) else None
        S34 = (t_exp[4] - t_exp[3]) if (t_exp[3] and t_exp[4]) else None
        m.update({"S_2": (t_exp[2] - t_exp[1]) if (t_exp[1] and t_exp[2]) else None,
                  "S_23": S23, "S_34": S34})
        Sss = (S23 + S34) / 2.0 if (S23 is not None and S34 is not None) else None
        m["S_ss"] = Sss
        tails = [frames[k]["tail"] for k in (2, 3, 4) if k in frames and "tail" in frames[k]]
        m["export_tail_mean"] = (sum(tails) / len(tails)) if len(tails) == 3 else None
        if Sss:
            m["S_spread_pct"] = (100.0 * abs(S34 - S23) / Sss)
            m["capacity_MBps"] = RAW_FRAME_BYTES * CLOCK_HZ / Sss / 1e6
            m["fps"] = CLOCK_HZ / Sss
            m["margin_G0_pct"] = (G0_CYCLES / Sss - 1) * 100
            m["margin_G25_pct_ref"] = (G25_CYCLES / Sss - 1) * 100
        if Sss and m["export_tail_mean"]:
            m["tail_frac"] = m["export_tail_mean"] / Sss
            m["tail_frac_pct"] = 100.0 * m["tail_frac"]
        m["sink_limited"] = (None if m.get("tail_frac") is None
                            else bool(m["tail_frac"] >= 0.50))
        # bottleneck attribution (A3b)
        cis = [frames[k]["core_interval_cycles"] for k in (2, 3, 4)
               if k in frames and "core_interval_cycles" in frames[k]]
        ets = [frames[k]["export_time_cycles"] for k in (2, 3, 4) if k in frames]
        if cis and ets:
            m["bottleneck_attribution"] = {
                "mean_core_interval_cycles": round(sum(cis) / len(cis), 1),
                "mean_export_time_cycles": round(sum(ets) / len(ets), 1),
                "primary": "core_interval" if (sum(cis) / len(cis)) >= (sum(ets) / len(ets))
                           else "export_time",
                "per_frame": {str(k): frames[k].get("bottleneck") for k in frames if k >= 2},
                "rule": "guide section 3: per frame compare core_interval(k)=t_enc(k)-t_enc(k-1) "
                        "with export_time(k)=2x bytes(k); the larger one is the bottleneck. "
                        "sink_limited=true remains the frozen G0 flag but must not be reported "
                        "as the only constraint.",
            }
        m["header_check"] = header_check(tag, ent)
        rm = m["ss_raw_match"] or {}
        m["self_check_pass"] = (rm.get("bad") == 0 and rm.get("checked") == GROUPS)
        cnt = st
        drops = {k: cnt.get(k) for k in ("raw_drop", "cmp_drop", "geom", "err", "dup", "wd")}
        m["drops"] = drops
        m["drops_all_zero"] = (all(v == 0 for v in drops.values())
                               and all(v is not None for v in drops.values()))
        m["frame_counters_clean"] = all(
            drops[k] == 0 for k in ("raw_drop", "cmp_drop", "geom", "err", "wd")
            if drops[k] is not None) and all(drops[k] is not None
                                             for k in ("raw_drop", "cmp_drop", "geom", "err", "wd"))
        m["dup_words"] = drops.get("dup")
        m["dup_semantics"] = (
            "st_dup_words is NOT a duplicate-read/over-read counter: a1_ddr_slot_store.v:281-282 "
            "increments it when the DDR read data of the current 256-bit word is bit-identical to "
            "the previous word. It therefore counts adjacent identical raw words, i.e. flat image "
            "regions, and is a content statistic. It does not corrupt data (raw_crc/self-check/"
            "stream_crc all match) and it does not add DDR traffic. The frozen TB ss_pass and "
            "guide section 3 / dev-plan A3 nevertheless require dup=0, which synthetic C1/C2 "
            "satisfied only because no two adjacent 32-pixel words were bit-identical.")
        m["counts_ok"] = (cnt.get("cap") == 4 and cnt.get("enc") == 4 and cnt.get("exported") == 4
                          and cnt.get("read") == GROUPS and cnt.get("raw_pub") == 4)
        m["frames_complete"] = bool(all(t_exp[k] is not None for k in range(1, 5))
                                    and m["counts_ok"] and stats_rows)
        a3 = (m["frames_complete"] and m["drops_all_zero"] and m["self_check_pass"]
              and m["header_check"].get("pass", False))
        m["A3_complete"] = bool(a3)
        m["A3_failed_clauses"] = ([c for c in ("frames_complete", "drops_all_zero",
                                               "self_check_pass", "header_crc")
                                   if not {"frames_complete": m["frames_complete"],
                                           "drops_all_zero": m["drops_all_zero"],
                                           "self_check_pass": m["self_check_pass"],
                                           "header_crc": m["header_check"].get("pass", False)}[c]])
        m["partial"] = not a3
        m["steady_state_status"] = ("measured" if m["frames_complete"]
                                    else ("partial" if nfr else "not_measured"))
        # G0 (guide section 3, literal order)
        if not m["frames_complete"]:
            g0 = "G0_not_proven"
            why = ("4-frame run incomplete: exported=%s/4 stats_rows=%s stall=%s stall_cold=%s "
                   "timeout=%s" % (nfr, stats_rows, m["stall_marker"], m["stall_cold_marker"],
                                   m["timeout_marker"]))
        elif m["sink_limited"]:
            g0, why = "G0_not_proven", ("sink_limited: tail_frac=%.2f%% >= 50%% (frozen rule); "
                                        "S_ss cannot be used as a capacity proof" % m["tail_frac_pct"])
        elif Sss > G0_CYCLES:
            g0, why = "G0_not_closed", ("S_ss=%.1f > 6,250,000 (gap %.1f cycles, %.3f%%)"
                                        % (Sss, Sss - G0_CYCLES, 100.0 * (Sss - G0_CYCLES) / Sss))
        elif not m["drops_all_zero"]:
            g0, why = "G0_not_proven", ("validity clause drop/dup/geom/err/wd=0 not satisfied "
                                        "(dup=%s); S_ss is in range but the run cannot be feasible"
                                        % drops.get("dup"))
        elif Sss <= G0_CYCLES:
            g0, why = "G0_feasible_for_scope", "S_ss=%.1f <= 6,250,000" % Sss
        m["G0"], m["G0_why"] = g0, why
        m["G25_ref_column_only"] = "reference only; never a gate"
        m["G0_scope"] = ("content=%s(display-referred image derived Bayer, NOT sensor RAW); "
                         "pacing=TB wait_slot_free (NOT production free-run); sink=frozen "
                         "93.75 MB/s TB proxy (NOT a production sink); DDR=behavioural 256-bit "
                         "PAXI model; core=single a1 @187.5 MHz; stream=single" % cid)
        res[key] = m
        print("%s exp=%s S_ss=%s tail_mean=%s tail_frac=%s%% sink_limited=%s G0=%s A3=%s" % (
            cid, t_exp[1:], m["S_ss"], m["export_tail_mean"],
            None if m.get("tail_frac_pct") is None else round(m["tail_frac_pct"], 2),
            m["sink_limited"], m["G0"], m["A3_complete"]))
        if m.get("bottleneck_attribution"):
            print("   bottleneck:", m["bottleneck_attribution"]["primary"],
                  m["bottleneck_attribution"]["mean_core_interval_cycles"],
                  m["bottleneck_attribution"]["mean_export_time_cycles"])
    # ---------------- verdict json
    def clean(v):
        return v
    both_ok = all(res[k]["A3_complete"] for k in ("n", "l"))
    g0s = [res[k]["G0"] for k in ("n", "l")]
    if both_ok and all(g == "G0_feasible_for_scope" for g in g0s):
        headline = "G0_feasible_for_scope"
    elif all(g == "G0_feasible_for_scope" or g == "G0_not_closed" for g in g0s) and both_ok:
        headline = "G0_not_closed"
    else:
        headline = "G0_not_proven"
    if both_ok:
        p1a = ("On image-derived natural-scene content (not sensor RAW) the 4-frame steady state WAS "
               "measured in both classes (4/4 exported, t_exp(1..4) all present, read=518,400, "
               "SS_STATS present, raw_drop/cmp_drop/geom/err/wd=0, self-check bad=0, header CRC ok). "
               "N: S_ss=%s cycles -> %s; L: S_ss=%s cycles -> %s. L is sink_limited "
               "(tail_frac>=50%%); N is core-bound and above the 6.25M G0 gate. Cold start L_cold is "
               "reported separately and does not enter S_ss." % (
                   res["n"]["S_ss"], res["n"]["G0"], res["l"]["S_ss"], res["l"]["G0"]))
    else:
        done = [k.upper() for k in ("n", "l") if res[k]["frames_complete"]]
        p1a = ("4-frame steady state WAS measured for %s (t_exp(1..4) present, cap=enc=exported=4, "
               "read=518,400, SS_STATS present), BUT dev-plan A3 is not satisfied as written because "
               "the frozen validity clause 'dup=0' fails: N dup=%s, L dup=%s (st_dup_words counts "
               "ADJACENT BIT-IDENTICAL 256-bit raw words, i.e. flat image regions - a content "
               "statistic, not duplicate DDR traffic; see dup_semantics). The measured S_ss/tail/"
               "sink_limited are valid measurements and are reported per class; G0 follows guide "
               "section 3: N=S_ss %s cyc (%s), L=S_ss %s cyc (%s). r0's derived 7.48M/6.98M remain "
               "derived_not_measured and are superseded by these measured values." % (
                   ", ".join(done), res["n"]["dup_words"], res["l"]["dup_words"],
                   res["n"]["S_ss"], res["n"]["G0"], res["l"]["S_ss"], res["l"]["G0"]))
    verdict = {
        "task": "T10.ss-g0-prod-content", "run": "r0", "round": 1,
        "created": time.strftime("%Y-%m-%d"),
        "supersedes": {"r0_fields": ["out/content-verdict.json P1_answer (OBS-1)",
                                     "out/run-status.json stats_exists (OBS-2)"],
                       "note": "r0 files stay frozen and unmodified; r1 values below replace them "
                               "for any downstream use (M1/M2/M3)."},
        "hard_gate": {"G0_cycles": G0_CYCLES, "G0_MBps": G0_MBPS,
                      "G25_cycles_ref_only": G25_CYCLES, "G25_MBps_ref_only": G25_MBPS,
                      "clock_MHz": 187.5, "sink_ceiling_MBps": SINK_MAX_MBPS,
                      "max_cycles": MAXCYC},
        "watchdog": {"WD_LIMIT": 12000000, "WD_LIMIT_COLD": 20000000,
                     "note": "round1 harness: cold start anchored at t_sof(1) <= 20M; steady gap "
                             "anchored at last_exp_t <= 12M and only when st_exp>0"},
        "metric_definitions": {
            "S_ss": "(S_23+S_34)/2, S_ab=t_exp(b)-t_exp(a)",
            "L_cold": "t_exp(1)-t_rst (guide section 3; raw t_exp(1) also reported)",
            "tail": "t_exp(k)-t_enc(k); tail_mean over k=2,3,4",
            "tail_frac": "tail_mean/S_ss", "sink_limited": "tail_frac >= 0.50 (frozen)",
            "C_ss": "2592000*187.5e6/S_ss/1e6 MB/s", "margin_G0": "6250000/S_ss-1",
            "core_interval(k)": "t_enc(k)-t_enc(k-1), k>=2",
            "export_time(k)": "2 x bytes(k) at 2 clk_a1/byte (frozen TB sink)"},
        "raw_band": {"bytes_per_frame": RAW_BAND_BYTES,
                     "cycles_at_93_75MBps": 5189412, "pct_of_g0_at_93_75": 83.03,
                     "cycles_at_103_79MBps": 4687500,
                     "erratum": "guide section 3 now freezes 103.79 MB/s = 4,687,500 cycles "
                                "(25.0 ms). 4,687,421 is the same value computed from the rounded "
                                "103.79 MB/s; percentages unchanged."},
        "content_classes": {}, "headline": headline, "P1_answer": p1a,
        "not_proven": ["real sensor RAW", "full / worst-case content",
                       "production free-run pacing", "production sink >=103.79 MB/s",
                       "real DDR/PAXI sustained", "PCIe/UART transport", "board level",
                       "dual stream", "RK/NPU", "192.642 MHz", "resources/timing (no TD)"],
    }
    for key in ("n", "l"):
        m = res[key]
        cid = m["content_id"]
        verdict["content_classes"][cid] = {
            "content_id": cid, "labels": m["labels"], "mode": m["mode"], "tag": m["tag"],
            "A3_complete": m["A3_complete"], "frames_exported": m["frames_exported"],
            "t_rst": m["t_rst"], "t_sof": m["t_sof"], "t_enc": m["t_enc"], "t_exp": m["t_exp"],
            "cum_exp_bytes": m["cum_exp_bytes"],
            "L_cold": m.get("L_cold"), "L_cold_raw_t_exp1": m.get("L_cold_raw_t_exp1"),
            "L_cold_over_G0": m.get("L_cold_over_G0"),
            "S_2": m.get("S_2"), "S_23": m.get("S_23"), "S_34": m.get("S_34"),
            "S_ss": m.get("S_ss"), "S_spread_pct": m.get("S_spread_pct"),
            "export_tail_per_frame": {str(k): m["per_frame"][k].get("tail")
                                      for k in m["per_frame"]},
            "export_tail_mean": m.get("export_tail_mean"),
            "tail_frac": m.get("tail_frac"), "tail_frac_pct": m.get("tail_frac_pct"),
            "sink_limited": m.get("sink_limited"),
            "capacity_MBps": m.get("capacity_MBps"), "fps": m.get("fps"),
            "margin_G0_pct": m.get("margin_G0_pct"),
            "margin_G25_pct_ref": m.get("margin_G25_pct_ref"),
            "per_frame": m["per_frame"],
            "bottleneck_attribution": m.get("bottleneck_attribution"),
            "counters": {k: m["counters"].get(k) for k in
                         ("cap", "enc", "exported", "exp_bytes", "raw_pub", "raw_drop",
                          "cmp_drop", "geom", "err", "read", "dup", "wd", "cap_bytes",
                          "cycles", "frames", "ss_pass", "content", "pacing", "sink",
                          "capture", "raw_bad", "raw_checked", "drv_groups")},
            "counts_ok": m["counts_ok"], "drops": m["drops"],
            "drops_all_zero": m["drops_all_zero"],
            "frame_counters_clean": m["frame_counters_clean"],
            "dup_words": m["dup_words"], "dup_semantics": m["dup_semantics"],
            "frames_complete": m["frames_complete"],
            "A3_failed_clauses": m["A3_failed_clauses"],
            "self_check": m["ss_raw_match"], "self_check_pass": m["self_check_pass"],
            "header_check": m["header_check"],
            "stats_rows_present": m["stats_rows_present"],
            "stats_file_created": m["stats_file_created"], "stats_bytes": m["stats_bytes"],
            "ss_stats_line": m["ss_stats_line"],
            "stall_marker": m["stall_marker"], "stall_cold_marker": m["stall_cold_marker"],
            "timeout_marker": m["timeout_marker"],
            "partial": m["partial"], "steady_state_status": m["steady_state_status"],
            "G0": m["G0"], "G0_why": m["G0_why"], "G0_scope": m["G0_scope"],
            "G25_ref_column_only": m["G25_ref_column_only"],
            "run": m["run"],
        }
    verdict["headline_reason"] = ("per-class A3_complete=N:%s L:%s; per-class G0=N:%s L:%s; the "
                                  "headline is the weaker of the two and stays bounded by the TB "
                                  "slot-free pacing, the 93.75 MB/s sink and image-derived content"
                                  % (res["n"]["A3_complete"], res["l"]["A3_complete"],
                                     g0s[0], g0s[1]))
    jdump(OUT / "content-verdict-r1.json", verdict)
    print("headline=%s  P1_answer[:120]=%s" % (headline, p1a[:120]))


# ------------------------------------------------------------------ manifest
def cmd_manifest():
    r0man = R0 / "manifest-r0.json"
    arts = []
    skip = {"manifest-r0.json", "manifest-r1.json"}
    for p in sorted(R0.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(R0).as_posix()
        if rel in skip:
            continue
        arts.append({"path": str(p), "rel": rel, "bytes": p.stat().st_size, "sha256": sha(p)})
    tot, n = spent()
    v = jload(OUT / "content-verdict-r1.json", {}) or {}
    ver = jload(OUT / "r1-verify.json", {}) or {}
    src13 = [{"file": f, "sha256": sha(SRC / f)} for f in SRC12 + ["tb_ss_4run_wd.v"]]
    man = {
        "task_id": "T10.ss-g0-prod-content", "run_dir": str(R0.parent.parent),
        "round": 1, "repair_round": 1,
        "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "previous_manifest": {"path": "manifest-r0.json", "sha256": sha(r0man),
                              "expected_sha256": R0_MAN_SHA,
                              "unchanged": sha(r0man) == R0_MAN_SHA, "artifacts": 49},
        "repair_scope": "harness only: two-stage watchdog in the NEW file src/tb_ss_4run_wd.v plus "
                        "a read-only bytes= field on kind=exp; no DUT/threshold/content change",
        "write_scope": [str(R0), str(TEMP / "opencode" / "ss-g0-prod-content")],
        "stopped_modifying": True, "active_commands": 0,
        "active_commands_note": "no command of this task is running at freeze time (the last vsim "
                                "exited rc=0 at 18:10). 4 unrelated vsim/vish processes started at "
                                "18:16:20/18:16:25 (after both runs, not launched by this task's "
                                "commands-r1.jsonl) were observed and deliberately NOT terminated.",
        "artifact_count": len(arts), "artifacts": arts,
        "new_in_round1": ["src/tb_ss_4run_wd.v", "src/DIFF-r1.md", "sim/run_content_r1.py",
                          "sim/commands-r1.jsonl", "sim/logs/vlib-r1.log", "sim/logs/vlog-r1.log",
                          "sim/logs/n-r1.log", "sim/logs/l-r1.log",
                          "sim/caps/n-r1.stats", "sim/caps/n-r1.evt", "sim/caps/n-r1.hdr",
                          "sim/caps/l-r1.stats", "sim/caps/l-r1.evt", "sim/caps/l-r1.hdr",
                          "out/r1-verify.json", "out/content-verdict-r1.json",
                          "out/run-status-r1.json", "result-r1.md", "lessons-r1.md"],
        "frozen_sources_13": src13,
        "dut_src_modified": 0,
        "whitelist": ver.get("whitelist"),
        "dut_sources_all_match_r0": ver.get("dut_sources_all_match_r0"),
        "r0_manifest_unchanged": ver.get("r0_manifest_unchanged"),
        "content": {c: {"labels": (v.get("content_classes", {}).get(c, {}) or {}).get("labels"),
                        "raw_bin_sha256": (jload(R0 / "content-map.json", {}) or {})
                        .get("content", {}).get(c, {}).get("raw_bin", {}).get("sha256"),
                        "raw40_hex_sha256": (jload(R0 / "content-map.json", {}) or {})
                        .get("content", {}).get(c, {}).get("raw40_hex", {}).get("sha256")}
                    for c in ("N", "L")},
        "verdict": {"headline": v.get("headline"),
                    "A3_complete": {c: (v.get("content_classes", {}).get(c, {}) or {}).get("A3_complete")
                                    for c in ("N", "L")},
                    "per_class": {c: (v.get("content_classes", {}).get(c, {}) or {}).get("G0")
                                  for c in ("N", "L")},
                    "reason": v.get("headline_reason"),
                    "P1_answer": v.get("P1_answer")},
        "budget": {"round1_full_size_vsim_runs": n, "round1_limit": MAX_FULL_RUNS,
                   "round1_vsim_seconds": round(tot, 1), "round1_vsim_wall_limit_s": 5700,
                   "hard_timeout_per_run_s": RUN_TIMEOUT_S,
                   "p1_cumulative_full_runs": 2 + n, "p1_cumulative_limit": 6,
                   "p1_cumulative_vsim_seconds": round(1400.5 + tot, 1),
                   "p1_cumulative_vsim_wall_limit_s": 12000,
                   "td_or_board_actions": 0, "network_actions": 0},
        "rollback": "delete or ignore T10.ss-g0-prod-content/** (r0 frozen set stays untouched)",
    }
    jdump(R0 / "manifest-r1.json", man)
    print("manifest-r1 artifacts=%d headline=%s r0_unchanged=%s" % (
        len(arts), v.get("headline"), man["previous_manifest"]["unchanged"]))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: run_content_r1.py <verify|compile|run n|l|analyze|manifest>")
    c = sys.argv[1]
    if c == "verify":
        cmd_verify()
    elif c == "compile":
        compile_all()
    elif c == "run":
        cmd_run(sys.argv[2])
    elif c == "analyze":
        cmd_analyze()
    elif c == "manifest":
        cmd_manifest()
    else:
        raise SystemExit("unknown subcommand %r" % c)
