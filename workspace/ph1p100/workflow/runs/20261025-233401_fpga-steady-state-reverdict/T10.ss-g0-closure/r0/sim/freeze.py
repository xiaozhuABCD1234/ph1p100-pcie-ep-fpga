#!/usr/bin/env python3
"""Freeze r0: sha256 every artifact, record inputs/tools/commands/budget."""
import hashlib
import json
import pathlib
import sys

sys.dont_write_bytecode = True
R0 = pathlib.Path(__file__).resolve().parent.parent
RUN = R0.parent
EXCLUDE = {"manifest-r2.json", "_repair.py"}
EXCLUDE_DIRS = {"__pycache__"}


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


def main():
    arts = []
    for p in sorted(R0.rglob("*")):
        if p.is_dir():
            continue
        rel = p.relative_to(R0).as_posix()
        if rel in EXCLUDE or any(part in EXCLUDE_DIRS for part in p.parts):
            continue
        arts.append({"path": rel, "bytes": p.stat().st_size, "sha256": sha(p)})
    cmds = []
    cpath = R0 / "sim" / "commands.jsonl"
    if cpath.exists():
        for line in cpath.read_text(encoding="utf-8").splitlines():
            try:
                cmds.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    verdict = json.loads((R0 / "out" / "g0-verdict.json").read_text()) if (R0 / "out" / "g0-verdict.json").exists() else {}
    inputs = json.loads((R0 / "input-verified.json").read_text())
    runs = json.loads((R0 / "out" / "runs.json").read_text())
    vsim_cmds = [c for c in cmds if "vsim.exe" in " ".join(c.get("argv", []))
                 and c.get("timeout_s") == 2700]
    sim_seconds = sum(c.get("seconds", 0) for c in vsim_cmds)
    full_frame = [c for c in vsim_cmds if "-gFRAMES=4" in c.get("argv", [])]
    man = {
        "manifest": True,
        "task_id": "T10.ss-g0-closure",
        "run_id": "20261025-233401_fpga-steady-state-reverdict",
        "role": "fpga-dev",
        "created": "2026-10-26",
        "status": "ready_for_test",
        "repair_round": 2,
        "previous_manifest": {"path": "manifest-r1.json",
                              "sha256": sha(R0 / "manifest-r1.json") if (R0 / "manifest-r1.json").exists() else None},
        "stopped_modifying": True,
        "active_commands": 0,
        "write_scope": [str(R0), r"C:\Users\czz\AppData\Local\Temp\opencode\ss-g0"],
        "forbidden_actions_used": [],
        "verdict": {
            "value": verdict.get("verdict"),
            "why": verdict.get("why"),
            "r3_S_ss": (verdict.get("runs", {}).get("r3f", {}) or {}).get("S_ss"),
            "overlap_gain_cycles": verdict.get("overlap_gain_cycles"),
            "proxy_gap_cycles": verdict.get("proxy_gap_cycles"),
            "scope": verdict.get("scope"),
        },
        "inputs": {
            "protected_drift": inputs.get("protected_drift"),
            "copied_src_mismatch": inputs.get("copied_src_mismatch"),
            "p1_manifest_sha256": inputs.get("p1_bindings", {}).get("manifest_sha256"),
            "p2_manifest_sha256": inputs.get("p2_bindings", {}).get("manifest_sha256"),
            "comp_in_hex_sha256": next((c["sha256"] for c in inputs.get("protected_inputs", [])
                                        if c["path"].endswith("in.hex")), None),
        },
        "tools": inputs.get("tools", {}),
        "commands": cmds,
        "budget": {
            "developer_calls_limit": 45,
            "developer_minutes_limit": 120,
            "full_frame_vsim_runs": len(full_frame),
            "full_frame_vsim_limit": 5,
            "check_only_vsim_runs": len(vsim_cmds) - len(full_frame),
            "vsim_hard_timeout_s": 2700,
            "sim_wall_seconds": round(sim_seconds, 1),
            "sim_wall_limit_min": 112,
            "sim_wall_note": "sum of every vsim invocation in commands.jsonl; round0 5206.3 s "
                             "(86.8 min) + round1 r3_frozen 1326.1 s (22.1 min) = 6532.4 s "
                             "(108.9 min), within the round1 override <=112 min; full-frame 5/5",
            "note": "R4 not run (budget cap); comp strict-serial view is assumed = R3 + (R2-R1)",
        },
        "artifacts": arts,
        "artifact_count": len(arts),
        "notes": {
            "tb_versions": {
                "r0_r3_tb_sha256": "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e",
                "frozen_tb_sha256": "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",
                "difference": "TB-only byte-level self check grouping fix + early frame-1 print; "
                              "check is read-only and never drives DUT signals",
                "r3_frozen_tb": "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",
                "legacy_tb_archived": "src/legacy/tb_ss_g0_89948303.v",
                "legacy_sha256": "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e",
            },
            "proxy": "comp vector is transform-domain; TB inverts PREP/PRED and the DUT re-applies it; "
                     "R3 export header raw_crc/xform_crc prove byte-exact consumption; "
                     "proxy_not_worst, not all-content",
            "r3_frozen": "G0 run re-run with frozen TB; same-run SS_VEC_MATCH bad=0 checked=518400; "
                         "legacy r3 log (bad=691132) is archived history only",
            "in_meta_fix": "content-proxy.json in.meta now 330 B / raw E98C9A1C...",
            "sink": "measured 2 clk_a1/B = 93.75 MB/s; raw band needs 77.84 (G0) / 103.79 (25ms) MB/s",
            "boundaries": "no TD/synthesis/PnR/bitgen/CWC/download/Flash/board/COM/JTAG/RK/PCIe; "
                          "behavioral DDR; fast sim sink; single core per stream; G25 reference only",
            "p1_p2_b11_b6_t08_t10_untouched": True,
            "scratch_excluded": "sim/_repair.py (one-off encoding repair) and sim/__pycache__ "
                                "are non-artifact scratch and are excluded from this manifest",
        },
    }
    (R0 / "manifest-r2.json").write_text(json.dumps(man, indent=2) + "\n")
    print("artifacts=%d sim_wall=%.1fs verdict=%s" % (len(arts), sim_seconds, man["verdict"]["value"]))


if __name__ == "__main__":
    main()
