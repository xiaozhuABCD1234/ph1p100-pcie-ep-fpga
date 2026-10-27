"""Freeze the r0 task: hash every artifact/input, write manifest-r0.json, then log its SHA.

The manifest never hashes itself and never includes logs/mk_manifest.out.txt (written after
the manifest). This script only reads commands.jsonl; it does not append to it.
"""
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


EXCLUDED_RELS = {"manifest-r0.json", "logs/mk_manifest.out.txt"}


def artifacts():
    out = []
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(ROOT).as_posix()
        if rel in EXCLUDED_RELS or "__pycache__" in rel:
            continue
        out.append({"path": str(p), "rel": rel, "bytes": p.stat().st_size, "sha256": sha256_file(p)})
    return out


def main():
    verified = json.loads((ROOT / "input-verified.json").read_text(encoding="utf-8"))
    inputs = verified["inputs"]
    arts = artifacts()

    journal = []
    jpath = ROOT / "commands.jsonl"
    if jpath.exists():
        journal = [json.loads(line) for line in jpath.read_text(encoding="utf-8").splitlines() if line.strip()]
    commands = list(journal)
    commands.append({
        "seq": len(commands) + 1,
        "argv": ["python", "model/mk_manifest.py"],
        "cwd": str(ROOT),
        "exit": 0,
        "timeout_s": 120,
        "time_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "purpose": "hash artifacts/inputs and write manifest-r0.json",
        "result": "MANIFEST_WRITTEN; the final manifest SHA256 is recorded in logs/mk_manifest.out.txt (self-reference excluded)",
    })

    scen = ROOT / "out" / "scenarios.csv"
    rows = scen.read_text(encoding="utf-8").splitlines()
    header = rows[0].split(",")
    import csv as _csv
    with open(scen, encoding="utf-8", newline="") as f:
        srows = list(_csv.DictReader(f))
    counts = {}
    for r in srows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1

    manifest = {
        "schema_version": 1,
        "task_id": "T10.dual-aplus-service-verdict",
        "run_id": "20261025-195604_fpga-dual-aplus-core-feasibility",
        "round": "r0",
        "repair_round": 1,
        "status": "ready_for_test",
        "stopped_modifying": True,
        "active_commands": 0,
        "freeze_time_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "write_scope": "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-aplus-service-verdict/**",
        "worktree": "D:/fpga/ph1p100",
        "round1_fixes": {
            "F1": "frontier.csv now carries margin_chain_pct and margin_core_pct; margin_pct and gate_25 are same-source with capacity_basis (core_only_comp -> core margin 25.1036/28.7074/4.2530; full_chain_* -> chain margin). check_outputs asserts source pairing and scenario-table equality.",
            "F2": "out/overhead-sensitivity.csv added (43 scenarios x 3 tiers = 129 rows; 1080p fixed to the measured anchor, applies=false; verdict re-derived per tier). Report discloses 1600x900@30 = 36.1774% at the primary tier and 21.0486% at 1,000,000 cycles (conditional), and adds the all-tier-robust alternate 1440x810@30 (worst 42.9485%).",
            "F3": "scenarios.csv gained required_clock_chain_25_mhz / required_clock_core_25_mhz / required_clock_chain_0_mhz; frontier.csv gained chain/core required clocks. Report section 9 states them for every recommendation (1600x900: 172.1100/156.1206; 1440x810: 142.4471/126.4577; 1080p@20: 160.5353/149.8757 MHz).",
            "regression": "43 rows and counts (8/22/13) unchanged; dual-core feasible 0; 1080p30 feasible 0; 5 negative-control fixtures still rejected; P1 manifest and b6 core SHA unchanged.",
        },
        "p1_dependency": {
            "manifest": "D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/"
                        "T10.dual-core-resource-baseline/r0/manifest-r0.json",
            "sha256": "228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0",
            "tester_report": "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/"
                             "test-reports/T10.dual-core-resource-baseline-r1-integrated.md",
        },
        "inputs": inputs,
        "artifacts": arts,
        "tools": {
            "python": sys.version.split()[0],
            "td_invocations": 0, "synthesis": 0, "place_route": 0, "bitgen": 0, "cwc": 0,
            "download": 0, "board": 0, "modelsim": 0, "network": 0, "rk": 0,
        },
        "commands": commands,
        "gate_summary": {
            "G0": "pass (22 inputs frozen: 11 anchors + 11 snapshots; 97 assertions, 0 mismatch)",
            "G1": "pass (pure-function model, 43-row grid reproducible, 129-row overhead sensitivity, 146 unit checks, 117 output checks, 5/5 negative-control fixtures rejected)",
            "G2": "not_applicable (no RTL/synthesis/route/candidate)",
            "G3": "not_applicable (no bitgen/CWC)",
            "G4": "not_applicable (no download/board)",
        },
        "local_checks": {
            "gen_assertions": 97,
            "gen_mismatch": 0,
            "test_calc": "146/146 PASS",
            "check_outputs": "117/117 PASS",
            "negative_controls": ["NEG-01a RAW12 PACKING_PROFILE_REJECTED",
                                  "NEG-01b RAW10 1.0x PACKING_MISMATCH",
                                  "NEG-02a aggregate 2C AGGREGATE_CAPACITY_FOR_PER_STREAM",
                                  "NEG-02b chain-margin claim FEASIBLE_CLAIM_BELOW_PER_STREAM_GATE",
                                  "NEG-03 synth STAGE_MIX_SYNTH_IN_FIT"],
            "scenario_rows": len(srows),
            "verdict_counts": counts,
            "frontier_rows": 16,
            "overhead_sensitivity_rows": 129,
            "dual_core_feasible_rows": sum(1 for r in srows if r["verdict"] == "feasible" and r["cores"] == "2"),
            "feasible_1080p30_rows": sum(1 for r in srows if r["verdict"] == "feasible"
                                         and r["W"] == "1920" and r["H"] == "1080" and r["fps"] == "30"),
            "primary": "1600x900-30fps-c1s1-187.5MHz",
            "primary_tier_status": "feasible at 426385 cycles (36.1774%); conditional at 1000000 cycles (21.0486%)",
            "alternates": ["1440x810-30fps-c1s1-187.5MHz", "1920x1080-20fps-c1s1-187.5MHz"],
            "report_table_rows": len(srows),
            "report_sha256": (ROOT / "logs" / "report.sha256").read_text(encoding="utf-8").splitlines()[0].split("=")[1],
        },
        "boundary_resolutions": {
            "full_grad": "1080p full frame (TB default W/H, STAT read_words=129600); .dec 180,425 B is a decimal text capture of 40,076 bytes, not payload",
            "1440x810": "H=810 is not a multiple of 4; valid because W=1440 -> 1,800 B stride and 291,600 integral groups, no padding; model requires W%4==0 and W*H%4==0",
        },
        "excluded": {
            "manifest-r0.json": "manifest does not hash itself",
            "logs/mk_manifest.out.txt": "freeze log written after the manifest with its SHA256",
            "__pycache__/**": "transient interpreter cache",
        },
        "test_input_paths": [
            "input-verified.json", "inputs/frozen-inputs.json", "model/calc.py", "model/rules.json",
            "model/test_calc.py", "model/gen_tables.py", "model/render_report.py", "model/check_outputs.py",
            "out/scenarios.csv", "out/content-sensitivity.csv", "out/ddr-budget.csv", "out/frontier.csv",
            "out/overhead-sensitivity.csv",
            "feasibility-report.md", "commands.jsonl", "logs/gen_tables.out.txt", "logs/test_calc.out.txt",
            "logs/render_report.out.txt", "logs/check_outputs.out.txt", "logs/report.sha256",
        ],
        "caveats": [
            "Natural-image / low-light / noise content unmeasured: comp is not a strict upper bound; no 'guarantee' claim.",
            "Chain overhead 426,385 cycles is assumed constant across content; only full_grad content measured.",
            "The 1600x900@30 primary is feasible only at the primary overhead tier (36.1774%); at 1,000,000 cycles it is 21.0486% (conditional). The all-tier-robust 30 fps tier is 1440x810 (worst 42.9485%).",
            "1-core/2-stream rows use the single-chain 187/300 ERAM bound; a second stream bridge+fabric (+21 -> about 208/300) is not added; still <=270 and verdict unchanged (conservative-low assumption).",
            "Dual-core Routed timing unproven: no dual-core build; 200 MHz also unproven.",
            "DDR uses theoretical 6,400 MB/s peak; sustained bandwidth / PAXI arbitration / single-beat efficiency unproven.",
            "Second full CSI is not in the routed netlist; +773/340/1,474 -> LUT6 26,822, REG 35,815, SLICE ~32,083, ERAM unchanged.",
            "Exact LUT4 not reported by TD (2xLUT6 upper bound); second-stream FIFO ERAM mapping and post-CWC ERAM unproven.",
            "Frame-level drop lower bound only; no cycle-level scheduler / one-outstanding reader / PAXI simulation.",
            "No TD, no synthesis, no route, no bitgen/CWC, no download, no board, no RK: G2-G4 not_applicable; P2 PASS is not a dual-stream system completion.",
        ],
    }

    path = ROOT / "manifest-r0.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    digest = sha256_file(path)
    log = ROOT / "logs" / "mk_manifest.out.txt"
    log.write_text(
        "sha256=%s\nbytes=%d\nartifacts=%d\ninputs=%d\ncommands=%d\n"
        "freeze_order=commands.jsonl -> artifacts -> manifest -> this log (excluded from artifacts)\n"
        "stopped_modifying=true\nactive_commands=0\n"
        % (digest, path.stat().st_size, len(arts), len(inputs), len(commands)),
        encoding="utf-8", newline="\n")
    print("MANIFEST_OK sha256=%s artifacts=%d inputs=%d commands=%d rows=%d"
          % (digest, len(arts), len(inputs), len(commands), len(srows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
