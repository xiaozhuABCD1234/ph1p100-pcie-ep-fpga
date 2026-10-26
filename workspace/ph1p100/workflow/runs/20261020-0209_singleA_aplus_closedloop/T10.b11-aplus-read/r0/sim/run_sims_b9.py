#!/usr/bin/env python3
"""run_sims_b9.py -- T10.b9-rawstore r0 simulator driver (ModelSim ASE).

Usage:  python run_sims_b9.py [case ...]
Cases:  compile geom p1 rawstore status3  (default: compile + all)

The work library lives on the short temp path (ModelSim log path limits);
artifacts that matter are copied back to r0/sim/caps and r0/sim/logs.
"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
PKG = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore"
R0 = PKG / "r0"
SIM = R0 / "sim"
CAPS = SIM / "caps"
LOGS = SIM / "logs"
UP = ROOT / "upstream/ph1p100-pcie-ep-fpga"
CSI = ROOT / "fpga/csi2"

MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
INI = pathlib.Path(r"D:\fpga\ph1p100\work\parallel-sim-20261024-2204\codec-throughput\modelsim.ini")
WORK = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\b9\simwork")
SCRATCH = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\b9\caps")

ENV = os.environ.copy()
ENV["MODEL_TECH"] = str(MS)
ENV["MODELSIM"] = str(INI)
ENV["PATH"] = str(MS) + os.pathsep + ENV.get("PATH", "")

FILES = [
    R0 / "changed-src/a1_raw_crop.v",
    R0 / "changed-src/a1_uart_export.v",
    R0 / "changed-src/camera_a1_uart_top.v",
    R0 / "changed-src/cam_diag_mailbox.v",
    R0 / "changed-src/a1_deflate_core.v",
    R0 / "changed-src/a1_ddr_slot_store.v",
    CSI / "src/a1/a1_ddr_arb2.v",
    CSI / "src/mem/capture_async_fifo.v",
    UP / "rtl/ep_side/codec/a1_frame_top.v",
    CSI / "prj/camera_peer/uisrc/03_ip/mipi_csi_2/csi_rx_packet_handler.v",
    CSI / "prj/camera_peer/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack.v",
    CSI / "prj/camera_peer/uisrc/03_ip/mipi_csi_2/csi_rx_hdr_ecc.v",
    R0 / "td/src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_packet_integrity.v",
    R0 / "td/src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack_checked.v",
    R0 / "td/src/p2_ddr_bridge.v",
    SIM / "a1_ddr_model.v",
    SIM / "p2_paxi_model.v",
    SIM / "tb_p1_chain.v",
    SIM / "tb_status_v3.v",
    SIM / "tb_raw_store.v",
    SIM / "tb_crop_geom_real.v",
    SIM / "tb_crop_pipe_real.v",
    SIM / "tb_crop_neg.v",
]


def run(args, cwd, log, timeout):
    t0 = time.monotonic()
    out = pathlib.Path(str(log) + ".out")
    with open(out, "w", encoding="utf-8", errors="replace") as lf:
        pr = subprocess.run(args, cwd=str(cwd), env=ENV, stdout=lf,
                            stderr=subprocess.STDOUT, timeout=timeout)
    return pr.returncode, round(time.monotonic() - t0, 1)


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def do_compile():
    WORK.mkdir(parents=True, exist_ok=True)
    SCRATCH.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    CAPS.mkdir(parents=True, exist_ok=True)
    if not WORK.joinpath("_info").exists():
        rc, el = run([str(MS / "vlib.exe"), "work"], WORK, LOGS / "vlib.log", 300)
        print("vlib rc=%d %.1fs" % (rc, el), flush=True)
    args = [str(MS / "vlog.exe"), "-work", "work", "+define+SIMULATION"] + [str(f) for f in FILES]
    rc, el = run(args, WORK, LOGS / "vlog.log", 900)
    print("vlog rc=%d %.1fs" % (rc, el), flush=True)
    txt = pathlib.Path(str(LOGS / "vlog.log") + ".out").read_text(errors="replace")
    tail = [l for l in txt.splitlines() if "Error" in l or "Warning" in l or "Errors:" in l]
    print("\n".join(tail[-25:]) if tail else "no vlog diagnostics", flush=True)
    return rc == 0


def vsim(top, plus, log, timeout, generics=None):
    args = [str(MS / "vsim.exe"), "-c", "-lib", "work", "-l", str(log), top] + plus
    if generics:
        args += generics
    args += ["-do", "run -all; quit -f"]
    rc, el = run(args, WORK, log, timeout)
    txt = pathlib.Path(log).read_text(errors="replace") if pathlib.Path(log).exists() else ""
    done = [l for l in txt.splitlines()
            if ("TB_" in l or "RESULT" in l or "CHECK_FAIL" in l) and
            ("DONE" in l or "TIMEOUT" in l or "FAIL" in l or "BAD" in l or "RESULT" in l)]
    return rc, el, done, txt


def case_geom():
    out = SCRATCH / "roi_real.bin"
    st = SCRATCH / "roi_real.stats"
    rc, el, done, txt = vsim("tb_crop_geom_real", ["+OUT=" + str(out), "+STAT=" + str(st)],
                             LOGS / "sim_geom_real.log", 3600)
    ref = SCRATCH / "roi_real.ref.bin"
    rc2 = subprocess.run([sys.executable, str(SIM / "make_ref_geom.py"), str(ref)],
                         capture_output=True, text=True)
    print(rc2.stdout.strip())
    res = dict(case="geom_real", exit=rc, seconds=el, tb=done,
               bin_bytes=out.stat().st_size if out.exists() else 0,
               bin_sha256=sha(out), ref_sha256=sha(ref),
               byte_identical=(sha(out) == sha(ref) and out.exists()),
               stats=st.read_text().strip().splitlines() if st.exists() else [])
    for src, dst in ((out, "roi_real.bin"), (st, "roi_real.stats"), (ref, "roi_real.ref.bin")):
        if src.exists():
            (CAPS / dst).write_bytes(src.read_bytes())
    print("geom_real identical=%s bytes=%d sha=%s" %
          (res["byte_identical"], res["bin_bytes"], res["bin_sha256"]), flush=True)
    return res


def case_pipe():
    rc, el, done, txt = vsim("tb_crop_pipe_real", [], LOGS / "sim_pipe_real.log", 600)
    print("pipe", done, flush=True)
    return dict(case="pipe_real", exit=rc, seconds=el, tb=done)


def case_neg():
    rc, el, done, txt = vsim("tb_crop_neg", [], LOGS / "sim_crop_neg.log", 1800)
    print("neg", done, flush=True)
    return dict(case="neg", exit=rc, seconds=el, tb=done)


def case_p1():
    out = {}
    for name, gens, gpfx in P1_CASES:
        dec = SCRATCH / (name + ".dec")
        stp = SCRATCH / (name + ".stats")
        rc, el, done, txt = vsim("tb_camera_a1_uart_top",
                                 ["+MODE=0", "+OUT=" + str(dec), "+STAT=" + str(stp)],
                                 LOGS / ("sim_p1_" + name + ".log"), 3600, generics=gens)
        s = sha(dec)
        gold = GOLD / (name + ".dec")
        gsha = sha(gold)
        stats = {}
        if stp.exists():
            for line in stp.read_text().splitlines():
                for tok in line.split():
                    if "=" in tok:
                        k, v = tok.split("=", 1)
                        stats[k] = v
        out[name] = dict(case="p1_" + name, exit=rc, seconds=el,
                         dec_bytes=dec.stat().st_size if dec.exists() else 0,
                         dec_sha256=s, gold_sha256=gsha,
                         golden_prefix_match=s.startswith(gpfx),
                         byte_identical=(s == gsha), stats=stats, tb=done)
        for src, dst in ((dec, name + ".dec"), (stp, name + ".stats")):
            if src.exists():
                (CAPS / dst).write_bytes(src.read_bytes())
        print("p1", name, "identical", out[name]["byte_identical"], "sha", s,
              "err", stats.get("err"), flush=True)
    return out


def case_rawstore():
    res = {}
    sizes = [("full", [], "")]
    smoke = os.environ.get("B9_RAWSTORE_SMOKE", "") == "1"
    if smoke:
        sizes = [("smoke", ["-gGROUPS=480", "-gRAW_WORDS=120", "-gEXP_BYTES=2400",
                            "-gABORT_BEATS=120"], "smoke_")]
    for tag, generics, prefix in sizes:
        for c in ("full2", "abort", "nofree", "rdy"):
            rc, el, done, txt = vsim("tb_raw_store", ["+CASE=" + c],
                                     LOGS / ("sim_rawstore_%s%s.log" % (prefix, c)),
                                     3600, generics=generics)
            line = [l.strip("# ").strip() for l in txt.splitlines() if "RESULT" in l]
            ok = bool(line) and "pass=1" in line[-1]
            key = "raw_%s%s" % (prefix, c)
            res[key] = dict(case=key, exit=rc, seconds=el,
                            result=line[-1] if line else "NO_RESULT",
                            pass_=ok, tb=done)
            print("rawstore", prefix + c, "pass" if ok else "FAIL",
                  line[-1] if line else "", flush=True)
    return res


def case_status3():
    res = {}
    sys.path.insert(0, str(R0 / "board"))
    from parse_status_v3 import parse, FIELDS
    for mode in (0, 1):
        out = SCRATCH / ("status_v3_m%d.txt" % mode)
        rc, el, done, txt = vsim("tb_status_v3",
                                 ["+OUT=" + str(out), "+NPKT=4", "+MODE=%d" % mode],
                                 LOGS / ("sim_status_v3_m%d.log" % mode), 900)
        n = 0
        bad = -1
        field_ok = False
        detail = ""
        if out.exists():
            raw = bytes(int(x) for x in out.read_text().split())
            pkts, bad_xor, bad_hdr, skipped = parse(raw)
            n, bad = len(pkts), bad_xor
            (CAPS / ("status_v3_m%d.txt" % mode)).write_bytes(out.read_bytes())
            if pkts and mode == 0:
                field_ok = all(pkts[0][k] == (0xA1B2C300 + k) % (1 << 32)
                               for k in range(43)) and all(p == pkts[0] for p in pkts)
                detail = "const fields ok=%s" % field_ok
            elif pkts and mode == 1:
                # every packet must contain exactly one value of (field_k - k)
                stamps = set()
                for p in pkts:
                    per = {(p[k] - k) & 0xFFFFFFFF for k in range(43)}
                    stamps.add(len(per))
                field_ok = all(s == 1 for s in stamps) and len(pkts) >= 2
                detail = "snapshot uniqueness per packet=%s (sets=%s)" % (
                    all(s == 1 for s in stamps), sorted(stamps))
        res["status_v3_m%d" % mode] = dict(case="status_v3_m%d" % mode, exit=rc,
                                           seconds=el, packets=n, bad_xor=bad,
                                           field_ok=field_ok, detail=detail, tb=done)
        print("status3 mode", mode, "packets", n, "bad_xor", bad, detail, flush=True)
    return res


GOLD = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/sim/captures"
P1_CASES = [
    ("micro8x2", ["-gW=8", "-gH=2", "-gCAM_W=32", "-gCAM_H=4", "-gROI_X=4", "-gROI_Y=2", "-gUART_DIV=1"],
     "fa513a2b5a7f268be9f29d62aea6c44aaab796d0f23256b0e1049f50acceedef"),
    ("mid64x8", ["-gW=64", "-gH=8", "-gCAM_W=128", "-gCAM_H=16", "-gROI_X=0", "-gROI_Y=0", "-gUART_DIV=1"],
     "ee61e6200d9abca6"),
    ("full_grad", [], "b992a8ad74063545"),
]


def main():
    cases = sys.argv[1:] or ["compile", "geom", "p1", "rawstore", "status3"]
    results = {}
    if "compile" in cases:
        if not do_compile():
            print("COMPILE_FAIL")
            return 2
    for c in cases:
        if c == "compile":
            continue
        if c == "geom":
            results["geom"] = case_geom()
        elif c == "pipe":
            results["pipe"] = case_pipe()
        elif c == "neg":
            results["neg"] = case_neg()
        elif c == "p1":
            results.update(case_p1())
        elif c == "rawstore":
            results.update(case_rawstore())
        elif c == "status3":
            results.update(case_status3())
    fp = SIM / "sim-results-b9.json"
    old = json.loads(fp.read_text()) if fp.exists() else {}
    old.update(results)
    fp.write_text(json.dumps(old, indent=2))
    print("SUMMARY", json.dumps(results, indent=1)[:6000])
    return 0


if __name__ == "__main__":
    sys.exit(main())
