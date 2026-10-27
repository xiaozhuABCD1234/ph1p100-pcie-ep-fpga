from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
OUTPUT_ROOT = Path(__file__).resolve().parent.parent
CANDIDATE = OUTPUT_ROOT / "candidates/T03.trial-A/r0"
sys.path.insert(0, str(CANDIDATE))
from r10f_receiver import MAX_FILE, MAX_PAYLOAD, REASON_PRIORITY
from trial_common import PROJECT_ROOT, SAMPLE_SHA256, sha256, write_json
from trial_suite import SEED
from freeze_a import item, static_check

PINS = {
    "integrity/protected-baseline.json": "5bd814043c0bfd0c7c70d65f9a4c767137bec42e81caa54e43a9ecf1d7aba97d",
    "integrity/T03.trial-A-r0-freeze-diff.json": "2e2f2154170d3ae712bd9d8d612d13ad628ad7455cb15ffb06b7ae812b1cab92",
    "concurrency-ruling-01.md": "07616bb17d24648e6c195ab7f3a7f19866499eaa36a9f08ff22e1ce89a8512fb",
}
ATTRIBUTED_PREFIX = "workflow/runs/20261016_130619_relay_workflow_revision"
ATTRIBUTED_FILES = {
    "images.md": (1836, "4bd145d9a7498e1c3be3d6f0ad5d951302d2f2b8394580f910aa7a6af9c7759e"),
    "main-log.md": (316, "cbab2e2e3cafe7ebfe325220c48f591cd130f2a723e592b45068c6bb152927c5"),
    "request.md": (938, "5f57e6ca81ea976765aa9b9d8bed872a2cafc2a474b718204e9458f52ba21155"),
}


def classify() -> dict:
    evidence = []
    for relative, expected in PINS.items():
        record = item(OUTPUT_ROOT / relative, "immutable_concurrency_evidence")
        if record["sha256"] != expected:
            raise RuntimeError(f"pinned_evidence_changed: {relative}")
        evidence.append(record)
    baseline = json.loads((OUTPUT_ROOT / "integrity/protected-baseline.json").read_text(encoding="utf-8"))
    original_diff = json.loads((OUTPUT_ROOT / "integrity/T03.trial-A-r0-freeze-diff.json").read_text(encoding="utf-8"))
    snapshot_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-resumed-01-snapshot.json"
    raw_diff_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-resumed-01-raw-diff.json"
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    raw_diff = json.loads(raw_diff_path.read_text(encoding="utf-8"))
    expected_changes = original_diff["differences"]
    actual_changes = raw_diff["differences"]
    unknown = [entry for entry in actual_changes if entry not in expected_changes]
    missing = [entry for entry in expected_changes if entry not in actual_changes]
    entries = {entry["relative_path"]: entry for entry in snapshot["trees"][0]["entries"]}
    exact_attributed = []
    for filename, (size, digest) in ATTRIBUTED_FILES.items():
        relative = ATTRIBUTED_PREFIX + "/" + filename
        observed = entries.get(relative)
        valid = bool(observed and observed["type"] == "file" and observed["bytes"] == size and observed["sha256"] == digest)
        exact_attributed.append({"path": relative, "bytes": size, "sha256": digest, "exact_match": valid})
    descendants = sorted(relative for relative in entries if relative.startswith(ATTRIBUTED_PREFIX + "/"))
    directory = entries.get(ATTRIBUTED_PREFIX)
    directory_exact = bool(directory and directory["type"] == "directory" and not directory["empty"] and descendants == sorted(ATTRIBUTED_PREFIX + "/" + name for name in ATTRIBUTED_FILES))
    dependencies = [PROJECT_ROOT / "parallel/frame/frame_contract.py", PROJECT_ROOT / "workflow/tasks.json", PROJECT_ROOT / "AGENTS.md"]
    dependencies += [PROJECT_ROOT / "parallel/evidence/frame_contract_20261015" / filename for filename in SAMPLE_SHA256]
    dependencies += sorted((PROJECT_ROOT / ".agents/skills").glob("fpga-*/SKILL.md"))
    dependencies += [PROJECT_ROOT / ".agents/skills/fpga-orchestrator/references" / filename for filename in ("report-contract.md", "project-context.md")]
    old_run = PROJECT_ROOT / "workflow/runs/20261016_121011_trial_task_design"
    dependencies += [old_run / filename for filename in ("new-chat-prompt.md", "request.md", "dev-plan.md", "fpga-design-guide.md", "input-index.md")]
    dependencies += [Path(snapshot["trees"][1]["root"]) / "tools/bayer_codec/codec.py"]
    baseline_files = {entry["absolute_path"]: entry for tree in baseline["trees"] for entry in tree["entries"] if entry["type"] == "file"}
    dependency_checks = []
    for path in dependencies:
        expected = baseline_files[str(path)]
        current = item(path, "required_read_only_dependency")
        current["baseline_sha256"] = expected["sha256"]
        current["unchanged"] = current["sha256"] == expected["sha256"] and current["bytes"] == expected["bytes"]
        dependency_checks.append(current)
    errors = raw_diff["errors"]
    ready = bool(actual_changes) and not unknown and not missing and directory_exact and all(entry["exact_match"] for entry in exact_attributed) and all(entry["unchanged"] for entry in dependency_checks) and not errors
    result = {
        "task_id": "T03.trial-A", "round": 0, "raw_tree_changed": bool(actual_changes),
        "raw_audit_exit_code": 1, "raw_audit_status": raw_diff["status"],
        "evidence": evidence + [item(snapshot_path, "new_full_tree_snapshot"), item(raw_diff_path, "new_raw_diff")],
        "attributed_directory": {"path": ATTRIBUTED_PREFIX, "exact_children_only": directory_exact},
        "attributed_files": exact_attributed,
        "attributed_git_additions": ["?? " + ATTRIBUTED_PREFIX + "/" + filename for filename in ATTRIBUTED_FILES],
        "raw_difference_count": len(actual_changes), "unattributed_differences": unknown, "missing_expected_differences": missing,
        "required_dependency_checks": dependency_checks, "read_errors": errors,
        "ready_for_freeze": ready,
        "classification": "exact_known_independent_chat_increment" if ready else "blocked_concurrent_change",
        "scope_unchanged": True, "baseline_replaced": False, "additional_exclusions": [],
    }
    destination = OUTPUT_ROOT / "integrity/T03.trial-A-r0-attribution-resumed-01.json"
    write_json(destination, result)
    print(json.dumps({"marker": "TRIAL_A_ATTRIBUTION_DONE", "ready_for_freeze": ready, "raw_tree_changed": bool(actual_changes), "unknown": len(unknown), "missing": len(missing), "dependencies": len(dependency_checks), "read_errors": len(errors)}, sort_keys=True))
    if not ready:
        raise RuntimeError("attribution_blocked")
    return result


