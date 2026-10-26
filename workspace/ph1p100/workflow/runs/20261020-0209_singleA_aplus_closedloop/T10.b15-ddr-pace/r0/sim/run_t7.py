#!/usr/bin/env python3
"""run_t7.py -- T10.b12-r1-last T7: SOF rejected by a full CDC FIFO.

Compiles the frozen b12 candidate sources with the T7 testbench (a copy of the
independent R1 testbench plus a CASE=2 branch) and runs check_t7.py.
"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = pathlib.Path(r"D:\fpga\ph1p100")
R0 = HERE.parent
CS = pathlib.Path(os.environ.get("T7_SRC", str(R0 / "changed-src")))
OUT = pathlib.Path(os.environ.get("T7_OUT", str(HERE / "run-t7")))
MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
INI = ROOT / "work/parallel-sim-20261024-2204/codec-throughput/modelsim.ini"
REPO = ROOT / "fpga/csi2/src"
WORK = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\b12") / ("work_t7_" + OUT.name)
OUT.mkdir(parents=True, exist_ok=True)

ENV = os.environ.copy()
ENV["MODEL_TECH"] = str(MS)
ENV["MODELSIM"] = str(INI)
ENV["PATH"] = str(MS) + os.pathsep + ENV.get("PATH", "")

FILES = [CS / n for n in ("a1_raw_crop.v", "cam_diag_mailbox.v", "a1_ddr_slot_store.v",
                          "a1_frame_top.v", "a1_deflate_core.v", "a1_uart_export.v",
                          "camera_a1_uart_top.v")] + \
        [REPO / "mem/capture_async_fifo.v", REPO / "a1/a1_ddr_arb2.v",
         HERE / "r1-b12/ddr_recovery_model.sv", HERE / "tb_r1_sof.sv"]


def run(argv, name, timeout=1800, allowed=(0,)):
    argv = [str(a) for a in argv]
    t0 = time.monotonic()
    log = OUT / (name + ".log")
    with open(log, "w", encoding="utf-8", errors="replace") as lf:
        pr = subprocess.run(argv, cwd=str(WORK), env=ENV, stdout=lf,
                            stderr=subprocess.STDOUT, timeout=timeout)
    print("%-12s exit=%d %.1fs" % (name, pr.returncode, time.monotonic() - t0), flush=True)
    return pr.returncode


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    if not (WORK / "_info").exists():
        run([MS / "vlib.exe", "work"], "vlib", 300)
    if run([MS / "vlog.exe", "-sv", "-work", "work", "+define+SIMULATION"] + FILES, "compile") != 0:
        print("COMPILE_FAIL")
        return 3
    txt = (OUT / "compile.log").read_text(errors="replace")
    errs = [l for l in txt.splitlines() if "** Error" in l]
    if errs:
        print("COMPILE_ERRORS %d" % len(errs))
        for l in errs[:10]:
            print("  " + l)
        return 3
    cdir = OUT / "case2"
    cdir.mkdir(exist_ok=True)
    rc = run([MS / "vsim.exe", "-c", "-lib", "work", "-voptargs=+acc",
              "-l", cdir / "transcript.log", "work.tb_r1_sof", "+CASE=2",
              "+OUT=" + (cdir / "capture.dec").as_posix(),
              "+UART=" + (cdir / "uart.dec").as_posix(),
              "+TRACE=" + (cdir / "trace.txt").as_posix(),
              "+STAT=" + (cdir / "stats.txt").as_posix(),
              "-do", "onerror {quit -code 1}; run -all; quit -code 0"], "simulate-t7",
            1800, allowed=(0, 1))
    (cdir / "console.log").write_text((OUT / "simulate-t7.log").read_text(errors="replace"),
                                      encoding="utf-8")
    chk = run([sys.executable, "-B", HERE / "check_t7.py", cdir], "check-t7", 600, (0, 2))
    status = "PASS" if chk == 0 else "FAIL"
    summary = dict(status=status, sim_exit=rc, checker_exit=chk,
                   source_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in FILES[:7]})
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("T7_STATUS %s" % status)
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
