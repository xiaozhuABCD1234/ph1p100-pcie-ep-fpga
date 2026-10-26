from __future__ import annotations

import json
from pathlib import Path
import re
import stat
import sys

sys.dont_write_bytecode = True
OUTPUT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(OUTPUT_ROOT / "candidates/T03.trial-A/r0"))
from trial_common import PROJECT_ROOT, sha256, write_json


def main() -> int:
    baseline_path = OUTPUT_ROOT / "integrity/protected-baseline.json"
    original_diff_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-freeze-diff.json"
    previous_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-attribution-resumed-01.json"
    snapshot_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-resumed-02-snapshot.json"
    diff_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-resumed-02-raw-diff.json"
    ruling01 = OUTPUT_ROOT / "concurrency-ruling-01.md"
    ruling02 = OUTPUT_ROOT / "concurrency-ruling-02.md"
    pins = {
        baseline_path: "5bd814043c0bfd0c7c70d65f9a4c767137bec42e81caa54e43a9ecf1d7aba97d",
        original_diff_path: "2e2f2154170d3ae712bd9d8d612d13ad628ad7455cb15ffb06b7ae812b1cab92",
        previous_path: "59dcfa2fff98954c8966596afb2a649a829b409e5537f3574eef8e17724ae895",
        ruling01: "07616bb17d24648e6c195ab7f3a7f19866499eaa36a9f08ff22e1ce89a8512fb",
        ruling02: "0835526d9e98adc18aa316d08c287c44342926024c238f5a9ad40a131c381bda",
    }
    evidence = []
    for path in (*pins, snapshot_path, diff_path):
        digest = sha256(path.read_bytes())
        if path in pins and digest != pins[path]:
            raise RuntimeError("pinned_evidence_changed")
        evidence.append({"path": str(path), "sha256": digest})
    original = json.loads(original_diff_path.read_text(encoding="utf-8"))
    previous = json.loads(previous_path.read_text(encoding="utf-8"))
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    raw = json.loads(diff_path.read_text(encoding="utf-8"))
    prefix = "workflow/runs/20261016_130619_relay_workflow_revision"
    log_relative = prefix + "/main-log.md"
    original_by_path = {entry["path"]: entry for entry in original["differences"] if "path" in entry}
    new_paths = [entry for entry in raw["differences"] if "path" in entry and entry["path"] not in original_by_path]
    changed_fixed = [entry for entry in raw["differences"] if "path" in entry and entry["path"] in original_by_path and entry["path"] != log_relative and entry != original_by_path[entry["path"]]]
    snapshot_files = {entry["absolute_path"]: entry for tree in snapshot["trees"] for entry in tree["entries"] if entry["type"] == "file"}
    dependencies = []
    for entry in previous["required_dependency_checks"]:
        current = snapshot_files.get(entry["path"])
        dependencies.append({"path": entry["path"], "baseline_sha256": entry["baseline_sha256"], "current_sha256": current["sha256"] if current else None, "unchanged": bool(current and current["sha256"] == entry["baseline_sha256"] and current["bytes"] == entry["bytes"])})
    log_path = PROJECT_ROOT / log_relative
    log_before = log_path.lstat()
    link = stat.S_ISLNK(log_before.st_mode) or bool(getattr(log_before, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
    log_data = b""
    format_ok = False
    if not link and stat.S_ISREG(log_before.st_mode) and log_before.st_size <= 65536:
        with log_path.open("rb") as stream:
            log_data = stream.read(65537)
        try:
            suffix = log_data[316:].decode("utf-8", errors="strict")
            format_ok = "\x00" not in suffix and all(re.fullmatch(r"- [0-9]{6} [0-9]{4} .+", line) for line in suffix.splitlines() if line)
        except UnicodeDecodeError:
            format_ok = False
    log_after = log_path.lstat()
    stable_read = (log_before.st_size, log_before.st_mtime_ns) == (log_after.st_size, log_after.st_mtime_ns)
    snapshot_log = snapshot_files.get(str(log_path))
    snapshot_match = bool(snapshot_log and sha256(log_data) == snapshot_log["sha256"] and len(log_data) == snapshot_log["bytes"])
    prefix316 = sha256(log_data[:316]) == "cbab2e2e3cafe7ebfe325220c48f591cd130f2a723e592b45068c6bb152927c5"
    prefix463 = sha256(log_data[:463]) == "68e48ebf2e8fb0345135ef51831d7111c73ffdf0a5c4cf675d3324198ba79829"
    log_shape = not link and stable_read and snapshot_match and 463 <= len(log_data) <= 65536 and prefix316 and prefix463 and format_ok
    source_git = next(entry for entry in original["differences"] if entry.get("git_field") == "protected_status")
    current_git = next((entry for entry in raw["differences"] if entry.get("git_field") == "protected_status"), None)
    git_extra = sorted(set(current_git["after"]) - set(source_git["after"])) if current_git else []
    git_missing = sorted(set(source_git["after"]) - set(current_git["after"])) if current_git else source_git["after"]
    unknown = new_paths + changed_fixed + [{"git_status_extra": line} for line in git_extra] + [{"git_status_missing": line} for line in git_missing]
    result = {
        "task_id": "T03.trial-A", "round": 0, "resume": 2, "state": "confirmed_blocked", "ready_for_freeze": False, "ready_for_test": False,
        "raw_audit_exit_code": 1, "raw_audit_status": raw["status"], "raw_tree_changed": True,
        "evidence": evidence, "unattributed_differences": unknown, "unapproved_new_file_count": len(new_paths),
        "required_dependency_checks": dependencies, "read_errors": raw["errors"],
        "external_log_append_shape": {"path": str(log_path), "snapshot_size": snapshot_log["bytes"] if snapshot_log else None, "snapshot_sha256": snapshot_log["sha256"] if snapshot_log else None, "previous_size": 463, "previous_sha256": "68e48ebf2e8fb0345135ef51831d7111c73ffdf0a5c4cf675d3324198ba79829", "original316_prefix_ok": prefix316, "previous463_prefix_ok": prefix463, "strict_utf8_dispatch_lines_ok": format_ok, "stable_single_read": stable_read, "matches_snapshot": snapshot_match, "within_64kib": len(log_data) <= 65536, "append_shape_ok": log_shape, "content_executed": False, "known_owner_thread": "01a142b7-d81c-7f23-be03-0f5485d965b3", "prior_append_execution_record": "exec-d46fc1b3-b9ed-469a-a550-9899ceb6eb3d", "later_append_owner_independent_review": "not_pursued_after_separate_rule_outside_new_files_stop"},
        "reason": "Five additional files in the external run are outside ruling02's single-path bounded-log exception; no automatic expansion or retry.",
        "baseline_replaced": False, "additional_exclusions": [], "candidate_modified": False, "acceptance_manifest": None,
    }
    write_json(OUTPUT_ROOT / "integrity/T03.trial-A-r0-attribution-resumed-02.json", result)
    print(json.dumps({"marker": "TRIAL_A_ATTRIBUTION_DONE", "state": result["state"], "ready_for_freeze": False, "unknown_records": len(unknown), "unapproved_new_file_count": len(new_paths), "dependencies_unchanged": sum(entry["unchanged"] for entry in dependencies), "dependencies_total": len(dependencies), "read_errors": len(raw["errors"]), "log_append_shape_ok": log_shape}, sort_keys=True))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