def freeze() -> None:
    attribution_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-attribution-resumed-01.json"
    attribution = json.loads(attribution_path.read_text(encoding="utf-8"))
    if not attribution["ready_for_freeze"] or attribution["unattributed_differences"] or attribution["read_errors"]:
        raise RuntimeError("attribution_not_ready")
    for entry in attribution["evidence"]:
        if sha256(Path(entry["path"]).read_bytes()) != entry["sha256"]:
            raise RuntimeError("attribution_evidence_changed")
    for entry in attribution["required_dependency_checks"]:
        if not entry["unchanged"] or sha256(Path(entry["path"]).read_bytes()) != entry["sha256"]:
            raise RuntimeError("required_dependency_changed")
    own_paths = sorted(path for path in CANDIDATE.rglob("*") if path.is_file())
    own_paths += [OUTPUT_ROOT / filename for filename in ("run_trial.py", "frame_cli.py", "README.md", "README-resumed-A.md", "lessons-learned.md", "lessons-learned-resumed-A.md")]
    own_paths += sorted((OUTPUT_ROOT / "integrity").glob("*.py"))
    analysis = static_check([path for path in own_paths if path.suffix == ".py"])
    inputs = [item(path, "candidate" if path.is_relative_to(CANDIDATE) else "run_support") for path in own_paths]
    plans = [item(OUTPUT_ROOT / filename, "frozen_plan") for filename in ("dev-plan.md", "fpga-design-guide.md", "input-index.md", "concurrency-ruling-01.md")]
    inputs += plans
    inputs += [{key: value for key, value in entry.items() if key not in ("unchanged", "baseline_sha256")} for entry in attribution["required_dependency_checks"]]
    integrity_evidence = attribution["evidence"] + [item(attribution_path, "precise_concurrency_attribution")]
    inputs += [entry for entry in integrity_evidence if entry["path"] not in {plan["path"] for plan in plans}]
    fixture_index = json.loads((CANDIDATE / "fixtures/index.json").read_text(encoding="utf-8"))
    source_contract = next(entry for entry in inputs if entry["path"] == str(PROJECT_ROOT / "parallel/frame/frame_contract.py"))
    source_samples = [entry for entry in inputs if Path(entry["path"]).name in SAMPLE_SHA256]
    manifest = {
        "schema": 1, "run_id": "20261016_124321_trial_execution", "task_id": "T03.trial-A", "parent_ids": ["T03"], "round": 0,
        "candidate_root": str(CANDIDATE),
        "entrypoints": {"runner": str(CANDIDATE / "run_trial.py"), "file_cli": str(CANDIDATE / "frame_cli.py"), "receiver_api": str(CANDIDATE / "r10f_receiver.py"), "root_runner": str(OUTPUT_ROOT / "run_trial.py"), "root_file_cli": str(OUTPUT_ROOT / "frame_cli.py"), "current_readme": str(OUTPUT_ROOT / "README-resumed-A.md")},
        "frozen_inputs": inputs, "plans": plans,
        "source_contract": source_contract, "source_samples": source_samples,
        "integrity_evidence": integrity_evidence,
        "protected_baseline": next(entry for entry in integrity_evidence if entry["path"].endswith("protected-baseline.json")),
        "concurrency": {"ruling": next(entry for entry in plans if entry["path"].endswith("concurrency-ruling-01.md")), "attribution": item(attribution_path, "precise_concurrency_attribution"), "raw_tree_changed": True, "raw_exit_code": 1, "raw_status": "blocked_concurrent_change", "ready_for_freeze": True, "unknown_residual_count": 0, "baseline_replaced": False, "new_exclusions": [], "meaning": "All actual dependencies unchanged; protected additions exactly attributed to the independent chat by ruling01. The protected tree did change."},
        "codec": {"applicable": False, "reason": "A is uncompressed; codec source is nevertheless protected and rehashed."}, "a_frozen_manifest": None,
        "profile": {"version": [1, 0], "header_bytes": 128, "codec_id": 0, "format_packing": [[0, 0], [1, 1]], "valid_bits": 10, "block_count": 1, "camera_ids": [0, 1], "phases": [0, 1, 2, 3], "flags": 0, "roi": [0, 0], "direction": 0, "mode_id": 1, "max_width": 3840, "max_height": 2160, "max_payload": MAX_PAYLOAD, "max_file": MAX_FILE, "alignment": 32, "row_padding": False, "seed": SEED, "k": None},
        "fixture_count": len(fixture_index), "fixtures": fixture_index, "error_priority": list(REASON_PRIORITY), "error_matrix": [entry for entry in fixture_index if entry["expected"] != "accepted"],
        "python": {"executable": sys.executable, "version": sys.version, "bytecode_disabled": sys.dont_write_bytecode, "dependencies": "standard library only"}, "static_analysis": analysis,
        "suggested_commands": [{"argv": [sys.executable, "-B", str(CANDIDATE / "run_trial.py"), "--task", "A", "--project-root", str(PROJECT_ROOT), "--out", str(OUTPUT_ROOT / "evidence/T03.trial-A/r0/REPLACE_WITH_FRESH_NAME")], "cwd": str(OUTPUT_ROOT)}],
        "exit_codes": {"success": 0, "protocol_rejection_or_regression_failure": 1, "call_io_dependency_error": 2}, "completion_markers": {"runner": "TRIAL_A_DONE", "file_cli": "R10F_RECEIVE_DONE", "file_call_error": "R10F_CALL_ERROR"},
        "gates": {"G0": {"applicable": True, "threshold": "Frozen trial-only field, size, length, padding, CRC and publication semantics."}, "G1": {"applicable": True, "threshold": "Exact positive samples and RAW, no rejected publication, precise reasons, file-CLI exit codes/recovery, deterministic fresh reruns, exact concurrency attribution and stable dependencies."}, "G2": {"applicable": False, "reason": "No RTL, constraints, IP, synthesis, STA or CDC change."}, "G3": {"applicable": False, "reason": "No board download or hardware observation."}, "G4": {"applicable": False, "reason": "No hardware stability, thermal or throughput test."}, "G5": {"applicable": False, "reason": "No FPGA-to-RK integration, DMA or publication."}},
        "formal_parent_state_updated": False, "original_blocked_handoff": str(OUTPUT_ROOT / "handoffs/T03.trial-A-r0.md"), "current_handoff": str(OUTPUT_ROOT / "handoffs/T03.trial-A-r0-resumed-01.md"),
    }
    destination = OUTPUT_ROOT / "manifests/T03.trial-A-r0.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    write_json(destination, manifest)
    print(json.dumps({"marker": "TRIAL_A_FROZEN", "manifest": str(destination), "sha256": sha256(destination.read_bytes()), "inputs": len(inputs), "fixture_count": len(fixture_index)}, ensure_ascii=True, sort_keys=True))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("classify", "freeze"))
    arguments = parser.parse_args()
    if arguments.action == "classify":
        classify()
    else:
        freeze()


if __name__ == "__main__":
    main()
