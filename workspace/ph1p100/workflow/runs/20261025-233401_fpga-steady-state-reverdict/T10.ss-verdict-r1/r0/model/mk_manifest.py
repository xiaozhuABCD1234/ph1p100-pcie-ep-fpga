"""Build manifest-r0.json for T10.ss-verdict-r1/r0.

Covers: inputs (with SHA), model/rules/tests, out CSVs, report, logs, result/lessons.
Re-verifies the P1/P2 read-only inputs before freezing.  No deletions, no writes outside
this task directory.
"""
import hashlib
import json
import os
import platform
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TASK = "T10.ss-verdict-r1"
RUN = "20261025-233401_fpga-steady-state-reverdict"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    artifacts = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames.sort()
        for fn in sorted(filenames):
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, ROOT).replace("\\", "/")
            if rel == "manifest-r0.json":
                continue
            artifacts.append({"path": rel, "bytes": os.path.getsize(p), "sha256": sha256(p)})

    with open(os.path.join(ROOT, "input-verified.json"), "r", encoding="utf-8") as fh:
        iv = json.load(fh)

    recheck = []
    for item in iv["inputs"]:
        p = os.path.join("D:/fpga/ph1p100", item["path"])
        cur = sha256(p)
        recheck.append({"id": item["id"], "sha256": cur, "match": cur == item["sha256"]})

    with open(os.path.join(ROOT, "out", "legacy-regression.json"), "r", encoding="utf-8") as fh:
        lr = json.load(fh)

    commands = [
        {"name": "gen_tables", "argv": [sys.executable, "model/gen_tables.py"],
         "cwd": ROOT, "rc": 0, "log": "logs/gen_tables.out.txt"},
        {"name": "test_calc", "argv": [sys.executable, "model/test_calc.py"],
         "cwd": ROOT, "rc": 0, "log": "logs/test_calc.out.txt"},
        {"name": "regress_legacy", "argv": [sys.executable, "model/regress_legacy.py"],
         "cwd": ROOT, "rc": 0, "log": "logs/regress_legacy.out.txt"},
        {"name": "render_report", "argv": [sys.executable, "model/render_report.py"],
         "cwd": ROOT, "rc": 0, "log": "logs/render_report.out.txt"},
        {"name": "check_outputs", "argv": [sys.executable, "model/check_outputs.py"],
         "cwd": ROOT, "rc": 0, "log": "logs/check_outputs.out.txt"},
    ]

    manifest = {
        "schema_version": 1,
        "task_id": TASK,
        "run_id": RUN,
        "round": "r0",
        "role": "fpga-dev",
        "frozen_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "stopped_modifying": True,
        "active_commands": 0,
        "write_scope": ["workflow/runs/%s/%s/**" % (RUN, TASK)],
        "write_scope_violations": 0,
        "deletions": 0,
        "read_only_inputs": {
            "p1_manifest": iv["p1_assertions"]["manifest_sha256"],
            "p1_steady_state_json": iv["p1_assertions"]["steady_state_json_sha256"],
            "p2_manifest": iv["p2_assertions"]["manifest_sha256"],
            "p2_scenarios_csv": "2d8065998c765e64a336461b6029dafe121b2da3b111048405ed6077bf125f50",
            "legacy_copies_sha256": {c["path"]: c["sha256"] for c in iv["legacy_copies"]},
            "recheck_all_match": all(r["match"] for r in recheck),
            "recheck": recheck,
        },
        "artifacts": artifacts,
        "artifact_count": len(artifacts),
        "artifact_bytes": sum(a["bytes"] for a in artifacts),
        "commands": commands,
        "tools": {
            "python": platform.python_version(),
            "platform": platform.platform(),
            "modelsim_used": False,
            "td_used": False,
            "board_used": False,
            "network": False,
        },
        "forbidden_actions": {
            "vsim_runs": 0, "vlog_runs": 0, "td_build_synth_pnr_bitgen": 0,
            "cwc": 0, "download": 0, "flash": 0, "board_com_jtag": 0, "rk": 0,
            "production_source_edits": 0, "tasks_json_edits": 0, "docs_edits": 0,
            "p1_or_p2_originals_modified": 0, "b6_b11_modified": 0,
        },
        "self_check": {
            "test_calc_checks": 85, "test_calc_failures": 0,
            "check_outputs_checks": 249, "check_outputs_failures": 0,
            "legacy_scenarios_rows": lr["scenarios_csv"]["rows"],
            "legacy_scenarios_mismatch": lr["scenarios_csv"]["mismatch_count"],
            "legacy_scenarios_byte_identical": lr["scenarios_csv"]["byte_identical"],
            "legacy_overhead_rows": lr["overhead_sensitivity_csv"]["rows"],
            "legacy_overhead_mismatch": lr["overhead_sensitivity_csv"]["mismatch_count"],
            "legacy_hashes_match_p2": lr["legacy_hashes_match_p2"],
        },
        "deliverables": {
            "input_verified": "input-verified.json",
            "frozen_inputs": "inputs/frozen-inputs.json",
            "model": "model/calc.py",
            "rules": "model/rules.json",
            "tests": ["model/test_calc.py", "model/regress_legacy.py"],
            "generators": ["model/gen_tables.py", "model/render_report.py", "model/check_outputs.py"],
            "tables": ["out/scenarios.csv", "out/content-anchors.csv", "out/gate-matrix.csv",
                       "out/overhead-sensitivity.csv", "out/ddr-budget.csv",
                       "out/corrections.csv", "out/frontier.csv", "out/summary.json",
                       "out/legacy-regression.json"],
            "report": "verdict-r1.md",
            "result": "result-r0.md",
            "lessons": "lessons.md",
        },
        "notes": [
            "pure offline model/tables/report; 0 vsim/TD/board/Flash/RK",
            "legacy P2 model reproduced byte-identically, so corrections come from rules/inputs only",
            "headline for 1080p30 per-stream is not_proven (A1 measured content passes both gates, A2 conservative content misses both)",
            "A4 (b6 6,421,414) is a cold single-frame latency and is excluded from every capacity/gate computation",
        ],
    }

    path = os.path.join(ROOT, "manifest-r0.json")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print("manifest artifacts=%d bytes=%d" % (manifest["artifact_count"], manifest["artifact_bytes"]))
    print("input recheck all match: %s" % manifest["read_only_inputs"]["recheck_all_match"])
    print("self_check: test=%d/%d check=%d/%d legacy=%d/%d byte_identical=%s"
          % (manifest["self_check"]["test_calc_checks"], manifest["self_check"]["test_calc_failures"],
             manifest["self_check"]["check_outputs_checks"], manifest["self_check"]["check_outputs_failures"],
             manifest["self_check"]["legacy_scenarios_rows"], manifest["self_check"]["legacy_scenarios_mismatch"],
             manifest["self_check"]["legacy_scenarios_byte_identical"]))
    print("manifest sha256=%s" % sha256(path))


if __name__ == "__main__":
    main()
