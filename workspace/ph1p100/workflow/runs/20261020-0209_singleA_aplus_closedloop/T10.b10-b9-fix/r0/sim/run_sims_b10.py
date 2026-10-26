#!/usr/bin/env python3
"""run_sims_b10.py -- T10.b10-b9-fix r0 simulator driver (ModelSim ASE).

Cases: compile arb_old arb_new sweep export layout r1 r2 r3 multi p1

New RTL and the cross-version TBs are compiled twice: `work` (this task's
sources) and `work_b9` (the frozen b9 exporter) so the B9-01 negative control
runs the SAME testbench source against the unchanged RTL.
"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
PKG = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix"
R0 = PKG / "r0"
SIM = R0 / "sim"
LOGS = SIM / "logs"
CAPS = SIM / "caps"
B9 = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/r0"
UP = ROOT / "upstream/ph1p100-pcie-ep-fpga"
CSI = ROOT / "fpga/csi2"
GOLD = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/sim/captures"

MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
INI = pathlib.Path(r"D:\fpga\ph1p100\work\parallel-sim-20261024-2204\codec-throughput\modelsim.ini")
WORK = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\b10\simwork")
WORK9 = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\b10\simwork_b9")
SCRATCH = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\b10\caps")

ENV = os.environ.copy()
ENV["MODEL_TECH"] = str(MS)
ENV["MODELSIM"] = str(INI)
ENV["PATH"] = str(MS) + os.pathsep + ENV.get("PATH", "")

DEPS = [
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
]

FILES_NEW = [
    R0 / "changed-src/a1_raw_crop.v",
    R0 / "changed-src/a1_uart_export.v",
    R0 / "changed-src/camera_a1_uart_top.v",
    R0 / "changed-src/cam_diag_mailbox.v",
    R0 / "changed-src/a1_deflate_core.v",
    R0 / "changed-src/a1_ddr_slot_store.v",
] + DEPS + [
    SIM / "tb_p1_chain.v",
    SIM / "tb_status_v3.v",
    SIM / "tb_raw_store.v",
    SIM / "tb_b10_export.sv",
    SIM / "tb_b10_layout.sv",
    SIM / "tb_b10_r123.sv",
    SIM / "tb_b10_multi.v",
    SIM / "tb_b10_arb.sv",
]

FILES_B9 = [
    B9 / "changed-src/a1_uart_export.v",
    SIM / "tb_b10_arb.sv",
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


def do_compile(work, files, tag):
    work.mkdir(parents=True, exist_ok=True)
    SCRATCH.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    if not work.joinpath("_info").exists():
        run([str(MS / "vlib.exe"), "work"], work, LOGS / ("vlib_%s.log" % tag), 300)
    args = [str(MS / "vlog.exe"), "-sv", "-work", "work", "+define+SIMULATION"] + [str(f) for f in files]
    rc, el = run(args, work, LOGS / ("vlog_%s.log" % tag), 1800)
    txt = pathlib.Path(str(LOGS / ("vlog_%s.log.out" % tag))).read_text(errors="replace")
    errs = [l for l in txt.splitlines() if "** Error" in l]
    print("compile %s rc=%d %.1fs errors=%d" % (tag, rc, el, len(errs)), flush=True)
    for l in errs[:12]:
        print("  " + l, flush=True)
    return rc == 0


def vsim(work, top, plus, log, timeout, generics=None):
    args = [str(MS / "vsim.exe"), "-c", "-lib", "work",
            "-l", str(log), top] + plus
    if generics:
        args += generics
    args += ["-do", "run -all; quit -f"]
    rc, el = None, None
    try:
        rc, el = run(args, work, log, timeout)
    except subprocess.TimeoutExpired:
        return 124, timeout, "VSIM_TIMEOUT"
    txt = pathlib.Path(log).read_text(errors="replace") if pathlib.Path(log).exists() else ""
    return rc, el, txt


def markers(txt):
    return [l.strip("# ").strip() for l in txt.splitlines()
            if "B10_" in l and ("RESULT" in l or "DONE" in l or "CONFIRMED" in l or "_BAD" in l)]


def case_vsim(name, top, plus, timeout=600, generics=None, work=None, expect="pass=1"):
    work = work or WORK
    log = LOGS / ("sim_%s.log" % name)
    rc, el, txt = vsim(work, top, plus, log, timeout, generics)
    mk = markers(txt)
    ok = (expect in txt) and (rc == 0) and ("B10_LAYOUT_FAIL" not in txt)
    print("%-16s ok=%s rc=%s %.1fs %s" % (name, ok, rc, el, " | ".join(mk[-2:])[:200]), flush=True)
    return dict(case=name, ok=bool(ok), rc=rc, seconds=el, markers=mk)


def main():
    cases = sys.argv[1:] or ["compile", "arb_old", "arb_new", "sweep", "export", "layout",
                             "r1", "r2", "r3", "multi", "p1"]
    results = {}
    if "compile" in cases:
        if not do_compile(WORK, FILES_NEW, "new"):
            print("COMPILE_FAIL")
            return 2
        if not do_compile(WORK9, FILES_B9, "b9"):
            print("COMPILE_B9_FAIL")
            return 2
    if "arb_old" in cases:
        results["arb_old"] = case_vsim("arb_old", "tb_b10_arb", ["+EXP=old"],
                                       generics=["-gSTATUS_DIV=5000", "-gFRAME_BYTES=2000", "-gEXPECT_OLD=1"], work=WORK9,
                                       expect="old_repro=1")
    if "arb_new" in cases:
        results["arb_new"] = case_vsim("arb_new", "tb_b10_arb", ["+EXP=new"],
                                       generics=["-gSTATUS_DIV=5000", "-gFRAME_BYTES=2000"], expect="new_pass=1")
    if "sweep" in cases:
        for div in (3500, 4000, 4500, 5000, 6000, 8000):
            results["sweep_%d" % div] = case_vsim(
                "arb_new_d%d" % div, "tb_b10_arb", ["+EXP=new"],
                generics=["-gSTATUS_DIV=%d" % div, "-gFRAME_BYTES=2000"], expect="new_pass=1")
    if "export" in cases:
        results["wrap"] = case_vsim("export_wrap", "tb_b10_export", ["+CASE=wrap"],
                                    generics=["-gNFRAMES=14", "-gSTATUS_DIV=5000"])
        results["samecycle"] = case_vsim("export_samecycle", "tb_b10_export", ["+CASE=samecycle"],
                                         generics=["-gNFRAMES=14", "-gSTATUS_DIV=5000"])
        results["reject"] = case_vsim("export_reject", "tb_b10_export", ["+CASE=reject"],
                                      generics=["-gNFRAMES=3", "-gSTATUS_DIV=0"])
        results["empty"] = case_vsim("export_empty", "tb_b10_export", ["+CASE=empty"],
                                     generics=["-gNFRAMES=0", "-gSTATUS_DIV=500"])
    if "layout" in cases:
        results["layout"] = case_vsim("layout_full", "tb_b10_layout", [], timeout=1800)
        results["layout_neg"] = case_vsim("layout_neg", "tb_b10_layout", ["+EXPECT_FAIL=1"],
                                          timeout=900, generics=["-gCMP_BASE=131072"],
                                          expect="old_layout_detected=1")
    if "r1" in cases:
        results["r1"] = case_vsim("r1", "tb_b10_r123", ["+CASE=r1"], timeout=900)
    if "r2" in cases:
        results["r2"] = case_vsim("r2", "tb_b10_r123", ["+CASE=r2"], timeout=300)
    if "r3" in cases:
        results["r3"] = case_vsim("r3", "tb_b10_r123", ["+CASE=r3"], timeout=300)
    if "multi" in cases:
        dec = SCRATCH / "multi.dec"
        st = SCRATCH / "multi.stats"
        r = case_vsim("multi", "tb_b10_multi", ["+OUT=" + str(dec), "+STAT=" + str(st)],
                      timeout=1800, expect="B10_MULTI_DONE")
        chk = subprocess.run([sys.executable, str(SIM / "check_multi.py"),
                              str(dec), str(st), str(CAPS / "multi")],
                             capture_output=True, text=True)
        print(chk.stdout.strip()[-1500:], flush=True)
        r["check_ok"] = "MULTI_CHECK_OK" in chk.stdout
        r["ok"] = r["ok"] and r["check_ok"]
        results["multi"] = r
    if "p1" in cases:
        for name, gens, gpfx in P1_CASES:
            dec = SCRATCH / (name + ".dec")
            stp = SCRATCH / (name + ".stats")
            log = LOGS / ("sim_p1_" + name + ".log")
            rc, el, txt = vsim(WORK, "tb_camera_a1_uart_top",
                               ["+MODE=0", "+OUT=" + str(dec), "+STAT=" + str(stp)],
                               log, 900, generics=gens)
            s = sha(dec)
            gsha = sha(GOLD / (name + ".dec"))
            if dec.exists():
                (CAPS / (name + ".dec")).write_bytes(dec.read_bytes())
            if stp.exists():
                (CAPS / (name + ".stats")).write_bytes(stp.read_bytes())
            ok = (s == gsha) and (rc == 0)
            print("p1 %-9s identical=%s rc=%s %.1fs sha=%s" % (name, s == gsha, rc, el, s[:16]), flush=True)
            results["p1_" + name] = dict(case="p1_" + name, ok=bool(ok), rc=rc,
                                         seconds=el, sha256=s, gold_sha256=gsha,
                                         byte_identical=(s == gsha))
    fp = SIM / "sim-results-b10.json"
    old = json.loads(fp.read_text()) if fp.exists() else {}
    old.update(results)
    fp.write_text(json.dumps(old, indent=2))
    n_ok = sum(1 for v in results.values() if v.get("ok"))
    print("SUMMARY %d/%d pass" % (n_ok, len(results)))
    print(json.dumps({k: v.get("ok") for k, v in results.items()}, indent=1))
    return 0


P1_CASES = [
    ("micro8x2", ["-gW=8", "-gH=2", "-gCAM_W=32", "-gCAM_H=4", "-gROI_X=4", "-gROI_Y=2", "-gUART_DIV=1"],
     "fa513a2b5a7f268be9f29d62aea6c44aaab796d0f23256b0e1049f50acceedef"),
    ("mid64x8", ["-gW=64", "-gH=8", "-gCAM_W=128", "-gCAM_H=16", "-gROI_X=0", "-gROI_Y=0", "-gUART_DIV=1"],
     "ee61e6200d9abca6"),
    ("full_grad", [], "b992a8ad74063545"),
]

if __name__ == "__main__":
    sys.exit(main())
