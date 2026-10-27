#!/usr/bin/env python3
"""run_b12.py -- T10.b12-r1-last fixed RTL simulator driver (ModelSim ASE 10.5b).

Groups (one per process so they can run in parallel; every child has a real
timeout and every result is written to r0/sim/sim-results-b12.json):

  r1b11   R1 counterexample on the frozen b11 r0 changed-src (must FAIL)
  r1      R1 fix on the b12 changed-src: T1 clean + T2 loss (must PASS)
  t7      T7 SOF-reject / head-of-line drain (top level, B12 RTL)
  store   T3/T4/T5/T6 directed a1_ddr_slot_store cases (B12 RTL)
  b9      T8/T9 b9 rawstore regressions abort/nofree/rdy at the b9 geometry
  main    v4 packet, P1 three goldens, b11 read nine cases, full two frames
  multi   T10 triple small-geometry frame sequence (v4 status packets)
"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
R0 = RUN / "T10.b12-r1-last/r0"
CS = R0 / "changed-src"
SIM = R0 / "sim"
IND = SIM / "indep"
LOGS = SIM / "logs"
CAPS = SIM / "caps"
CASE = SIM / "cases"
CSI = ROOT / "fpga/csi2"
B11 = RUN / "T10.b11-aplus-read/r0"
B9 = RUN / "T10.b9-rawstore/r0"
GOLD = RUN / "T10.b5-a1-htab-pipe/r0/sim/captures"
INDEP_W = ROOT / "work/b10-gap-sim-20261025-132023"

MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
SCRATCH = pathlib.Path(r"C:\Users\czz\AppData\Local\Temp\opencode\b12")
RESULTS = SIM / "sim-results-b12.json"

B12_FILES = [CS / n for n in ("a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v",
                              "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
                              "a1_deflate_core.v")]
B11_FILES = [B11 / "changed-src" / n for n in ("a1_raw_crop.v", "a1_ddr_slot_store.v",
                                              "a1_uart_export.v", "camera_a1_uart_top.v",
                                              "cam_diag_mailbox.v", "a1_frame_top.v",
                                              "a1_deflate_core.v")]
DEPS = [CSI / "src/a1/a1_ddr_arb2.v", CSI / "src/mem/capture_async_fifo.v"]

P1_CASES = [
    ("micro8x2", ["-gW=8", "-gH=2", "-gCAM_W=32", "-gCAM_H=4", "-gROI_X=4", "-gROI_Y=2", "-gUART_DIV=1"]),
    ("mid64x8", ["-gW=64", "-gH=8", "-gCAM_W=128", "-gCAM_H=16", "-gROI_X=0", "-gROI_Y=0", "-gUART_DIV=1"]),
    ("full_grad", []),
]
READ_CASES = {
    "read_one":   (["+NAME=one"],   ["-gNWRITE=1"]),
    "read_multi": (["+NAME=multi"], ["-gNWRITE=2000"]),
    "read_bp":    (["+NAME=bp"],    ["-gNWRITE=2000", "-gAR_GAP=2", "-gR_GAP=12"]),
    "read_late":  (["+NAME=late"],  ["-gNWRITE=2000", "-gR_GAP=40"]),
    "read_stray": (["+NAME=stray"], ["-gNWRITE=2000", "-gSTRAY_R=1"]),
    "read_dup":   (["+NAME=dup"],   ["-gNWRITE=9000", "-gDUP_R=1"]),
    "read_reset": (["+NAME=reset"], ["-gNWRITE=2000", "-gDO_RESET=1"]),
    "read_full":  (["+NAME=full"],  ["-gNWRITE=129600"]),
}


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def record(res, group):
    path = SIM / ("sim-results-b12-%s.json" % group)
    path.write_text(json.dumps(res, indent=2))


def run(args, cwd, log, timeout):
    t0 = time.monotonic()
    out = pathlib.Path(str(log) + ".out")
    with open(out, "w", encoding="utf-8", errors="replace") as lf:
        try:
            pr = subprocess.run([str(a).replace("\\", "/") for a in args], cwd=str(cwd), stdout=lf,
                                stderr=subprocess.STDOUT, timeout=timeout,
                                env={**os.environ, "PATH": str(MS) + os.pathsep + os.environ.get("PATH", "")})
            rc = pr.returncode
        except subprocess.TimeoutExpired:
            rc = 124
    return rc, round(time.monotonic() - t0, 1)


def build(name, files):
    work = SCRATCH / name
    lib = work / "work"
    work.mkdir(parents=True, exist_ok=True)
    ini = work / "modelsim.ini"
    ini.write_text("[Library]\nwork = " + lib.as_posix() + "\n\n[vsim]\nResolution = ps\n", encoding="ascii")
    LOGS.mkdir(parents=True, exist_ok=True)
    if not lib.exists():
        rc, el = run([MS / "vlib.exe", lib], work, LOGS / ("vlib_%s.log" % name), 300)
        print("[%s] vlib rc=%d %.1fs" % (name, rc, el), flush=True)
        if rc != 0:
            raise SystemExit("vlib failed")
    rc, el = run([MS / "vlog.exe", "-modelsimini", ini, "-sv", "-work", "work",
                  "+define+SIMULATION"] + list(files), work, LOGS / ("vlog_%s.log" % name), 1800)
    txt = pathlib.Path(str(LOGS / ("vlog_%s.log.out" % name))).read_text(errors="replace")
    errs = [l for l in txt.splitlines() if "** Error" in l]
    print("[%s] compile rc=%d %.1fs errors=%d" % (name, rc, el, len(errs)), flush=True)
    for l in errs[:20]:
        print("   " + l, flush=True)
    return (work, ini) if rc == 0 and not errs else (None, None)


def vsim(name, work, ini, top, plus, log, timeout, generics=None):
    args = [MS / "vsim.exe", "-c", "-modelsimini", ini, "-lib", "work", "-voptargs=+acc",
            "-l", log, top] + list(plus) + list(generics or []) + ["-do", "run -all; quit -f"]
    rc, el = run(args, work, log, timeout)
    txt = pathlib.Path(log).read_text(errors="replace") if pathlib.Path(log).exists() else ""
    return rc, el, txt


def grp_r1(tag, srcfiles, cases):
    work, ini = build(tag, srcfiles + [IND / "ddr_recovery_model.sv", IND / "tb_r1_loss.sv"])
    if work is None:
        return {"%s_build" % tag: dict(case="%s_build" % tag, ok=False, errors="compile failed")}
    out = {}
    for case_id, cname in cases:
        d = CASE / tag / cname
        d.mkdir(parents=True, exist_ok=True)
        log = LOGS / ("sim_%s_%s.log" % (tag, cname))
        rc, el, txt = vsim(tag, work, ini, "tb_r1_loss",
                           ["+CASE=%d" % case_id, "+OUT=" + (d / "capture.dec").as_posix(),
                            "+UART=" + (d / "uart.dec").as_posix(),
                            "+TRACE=" + (d / "trace.txt").as_posix(),
                            "+STAT=" + (d / "stats.txt").as_posix()],
                           log, 3600)
        (d / "console.log").write_bytes(pathlib.Path(log).read_bytes())
        crc, cel = run([sys.executable, IND / "check_r1.py", d], d, LOGS / ("check_%s_%s.log" % (tag, cname)), 600)
        res = json.loads((d / "result.json").read_text()) if (d / "result.json").exists() else {}
        out["%s_%s" % (tag, cname)] = dict(case="%s_%s" % (tag, cname), exit=rc, check_exit=crc,
                                           seconds=el, status=res.get("status"),
                                           errors=res.get("errors"), stats=res.get("stats"),
                                           failure_evidence=res.get("failure_evidence"),
                                           log=log.as_posix(), case_dir=d.as_posix())
        print("[%s/%s] vsim=%d check=%d status=%s" % (tag, cname, rc, crc, res.get("status")), flush=True)
        if res.get("errors"):
            print("   errors: %s" % res["errors"][:4], flush=True)
    return out


def grp_t7():
    work, ini = build("t7", B12_FILES + DEPS +
                      [IND / "ddr_recovery_model.sv", IND / "tb_r1_loss.sv", SIM / "tb_r1_sof.v"])
    if work is None:
        return {"t7": dict(case="t7", ok=False, errors="compile failed")}
    d = CASE / "t7"
    d.mkdir(parents=True, exist_ok=True)
    log = LOGS / "sim_t7.log"
    rc, el, txt = vsim("t7", work, ini, "tb_r1_sof",
                       ["+OUT=" + (d / "capture.dec").as_posix(),
                        "+UART=" + (d / "uart.dec").as_posix(),
                        "+TRACE=" + (d / "trace.txt").as_posix(),
                        "+STAT=" + (d / "stats.txt").as_posix()], log, 3600)
    (d / "console.log").write_bytes(pathlib.Path(log).read_bytes())
    crc, cel = run([sys.executable, SIM / "check_t7.py", d], d, LOGS / "check_t7.log", 600)
    res = json.loads((d / "result.json").read_text()) if (d / "result.json").exists() else {}
    print("[t7] vsim=%d check=%d status=%s %s" % (rc, crc, res.get("status"), res.get("errors")), flush=True)
    return {"t7": dict(case="t7", exit=rc, check_exit=crc, seconds=el, status=res.get("status"),
                       errors=res.get("errors"), stats=res.get("stats"), decoded=res.get("decoded"),
                       log=log.as_posix(), case_dir=d.as_posix())}


def grp_store():
    work, ini = build("store", [CS / "a1_ddr_slot_store.v", SIM / "tb_store_r1.v"])
    if work is None:
        return {"store_build": dict(case="store_build", ok=False, errors="compile failed")}
    out = {}
    for cname in ("t3", "t4", "t5", "t6"):
        log = LOGS / ("sim_store_%s.log" % cname)
        rc, el, txt = vsim("store", work, ini, "tb_store_r1", ["+CASE=" + cname], log, 1800)
        line = [l.strip() for l in txt.splitlines() if l.startswith("# RESULT") or "RESULT case=" in l]
        ok = bool(line) and "pass=1" in line[-1]
        out["store_" + cname] = dict(case="store_" + cname, exit=rc, seconds=el, ok=bool(ok),
                                     result=line[-1] if line else "NO_RESULT", log=log.as_posix())
        print("[store/%s] vsim=%d pass=%s | %s" % (cname, rc, ok, line[-1] if line else "-"), flush=True)
    return out


def grp_b9():
    work, ini = build("b9", [CS / "a1_ddr_slot_store.v", B9 / "td/src/p2_ddr_bridge.v",
                             CSI / "src/mem/capture_async_fifo.v",
                             SIM / "p2_paxi_model.v", SIM / "tb_raw_store.v"])
    if work is None:
        return {"b9_build": dict(case="b9_build", ok=False, errors="compile failed")}
    out = {}
    for cname in ("abort", "nofree", "rdy"):
        log = LOGS / ("sim_rawstore_%s.log" % cname)
        rc, el, txt = vsim("b9", work, ini, "tb_raw_store", ["+CASE=" + cname], log, 3600)
        line = [l.strip() for l in txt.splitlines() if "RESULT case=" in l]
        ok = bool(line) and "pass=1" in line[-1]
        out["b9_" + cname] = dict(case="b9_" + cname, exit=rc, seconds=el, ok=bool(ok),
                                  result=line[-1] if line else "NO_RESULT", log=log.as_posix())
        print("[b9/%s] vsim=%d pass=%s | %s" % (cname, rc, ok, line[-1] if line else "-"), flush=True)
    return out


def grp_main():
    files = B12_FILES + DEPS + [CS / "p2_ddr_bridge.v", SIM / "p2_paxi_model_b11.v",
                                SIM / "a1_ddr_model.v", SIM / "tb_p1_chain.v",
                                SIM / "tb_b11_read.sv", SIM / "tb_status_v4.v", SIM / "tb_b11_full.v"]
    work, ini = build("main", files)
    if work is None:
        return {"main_build": dict(case="main_build", ok=False, errors="compile failed")}
    out = {}
    which = sys.argv[2:] or ["v4", "p1", "read", "full"]
    if "v4" in which:
        log = LOGS / "sim_status_v4.log"
        rc, el, txt = vsim("main", work, ini, "tb_status_v4", [], log, 600)
        mk = [l.strip() for l in txt.splitlines() if "B11_V4_" in l]
        ok = ("B11_V4_RESULT pass=1" in txt) and ("B10_ASSERT_FAIL" not in txt)
        out["v4"] = dict(case="v4", ok=bool(ok), exit=rc, seconds=el, markers=mk)
        print("[v4] ok=%s rc=%d %.1fs | %s" % (ok, rc, el, " | ".join(mk[-2:])), flush=True)
    if "p1" in which:
        for name, gens in P1_CASES:
            dec = CAPS / (name + ".dec")
            stp = CAPS / (name + ".stats")
            log = LOGS / ("sim_p1_" + name + ".log")
            rc, el, txt = vsim("main", work, ini, "tb_camera_a1_uart_top",
                               ["+MODE=0", "+OUT=" + dec.as_posix(), "+STAT=" + stp.as_posix()],
                               log, 3600, generics=gens)
            s = sha(dec)
            gsha = sha(GOLD / (name + ".dec"))
            ok = (s == gsha) and rc == 0
            out["p1_" + name] = dict(case="p1_" + name, ok=bool(ok), exit=rc, seconds=el,
                                     sha256=s, gold_sha256=gsha, byte_identical=(s == gsha))
            print("[p1 %s] identical=%s rc=%d %.1fs sha=%s" % (name, s == gsha, rc, el, s[:16]), flush=True)
    if "read" in which:
        for cname, (plus, gens) in READ_CASES.items():
            log = LOGS / ("sim_%s.log" % cname)
            rc, el, txt = vsim("main", work, ini, "tb_b11_read", plus, log, 3600, generics=gens)
            mk = [l.strip() for l in txt.splitlines() if "B11_READ_" in l]
            ok = ("B11_READ_RESULT" in txt) and ("pass=1" in txt.split("B11_READ_RESULT")[-1])
            out[cname] = dict(case=cname, ok=bool(ok), exit=rc, seconds=el, markers=mk)
            print("[%s] ok=%s rc=%d %.1fs | %s" % (cname, ok, rc, el, " | ".join(mk[-1:])), flush=True)
    if "full" in which:
        stp = CAPS / "full.stats"
        log = LOGS / "sim_full.log"
        rc, el, txt = vsim("main", work, ini, "tb_b11_full", ["+STAT=" + stp.as_posix()], log, 7200)
        mk = [l.strip() for l in txt.splitlines() if "B11_FULL_" in l]
        ok = "B11_FULL_RESULT pass=1" in txt
        out["full"] = dict(case="full", ok=bool(ok), exit=rc, seconds=el, markers=mk)
        print("[full] ok=%s rc=%d %.1fs | %s" % (ok, rc, el, " | ".join(mk[-3:])), flush=True)
    return out


def grp_multi():
    work, ini = build("multi", B12_FILES + DEPS +
                      [SIM / "a1_ddr_model.v", SIM / "tb_b10_multi_b12.sv"])
    if work is None:
        return {"multi_build": dict(case="multi_build", ok=False, errors="compile failed")}
    out = {}
    for name, n, sts in (("control", 1, 0), ("triple", 3, 25000)):
        d = CASE / "multi" / name
        d.mkdir(parents=True, exist_ok=True)
        log = LOGS / ("sim_multi_%s.log" % name)
        rc, el, txt = vsim("multi", work, ini, "tb_b10_multi_strict",
                           ["+OUT=" + (d / "capture.dec").as_posix(),
                            "+WIRE=" + (d / "wire.dec").as_posix(),
                            "+TRACE=" + (d / "trace.txt").as_posix(),
                            "+STAT=" + (d / "stats.txt").as_posix()],
                           log, 3600, generics=["-gNFRAMES=%d" % n, "-gSTA_DIV=%d" % sts])
        (d / "console.log").write_bytes(pathlib.Path(log).read_bytes())
        crc, cel = run([sys.executable, SIM / "check_multi_b12.py", d], d, LOGS / ("check_multi_%s.log" % name), 600)
        res = json.loads((d / "result.json").read_text()) if (d / "result.json").exists() else {}
        out["multi_" + name] = dict(case="multi_" + name, exit=rc, check_exit=crc, seconds=el,
                                    status=res.get("status"), errors=res.get("errors"),
                                    stats=res.get("stats"),
                                    statuses=len(res.get("decoded", {}).get("statuses", [])),
                                    frames=len(res.get("decoded", {}).get("frames", [])),
                                    case_dir=d.as_posix(), log=log.as_posix())
        print("[multi/%s] vsim=%d check=%d status=%s statuses=%d frame_sha=%s errors=%s" %
              (name, rc, crc, res.get("status"), len(res.get("decoded", {}).get("statuses", [])),
               [f["raw_sha256"][:8] for f in res.get("decoded", {}).get("frames", [])],
               (res.get("errors") or [])[:3]), flush=True)
    return out


def main():
    group = sys.argv[1] if len(sys.argv) > 1 else "r1"
    CAPS.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    CASE.mkdir(parents=True, exist_ok=True)
    if group == "r1b11":
        res = grp_r1("r1b11", B11_FILES + DEPS, [(0, "clean"), (1, "loss")])
    elif group == "r1":
        res = grp_r1("r1", B12_FILES + DEPS, [(0, "clean"), (1, "loss")])
    elif group == "t7":
        res = grp_t7()
    elif group == "store":
        res = grp_store()
    elif group == "b9":
        res = grp_b9()
    elif group == "main":
        res = grp_main()
    elif group == "multi":
        res = grp_multi()
    else:
        raise SystemExit("unknown group " + group)
    record(res, group)
    print("GROUP_DONE %s %s" % (group, json.dumps({k: (v.get("ok", v.get("status")))
                                                   for k, v in res.items()})), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
