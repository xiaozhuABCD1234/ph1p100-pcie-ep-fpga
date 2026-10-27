#!/usr/bin/env python3
"""run_b13.py -- T10.b13-ddr-retry simulator driver (ModelSim ASE 10.5b).

Groups:
  store    unit: a1_ddr_slot_store RETRY_EN=1 + arbiter + drop-R model
           (clean / retry / guard / budget)
  chain    full read path: camera_a1_uart_top -> a1_ddr_arb2 -> p2_ddr_bridge
           -> p2_paxi_model_b13 with deterministic drop/late-R injection, v5
           status packets decoded by check_b13.py
  regress  b12 R1 clean/loss, T7 SOF, b12 store T3-T7, multi control/triple,
           P1 three goldens, b11 read nine cases, full two frames
  status   v5 status packet structure (tb_status_v5)

Every result is written to r0/sim/sim-results-b13-<group>.json.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
R0 = RUN / "T10.b13-ddr-retry/r0"
CS = R0 / "changed-src"
SIM = R0 / "sim"
CSI = ROOT / "fpga/csi2"

sys.path.insert(0, str(SIM))
import run_b12 as R  # noqa: E402  (reuse build/vsim helpers)

# ---- re-point the b12 helpers at the b13 tree ------------------------------
R.CS = CS
R.SIM = SIM
R.LOGS = SIM / "logs"
R.CASE = SIM / "cases"
R.CAPS = SIM / "caps"
R.B12_FILES = [CS / n for n in ("a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v",
                                "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
                                "a1_deflate_core.v")]
R.DEPS = [CS / "a1_ddr_arb2.v", CSI / "src/mem/capture_async_fifo.v"]
R.record = lambda res, group: (SIM / ("sim-results-b13-%s.json" % group)).write_text(
    json.dumps(res, indent=2))
B13_FILES = R.B12_FILES

CHAIN_CASES = [
    # name, nframes, generics, expectations for check_b13.py
    ("clean", 1, {}, {"exported": 1, "timeout": 0, "retry": 0, "giveup": 0, "stale": 0}),
    ("drop1", 1, {"DROP_ADDR": 16, "DROP_OCC": 1},
     {"exported": 1, "timeout": 1, "retry": 1, "giveup": 0}),
    ("late1", 1, {"LATE_ADDR": 16, "LATE_OCC": 1, "LATE_DELAY": 12000},
     {"exported": 1, "timeout": 1, "retry": 1, "giveup": 0}),
    ("three_f2", 3, {"DROP_ADDR": 16, "DROP_OCC": 2},
     {"exported": 3, "timeout": 1, "retry": 1, "giveup": 0}),
    ("budget", 2, {"DROP_FIRST_N": 3},
     {"exported": 1, "timeout": 3, "retry": 2, "giveup": 1}),
]
STORE_CASES = ("clean", "retry", "guard", "budget")


def grp_store_retry():
    work, ini = R.build("b13store", [CS / "a1_ddr_slot_store.v", CS / "a1_ddr_arb2.v",
                                     SIM / "tb_b13_store_retry.v"])
    if work is None:
        return {"store_build": dict(case="store_build", ok=False, errors="compile failed")}
    out = {}
    for cname in STORE_CASES:
        log = R.LOGS / ("b13_sim_store_%s.log" % cname)
        rc, el, txt = R.vsim("b13store", work, ini, "tb_b13_store_retry",
                             ["+NAME=" + cname], log, 1800)
        line = [l.strip() for l in txt.splitlines() if "B13_STORE_RESULT" in l]
        ok = bool(line) and "pass=1" in line[-1]
        out["store_" + cname] = dict(case=cname, exit=rc, seconds=el, ok=ok,
                                     result=line[-1] if line else "NO_RESULT",
                                     log=log.as_posix())
        print("[b13store/%s] rc=%d %ss pass=%s | %s" %
              (cname, rc, el, ok, line[-1] if line else "-"), flush=True)
    return out


def grp_chain():
    files = B13_FILES + R.DEPS + [CS / "p2_ddr_bridge.v", SIM / "p2_paxi_model_b13.v",
                                  SIM / "tb_b13_chain.sv"]
    work, ini = R.build("b13chain", files)
    if work is None:
        return {"chain_build": dict(case="chain_build", ok=False, errors="compile failed")}
    out = {}
    for name, n, gens, exp in CHAIN_CASES:
        d = R.CASE / "b13chain" / name
        d.mkdir(parents=True, exist_ok=True)
        log = R.LOGS / ("b13_sim_chain_%s.log" % name)
        gargs = ["-gNFRAMES=%d" % n, "-gSTA_DIV=%d" % 10000] + \
                ["-g%s=%d" % (k, v) for k, v in gens.items()]
        rc, el, txt = R.vsim("b13chain", work, ini, "tb_b13_chain",
                             ["+OUT=" + (d / "capture.dec").as_posix(),
                              "+WIRE=" + (d / "wire.dec").as_posix(),
                              "+TRACE=" + (d / "trace.txt").as_posix(),
                              "+STAT=" + (d / "stats.txt").as_posix()],
                             log, 5400, generics=gargs)
        (d / "console.log").write_bytes(pathlib.Path(log).read_bytes())
        cargs = [sys.executable, str(SIM / "check_b13.py"), str(d)] + \
                ["%s=%d" % (k, v) for k, v in exp.items()]
        crc, cel = R.run(cargs, d, R.LOGS / ("b13_check_chain_%s.log" % name), 600)
        res = json.loads((d / "result.json").read_text()) if (d / "result.json").exists() else {}
        out["chain_" + name] = dict(case=name, exit=rc, check_exit=crc, seconds=el,
                                    status=res.get("status"), errors=res.get("errors"),
                                    stats=res.get("stats"), timeouts=res.get("timeouts"),
                                    frames=[f.get("seed") for f in
                                            res.get("decoded", {}).get("frames", [])],
                                    statuses=len(res.get("decoded", {}).get("statuses", [])),
                                    case_dir=d.as_posix(), log=log.as_posix())
        print("[b13chain/%s] vsim=%d check=%d status=%s timeout=%s retry=%s giveup=%s stale=%s "
              "exp=%s err=%s" %
              (name, rc, crc, res.get("status"),
               (res.get("stats") or {}).get("timeout_cnt"),
               (res.get("stats") or {}).get("retry_cnt"),
               (res.get("stats") or {}).get("giveup_cnt"),
               (res.get("stats") or {}).get("stale_guard_cnt"),
               (res.get("stats") or {}).get("exported"), (res.get("errors") or [])[:3]),
              flush=True)
    return out


def grp_regress():
    out = {}
    # b12 R1 clean/loss on the b13 sources
    out.update(R.grp_r1("b13r1", B13_FILES + R.DEPS, [(0, "clean"), (1, "loss")]))
    # T7 SOF reject / head-of-line drain
    out.update(R.grp_t7())
    # b12 store T3-T7 (RETRY_EN=0 default -> must behave like b12)
    out.update(R.grp_store())
    # multi (control + triple)
    out.update(R.grp_multi())
    # P1 goldens, b11 read nine cases, full two frames (no v4 status case)
    sys.argv = [sys.argv[0], "main", "p1", "read", "full"]
    out.update(R.grp_main())
    return out


def grp_status():
    work, ini = R.build("b13status", [CS / "a1_uart_export.v", SIM / "tb_status_v5.v"])
    if work is None:
        return {"status_build": dict(case="status_build", ok=False, errors="compile failed")}
    log = R.LOGS / "b13_sim_status_v5.log"
    rc, el, txt = R.vsim("b13status", work, ini, "tb_status_v5", [], log, 900)
    mk = [l.strip() for l in txt.splitlines() if "B13_V5_" in l]
    ok = ("B13_V5_RESULT pass=1" in txt) and ("B13_V5_ASSERT_FAIL" not in txt)
    print("[b13status] rc=%d %ss ok=%s | %s" % (rc, el, ok, " | ".join(mk[-2:])), flush=True)
    return {"v5": dict(case="v5", ok=ok, exit=rc, seconds=el, markers=mk,
                       log=log.as_posix())}


def main():
    group = sys.argv[1] if len(sys.argv) > 1 else "store"
    for p in (R.LOGS, R.CASE, R.CAPS):
        p.mkdir(parents=True, exist_ok=True)
    if group == "store":
        res = grp_store_retry()
    elif group == "chain":
        res = grp_chain()
    elif group == "regress":
        res = grp_regress()
    elif group == "status":
        res = grp_status()
    else:
        raise SystemExit("unknown group " + group)
    R.record(res, group)
    print("GROUP_DONE %s %s" % (group, json.dumps({k: (v.get("ok", v.get("status")))
                                                   for k, v in res.items()})), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
