#!/usr/bin/env python3
"""P4 freeze: append the manual preflight record, then write manifest-r0.json.

Artifacts are every file under r0/ except the manifest itself and caches.
"""
import hashlib
import json
import pathlib
import sys

sys.dont_write_bytecode = True

HERE = pathlib.Path(__file__).resolve().parent
R0 = HERE.parent
SIM = HERE
ROOT = pathlib.Path(r"D:/fpga/ph1p100")


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


def jload(p, default=None):
    p = pathlib.Path(p)
    return json.loads(p.read_text()) if p.exists() else default


def record_preflight():
    log = SIM / "commands.jsonl"
    recs = [json.loads(x) for x in log.read_text().splitlines() if x.strip()]
    if any("chk_raw.log" in str(r.get("log", "")) for r in recs):
        return
    argv = [
        r"D:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe", "-c", "-lib", "work",
        "-l", str(SIM / "logs" / "chk_raw.log"), "tb_ss_4run",
        "+STAT=" + str(SIM / "caps" / "chk_raw.stats"),
        "+EVT=" + str(SIM / "caps" / "chk_raw.evt"),
        "+HDR=" + str(SIM / "caps" / "chk_raw.hdr"),
        "+RAW40=" + str(R0 / "content" / "raw40_p1d1.hex"),
        "-gFRAMES=1", "-gCONTENT=2", "-gPACING=0", "-gSINK=1", "-gCAPTURE=0",
        "-gMAX_CYCLES=2000000", "-do", "run -all; quit -f",
    ]
    rec = {"argv": argv, "cwd": str(pathlib.Path.home() / "AppData/Local/Temp/opencode/ss-4run/work"),
           "rc": 0, "timed_out": False, "seconds": 86.0, "timeout_s": 900,
           "log": str(SIM / "logs" / "chk_raw.log"),
           "manual": True,
           "seconds_source": "ModelSim transcript 'Elapsed time: 0:01:26'; not a full-size run",
           "purpose": "preflight: CONTENT=2 raw40 load + SS_RAW_MATCH before the 4 full runs"}
    with open(log, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")


def main():
    record_preflight()
    cmds = [json.loads(x) for x in (SIM / "commands.jsonl").read_text().splitlines() if x.strip()]
    full = [c for c in cmds if ("tb_ss_4run" in str(c.get("argv", []))
                                and c.get("timeout_s") == 2700)]
    full_s = sum(c.get("seconds", 0.0) for c in full)
    pre = [c for c in cmds if c.get("manual")]
    pre_s = sum(c.get("seconds", 0.0) for c in pre)

    files = []
    for p in sorted(R0.rglob("*")):
        if not p.is_file():
            continue
        if p.name == "manifest-r0.json" or "__pycache__" in p.parts:
            continue
        rel = p.relative_to(R0).as_posix()
        files.append({"path": rel, "bytes": p.stat().st_size, "sha256": sha(p)})

    inputs = jload(R0 / "input-verified.json", {})
    verdict = jload(R0 / "out/g0-verdict.json", {})
    runs = jload(R0 / "out/runs.json", {})
    man = {
        "manifest": True,
        "task_id": "T10.ss-4run-matrix",
        "run_id": "20261025-233401_fpga-steady-state-reverdict",
        "role": "fpga-dev",
        "created": "2026-10-26",
        "status": "ready_for_test",
        "repair_round": 0,
        "previous_manifest": None,
        "stopped_modifying": True,
        "active_commands": 0,
        "write_scope": [
            "D:\\fpga\\ph1p100\\workflow\\runs\\20261025-233401_fpga-steady-state-reverdict\\T10.ss-4run-matrix",
            "C:\\Users\\czz\\AppData\\Local\\Temp\\opencode\\ss-4run",
        ],
        "forbidden_actions_used": [],
        "verdict": {
            "headline": verdict.get("headline"),
            "headline_why": verdict.get("headline_why"),
            "headline_scope": verdict.get("headline_scope"),
            "blocked": verdict.get("blocked"),
            "r4_reproduction": verdict.get("r4_reproduction"),
            "overlap_penalty": verdict.get("overlap_penalty"),
            "runs": {k: {"S_ss": v.get("S_ss"), "G0": v.get("G0"),
                         "sink_limited": v.get("sink_limited")}
                     for k, v in (verdict.get("runs") or {}).items()},
        },
        "inputs": {
            "protected_drift": inputs.get("protected_drift"),
            "copied_src_mismatch": inputs.get("copied_src_mismatch"),
            "content_mismatch": inputs.get("content_mismatch"),
            "p3_manifest_r2_sha256": (inputs.get("p3_bindings") or {}).get("manifest_r2_sha256"),
            "p3_tb_sha256": (inputs.get("p3_bindings") or {}).get("tb_ss_g0_sha256"),
            "p1_manifest_sha256": "39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a",
            "p2_manifest_sha256": "fd27c70f304f51ba0b0b022398acd46f1f5f43a32351acfc472dea12e034fad0",
            "content_map_sha256": sha(R0 / "out/content-map.json"),
        },
        "tools": {
            "modelsim": r"D:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe",
            "python": sys.version.split()[0],
        },
        "budget": {
            "full_size_vsim_count": len(full),
            "full_size_vsim_limit": 5,
            "full_size_vsim_seconds": round(full_s, 1),
            "full_size_vsim_wall_limit_s": 7200,
            "preflight_seconds": round(pre_s, 1),
            "per_run_seconds": {k: (runs.get(k) or {}).get("command_seconds") for k in
                                ("r1", "r2", "r3", "r4")},
            "sim_wall_with_preflight_s": round(full_s + pre_s, 1),
            "max_single_vsim_s": 2700,
            "retries_used": 0,
        },
        "commands": cmds,
        "notes": [
            "tb_ss_4run.v derived from P3 freeze tb_ss_g0.v a565c6f2...; 12 DUT/model "
            "sources byte-identical to the P1 manifest; no DUT line modified.",
            "R4 reproduces P3 R3 5,928,286 with delta 0 cycles and identical stats counters.",
            "R1/R2 use the same C1 raw40 and SINK=1; R2-R1 is the strict-serial pacing penalty "
            "(upper bound including camera serialization).",
            "R3 is the C2 incompressible raw-band sink stress: sink_limited=true, G0_not_proven; "
            "production sink needs >=77.84 MB/s (G0) / >=103.79 MB/s (25 ms) are listed separately.",
            "All content is synthetic/proxy: full_frame_raw_synthetic / proxy_not_natural / "
            "proxy_not_worst; no natural-image corpus.",
            "No TD/synthesis/PnR/bitgen/CWC/download/Flash/board/COM/JTAG/RK; no P1/P2/P3, "
            "b11/b6/T08/T10, production source, tasks.json, docs or .agents modification.",
            "Scope deviation (disclosed): one 1 KB read-only debug script "
            "%TEMP%/opencode/dbg_comp.py (prints comp hex SHA/CRC only) was written before the "
            "preflight; deletion was denied by the environment. It is not an artifact and does "
            "not affect any evidence.",
        ],
        "artifacts": files,
    }
    out = R0 / "manifest-r0.json"
    out.write_text(json.dumps(man, indent=2) + "\n", encoding="utf-8")
    print("artifacts=%d full_runs=%d full_s=%.1f preflight_s=%.1f" % (
        len(files), len(full), full_s, pre_s))
    print("manifest_sha256=%s" % sha(out))


if __name__ == "__main__":
    main()
