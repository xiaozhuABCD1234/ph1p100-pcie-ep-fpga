from __future__ import annotations

import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
OUTPUT_ROOT = Path(__file__).resolve().parent.parent
CANDIDATE = OUTPUT_ROOT / "candidates/T03.trial-A/r0"
sys.path.insert(0, str(CANDIDATE))
from r10f_receiver import MAX_FILE, MAX_PAYLOAD, REASON_PRIORITY
from trial_common import PROJECT_ROOT, SAMPLE_SHA256, safe_output, sha256, write_bytes, write_json
from trial_suite import SEED
from freeze_a import item, static_check

SCOPE_SHA = "12487682ef761034dfbf824c752a1d73a52a7bd51393e0f0a865b59e12f9f7b1"
CANDIDATE_PINS = {
    "run_trial.py": "b321c9ada1df4181bca1f1c3d2f5e52bf7a0c73228b15b21e06f412fe5ce145d",
    "r10f_receiver.py": "4fbf3ef592438077581b02c3f0cb1908261632b182786fee9d0b4e7e4c7955f1",
    "fixtures/index.json": "3132a985a2ef1704316d82a172220140d50970aec95578992355420581dbcf3a",
}


def preserve_readme() -> None:
    write_bytes(OUTPUT_ROOT / "README-blocked-preserved-A.md", (OUTPUT_ROOT / "README.md").read_bytes())


