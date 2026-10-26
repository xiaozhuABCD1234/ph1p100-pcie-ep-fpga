#!/usr/bin/env python3
"""run_b15.py -- T10.b15-ddr-pace simulator driver (ModelSim ASE 10.5b).

Groups (one process each so expensive full-frame cases can run in parallel):
  chain <case>  real b15 chain (camera_a1_uart_top -> a1_ddr_arb2 ->
                p2_ddr_bridge(b15) -> p2_paxi_model_b15) + check_b15.py
  p1            P1 three goldens (micro8x2 / mid64x8 / full_grad) on the b15 RTL
  regress       b12 R1 clean/loss, T7 SOF, b12 store T3-T7, b13 store retry
  status        v5 status packet structure (241 B / 59 fields)

Every case writes r0/sim/cases/<...>/result.json and the group result to
r0/sim/sim-results-b15-<group>.json.
"""
import json
import os
import pathlib
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
R0 = RUN / "T10.b15-ddr-pace/r0"
CS = R0 / "changed-src"
SIM = R0 / "sim"
CSI = ROOT / "fpga/csi2"

sys.path.insert(0, str(SIM))
import run_b12 as R  # noqa: E402  (build/vsim helpers)

R.CS = CS
R.SIM = SIM
R.LOGS = SIM / "logs"
R.CASE = SIM / "cases"
R.CAPS = SIM / "caps"
R.record = lambda res, group: (SIM / ("sim-results-b15-%s.json" % group)).write_text(
    json.dumps(res, indent=2))

B15_FILES = [CS / n for n in ("a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v",
                              "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
                              "a1_deflate_core.v")]
DEPS = [CS / "a1_ddr_arb2.v", CSI / "src/mem/capture_async_fifo.v"]

# board geometry: CAM_W/CAM_H = 3864x2192, ROI 972/556 -> 1920x1080
FULL = {"W": 1920, "H": 1080, "CAM_W": 3864, "CAM_H": 2192, "ROI_X": 972, "ROI_Y": 556}
SMALL = {"CAM_W": 72, "CAM_H": 10, "ROI_X": 4, "ROI_Y": 2, "W": 64, "H": 8}
MID = {"CAM_W": 1024, "CAM_H": 512, "ROI_X": 0, "ROI_Y": 0, "W": 512, "H": 256}


def gens(geom, nframes, max_cycles, extra):
    g = ["-gW=%d" % geom["W"], "-gH=%d" % geom["H"],
         "-gCAM_W=%d" % geom["CAM_W"], "-gCAM_H=%d" % geom["CAM_H"],
         "-gROI_X=%d" % geom["ROI_X"], "-gROI_Y=%d" % geom["ROI_Y"],
         "-gNFRAMES=%d" % nframes, "-gMAX_CYCLES=%d" % max_cycles,
         "-gUART_DIV=1", "-gSTA_DIV=25000"]
    g += ["-g%s=%d" % (k, v) for k, v in extra.items()]
    return g


# name: (geometry, frames, max_cycles, injections, checker expects, b15 expects)
CHAIN_CASES = {
    # ---- required frame matrix (dev-plan section 5) --------------------------
    "s1_full_clean": (FULL, 1, 90000000, {},
                      {"exported": 1, "timeout": 0, "retry": 0, "giveup": 0, "stale": 0},
                      {"b15_short_burst": 0, "b15_stale_r": 0, "b15_ar_minus_rlast_max": 1, "b15_full_frame": 1}),
    "s2_drop1": (SMALL, 1, 4000000, {"DROP_ADDR": 16, "DROP_OCC": 1},
                 {"exported": 1, "timeout": 1, "retry": 1, "giveup": 0},
                 {"b15_purge_close_min": 1, "b15_ar_minus_rlast_max": 1}),
    "s3_small_three": (SMALL, 3, 6000000, {"DROP_ADDR": 16, "DROP_OCC": 2},
                       {"exported": 3, "timeout": 1, "retry": 1, "giveup": 0},
                       {"b15_ar_minus_rlast_max": 1}),
    "s3_full_three": (FULL, 3, 180000000, {},
                      {"exported": 3, "timeout": 0, "retry": 0, "giveup": 0, "stale": 0},
                      {"b15_short_burst": 0, "b15_stale_r": 0, "b15_ar_minus_rlast_max": 1}),
    "s4_full_two": (FULL, 2, 130000000, {},
                    {"exported": 2, "timeout": 0, "retry": 0, "giveup": 0, "stale": 0},
                    {"b15_short_burst": 0, "b15_stale_r": 0, "b15_ar_minus_rlast_max": 1}),
    # ---- S7 adversarial (dev-plan section 5) --------------------------------
    "s7a_drop_rlast": (MID, 1, 8000000, {"DROP_ADDR": 16, "DROP_OCC": 1},
                       {"exported": 1, "timeout": 1, "retry": 1, "giveup": 0},
                       {"b15_purge_close_min": 1}),
    "s7b_late_dup": (MID, 1, 8000000,
                     {"LATE_ADDR": 16, "LATE_OCC": 1, "LATE_DELAY": 12000, "DUP_R": 1},
                     {"exported": 1, "timeout": 1, "retry": 1, "giveup": 0},
                     {"b15_stale_r_min": 1}),
    "s7c_ar_stall": (MID, 1, 8000000, {"AR_STALL_OCC": 40, "AR_STALL_N": 100},
                     {"exported": 1, "timeout": 0, "retry": 0, "giveup": 0},
                     {"b15_short_burst": 0}),
    "s7d_rv_gap": (MID, 1, 8000000, {"RV_GAP_OCC": 40, "RV_GAP_N": 64},
                   {"exported": 1, "timeout": 0, "retry": 0, "giveup": 0},
                   {"b15_short_burst": 0}),
}


