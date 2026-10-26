#!/usr/bin/env python3
"""run_b11.py -- T10.b11-aplus-read simulator driver (ModelSim ASE 10.5b).

Cases:
  compile            build the work library from the frozen b11 sources
  read_<case>        tb_b11_read discrimination cases (one/multi/bp/late/stray/dup/full/reset)
  v4                 tb_status_v4 status packet v4 format check
  p1                 tb_camera_a1_uart_top three goldens (micro8x2/mid64x8/full_grad)
  full               tb_b11_full 1920x1080 two-frame integration through the bridge
"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
R0 = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0"
CS = R0 / "changed-src"
SIM = R0 / "sim"
LOGS = SIM / "logs"
CAPS = SIM / "caps"
CSI = ROOT / "fpga/csi2"
GOLD = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/sim/captures"

MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
INI = pathlib.Path(r"D:\fpga\ph1p100\work\parallel-sim-20261024-2204\codec-throughput\modelsim.ini")
WORK = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\b11\simwork")

ENV = os.environ.copy()
ENV["MODEL_TECH"] = str(MS)
ENV["MODELSIM"] = str(INI)
ENV["PATH"] = str(MS) + os.pathsep + ENV.get("PATH", "")

FILES = [
    CS / "a1_raw_crop.v",
    CS / "a1_ddr_slot_store.v",
    CS / "a1_uart_export.v",
    CS / "camera_a1_uart_top.v",
    CS / "cam_diag_mailbox.v",
    CS / "a1_frame_top.v",
    CS / "a1_deflate_core.v",
    CS / "p2_ddr_bridge.v",
    CSI / "src/a1/a1_ddr_arb2.v",
    CSI / "src/mem/capture_async_fifo.v",
    SIM / "p2_paxi_model_b11.v",
    SIM / "a1_ddr_model.v",
    SIM / "tb_p1_chain.v",
    SIM / "tb_b11_read.sv",
    SIM / "tb_status_v4.v",
    SIM / "tb_b11_full.v",
]

P1_CASES = [
    ("micro8x2", ["-gW=8", "-gH=2", "-gCAM_W=32", "-gCAM_H=4", "-gROI_X=4", "-gROI_Y=2", "-gUART_DIV=1"]),
    ("mid64x8",  ["-gW=64", "-gH=8", "-gCAM_W=128", "-gCAM_H=16", "-gROI_X=0", "-gROI_Y=0", "-gUART_DIV=1"]),
    ("full_grad", []),
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
    LOGS.mkdir(parents=True, exist_ok=True)
    CAPS.mkdir(parents=True, exist_ok=True)
    if not (WORK / "_info").exists():
        run([str(MS / "vlib.exe"), "work"], WORK, LOGS / "vlib.log", 300)
    args = [str(MS / "vlog.exe"), "-sv", "-work", "work", "+define+SIMULATION"] + [str(f) for f in FILES]
    rc, el = run(args, WORK, LOGS / "vlog.log", 1800)
    txt = pathlib.Path(str(LOGS / "vlog.log.out")).read_text(errors="replace")
    errs = [l for l in txt.splitlines() if "** Error" in l]
    print("compile rc=%d %.1fs errors=%d" % (rc, el, len(errs)), flush=True)
    for l in errs[:20]:
        print("  " + l, flush=True)
    return rc == 0


def vsim(top, plus, log, timeout, generics=None):
    args = [str(MS / "vsim.exe"), "-c", "-lib", "work", "-l", str(log), top] + plus
    if generics:
        args += generics
    args += ["-do", "run -all; quit -f"]
    try:
        rc, el = run(args, WORK, log, timeout)
    except subprocess.TimeoutExpired:
        return 124, timeout, "VSIM_TIMEOUT"
    txt = pathlib.Path(log).read_text(errors="replace") if pathlib.Path(log).exists() else ""
    return rc, el, txt


def main():
    cases = sys.argv[1:] or ["compile"]
    results = {}
    if "compile" in cases:
        if not do_compile():
            print("COMPILE_FAIL")
            return 2
    if "v4" in cases:
        log = LOGS / "sim_status_v4.log"
        rc, el, txt = vsim("tb_status_v4", [], log, 600)
        ok = ("B11_V4_RESULT pass=1" in txt) and ("B10_ASSERT_FAIL" not in txt)
        mk = [l.strip() for l in txt.splitlines() if "B11_V4_" in l]
        print("v4 ok=%s rc=%s %.1fs | %s" % (ok, rc, el, " | ".join(mk[-2:])), flush=True)
        results["v4"] = dict(case="v4", ok=bool(ok), rc=rc, seconds=el, markers=mk)
    READ_CASES = {
        "read_one":    (["+NAME=one"],    ["-gNWRITE=1"]),
        "read_multi":  (["+NAME=multi"],  ["-gNWRITE=2000"]),
        "read_bp":     (["+NAME=bp"],     ["-gNWRITE=2000", "-gAR_GAP=2", "-gR_GAP=12"]),
        "read_late":   (["+NAME=late"],   ["-gNWRITE=2000", "-gR_GAP=40"]),
        "read_stray":  (["+NAME=stray"],  ["-gNWRITE=2000", "-gSTRAY_R=1"]),
        "read_dup":    (["+NAME=dup"],    ["-gNWRITE=9000", "-gDUP_R=1"]),
        "read_reset":  (["+NAME=reset"],  ["-gNWRITE=2000", "-gDO_RESET=1"]),
        "read_full":   (["+NAME=full"],   ["-gNWRITE=129600"]),
    }
    for cname, (plus, gens) in READ_CASES.items():
        if cname not in cases and "read" not in cases:
            continue
        log = LOGS / ("sim_%s.log" % cname)
        rc, el, txt = vsim("tb_b11_read", plus, log, 1800, generics=gens)
        mk = [l.strip() for l in txt.splitlines() if "B11_READ_" in l]
        ok = ("B11_READ_RESULT" in txt) and ("pass=1" in txt.split("B11_READ_RESULT")[-1])
        print("%-12s ok=%s rc=%s %.1fs | %s" % (cname, ok, rc, el, " | ".join(mk[-1:])), flush=True)
        results[cname] = dict(case=cname, ok=bool(ok), rc=rc, seconds=el, markers=mk)
    if "p1" in cases:
        for name, gens in P1_CASES:
            dec = CAPS / (name + ".dec")
            stp = CAPS / (name + ".stats")
            log = LOGS / ("sim_p1_" + name + ".log")
            rc, el, txt = vsim("tb_camera_a1_uart_top",
                               ["+MODE=0", "+OUT=" + str(dec), "+STAT=" + str(stp)],
                               log, 1800, generics=gens)
            s = sha(dec)
            gsha = sha(GOLD / (name + ".dec"))
            ok = (s == gsha) and rc == 0
            print("p1 %-9s identical=%s rc=%s %.1fs sha=%s" % (name, s == gsha, rc, el, s[:16]), flush=True)
            results["p1_" + name] = dict(case="p1_" + name, ok=bool(ok), rc=rc, seconds=el,
                                         sha256=s, gold_sha256=gsha, byte_identical=(s == gsha))
    if "full" in cases:
        stp = CAPS / "full.stats"
        log = LOGS / "sim_full.log"
        rc, el, txt = vsim("tb_b11_full", ["+STAT=" + str(stp)], log, 5400)
        mk = [l.strip() for l in txt.splitlines() if "B11_FULL_" in l]
        ok = ("B11_FULL_RESULT pass=1" in txt)
        print("full ok=%s rc=%s %.1fs | %s" % (ok, rc, el, " | ".join(mk[-3:])), flush=True)
        results["full"] = dict(case="full", ok=bool(ok), rc=rc, seconds=el, markers=mk)
    fp = SIM / "sim-results-b11.json"
    old = json.loads(fp.read_text()) if fp.exists() else {}
    old.update(results)
    fp.write_text(json.dumps(old, indent=2))
    n_ok = sum(1 for v in results.values() if v.get("ok"))
    print("SUMMARY %d/%d pass" % (n_ok, len(results)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
