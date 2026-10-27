#!/usr/bin/env python3
"""run_r1.py -- T10.b12-r1-last R1 loss/abort driver (ModelSim ASE 10.5b).

Runs the frozen independent reproduction testbench (`r1-b11/tb_r1_loss.sv`,
`r1-b11/check_r1.py`, `r1-b11/ddr_recovery_model.sv`) against a real candidate
source tree:

    python run_r1.py --src <changed-src> --out <dir> [--tag b11|b12]

CASE=0 is the clean control, CASE=1 is the FIFO-rejection / lost-LAST recovery
case.  The checker is byte-identical to the independent workspace; PASS gates
are NOT relaxed.  Every child process has a real timeout.
"""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = pathlib.Path(r"D:\fpga\ph1p100")
MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
INI = ROOT / "work/parallel-sim-20261024-2204/codec-throughput/modelsim.ini"
REPO = ROOT / "fpga/csi2/src"
TMP = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode")

SELF = ["a1_raw_crop.v", "cam_diag_mailbox.v", "a1_ddr_slot_store.v",
        "a1_frame_top.v", "a1_deflate_core.v", "a1_uart_export.v",
        "camera_a1_uart_top.v"]
DEPS = [REPO / "mem/capture_async_fifo.v", REPO / "a1/a1_ddr_arb2.v"]


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", default="b12")
    ap.add_argument("--tb-dir", default="r1-b11")
    args = ap.parse_args()

    src = pathlib.Path(args.src)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    tbdir = HERE / args.tb_dir
    work = TMP / ("b12-r1-" + args.tag) / "work"
    work.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env["MODEL_TECH"] = str(MS)
    env["MODELSIM"] = str(INI)
    env["PATH"] = str(MS) + os.pathsep + env.get("PATH", "")

    receipts = []

    def run(argv, name, allowed=(0,), timeout=900):
        argv = [str(a).replace("\\", "/") for a in argv]
        t0 = time.monotonic()
        item = dict(name=name, argv=argv, cwd=work.as_posix(), timeout_seconds=timeout,
                    started=datetime.datetime.now().isoformat(timespec="seconds"))
        log = out / (name + ".log")
        with open(log, "w", encoding="utf-8", errors="replace") as lf:
            try:
                pr = subprocess.run(argv, cwd=str(work), env=env, stdout=lf,
                                    stderr=subprocess.STDOUT, timeout=timeout)
                item.update(exit_code=pr.returncode, timed_out=False)
            except subprocess.TimeoutExpired:
                item.update(exit_code=None, timed_out=True)
        item["seconds"] = round(time.monotonic() - t0, 1)
        receipts.append(item)
        (out / "commands.json").write_text(json.dumps(receipts, indent=2), encoding="utf-8")
        print("%-14s exit=%s %.1fs" % (name, item["exit_code"], item["seconds"]), flush=True)
        return item

    if not (work / "_info").exists():
        run([MS / "vlib.exe", "work"], "vlib", timeout=300)

    files = [src / n for n in SELF] + DEPS + [tbdir / "ddr_recovery_model.sv",
                                              tbdir / "tb_r1_loss.sv"]
    comp = run([MS / "vlog.exe", "-sv", "-work", "work", "+define+SIMULATION"] + files,
               "compile", timeout=1800)
    txt = (out / "compile.log").read_text(errors="replace")
    errs = [l for l in txt.splitlines() if "** Error" in l]
    print("compile errors=%d" % len(errs), flush=True)
    for l in errs[:10]:
        print("  " + l, flush=True)
    if comp["exit_code"] != 0 or errs:
        (out / "summary.json").write_text(json.dumps(
            dict(status="COMPILE_FAIL", errors=errs[:20]), indent=2), encoding="utf-8")
        return 3

    results = {}
    for case, name in ((0, "clean"), (1, "loss")):
        cdir = out / name
        cdir.mkdir(exist_ok=True)
        sim = run([MS / "vsim.exe", "-c", "-lib", "work", "-voptargs=+acc",
                   "-l", cdir / "transcript.log", "work.tb_r1_loss",
                   "+CASE=" + str(case),
                   "+OUT=" + (cdir / "capture.dec").as_posix(),
                   "+UART=" + (cdir / "uart.dec").as_posix(),
                   "+TRACE=" + (cdir / "trace.txt").as_posix(),
                   "+STAT=" + (cdir / "stats.txt").as_posix(),
                   "-do", "onerror {quit -code 1}; run -all; quit -code 0"],
                  "simulate-" + name, allowed=(0, 1), timeout=1800)
        (cdir / "console.log").write_text((out / ("simulate-" + name + ".log")).read_text(
            errors="replace"), encoding="utf-8")
        chk = run([sys.executable, "-B", tbdir / "check_r1.py", cdir], "check-" + name,
                  allowed=(0, 2), timeout=600)
        rj = cdir / "result.json"
        results[name] = json.loads(rj.read_text()) if rj.exists() else dict(
            status="INVALID", errors=["checker produced no result.json"])
        results[name]["checker_exit"] = chk["exit_code"]
        results[name]["sim_exit"] = sim["exit_code"]
        print("%s -> %s" % (name, results[name].get("status")), flush=True)

    status = "PASS" if all(v.get("status") == "PASS" for v in results.values()) else \
             ("DUT_FAIL_VALID" if results["loss"].get("status") == "DUT_FAIL_VALID" and
              results["clean"].get("status") == "PASS" else "INVALID")
    summary = dict(tag=args.tag, status=status, clean=results["clean"], loss=results["loss"],
                   source_dir=src.as_posix(),
                   source_sha256={n: sha(src / n) for n in SELF},
                   dep_sha256={p.name: sha(p) for p in DEPS},
                   tb_sha256={n: sha(tbdir / n) for n in
                              ("tb_r1_loss.sv", "check_r1.py", "ddr_recovery_model.sv")})
    (out / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("R1_STATUS %s (%s)" % (status, args.tag), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
