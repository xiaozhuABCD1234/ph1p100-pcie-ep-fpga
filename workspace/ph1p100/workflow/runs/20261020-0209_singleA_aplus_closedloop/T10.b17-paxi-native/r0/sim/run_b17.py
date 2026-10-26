#!/usr/bin/env python3
"""run_b17.py -- T10.b17-paxi-native ModelSim driver (ASE 10.5b).

Groups:
  native  16-word native boundary test + mask/address/b15/concurrency negatives
  status  v6 status packet structure (273 B / 67 fields)
  chain   tb_b17_chain + check_b17.py  (s1_full_clean / s2_full_two / s3_drop1)
  p1      P1 three goldens on the b17 RTL (byte-identical compressed streams)

Every case writes r0/sim/cases/<...>/ and a group result to
r0/sim/sim-results-b17-<group>.json.  Temporary work libraries live only under
%TEMP%/opencode/T10.b17-paxi-native/.
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
R0 = RUN / "T10.b17-paxi-native/r0"
SIM = R0 / "sim"
CS = R0 / "changed-src"
CSI = ROOT / "fpga/csi2"
MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
SCRATCH = pathlib.Path(os.environ.get("TEMP", r"C:\Users\czz\AppData\Local\Temp")) / \
    "opencode/T10.b17-paxi-native"
LOGS = SIM / "logs"
CASE = SIM / "cases"
CAPS = SIM / "caps"

SRC = [CS / n for n in ("a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_ddr_arb2.v",
                        "a1_uart_export.v", "camera_a1_uart_top.v",
                        "cam_diag_mailbox.v", "a1_frame_top.v", "a1_deflate_core.v")]
DEPS = [CS / "p2_ddr_bridge.v", CSI / "src/mem/capture_async_fifo.v"]

FULL = {"W": 1920, "H": 1080, "CAM_W": 3864, "CAM_H": 2192, "ROI_X": 972, "ROI_Y": 556}
SMALL = {"CAM_W": 72, "CAM_H": 10, "ROI_X": 4, "ROI_Y": 2, "W": 64, "H": 8}

CHAIN_CASES = {
    "s1_full_clean": (FULL, 1, 90000000, {},
                      {"exported": 1, "timeout": 0, "retry": 0, "giveup": 0, "stale": 0},
                      {"b15_short_burst": 0, "b15_stale_r": 0,
                       "b15_ar_minus_rlast_max": 1, "b15_full_frame": 1, "b17_bit0": 0}),
    "s2_full_two": (FULL, 2, 130000000, {},
                    {"exported": 2, "timeout": 0, "retry": 0, "giveup": 0, "stale": 0},
                    {"b15_short_burst": 0, "b15_stale_r": 0,
                     "b15_ar_minus_rlast_max": 1, "b17_bit0": 0}),
    "s3_drop1": (SMALL, 1, 4000000, {"DROP_ADDR": 16, "DROP_OCC": 1},
                 {"exported": 1, "timeout": 1, "retry": 1, "giveup": 0},
                 {"b15_purge_close_min": 1, "b15_ar_minus_rlast_max": 1, "b17_bit0": 1}),
}


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def run(args, cwd, log, timeout):
    t0 = time.monotonic()
    out = pathlib.Path(str(log) + ".out")
    with open(out, "w", encoding="utf-8", errors="replace") as lf:
        try:
            pr = subprocess.run([str(a).replace("\\", "/") for a in args], cwd=str(cwd),
                                stdout=lf, stderr=subprocess.STDOUT, timeout=timeout,
                                env={**os.environ,
                                     "PATH": str(MS) + os.pathsep + os.environ.get("PATH", "")})
            rc = pr.returncode
        except subprocess.TimeoutExpired:
            rc = 124
    return rc, round(time.monotonic() - t0, 1)


def build(name, files, sv=True):
    work = SCRATCH / name
    lib = work / "work"
    work.mkdir(parents=True, exist_ok=True)
    ini = work / "modelsim.ini"
    ini.write_text("[Library]\nwork = " + lib.as_posix() + "\n\n[vsim]\nResolution = ps\n",
                   encoding="ascii")
    LOGS.mkdir(parents=True, exist_ok=True)
    if not lib.exists():
        rc, el = run([MS / "vlib.exe", lib], work, LOGS / ("vlib_%s.log" % name), 300)
        if rc != 0:
            return None, None
    cmd = [MS / "vlog.exe", "-modelsimini", ini.as_posix()]
    if sv:
        cmd.append("-sv")
    cmd += ["-work", "work", "+define+SIMULATION"] + list(files)
    rc, el = run(cmd, work, LOGS / ("vlog_%s.log" % name), 1800)
    txt = pathlib.Path(str(LOGS / ("vlog_%s.log.out" % name))).read_text(errors="replace")
    errs = [l for l in txt.splitlines() if "** Error" in l]
    print("[%s] compile rc=%d %.1fs errors=%d" % (name, rc, el, len(errs)), flush=True)
    for l in errs[:10]:
        print("   " + l, flush=True)
    return (work, ini) if rc == 0 and not errs else (None, None)


def vsim(name, work, ini, top, plus, log, timeout, generics=None):
    args = [MS / "vsim.exe", "-c", "-modelsimini", ini.as_posix(), "-lib", "work",
            "-voptargs=+acc", "-l", log, top] + list(plus) + list(generics or []) + \
           ["-do", "run -all; quit -f"]
    rc, el = run(args, work, log, timeout)
    txt = pathlib.Path(log).read_text(errors="replace") if pathlib.Path(log).exists() else ""
    return rc, el, txt


def grp_native():
    work, ini = build("b17native", [CSI / "src/mem/capture_async_fifo.v",
                                    CS / "cam_diag_mailbox.v", CS / "p2_ddr_bridge.v",
                                    SIM / "p2_paxi_model_b17.v",
                                    SIM / "neg/p2_ddr_bridge_b15.v",
                                    SIM / "tb_b17_paxi_native.sv"])
    if work is None:
        return {"native_build": dict(case="native_build", ok=False)}
    out = {}
    for c in ("main", "mask", "addr", "conc", "b15"):
        log = LOGS / ("b17_native_%s.log" % c)
        rc, el, txt = vsim("b17native", work, ini, "tb_b17_paxi_native",
                           ["+CASE=%s" % c], log, 900)
        mk = [l.strip() for l in txt.splitlines() if "B17_" in l and "RESULT" in l]
        ok = ("pass=1" in txt) and ("B17_CASE_DONE" in txt) and (rc == 0)
        out["native_" + c] = dict(case=c, ok=bool(ok), exit=rc, seconds=el,
                                  markers=mk, log=log.as_posix())
        print("[native/%s] ok=%s rc=%d %.1fs | %s" % (c, ok, rc, el, mk[-1:] ), flush=True)
    return out


def grp_status():
    work, ini = build("b17status", [CS / "a1_uart_export.v", SIM / "tb_status_v6.v"])
    if work is None:
        return {"status_build": dict(case="status_build", ok=False)}
    log = LOGS / "b17_status_v6.log"
    rc, el, txt = vsim("b17status", work, ini, "tb_status_v6", [], log, 900)
    mk = [l.strip() for l in txt.splitlines() if "B17_V6_" in l]
    ok = ("B17_V6_RESULT pass=1" in txt) and ("B17_V6_BAD" not in txt)
    print("[status/v6] ok=%s rc=%d %.1fs | %s" % (ok, rc, el, " | ".join(mk[-2:])), flush=True)
    return {"v6": dict(case="v6", ok=bool(ok), exit=rc, seconds=el, markers=mk,
                       log=log.as_posix())}


def grp_chain(only):
    files = SRC + DEPS + [SIM / "p2_paxi_model_b17.v", SIM / "tb_b17_chain.sv"]
    work, ini = build("b17chain", files)
    if work is None:
        return {"chain_build": dict(case="chain_build", ok=False)}
    out = {}
    for name, (geom, n, maxc, inj, exp, bexp) in CHAIN_CASES.items():
        if only and name not in only:
            continue
        d = CASE / "b17chain" / name
        d.mkdir(parents=True, exist_ok=True)
        log = LOGS / ("b17_chain_%s.log" % name)
        g = ["-gW=%d" % geom["W"], "-gH=%d" % geom["H"],
             "-gCAM_W=%d" % geom["CAM_W"], "-gCAM_H=%d" % geom["CAM_H"],
             "-gROI_X=%d" % geom["ROI_X"], "-gROI_Y=%d" % geom["ROI_Y"],
             "-gNFRAMES=%d" % n, "-gMAX_CYCLES=%d" % maxc,
             "-gUART_DIV=1", "-gSTA_DIV=25000"]
        g += ["-g%s=%d" % (k, v) for k, v in inj.items()]
        rc, el, txt = vsim("b17chain", work, ini, "tb_b17_chain",
                           ["+OUT=" + (d / "capture.dec").as_posix(),
                            "+WIRE=" + (d / "wire.dec").as_posix(),
                            "+TRACE=" + (d / "trace.txt").as_posix(),
                            "+STAT=" + (d / "stats.txt").as_posix()],
                           log, 2700, generics=g)
        (d / "console.log").write_bytes(pathlib.Path(log).read_bytes())
        cargs = [sys.executable, str(SIM / "check_b17.py"), str(d)] + \
                ["%s=%d" % (k, v) for k, v in exp.items()] + \
                ["%s=%d" % (k, v) for k, v in bexp.items()]
        crc, cel = run(cargs, d, LOGS / ("b17_check_%s.log" % name), 3600)
        res = json.loads((d / "result.json").read_text()) if (d / "result.json").exists() else {}
        out["chain_" + name] = dict(case=name, exit=rc, check_exit=crc, seconds=el,
                                    status=res.get("status"), errors=res.get("errors"),
                                    stats=res.get("stats"), b17=res.get("b17"),
                                    b17_status=res.get("b17_status"),
                                    expectations={**exp, **bexp},
                                    frames=[f.get("seed") for f in
                                            res.get("decoded", {}).get("frames", [])],
                                    statuses=len(res.get("decoded", {}).get("statuses", [])),
                                    case_dir=d.as_posix(), log=log.as_posix())
        print("[chain/%s] vsim=%d check=%d status=%s exp=%s err=%s" %
              (name, rc, crc, res.get("status"), res.get("stats", {}).get("exported"),
               (res.get("errors") or [])[:3]), flush=True)
    return out


def grp_p1():
    work, ini = build("b17p1", SRC + [CSI / "src/mem/capture_async_fifo.v",
                                     SIM / "a1_ddr_model.v", SIM / "tb_p1_chain.v"])
    if work is None:
        return {"p1_build": dict(case="p1_build", ok=False)}
    out = {}
    cases = [("micro8x2", ["-gW=8", "-gH=2", "-gCAM_W=32", "-gCAM_H=4",
                           "-gROI_X=4", "-gROI_Y=2", "-gUART_DIV=1"]),
             ("mid64x8", ["-gW=64", "-gH=8", "-gCAM_W=128", "-gCAM_H=16",
                          "-gROI_X=0", "-gROI_Y=0", "-gUART_DIV=1"]),
             ("full_grad", [])]
    for name, gens in cases:
        dec = CASE / "b17p1" / (name + ".dec")
        dec.parent.mkdir(parents=True, exist_ok=True)
        stp = CASE / "b17p1" / (name + ".stats")
        log = LOGS / ("b17_p1_%s.log" % name)
        rc, el, txt = vsim("b17p1", work, ini, "tb_camera_a1_uart_top",
                           ["+MODE=0", "+OUT=" + dec.as_posix(),
                            "+STAT=" + stp.as_posix()], log, 3600, generics=gens)
        s, gsha = sha(dec), sha(CAPS / (name + ".dec"))
        ok = (s == gsha) and rc == 0
        out["p1_" + name] = dict(case="p1_" + name, ok=bool(ok), exit=rc, seconds=el,
                                 sha256=s, gold_sha256=gsha, byte_identical=(s == gsha),
                                 log=log.as_posix())
        print("[p1 %s] identical=%s rc=%d %.1fs sha=%s" %
              (name, s == gsha, rc, el, s[:16]), flush=True)
    return out


def main():
    group = sys.argv[1] if len(sys.argv) > 1 else "native"
    for p in (LOGS, CASE, CAPS):
        p.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[2:])
    if group == "native":
        res = grp_native()
    elif group == "status":
        res = grp_status()
    elif group == "chain":
        res = grp_chain(only)
    elif group == "p1":
        res = grp_p1()
    else:
        raise SystemExit("unknown group " + group)
    tag = group if not (group == "chain" and only) else "chain-" + "-".join(sorted(only))
    (SIM / ("sim-results-b17-%s.json" % tag)).write_text(json.dumps(res, indent=2))
    print("GROUP_DONE %s %s" % (tag, json.dumps(
        {k: (v.get("ok", v.get("status"))) for k, v in res.items()})), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
