from __future__ import annotations

import argparse
import ast
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
OUTPUT_ROOT = Path(__file__).resolve().parent.parent
CANDIDATE = OUTPUT_ROOT / "candidates/T03.trial-A/r0"
sys.path.insert(0, str(CANDIDATE))
from r10f_receiver import MAX_FILE, MAX_PAYLOAD, REASON_PRIORITY, Receiver
from trial_common import PROJECT_ROOT, SAMPLE_SHA256, sha256, write_json
from trial_suite import SEED, emit_fixtures, fixture_cases


def item(path: Path, role: str) -> dict:
    data = path.read_bytes()
    return {"path": str(path.resolve()), "role": role, "type": "file", "bytes": len(data), "sha256": sha256(data)}


def static_check(paths: list[Path]) -> dict:
    own_modules = {path.stem for path in paths}
    imports = set()
    for path in paths:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                imports.update(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imports.add(node.module.split(".")[0])
    unknown = sorted(imports - sys.stdlib_module_names - own_modules)
    if unknown:
        raise RuntimeError(f"nonstdlib_imports: {unknown}")
    return {"status": "pass", "parsed_files": len(paths), "imports": sorted(imports), "third_party_imports": unknown}


def freeze() -> None:
    audit_path = OUTPUT_ROOT / "integrity/T03.trial-A-r0-freeze-diff.json"
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    if audit["status"] != "unchanged" or audit["differences"] or audit["errors"]:
        raise RuntimeError("protected_input_drift")
    candidate_files = sorted(path for path in CANDIDATE.rglob("*") if path.is_file())
    own_paths = candidate_files + [OUTPUT_ROOT / filename for filename in ("run_trial.py", "frame_cli.py", "README.md", "lessons-learned.md")]
    own_paths += sorted((OUTPUT_ROOT / "integrity").glob("*.py"))
    analysis = static_check([path for path in own_paths if path.suffix == ".py"])
    inputs = [item(path, "candidate" if path.is_relative_to(CANDIDATE) else "run_support") for path in own_paths]
    plans = [item(OUTPUT_ROOT / filename, "frozen_plan") for filename in ("dev-plan.md", "fpga-design-guide.md", "input-index.md")]
    original_dir = PROJECT_ROOT / "workflow/runs/20261016_121011_trial_task_design"
    original = [item(original_dir / filename, "original_requirement") for filename in ("new-chat-prompt.md", "request.md", "dev-plan.md", "fpga-design-guide.md", "input-index.md")]
    contract = item(PROJECT_ROOT / "parallel/frame/frame_contract.py", "read_only_contract")
    samples = [item(PROJECT_ROOT / "parallel/evidence/frame_contract_20261015" / filename, "read_only_sample") for filename in SAMPLE_SHA256]
    baseline = item(OUTPUT_ROOT / "integrity/protected-baseline.json", "protected_baseline")
    inputs += plans + original + [contract] + samples + [baseline]
    fixture_index = json.loads((CANDIDATE / "fixtures/index.json").read_text(encoding="utf-8"))
    local_records = []
    for name in ("prefreeze-01", "prefreeze-02", "candidate-01"):
        evidence = OUTPUT_ROOT / "evidence/T03.trial-A/r0/dev" / name
        command = json.loads((evidence / "command.json").read_text(encoding="utf-8"))
        result = json.loads((evidence / "run/result.json").read_text(encoding="utf-8"))
        if command["exit_code"] != 0 or result["failed"] or result["marker"] != "TRIAL_A_DONE":
            raise RuntimeError("local_check_failed")
        local_records.append({"evidence": str(evidence), "command_record": str(evidence / "command.json"), "exit_code": command["exit_code"], "marker": result["marker"], "total": result["total"], "passed": result["passed"], "failed": result["failed"], "binding": "pre_manifest_development"})
    manifest = {
        "schema": 1,
        "run_id": "20261016_124321_trial_execution",
        "task_id": "T03.trial-A", "parent_ids": ["T03"], "round": 0,
        "candidate_root": str(CANDIDATE),
        "entrypoints": {"runner": str(CANDIDATE / "run_trial.py"), "file_cli": str(CANDIDATE / "frame_cli.py"), "receiver_api": str(CANDIDATE / "r10f_receiver.py"), "root_runner": str(OUTPUT_ROOT / "run_trial.py"), "root_file_cli": str(OUTPUT_ROOT / "frame_cli.py")},
        "frozen_inputs": inputs,
        "plans": plans,
        "source_contract": contract, "source_samples": samples,
        "protected_baseline": baseline,
        "freeze_integrity": {"snapshot": str(OUTPUT_ROOT / "integrity/T03.trial-A-r0-freeze-snapshot.json"), "diff": str(audit_path), "diff_sha256": sha256(audit_path.read_bytes()), "status": "unchanged"},
        "codec": {"applicable": False, "reason": "A is uncompressed; codec tree remains included in protected baseline."},
        "a_frozen_manifest": None,
        "profile": {"version": [1, 0], "header_bytes": 128, "codec_id": 0, "format_packing": [[0, 0], [1, 1]], "valid_bits": 10, "block_count": 1, "camera_ids": [0, 1], "phases": [0, 1, 2, 3], "flags": 0, "roi": [0, 0], "direction": 0, "mode_id": 1, "max_width": 3840, "max_height": 2160, "max_payload": MAX_PAYLOAD, "max_file": MAX_FILE, "alignment": 32, "row_padding": False, "seed": SEED, "k": None},
        "fixture_count": len(fixture_index), "fixtures": fixture_index,
        "error_priority": list(REASON_PRIORITY),
        "error_matrix": [entry for entry in fixture_index if entry["expected"] != "accepted"],
        "python": {"executable": sys.executable, "version": sys.version, "bytecode_disabled": sys.dont_write_bytecode, "dependencies": "standard library only"},
        "static_analysis": analysis,
        "actual_local_checks": local_records,
        "suggested_commands": [
            {"argv": [sys.executable, "-B", str(CANDIDATE / "run_trial.py"), "--task", "A", "--project-root", str(PROJECT_ROOT), "--out", str(OUTPUT_ROOT / "evidence/T03.trial-A/r0/REPLACE_WITH_FRESH_NAME")], "cwd": str(OUTPUT_ROOT)},
            {"argv": [sys.executable, "-B", str(CANDIDATE / "frame_cli.py"), "--project-root", str(PROJECT_ROOT), "--input", str(samples[0]["path"]), "--out", str(OUTPUT_ROOT / "evidence/T03.trial-A/r0/REPLACE_WITH_FRESH_FILE_NAME")], "cwd": str(OUTPUT_ROOT)},
        ],
        "exit_codes": {"success": 0, "protocol_rejection_or_regression_failure": 1, "call_io_dependency_error": 2},
        "completion_markers": {"runner": "TRIAL_A_DONE", "file_cli": "R10F_RECEIVE_DONE", "file_call_error": "R10F_CALL_ERROR"},
        "gates": {"G0": {"applicable": True, "threshold": "Frozen trial-only field, size, length, padding, CRC and publication semantics."}, "G1": {"applicable": True, "threshold": "All expected samples/RAW bytes exact, every negative category rejected without publication, CLI codes/recovery, deterministic fresh reruns and protected audits."}, "G2": {"applicable": False, "reason": "No RTL, constraints, IP, synthesis, STA or CDC change."}, "G3": {"applicable": False, "reason": "No board download or hardware observation."}, "G4": {"applicable": False, "reason": "No hardware stability, thermal or throughput test."}, "G5": {"applicable": False, "reason": "No FPGA-to-RK integration, DMA or publication."}},
        "ownership": {"all_new_writes": str(OUTPUT_ROOT), "protected_roots": [str(PROJECT_ROOT), "C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道"], "main_state_owner": "orchestrator", "formal_parent_state_updated": False},
    }
    destination = OUTPUT_ROOT / "manifests/T03.trial-A-r0.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    write_json(destination, manifest)
    print(json.dumps({"marker": "TRIAL_A_FROZEN", "manifest": str(destination), "sha256": sha256(destination.read_bytes()), "inputs": len(inputs), "fixture_count": len(fixture_index)}, ensure_ascii=True, sort_keys=True))


def compare_runs() -> None:
    paths = [OUTPUT_ROOT / "evidence/T03.trial-A/r0/dev" / name / "run/result.json" for name in ("frozen-01", "frozen-02")]
    results = [json.loads(path.read_text(encoding="utf-8")) for path in paths]
    raw_maps = []
    for path in paths:
        raw_maps.append({raw.relative_to(path.parent).as_posix(): sha256(raw.read_bytes()) for raw in (path.parent / "cli").rglob("raw.bin")})
    manifest_path = OUTPUT_ROOT / "manifests/T03.trial-A-r0.json"
    passed = all(result["failed"] == 0 and result["total"] == result["passed"] and result["marker"] == "TRIAL_A_DONE" for result in results)
    passed = passed and results[0]["fixture_sha256"] == results[1]["fixture_sha256"] and raw_maps[0] == raw_maps[1] and bool(raw_maps[0])
    summary = {"marker": "TRIAL_A_DETERMINISM_DONE", "passed": passed, "manifest_path": str(manifest_path), "manifest_sha256": sha256(manifest_path.read_bytes()), "result_paths": [str(path) for path in paths], "fixture_count": len(results[0]["fixture_sha256"]), "restored_raw_count": len(raw_maps[0]), "raw_sha256": raw_maps[0], "non_deterministic_fields": ["absolute output paths", "command paths", "cwd"], "totals": [{key: result[key] for key in ("total", "passed", "failed")} for result in results]}
    write_json(OUTPUT_ROOT / "evidence/T03.trial-A/r0/dev/frozen-determinism.json", summary)
    print(json.dumps({"marker": summary["marker"], "passed": passed, "fixture_count": summary["fixture_count"], "restored_raw_count": summary["restored_raw_count"]}, sort_keys=True))
    if not passed:
        raise RuntimeError("fresh_run_nondeterminism")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("emit-fixtures", "freeze", "compare-runs"))
    arguments = parser.parse_args()
    if arguments.action == "emit-fixtures":
        entries = emit_fixtures(fixture_cases(Receiver(PROJECT_ROOT), PROJECT_ROOT), CANDIDATE / "fixtures")
        print(json.dumps({"marker": "TRIAL_A_FIXTURES_FROZEN", "count": len(entries)}, sort_keys=True))
    elif arguments.action == "freeze":
        freeze()
    else:
        compare_runs()


if __name__ == "__main__":
    main()
