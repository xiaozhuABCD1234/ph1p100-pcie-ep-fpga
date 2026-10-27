#!/usr/bin/env python3
"""Final freeze for T10.dual-core-resource-baseline r0 (round1).

Order matters (fixes the round0 F2 binding defect):
  1) verify deliverables and the T2 6/6 PASS log
  2) append this freeze run to commands.jsonl (so the manifest covers it)
  3) hash all artifacts (excluding manifest-r0.json and this freeze log)
  4) write manifest-r0.json
  5) read back its SHA256 and write logs/mk_manifest.out.txt containing it
  6) no further writes

The freeze log is excluded from the manifest to avoid a self-referential hash.
Run only after all other work is finished; this is the last write.
"""
import datetime
import hashlib
import json
import platform
import sys
from pathlib import Path

PROJ = Path("D:/fpga/ph1p100")
RUN = PROJ / "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility"
R0 = RUN / "T10.dual-core-resource-baseline" / "r0"
MANIFEST = R0 / "manifest-r0.json"
FREEZE_LOG = R0 / "logs" / "mk_manifest.out.txt"
FREEZE_PURPOSE = "round1 final freeze (F2): manifest + log self-bound"

REQUIRED = [
    "input-verified.json", "resource-table.csv", "dual-core-budget.csv",
    "resource-baseline.md", "check_tables.py", "gen_baseline.py",
    "commands.jsonl", "result-r0.md", "lessons.md",
    "tests/negative/neg-01-synth-mixed-into-routed-fit.json",
    "tests/negative/neg-02-missing-dramhardcon.json",
    "tests/negative/neg-03-top102x2-single-column.json",
    "logs/gen_baseline.out.txt", "logs/check_tables.out.txt",
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_log_text(path):
    raw = path.read_bytes()
    for enc in ("utf-8", "utf-16", "utf-16-le", "latin-1"):
        try:
            cand = raw.decode(enc)
        except UnicodeDecodeError:
            continue
        if '"status": "PASS"' in cand:
            return cand
    return None


def main():
    missing = [p for p in REQUIRED if not (R0 / p).exists()]
    if missing:
        print(f"BLOCKED missing deliverables: {missing}")
        return 2
    check_log = read_log_text(R0 / "logs/check_tables.out.txt")
    if check_log is None or check_log.count("PASS ") < 6:
        print("BLOCKED: check_tables log is not a 6/6 PASS run")
        return 3
    iv = json.loads((R0 / "input-verified.json").read_text(encoding="utf-8"))
    if iv.get("mismatch_count") != 0:
        print("BLOCKED: input-verified mismatch_count != 0")
        return 4

    cmds_path = R0 / "commands.jsonl"
    cmds = [json.loads(line) for line in cmds_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not any(c.get("purpose") == FREEZE_PURPOSE for c in cmds):
        cmds.append({
            "seq": len(cmds) + 1,
            "argv": ["python", "mk_manifest.py"],
            "cwd": str(R0).replace("\\", "/"),
            "exit": 0,
            "timeout_s": 120,
            "time_local": datetime.date.today().isoformat(),
            "purpose": FREEZE_PURPOSE,
            "result": ("manifest-r0.json written; its SHA256 is recorded in "
                       "logs/mk_manifest.out.txt; stopped_modifying=true, active_commands=0"),
        })
        cmds_path.write_text("".join(json.dumps(c, ensure_ascii=False) + "\n" for c in cmds),
                             encoding="utf-8")

    excluded = {"manifest-r0.json", "logs/mk_manifest.out.txt"}
    artifacts = []
    for p in sorted(R0.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(R0).as_posix()
        if rel in excluded or "__pycache__" in rel:
            continue
        artifacts.append({"path": str(p.resolve()).replace("\\", "/"),
                          "rel": rel, "bytes": p.stat().st_size, "sha256": sha256(p)})
    if len(artifacts) != 15:
        print(f"BLOCKED: expected 15 artifacts, found {len(artifacts)}")
        return 5
    if sum(1 for a in artifacts if a["rel"] == "logs/mk_manifest.out.txt"):
        print("BLOCKED: freeze log must not be an artifact")
        return 6

    manifest = {
        "schema_version": 1,
        "task_id": "T10.dual-core-resource-baseline",
        "run_id": "20261025-195604_fpga-dual-aplus-core-feasibility",
        "round": "r0",
        "repair_round": 1,
        "status": "ready_for_test",
        "stopped_modifying": True,
        "active_commands": 0,
        "freeze_time_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "write_scope": "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/T10.dual-core-resource-baseline/**",
        "worktree": str(PROJ).replace("\\", "/"),
        "round1_fixes": {
            "F1": ("marginal LUT6/LUT4 now use TD identity: 25,709 / 51,418; "
                   "LUT6 headroom 45,971; LUT4 headroom 77,606; "
                   "logic-only lower bound 23,488 is a separate column and not the fit value"),
            "F2": ("this freeze run appends its command, writes the manifest, then writes "
                   "logs/mk_manifest.out.txt containing the final manifest SHA256; log excluded from artifacts"),
            "F3": ("u_camera routed contains only u_csi_a; u_csi_b is not implemented in routed; "
                   "second full CSI cost 773/340/1474/0 is explicitly excluded from marginal and documented"),
        },
        "artifacts": artifacts,
        "inputs": [{"id": x["id"], "role": x["role"], "path": x["path"],
                    "bytes": x["bytes"], "sha256": x["sha256"]} for x in iv["inputs"]],
        "tools": {
            "python": platform.python_version(),
            "td_report_header": "Tang Dynasty Release_2026.2",
            "td_version_line": "TD V6.2.3.210850",
            "device": "PH1P100SBG484",
            "speed": "3",
            "sta_confidence": "Routed",
            "td_invocations": 0,
            "synthesis": 0,
            "place_route": 0,
            "bitgen": 0,
            "cwc": 0,
            "download": 0,
            "board": 0,
            "modelsim": 0,
        },
        "commands": cmds,
        "gate_summary": {
            "G0": "pass (27 inputs frozen, 0 mismatch, 0 drift)",
            "G1": "pass (tables reproducible, TD LUT6 identity, hierarchy closes, 3/3 negative controls rejected)",
            "G2": "not_applicable (no synthesis/route/candidate; synth rows are checkpoints only)",
            "G3": "not_applicable (no bitgen/CWC)",
            "G4": "not_applicable (no download/board)",
        },
        "local_checks": {
            "check_tables": "6/6 PASS, exit 0",
            "negative_controls": ["STAGE_MIX_SYNTH_IN_FIT", "MISSING_DRAMHARDCON",
                                  "MISSING_TWO_COLUMN_BUDGET"],
            "resource_rows": 64,
            "budget_rows": 4,
            "marginal_eram_total": 231,
            "conservative_eram_total": 289,
            "marginal_lut6_td": 25709,
            "marginal_lut4_upper": 51418,
            "dual_core_timing": "unproven",
        },
        "excluded": {
            "manifest-r0.json": "manifest does not hash itself",
            "logs/mk_manifest.out.txt": "freeze log, written after the manifest with its SHA256; excluded to avoid self-reference",
            "__pycache__/**": "transient Python interpreter cache, not evidence",
        },
        "test_input_paths": [
            "input-verified.json", "resource-table.csv", "dual-core-budget.csv",
            "resource-baseline.md", "check_tables.py", "commands.jsonl",
            "tests/negative/*.json", "logs/check_tables.out.txt",
        ],
        "caveats": [
            "Dual-core timing is unproven: no dual-core routed build exists; do not extrapolate single-core WNS.",
            "Conservative 289/300 is an upper bound that also duplicates 2x15 debug CWC ERAM.",
            "Exact LUT4 usage is not reported by TD; LUT4 column is a 2xLUT6 upper bound (51,418 marginal).",
            "Second-stream 6 ERAM and slice 30,733 are derived/assumed; FIFO ERAM mapping needs P3 or a later build.",
            "Second full CSI RX (u_csi_b) is not in the routed netlist and is not included in marginal; if required add 773/340/1474/0 -> LUT6 26,822, REG 35,815.",
            "The round0 tester script independent_verify.py hardcodes the pre-fix marginal LUT6 (23,488) in its expected tuple and cannot pass after F1; the tester must update it for r1.",
            "P1 PASS only means the offline resource tables are reproducible on frozen inputs; it is not synthesis, route, board or production evidence.",
        ],
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    man_sha = sha256(MANIFEST)
    lines = [
        "MANIFEST_OK",
        f"artifacts={len(artifacts)} inputs={len(manifest['inputs'])} commands={len(cmds)}",
        f"manifest={MANIFEST}",
        f"sha256={man_sha}",
        "stopped_modifying=true active_commands=0",
        "freeze_order=commands.jsonl -> artifacts -> manifest -> this log (log excluded from artifacts)",
    ]
    FREEZE_LOG.parent.mkdir(parents=True, exist_ok=True)
    FREEZE_LOG.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
