#!/usr/bin/env python3
"""run_b14.py -- T10.b14-cam-b simulator driver (ModelSim ASE 10.5b).

Groups:
  s1      B-geometry (3864x2192, ROI 972/556, 1920x1080) full chain, clean
  s2      P1 three goldens on the b14 changed-src (byte-identical check)
  s3      v5 status packet structure + cam_sysstat bit20 (B counts)
  s4      dead B byte clock (clk_cam stopped): status packets still emit
  s5      B tap short-line/geometry error: no publish/export, next good frame OK

Results are written to r0/sim/sim-results-b14-<group>.json.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
R0 = RUN / "T10.b14-cam-b/r0"
CS = R0 / "changed-src"
SIM = R0 / "sim"
CSI = ROOT / "fpga/csi2"
B13 = RUN / "T10.b13-ddr-retry"

sys.path.insert(0, str(SIM))
import run_b12 as R  # noqa: E402  (build/vsim helpers)

R.CS = CS
R.SIM = SIM
R.LOGS = SIM / "logs"
R.CASE = SIM / "cases"
R.CAPS = SIM / "caps"
B14_FILES = [CS / n for n in ("a1_raw_crop.v", "a1_ddr_slot_store.v",
                              "a1_uart_export.v", "camera_a1_uart_top.v",
                              "cam_diag_mailbox.v", "a1_frame_top.v",
                              "a1_deflate_core.v")]
DEPS = [CS / "a1_ddr_arb2.v", CSI / "src/mem/capture_async_fifo.v"]
GOLDS = B13 / "r0/sim/caps"

P1_CASES = [
    ("micro8x2", ["-gW=8", "-gH=2", "-gCAM_W=32", "-gCAM_H=4", "-gROI_X=4", "-gROI_Y=2", "-gUART_DIV=1"]),
    ("mid64x8", ["-gW=64", "-gH=8", "-gCAM_W=128", "-gCAM_H=16", "-gROI_X=0", "-gROI_Y=0", "-gUART_DIV=1"]),
    ("full_grad", []),
]


def record(res, group):
    (SIM / ("sim-results-b14-%s.json" % group)).write_text(json.dumps(res, indent=2))


def chain_files():
    return B14_FILES + DEPS + [CS / "p2_ddr_bridge.v", SIM / "p2_paxi_model_b13.v",
                               SIM / "tb_b14_chain.sv"]


def run_chain(work, ini, name, generics, expect, check, tag):
    d = R.CASE / tag / name
    d.mkdir(parents=True, exist_ok=True)
    log = R.LOGS / ("b14_sim_%s.log" % name)
    rc, el, txt = R.vsim(tag, work, ini, "tb_b14_chain",
                         ["+OUT=" + (d / "capture.dec").as_posix(),
                          "+WIRE=" + (d / "wire.dec").as_posix(),
                          "+TRACE=" + (d / "trace.txt").as_posix(),
                          "+STAT=" + (d / "stats.txt").as_posix()],
                         log, 7200, generics=generics)
    (d / "console.log").write_bytes(pathlib.Path(log).read_bytes())
    cargs = [sys.executable, str(SIM / check), str(d)] + ["%s=%d" % (k, v) for k, v in expect.items()]
    crc, cel = R.run(cargs, d, R.LOGS / ("b14_check_%s.log" % name), 1800)
    res = json.loads((d / "result.json").read_text()) if (d / "result.json").exists() else {}
    fr = res.get("decoded") or {}
    flist = fr.get("frames", [])
    seeds = [f.get("seed") for f in flist if isinstance(f, dict)] if isinstance(flist, list) else []
    print("[%s/%s] vsim=%d check=%d status=%s exp=%s err=%s" %
          (tag, name, rc, crc, res.get("status"), (res.get("stats") or {}).get("exported"),
           (res.get("errors") or [])[:3]), flush=True)
    return dict(case=name, exit=rc, check_exit=crc, seconds=el, status=res.get("status"),
                errors=res.get("errors"), stats=res.get("stats"),
                frames=seeds,
                statuses=len(fr.get("statuses", [])) if isinstance(fr.get("statuses"), list) else fr.get("statuses"),
                case_dir=d.as_posix(), log=log.as_posix())


def grp_s1():
    work, ini = R.build("b14chain", chain_files())
    if work is None:
        return {"s1_build": dict(case="s1_build", ok=False, errors="compile failed")}
    gens = ["-gCAM_W=3864", "-gCAM_H=2192", "-gROI_X=972", "-gROI_Y=556",
            "-gW=1920", "-gH=1080", "-gDRIVE_LINES=2192", "-gNFRAMES=1",
            "-gMAX_CYCLES=80000000", "-gUART_DIV=1", "-gSTA_DIV=25000",
            "-gDBG_SYS_HI=1048576"]
    out = {"s1_b_geometry": run_chain(work, ini, "b_geometry", gens,
                                      {"exported": 1, "timeout": 0, "retry": 0,
                                       "giveup": 0, "stale": 0}, "check_b14.py", "b14s1")}
    d = pathlib.Path(out["s1_b_geometry"]["case_dir"])
    vrc, vel = R.run([sys.executable, str(SIM / "verify_b14_s1.py"), str(d)], d,
                     R.LOGS / "b14_verify_s1.log", 1800)
    vs = json.loads((d / "s1_verify.json").read_text()) if (d / "s1_verify.json").exists() else {}
    out["s1_verify"] = dict(case="s1_verify", exit=vrc, seconds=vel,
                            status=vs.get("status"), checks=vs.get("checks"),
                            errors=vs.get("errors"))
    print("[s1/verify] rc=%d status=%s errors=%s" % (vrc, vs.get("status"), vs.get("errors")),
          flush=True)
    return out


def grp_s2():
    work, ini = R.build("b14p1", B14_FILES + DEPS + [SIM / "a1_ddr_model.v", SIM / "tb_p1_chain.v"])
    if work is None:
        return {"s2_build": dict(case="s2_build", ok=False, errors="compile failed")}
    out = {}
    for name, gens in P1_CASES:
        dec = R.CAPS / (name + ".dec")
        stp = R.CAPS / (name + ".stats")
        log = R.LOGS / ("b14_sim_p1_" + name + ".log")
        rc, el, txt = R.vsim("b14p1", work, ini, "tb_camera_a1_uart_top",
                             ["+MODE=0", "+OUT=" + dec.as_posix(), "+STAT=" + stp.as_posix()],
                             log, 3600, generics=gens)
        s = R.sha(dec)
        gsha = R.sha(GOLDS / (name + ".dec"))
        ok = (s == gsha) and rc == 0
        out["p1_" + name] = dict(case="p1_" + name, ok=bool(ok), exit=rc, seconds=el,
                                 sha256=s, gold_sha256=gsha, byte_identical=(s == gsha))
        print("[p1 %s] identical=%s rc=%d %.1fs sha=%s" % (name, s == gsha, rc, el, s[:16]),
              flush=True)
    return out


def grp_s3():
    work, ini = R.build("b14status", [CS / "a1_uart_export.v", SIM / "tb_status_v5_b14.v"])
    if work is None:
        return {"s3_build": dict(case="s3_build", ok=False, errors="compile failed")}
    log = R.LOGS / "b14_sim_status_v5.log"
    rc, el, txt = R.vsim("b14status", work, ini, "tb_status_v5_b14", [], log, 900)
    mk = [l.strip() for l in txt.splitlines() if "B14_V5_" in l]
    ok = ("B14_V5_RESULT pass=1" in txt) and ("B10_ASSERT_FAIL" not in txt)
    print("[s3] rc=%d %ss ok=%s | %s" % (rc, el, ok, " | ".join(mk[-2:])), flush=True)
    return {"s3_v5_bit20": dict(case="v5_bit20", ok=bool(ok), exit=rc, seconds=el,
                                markers=mk, log=log.as_posix())}


def grp_s4():
    work, ini = R.build("b14dead", B14_FILES + DEPS + [SIM / "tb_b14_deadclk.sv"])
    if work is None:
        return {"s4_build": dict(case="s4_build", ok=False, errors="compile failed")}
    log = R.LOGS / "b14_sim_deadclk.log"
    rc, el, txt = R.vsim("b14dead", work, ini, "tb_b14_deadclk", [], log, 1800)
    mk = [l.strip() for l in txt.splitlines() if "B14_DEADCLK_" in l]
    ok = ("B14_DEADCLK_RESULT pass=1" in txt) and ("WATCHDOG" not in txt)
    print("[s4] rc=%d %ss ok=%s | %s" % (rc, el, ok, " | ".join(mk[-2:])), flush=True)
    return {"s4_dead_clk": dict(case="dead_clk", ok=bool(ok), exit=rc, seconds=el,
                                markers=mk, log=log.as_posix())}


def grp_s5():
    work, ini = R.build("b14chain", chain_files())
    if work is None:
        return {"s5_build": dict(case="s5_build", ok=False, errors="compile failed")}
    gens = ["-gCAM_W=96", "-gCAM_H=12", "-gROI_X=4", "-gROI_Y=2",
            "-gW=64", "-gH=8", "-gNFRAMES=2", "-gEXPECT_EXPORTED=1",
            "-gBAD_FIRST=1", "-gSHORT_LINE=3", "-gSHORT_BEATS=20",
            "-gUART_DIV=1", "-gSTA_DIV=25000", "-gDBG_SYS_HI=1048576"]
    return {"s5_short_line": run_chain(work, ini, "short_line", gens, {},
                                       "check_b14_s5.py", "b14s5")}


def main():
    group = sys.argv[1] if len(sys.argv) > 1 else "s1"
    for p in (R.LOGS, R.CASE, R.CAPS):
        p.mkdir(parents=True, exist_ok=True)
    fn = {"s1": grp_s1, "s2": grp_s2, "s3": grp_s3, "s4": grp_s4, "s5": grp_s5}[group]
    res = fn()
    record(res, group)
    print("GROUP_DONE %s %s" % (group, json.dumps({k: (v.get("ok", v.get("status")))
                                                   for k, v in res.items()})), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
