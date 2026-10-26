from __future__ import annotations

import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
OUTPUT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(OUTPUT_ROOT / "candidates/T03.trial-A/r0"))
from trial_common import PROJECT_ROOT, sha256, write_json


def main() -> int:
    ruling = OUTPUT_ROOT / "concurrency-ruling-03.md"
    if sha256(ruling.read_bytes()) != "5502cd1089f46be4e4160d28fdb7f7c89e8122f2fffb60a8188276592116c87f":
        raise RuntimeError("ruling03_sha_mismatch")
    snapshot_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-resumed-03-snapshot.json"
    raw_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-resumed-03-raw-diff.json"
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    raw = json.loads(raw_path.read_text(encoding="utf-8"))
    previous = json.loads((OUTPUT_ROOT / "integrity/T03.trial-A-r0-attribution-resumed-01.json").read_text(encoding="utf-8"))
    observed_files = {entry["absolute_path"]: entry for tree in snapshot["trees"] for entry in tree["entries"] if entry["type"] == "file"}
    dependencies = []
    for entry in previous["required_dependency_checks"]:
        current = observed_files.get(entry["path"])
        dependencies.append({"path": entry["path"], "baseline_sha256": entry["baseline_sha256"], "current_sha256": current["sha256"] if current else None, "unchanged": bool(current and current["sha256"] == entry["baseline_sha256"] and current["bytes"] == entry["bytes"])})
    allowed_root = PROJECT_ROOT / "workflow/runs/20261016_130619_relay_workflow_revision"
    observed_known = []
    unknown = []
    for difference in raw["differences"]:
        if "path" in difference:
            path = Path(difference["root"]) / difference["path"]
            physical = path.resolve()
            if path.is_relative_to(allowed_root) and physical.is_relative_to(allowed_root) and allowed_root.resolve() == allowed_root:
                observed_known.append({"path": str(path), "category": "observed_inside_known_external_run", "source_thread": "01a142b7-d81c-7f23-be03-0f5485d965b3", "source_role": "/root/relay_v2_planner", "observation": difference, "not_used_as_execution_input": True})
            else:
                unknown.append(difference)
        elif difference.get("git_field") == "protected_status":
            for direction, first, second in (("added", difference["before"], difference["after"]), ("removed", difference["after"], difference["before"])):
                for line in sorted(set(second) - set(first)):
                    relative = line[3:].strip('"')
                    path = Path(difference["root"]) / relative
                    record = {"git_change": direction, "git_status": line, "path": str(path)}
                    if path.is_relative_to(allowed_root):
                        observed_known.append(record | {"category": "observed_inside_known_external_run", "source_thread": "01a142b7-d81c-7f23-be03-0f5485d965b3"})
                    else:
                        unknown.append(record)
        else:
            unknown.append(difference)
    if not unknown:
        raise RuntimeError("This stop-only recorder requires independently observed outside-rule differences; it cannot authorize freezing.")
    evidence_paths = [OUTPUT_ROOT / "integrity/protected-baseline.json", ruling, OUTPUT_ROOT / "concurrency-ruling-01.md", OUTPUT_ROOT / "concurrency-ruling-02.md", snapshot_path, raw_path]
    evidence_paths += [OUTPUT_ROOT / "integrity" / filename for filename in (
        "T03.trial-A-r0-freeze-snapshot.json", "T03.trial-A-r0-freeze-diff.json",
        "T03.trial-A-r0-resumed-01-snapshot.json", "T03.trial-A-r0-resumed-01-raw-diff.json", "T03.trial-A-r0-attribution-resumed-01.json",
        "T03.trial-A-r0-resumed-02-snapshot.json", "T03.trial-A-r0-resumed-02-raw-diff.json", "T03.trial-A-r0-attribution-resumed-02.json",
    )]
    result = {
        "task_id": "T03.trial-A", "round": 0, "resume": 3, "state": "confirmed_blocked", "ready_for_freeze": False, "ready_for_test": False,
        "raw_audit_exit_code": 1, "raw_audit_status": raw["status"], "raw_tree_changed": True,
        "evidence": [{"path": str(path), "sha256": sha256(path.read_bytes())} for path in evidence_paths],
        "known_external_observations": observed_known, "unattributed_differences": unknown,
        "required_dependency_checks": dependencies, "read_errors": raw["errors"],
        "source_and_alias_gate": "not_completed_for_freeze_because_two_new_outside_rule_roots_already_confirm_blocking",
        "actual_input_closure_path_intersection_with_known_external_run": [],
        "write_scope": str(OUTPUT_ROOT), "candidate_modified": False, "acceptance_manifest": None,
        "baseline_replaced": False, "additional_exclusions": [],
        "reason": "Two new external run roots and four files lie outside ruling03's unique physical subtree. No source investigation, scope expansion or retry was performed.",
    }
    write_json(OUTPUT_ROOT / "integrity/T03.trial-A-r0-attribution-resumed-03.json", result)
    print(json.dumps({"marker": "TRIAL_A_ATTRIBUTION_DONE", "state": "confirmed_blocked", "ready_for_freeze": False, "unknown_records": len(unknown), "dependencies_unchanged": sum(entry["unchanged"] for entry in dependencies), "dependencies_total": len(dependencies), "read_errors": len(raw["errors"])}, sort_keys=True))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
