#!/usr/bin/env python3
"""run_b18.py -- T10.b18-b17-b ModelSim ASE driver.

Groups:
  merge   W:  nothing (placeholder, uses check_merge_b18.py)
  camsel  stub-top structural test of the REAL merged p2_a1_board_top:
          CAM_SEL bit12, B tap selected (C18 / T5)
  native  16-word native readback + mask/addr/b15/concurrency negatives (T2)
  status  v6 packet structure 273/6/67 + field #13 bit12 (T5)
  p1      P1 three goldens byte-identical (T3)
  chain   t1_b_geometry (T1) / t4a_drop1 (T4) / t4b_drop_mid3 (T4)

Temporary work libraries live only under %TEMP%/opencode/T10.b18-b17-b/.
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
R0 = RUN / "T10.b18-b17-b/r0"
SIM = R0 / "sim"
CS = R0 / "changed-src"
CSI = ROOT / "fpga/csi2"
MS = pathlib.Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
SCRATCH = pathlib.Path(os.environ.get("TEMP", r"C:\Users\czz\AppData\Local\Temp")) / \
    "opencode/T10.b18-b17-b"
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
    # T1: b14 S1 stimulus shape (full 1080p B geometry)
    "t1_b_geometry": (FULL, 1, 90000000, {},
                      {"exported": 1, "timeout": 0, "retry": 0, "giveup": 0, "stale": 0},
                      {"b15_short_burst": 0, "b15_stale_r": 0,
                       "b15_ar_minus_rlast_max": 1, "b15_full_frame": 1, "b17_bit0": 0}),
    # T4a: frozen b17 drop-1-R stimulus (single frame, timeout -> retry -> export)
    "t4a_drop1": (SMALL, 1, 4000000, {"DROP_ADDR": 16, "DROP_OCC": 1},
                  {"exported": 1, "timeout": 1, "retry": 1, "giveup": 0},
                  {"b15_purge_close_min": 1, "b15_ar_minus_rlast_max": 1, "b17_bit0": 1}),
    # T4b: three frames, the first read of native address 16 dropped once
    # (timeout -> retry -> recovery) while the run keeps going; all three frames
    # export.  A two-drop variant was also run: 3/3 frames recovered, but the
    # inherited b17 gate "at most one AR unanswered at rest" rejects two injected
    # drops by construction, so the accepted case keeps exactly one drop.
    "t4b_drop_mid3": (SMALL, 3, 8000000, {"DROP_ADDR": 16, "DROP_OCC": 1},
                      {"exported": 3, "timeout": 1, "retry": 1, "giveup": 0},
                      {"b15_purge_close_min": 1, "b17_bit0": 1}),
}
# T1 geometry gate (dev-plan S2 / design guide 1)
T1_GEOM = {"pix_beats": 2117472, "line_rises": 2192, "frame_rises": 1,
           "frame_falls": 1, "crop_roi_frames": 1, "crop_groups": 518400,
           "raw_len": 2592000}


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


def grp_camsel():
    files = sorted((SIM / "stub").glob("*_stub.v")) + \
        [CS / "cam_diag_mailbox.v", CS / "p2_a1_board_top.v", SIM / "tb_b18_camsel.sv"]
    work, ini = build("b18camsel", files)
    if work is None:
        return {"camsel_build": dict(case="camsel_build", ok=False)}
    log = LOGS / "b18_camsel.log"
    rc, el, txt = vsim("b18camsel", work, ini, "tb_b18_camsel", [], log, 300)
    mk = [l.strip() for l in txt.splitlines() if "B18_CAMSEL_" in l]
    ok = ("B18_CAMSEL_RESULT pass=1" in txt) and rc == 0
    return {"camsel_main": dict(case="camsel", ok=bool(ok), exit=rc, seconds=el,
                                bit12=("bit12=1" in txt),
                                b_selected=("b_selected=1" in txt),
                                markers=mk, log=log.as_posix())}


def grp_native():
    work, ini = build("b18native", [CSI / "src/mem/capture_async_fifo.v",
                                    CS / "cam_diag_mailbox.v", CS / "p2_ddr_bridge.v",
                                    SIM / "p2_paxi_model_b17.v",
                                    SIM / "neg/p2_ddr_bridge_b15.v",
                                    SIM / "tb_b17_paxi_native.sv"])
    if work is None:
        return {"native_build": dict(case="native_build", ok=False)}
    out = {}
    for c in ("main", "mask", "addr", "conc", "b15"):
        log = LOGS / ("b18_native_%s.log" % c)
        rc, el, txt = vsim("b18native", work, ini, "tb_b17_paxi_native",
                           ["+CASE=%s" % c], log, 900)
        mk = [l.strip() for l in txt.splitlines() if "B17_" in l and "RESULT" in l]
        ok = ("pass=1" in txt) and ("B17_CASE_DONE" in txt) and (rc == 0)
        out["native_" + c] = dict(case=c, ok=bool(ok), exit=rc, seconds=el,
                                  markers=mk, log=log.as_posix())
        print("[native/%s] ok=%s rc=%d %.1fs" % (c, ok, rc, el), flush=True)
    return out


def grp_status():
    work, ini = build("b18status", [CS / "a1_uart_export.v", SIM / "tb_status_v6.v"])
    if work is None:
        return {"status_build": dict(case="status_build", ok=False)}
    log = LOGS / "b18_status_v6.log"
    rc, el, txt = vsim("b18status", work, ini, "tb_status_v6", [], log, 900)
    mk = [l.strip() for l in txt.splitlines() if "B18_V6_" in l or "B17_V6_DONE" in l]
    f13 = [l.split("f13=")[-1] for l in mk if "F13" in l]
    ok = ("B17_V6_RESULT pass=1" in txt and "B18_V6_F13_BIT12_OK" in txt and rc == 0)
    return {"v6": dict(case="v6", ok=bool(ok), exit=rc, seconds=el, markers=mk,
                       f13=f13[0] if f13 else None, log=log.as_posix())}


def grp_p1():
    work, ini = build("b18p1", SRC + [CSI / "src/mem/capture_async_fifo.v",
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
        dec = CASE / "b18p1" / (name + ".dec")
        dec.parent.mkdir(parents=True, exist_ok=True)
        stp = CASE / "b18p1" / (name + ".stats")
        log = LOGS / ("b18_p1_%s.log" % name)
        rc, el, txt = vsim("b18p1", work, ini, "tb_camera_a1_uart_top",
                           ["+MODE=0", "+OUT=" + dec.as_posix(),
                            "+STAT=" + stp.as_posix()], log, 3600, generics=gens)
        s, gsha = sha(dec), sha(CAPS / (name + ".dec"))
        ok = (s == gsha) and rc == 0
        out["p1_" + name] = dict(case="p1_" + name, ok=bool(ok), exit=rc, seconds=el,
                                 sha256=s, gold_sha256=gsha, byte_identical=(s == gsha),
                                 log=log.as_posix())
        print("[p1 %s] identical=%s rc=%d %.1fs" % (name, s == gsha, rc, el), flush=True)
    return out


def grp_chain(only):
    files = SRC + DEPS + [SIM / "p2_paxi_model_b17.v", SIM / "tb_b17_chain.sv"]
    work, ini = build("b18chain", files)
    if work is None:
        return {"chain_build": dict(case="chain_build", ok=False)}
    out = {}
    for name, (geom, n, maxc, inj, exp, bexp) in CHAIN_CASES.items():
        if only and name not in only:
            continue
        d = CASE / "b18chain" / name
        d.mkdir(parents=True, exist_ok=True)
        log = LOGS / ("b18_chain_%s.log" % name)
        g = ["-gW=%d" % geom["W"], "-gH=%d" % geom["H"],
             "-gCAM_W=%d" % geom["CAM_W"], "-gCAM_H=%d" % geom["CAM_H"],
             "-gROI_X=%d" % geom["ROI_X"], "-gROI_Y=%d" % geom["ROI_Y"],
             "-gNFRAMES=%d" % n, "-gMAX_CYCLES=%d" % maxc,
             "-gUART_DIV=1", "-gSTA_DIV=25000"]
        g += ["-g%s=%d" % (k, v) for k, v in inj.items()]
        rc, el, txt = vsim("b18chain", work, ini, "tb_b17_chain",
                           ["+OUT=" + (d / "capture.dec").as_posix(),
                            "+WIRE=" + (d / "wire.dec").as_posix(),
                            "+TRACE=" + (d / "trace.txt").as_posix(),
                            "+STAT=" + (d / "stats.txt").as_posix()],
                           log, 3600, generics=g)
        (d / "console.log").write_bytes(pathlib.Path(log).read_bytes())
        cargs = [sys.executable, str(SIM / "check_b18.py"), str(d)] + \
                (["--geom"] if name.startswith("t1") else []) + \
                ["%s=%d" % (k, v) for k, v in exp.items()] + \
                ["%s=%d" % (k, v) for k, v in bexp.items()]
        crc, cel = run(cargs, d, LOGS / ("b18_check_%s.log" % name), 3600)
        res = json.loads((d / "result.json").read_text()) if (d / "result.json").exists() else {}
        out["chain_" + name] = dict(case=name, exit=rc, check_exit=crc, seconds=el,
                                    status=res.get("status"), errors=res.get("errors"),
                                    stats=res.get("stats"), geom=res.get("geom_gate"),
                                    b17_status=res.get("b17_status"),
                                    expectations={**exp, **bexp},
                                    case_dir=d.as_posix(), log=log.as_posix())
        print("[chain/%s] vsim=%d check=%d status=%s geom=%s err=%s" %
              (name, rc, crc, res.get("status"), res.get("geom_gate"),
               (res.get("errors") or [])[:3]), flush=True)
    return out


def main():
    group = sys.argv[1] if len(sys.argv) > 1 else "camsel"
    for p in (LOGS, CASE, CAPS):
        p.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[2:])
    if group == "camsel":
        res = grp_camsel()
    elif group == "native":
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
    (SIM / ("sim-results-b18-%s.json" % tag)).write_text(json.dumps(res, indent=2))
    print("GROUP_DONE %s %s" % (tag, json.dumps(
        {k: (v.get("ok", v.get("status"))) for k, v in res.items()})), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