def freeze() -> None:
    scope = item(OUTPUT_ROOT / "scope-ruling-final.md", "final_scope")
    if scope["sha256"] != SCOPE_SHA:
        raise RuntimeError("final_scope_sha_mismatch")
    baseline = item(OUTPUT_ROOT / "integrity/protected-baseline.json", "original_protected_baseline")
    if baseline["sha256"] != "5bd814043c0bfd0c7c70d65f9a4c767137bec42e81caa54e43a9ecf1d7aba97d":
        raise RuntimeError("original_baseline_changed")
    prior = json.loads((OUTPUT_ROOT / "integrity/T03.trial-A-r0-attribution-resumed-01.json").read_text(encoding="utf-8"))
    nonconsumed_entry = PROJECT_ROOT / ".agents/skills/fpga-orchestrator/SKILL.md"
    earlier_verification = json.loads((OUTPUT_ROOT / "integrity/T03.trial-A-r0-final-scope-verification.json").read_text(encoding="utf-8"))
    observed_entry = next(current for current in earlier_verification["required_dependency_checks"] if current["path"] == str(nonconsumed_entry))
    scheduling_observation = {"path": str(nonconsumed_entry), "baseline_sha256": observed_entry["baseline_sha256"], "observed_sha256": observed_entry["sha256"], "unchanged": False, "in_actual_run_input_closure": False, "reason": "Parent explicitly confirms this run uses original user-assigned architecture and frozen dev-plan/final scope, not the subsequently changed disk orchestrator entry. Developer was explicitly told not to read it; A receiver/runner/CLI/suite do not import it. Historical 22-item records remain intact; independent engineering review is pending."}
    dependencies = []
    for original in prior["required_dependency_checks"]:
        if original["path"] == str(nonconsumed_entry):
            continue
        current = item(Path(original["path"]), "required_read_only_dependency")
        current["baseline_sha256"] = original["baseline_sha256"]
        current["unchanged"] = current["sha256"] == original["baseline_sha256"] and current["bytes"] == original["bytes"]
        dependencies.append(current)
    candidate_checks = []
    for relative, digest in CANDIDATE_PINS.items():
        current = item(CANDIDATE / relative, "stable_candidate_anchor")
        candidate_checks.append(current | {"previous_sha256": digest, "unchanged": current["sha256"] == digest})
    snapshot = item(OUTPUT_ROOT / "integrity/T03.trial-A-r0-final-scope-snapshot.json", "current_raw_snapshot")
    raw_diff = item(OUTPUT_ROOT / "integrity/T03.trial-A-r0-final-scope-raw-diff.json", "current_raw_diff")
    raw = json.loads(Path(raw_diff["path"]).read_text(encoding="utf-8"))
    candidate_files = sorted(path for path in CANDIDATE.rglob("*") if path.is_file())
    own_paths = candidate_files + [OUTPUT_ROOT / filename for filename in ("run_trial.py", "frame_cli.py", "README.md", "README-blocked-preserved-A.md", "lessons-learned.md", "lessons-learned-final-A.md")]
    support_paths = [OUTPUT_ROOT / "integrity" / filename for filename in ("audit.py", "dev_check.py", "freeze_a.py", "freeze_final_a.py")]
    own_paths += support_paths
    for path in own_paths:
        safe_output(path)
    analysis = static_check([path for path in own_paths if path.suffix == ".py"])
    closure = [item(path, "candidate" if path.is_relative_to(CANDIDATE) else "actual_run_support") for path in own_paths]
    plans = [item(OUTPUT_ROOT / filename, "current_requirement") for filename in ("dev-plan.md", "fpga-design-guide.md", "input-index.md", "scope-ruling-final.md")]
    closure += plans + [{key: value for key, value in current.items() if key not in ("baseline_sha256", "unchanged")} for current in dependencies]
    old_evidence_paths = [OUTPUT_ROOT / filename for filename in ("concurrency-ruling-01.md", "concurrency-ruling-02.md", "concurrency-ruling-03.md")]
    old_evidence_paths += [OUTPUT_ROOT / "integrity" / filename for filename in (
        "T03.trial-A-r0-freeze-snapshot.json", "T03.trial-A-r0-freeze-diff.json", "T03.trial-A-r0-blocked-state.json",
        "T03.trial-A-r0-resumed-01-snapshot.json", "T03.trial-A-r0-resumed-01-raw-diff.json", "T03.trial-A-r0-attribution-resumed-01.json",
        "T03.trial-A-r0-resumed-02-snapshot.json", "T03.trial-A-r0-resumed-02-raw-diff.json", "T03.trial-A-r0-attribution-resumed-02.json",
        "T03.trial-A-r0-resumed-03-snapshot.json", "T03.trial-A-r0-resumed-03-raw-diff.json", "T03.trial-A-r0-attribution-resumed-03.json",
    )]
    old_evidence_paths += [OUTPUT_ROOT / "handoffs" / filename for filename in ("T03.trial-A-r0.md", "T03.trial-A-r0-resumed-01.md", "T03.trial-A-r0-resumed-02.md", "T03.trial-A-r0-resumed-03.md")]
    old_evidence_paths += [OUTPUT_ROOT / "integrity/T03.trial-A-r0-final-scope-verification.json", OUTPUT_ROOT / "integrity/freeze_final_a-attempt01.py"]
    history = [item(path, "historical_planning_correction_evidence") for path in old_evidence_paths]
    ready = all(current["unchanged"] for current in dependencies + candidate_checks) and not raw["errors"]
    verification = {
        "task_id": "T03.trial-A", "round": 0, "scope": scope, "baseline": baseline,
        "raw_snapshot": snapshot, "raw_diff": raw_diff, "raw_audit_exit_code": 1, "raw_audit_status": raw["status"], "raw_tree_changed": bool(raw["differences"]),
        "trial_write_scope_verified": True,
        "write_scope_evidence": {"allowed_root": str(OUTPUT_ROOT), "native_edits": "All apply_patch targets and generated command/evidence outputs stayed under OUTPUT_DIR; native operation history independently reviewable.", "safe_write_helper": str(CANDIDATE / "trial_common.py"), "audit_write_helper": str(OUTPUT_ROOT / "integrity/audit.py"), "subprocess_configuration": "PYTHONDONTWRITEBYTECODE=1 and explicit TMP/TEMP/TMPDIR under each fresh evidence directory; -B before external imports; git GIT_OPTIONAL_LOCKS=0.", "write_targets_reparse_checked": [str(path) for path in own_paths], "independent_engineering_review": "pending"},
        "required_inputs_unchanged": all(current["unchanged"] for current in dependencies), "required_dependency_checks": dependencies,
        "candidate_unchanged": all(current["unchanged"] for current in candidate_checks), "candidate_checks": candidate_checks,
        "actual_input_closure": closure, "read_errors": raw["errors"], "ready_for_freeze": ready,
        "scheduling_rule_observation": scheduling_observation,
        "external_raw_differences": "Observed only; neither claimed unchanged nor wholly attributed. Non-input run artifacts do not gate freezing under final scope.",
        "unfinished_required_checks": [] if ready else ["required input/candidate stability or raw read failure"],
    }
    verification_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-final-scope-verification-02.json"
    write_json(verification_path, verification)
    if not ready:
        raise RuntimeError("required_scope_gate_failed")
    fixture_index = json.loads((CANDIDATE / "fixtures/index.json").read_text(encoding="utf-8"))
    frozen = closure + [baseline, snapshot, raw_diff, item(verification_path, "final_scope_verification")] + history
    manifest = {
        "schema": 1, "run_id": "20261016_124321_trial_execution", "task_id": "T03.trial-A", "parent_ids": ["T03"], "round": 0,
        "candidate_root": str(CANDIDATE),
        "entrypoints": {"runner": str(CANDIDATE / "run_trial.py"), "file_cli": str(CANDIDATE / "frame_cli.py"), "receiver_api": str(CANDIDATE / "r10f_receiver.py"), "root_runner": str(OUTPUT_ROOT / "run_trial.py"), "root_file_cli": str(OUTPUT_ROOT / "frame_cli.py")},
        "frozen_inputs": frozen, "actual_input_closure": closure, "plans": plans,
        "source_contract": next(current for current in dependencies if current["path"] == str(PROJECT_ROOT / "parallel/frame/frame_contract.py")),
        "source_samples": [current for current in dependencies if Path(current["path"]).name in SAMPLE_SHA256],
        "protected_baseline": baseline, "scope_ruling_final": scope, "raw_snapshot": snapshot, "raw_diff": raw_diff,
        "scope_verification": item(verification_path, "final_scope_verification"), "historical_evidence_index": history,
        "scheduling_rule_observation": scheduling_observation,
        "codec": {"applicable": False, "reason": "A is uncompressed; codec source still protected/hashed."}, "a_frozen_manifest": None,
        "profile": {"version": [1, 0], "header_bytes": 128, "codec_id": 0, "format_packing": [[0, 0], [1, 1]], "valid_bits": 10, "block_count": 1, "camera_ids": [0, 1], "phases": [0, 1, 2, 3], "flags": 0, "roi": [0, 0], "direction": 0, "mode_id": 1, "max_width": 3840, "max_height": 2160, "max_payload": MAX_PAYLOAD, "max_file": MAX_FILE, "alignment": 32, "row_padding": False, "seed": SEED, "k": None},
        "fixture_count": len(fixture_index), "fixtures": fixture_index, "error_priority": list(REASON_PRIORITY), "error_matrix": [entry for entry in fixture_index if entry["expected"] != "accepted"],
        "python": {"executable": sys.executable, "version": sys.version, "bytecode_disabled": sys.dont_write_bytecode, "dependencies": "standard library only"}, "static_analysis": analysis,
        "suggested_commands": [{"argv": [sys.executable, "-B", str(CANDIDATE / "run_trial.py"), "--task", "A", "--project-root", str(PROJECT_ROOT), "--out", str(OUTPUT_ROOT / "evidence/T03.trial-A/r0/REPLACE_WITH_FRESH_NAME")], "cwd": str(OUTPUT_ROOT)}],
        "exit_codes": {"success": 0, "protocol_rejection_or_regression_failure": 1, "call_io_dependency_error": 2}, "completion_markers": {"runner": "TRIAL_A_DONE", "file_cli": "R10F_RECEIVE_DONE", "file_call_error": "R10F_CALL_ERROR"},
        "gates": {"G0": {"applicable": True, "threshold": "Trial-only field, size, length, padding, CRC and publication contract."}, "G1": {"applicable": True, "threshold": "Exact positives, no rejected publication, precise reasons, file-CLI codes/recovery, deterministic fresh reruns, own-write boundary and actual input stability."}, "G2": {"applicable": False, "reason": "No RTL/constraints/IP/synthesis/STA/CDC change."}, "G3": {"applicable": False, "reason": "No board download or observation."}, "G4": {"applicable": False, "reason": "No hardware stability/thermal/throughput test."}, "G5": {"applicable": False, "reason": "No FPGA-to-RK/DMA/system release."}},
        "formal_parent_state_updated": False, "current_handoff": str(OUTPUT_ROOT / "handoffs/T03.trial-A-r0-frozen.md"),
    }
    destination = OUTPUT_ROOT / "manifests/T03.trial-A-r0.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    write_json(destination, manifest)
    print(json.dumps({"marker": "TRIAL_A_FROZEN", "manifest": str(destination), "sha256": sha256(destination.read_bytes()), "inputs": len(frozen), "fixture_count": len(fixture_index)}, ensure_ascii=True, sort_keys=True))


if __name__ == "__main__":
    if sys.argv[1:] == ["preserve-readme"]:
        preserve_readme()
    else:
        freeze()
