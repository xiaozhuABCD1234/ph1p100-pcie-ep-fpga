#!/usr/bin/env python3
"""T10.b12-r1-last T10: three consecutive small-geometry frames (independent
supplemental case) re-run on the b12 candidate source.

The testbench and strict sequential parser are the frozen independent copies;
only the DUT source directory changes (b12 changed-src + the two repo deps).
"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = pathlib.Path(r"D:\fpga\ph1p100")
R0 = HERE.parent.parent
CS = pathlib.Path(os.environ.get("T10_SRC", str(R0 / "changed-src")))
OUTROOT = pathlib.Path(os.environ.get("T10_OUT", str(HERE)))
REPO = ROOT / "fpga/csi2/src"
MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")

FILES = [CS / n for n in ("a1_raw_crop.v", "cam_diag_mailbox.v", "a1_ddr_slot_store.v",
                          "a1_frame_top.v", "a1_deflate_core.v", "a1_uart_export.v",
                          "camera_a1_uart_top.v")] + \
        [REPO / "mem/capture_async_fifo.v", REPO / "a1/a1_ddr_arb2.v"] + \
        [HERE.parent / "a1_ddr_model.v", HERE / "tb_b10_multi_strict.sv"]


def p(x):
    return pathlib.Path(x).as_posix()


def run(argv, cwd, log, timeout=1800):
    argv = [str(x) for x in argv]
    with open(log, "w", encoding="utf-8", errors="replace") as lf:
        pr = subprocess.run(argv, cwd=str(cwd), stdout=lf, stderr=subprocess.STDOUT,
                            timeout=timeout,
                            env={**os.environ, "MODEL_TECH": str(MS),
                                 "PATH": str(MS) + os.pathsep + os.environ.get("PATH", "")})
    return pr.returncode


def execute(name, nframes, sts):
    case = OUTROOT / name
    case.mkdir(parents=True, exist_ok=True)
    ini = case / "modelsim.ini"
    run([MS / "vmap.exe", "-c"], case, case / "vmap_create.log", 300)
    run([MS / "vlib.exe", p(case / "work")], case, case / "vlib.log", 300)
    run([MS / "vmap.exe", "-modelsimini", p(ini), "work", p(case / "work")], case, case / "vmap.log", 300)
    rc = run([MS / "vlog.exe", "-modelsimini", p(ini), "-work", "work", "-sv",
              "+define+SIMULATION"] + FILES, case, case / "compile.log", 1800)
    errs = [l for l in (case / "compile.log").read_text(errors="replace").splitlines()
            if "** Error" in l]
    if rc or errs:
        print("%s COMPILE_FAIL rc=%s errors=%d" % (name, rc, len(errs)), flush=True)
        for l in errs[:10]:
            print("  " + l, flush=True)
        return None
    (case / "simulate.do").write_text(
        "onbreak {quit -code 2}\nonerror {quit -code 2}\nrun -all\nquit -code 0\n",
        encoding="ascii")
    run([MS / "vsim.exe", "-c", "-modelsimini", p(ini), "-wlf", p(case / "simulation.wlf"),
         "-l", p(case / "transcript.log"), "-voptargs=+acc", "work.tb_b10_multi_strict",
         "-gNFRAMES=%d" % nframes, "-gSTA_DIV=%d" % sts,
         "+OUT=" + p(case / "capture.dec"), "+WIRE=" + p(case / "wire.dec"),
         "+TRACE=" + p(case / "trace.txt"), "+STAT=" + p(case / "stats.txt"),
         "-do", "do " + p(case / "simulate.do")], case, case / "console.log", 3600)
    rc = run([sys.executable, "-B", HERE / "check_strict.py", case], HERE,
             case / "checker.log", 600)
    print("%s checker_exit=%d" % (name, rc), flush=True)
    return rc


def main():
    out = {}
    for name, n, sts in (("control", 1, 0), ("triple", 3, 10000)):
        rc = execute(name, n, sts)
        res = dict(case=name, checker_exit=rc, status="PASS" if rc == 0 else "FAIL")
        rj = HERE / name / "result.json"
        if rj.exists():
            res["result"] = json.loads(rj.read_text())
        out[name] = res
        print("%s -> %s" % (name, res["status"]), flush=True)
    out["source_sha256"] = {p_.name: hashlib.sha256(p_.read_bytes()).hexdigest()
                            for p_ in FILES[:7]}
    ((OUTROOT / "summary.json")).write_text(json.dumps(out, indent=2), encoding="utf-8")
    ok = all(v.get("status") == "PASS" for k, v in out.items() if k in ("control", "triple"))
    print("T10_STATUS %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