def grp_chain(only):
    files = B15_FILES + DEPS + [CS / "p2_ddr_bridge.v", SIM / "p2_paxi_model_b15.v",
                                SIM / "tb_b15_chain.sv"]
    work, ini = R.build(os.environ.get("B15_BUILD", "b15chain"), files)
    if work is None:
        return {"chain_build": dict(case="chain_build", ok=False, errors="compile failed")}
    out = {}
    for name, (geom, n, maxc, inj, exp, bexp) in CHAIN_CASES.items():
        if only and name not in only:
            continue
        d = R.CASE / "b15chain" / name
        d.mkdir(parents=True, exist_ok=True)
        log = R.LOGS / ("b15_sim_chain_%s.log" % name)
        rc, el, txt = R.vsim(os.environ.get("B15_BUILD", "b15chain"), work, ini, "tb_b15_chain",
                             ["+OUT=" + (d / "capture.dec").as_posix(),
                              "+WIRE=" + (d / "wire.dec").as_posix(),
                              "+TRACE=" + (d / "trace.txt").as_posix(),
                              "+STAT=" + (d / "stats.txt").as_posix()],
                             log, 21600, generics=gens(geom, n, maxc, inj))
        (d / "console.log").write_bytes(pathlib.Path(log).read_bytes())
        cargs = [sys.executable, str(SIM / "check_b15.py"), str(d)] + \
                ["%s=%d" % (k, v) for k, v in exp.items()] + \
                ["%s=%d" % (k, v) for k, v in bexp.items()]
        crc, cel = R.run(cargs, d, R.LOGS / ("b15_check_chain_%s.log" % name), 3600)
        res = json.loads((d / "result.json").read_text()) if (d / "result.json").exists() else {}
        out["chain_" + name] = dict(case=name, exit=rc, check_exit=crc, seconds=el,
                                    status=res.get("status"), errors=res.get("errors"),
                                    stats=res.get("stats"), timeouts=res.get("timeouts"),
                                    b15=res.get("b15"), expectations={**exp, **bexp},
                                    frames=[f.get("seed") for f in
                                            res.get("decoded", {}).get("frames", [])],
                                    statuses=len(res.get("decoded", {}).get("statuses", [])),
                                    case_dir=d.as_posix(), log=log.as_posix())
        print("[b15chain/%s] vsim=%d check=%d status=%s exp=%s err=%s" %
              (name, rc, crc, res.get("status"), res.get("stats", {}).get("exported"),
               (res.get("errors") or [])[:3]), flush=True)
    return out


def grp_p1():
    sys.argv = [sys.argv[0], "main", "p1"]
    return R.grp_main()


def grp_regress():
    out = {}
    out.update(R.grp_r1("b15r1", B15_FILES + DEPS, [(0, "clean"), (1, "loss")]))
    out.update(R.grp_t7())
    out.update(R.grp_store())
    # b13 slot-store retry/guard/budget (the frozen fallback must still work)
    work, ini = R.build("b15store", [CS / "a1_ddr_slot_store.v", CS / "a1_ddr_arb2.v",
                                     SIM / "tb_b13_store_retry.v"])
    if work is None:
        out["store_build"] = dict(case="store_build", ok=False)
        return out
    for cname in ("clean", "retry", "guard", "budget"):
        log = R.LOGS / ("b15_sim_store_%s.log" % cname)
        rc, el, txt = R.vsim("b15store", work, ini, "tb_b13_store_retry",
                             ["+NAME=" + cname], log, 1800)
        line = [l.strip() for l in txt.splitlines() if "B13_STORE_RESULT" in l]
        ok = bool(line) and "pass=1" in line[-1]
        out["store_" + cname] = dict(case=cname, exit=rc, seconds=el, ok=ok,
                                     result=line[-1] if line else "NO_RESULT",
                                     log=log.as_posix())
        print("[b15store/%s] rc=%d pass=%s" % (cname, rc, ok), flush=True)
    return out


def grp_status():
    work, ini = R.build("b15status", [CS / "a1_uart_export.v", SIM / "tb_status_v5.v"])
    if work is None:
        return {"status_build": dict(case="status_build", ok=False, errors="compile failed")}
    log = R.LOGS / "b15_sim_status_v5.log"
    rc, el, txt = R.vsim("b15status", work, ini, "tb_status_v5", [], log, 900)
    mk = [l.strip() for l in txt.splitlines() if "B13_V5_" in l]
    ok = ("B13_V5_RESULT pass=1" in txt) and ("B13_V5_ASSERT_FAIL" not in txt)
    print("[b15status] rc=%d ok=%s | %s" % (rc, ok, " | ".join(mk[-2:])), flush=True)
    return {"v5": dict(case="v5", ok=ok, exit=rc, seconds=el, markers=mk, log=log.as_posix())}


def main():
    group = sys.argv[1] if len(sys.argv) > 1 else "chain"
    for p in (R.LOGS, R.CASE, R.CAPS):
        p.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[2:])
    if group == "chain":
        res = grp_chain(only)
    elif group == "p1":
        res = grp_p1()
    elif group == "regress":
        res = grp_regress()
    elif group == "status":
        res = grp_status()
    else:
        raise SystemExit("unknown group " + group)
    if group == "chain" and only:
        tag = "chain-" + "-".join(sorted(only))
    else:
        tag = group
    R.record(res, tag)
    print("GROUP_DONE %s %s" % (tag, json.dumps({k: (v.get("ok", v.get("status")))
                                                 for k, v in res.items()})), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
