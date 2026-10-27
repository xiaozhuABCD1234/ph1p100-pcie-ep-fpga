"""Read-only candidate checks; writes only this system tester's evidence JSON."""
from pathlib import Path
import difflib
import hashlib
import json
import re
import sys
from datetime import datetime

ROOT = Path(__file__).resolve().parents[4]
RUN = Path(__file__).resolve().parents[1]
MANIFEST = RUN / "candidate-manifest.json"
manifest = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
baseline = json.loads((RUN / "baseline-index.json").read_text(encoding="utf-8-sig"))
checks = []


def record(name, passed, detail):
    checks.append({"name": name, "passed": bool(passed), "detail": detail})


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def content(path):
    return path.read_text(encoding="utf-8-sig")


def section(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


record("actual_project_root", ROOT == Path(manifest["project_root"]).resolve(), str(ROOT))
all_items = manifest["candidate_files"] + manifest["supporting_artifacts"] + manifest["baseline_artifacts"]
path_errors = []
hash_errors = []
for item in all_items:
    path = Path(item["path"]).resolve()
    if not path.is_relative_to(ROOT):
        path_errors.append(str(path))
    if not path.is_file() or digest(path) != item["sha256"]:
        hash_errors.append(str(path))
record("frozen_paths_within_project", not path_errors, path_errors)
record("all_frozen_hashes_match", not hash_errors, {"count": len(all_items), "errors": hash_errors})
record("candidate_count", len(manifest["candidate_files"]) == 16, len(manifest["candidate_files"]))
record("developer_stopped", manifest["developer_stopped_modifying"] is True, manifest["status"])

diffs = []
baseline_errors = []
for item in manifest["candidate_files"]:
    relative = item["relative_path"]
    old_path = RUN / "baseline" / relative
    if item["change"] == "modified" and digest(old_path) != item["before_sha256"]:
        baseline_errors.append(relative)
    before = content(old_path) if old_path.exists() else ""
    after = content(ROOT / relative)
    diffs.extend(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True), fromfile="before/" + relative, tofile="after/" + relative))
record("baseline_before_hashes", not baseline_errors, baseline_errors)
record("configuration_diff_matches", "".join(diffs) == content(RUN / "configuration.diff"), "Regenerated from all 16 candidates and frozen baseline")

old_agents = (RUN / "baseline/AGENTS.md").read_bytes()
new_agents = (ROOT / "AGENTS.md").read_bytes()
marker = "## 后续任务的默认工作流".encode("utf-8")
record("AGENTS_protected_prefix", old_agents.split(marker, 1)[0] == new_agents.split(marker, 1)[0], "Deletion restriction and complete DeepSeek block unchanged")
old_readme = content(RUN / "baseline/workflow/README.md")
new_readme = content(ROOT / "workflow/README.md")
record("G_layer_contract_unchanged", section(old_readme, "## 4. 六层验证", "## 5. 每次验证") == section(new_readme, "## 4. 六层验证", "## 5. 每次验证"), "G0-G5 definitions and evidence boundaries retained")
old_gate = section(old_readme, "### 5.1", "## 6.")
new_gate = section(new_readme, "### 5.1", "## 6.")
record("hardware_gate_items_unchanged", re.sub(r"^6\..*$", "", old_gate, flags=re.M) == re.sub(r"^6\..*$", "", new_gate, flags=re.M), "Only role assignment item 6 differs")
old_ai = content(RUN / "baseline/workflow/AI协作与工具接入.md")
new_ai = content(ROOT / "workflow/AI协作与工具接入.md")
record("DeepSeek_and_execution_boundaries", section(old_ai, "## 2.", "## 3.") == section(new_ai, "## 2.", "## 3.") and old_ai.split("## 6.", 1)[1] == new_ai.split("## 6.", 1)[1], "AI sections 2 and 6 unchanged")
protected_errors = [item["path"] for item in baseline["protected_existing_dirty"] if digest(ROOT / item["path"]) != item["sha256"]]
record("protected_existing_files", not protected_errors, {"count": len(baseline["protected_existing_dirty"]), "errors": protected_errors})

required = ["AGENTS.md", "workflow/FPGA多智能体工作流_使用说明.md"]
required += [f".agents/skills/{role}/SKILL.md" for role in ("fpga-orchestrator", "fpga-planner", "fpga-design-guide", "fpga-dev", "fpga-tester-functional", "fpga-tester-engineering", "fpga-tester-system")]
required += [f".agents/skills/fpga-orchestrator/references/{name}.md" for name in ("codex-calls", "relay-contract", "report-contract", "project-context")]
record("default_entry_and_role_files_exist", all((ROOT / name).is_file() for name in required), required)
dispatch = json.loads(content(RUN / "dispatch.json"))
dispatch_paths = [dispatch["project_root"], dispatch["output_dir"], dispatch["next_action"]["skill_path"]] + dispatch["input_paths"]
record("planner_dispatch_paths", all(Path(name).resolve().is_relative_to(ROOT) and Path(name).exists() for name in dispatch_paths), dispatch_paths)
record("planner_dispatch_boundary", dispatch["batch_size"] == 1 and dispatch["next_action"]["operation"] == "spawn_agent" and dispatch["next_action"]["fork_turns"] == "none" and dispatch["terminal_or_blocked"]["target_slot"] == "original_planner", "Static metadata only; no dispatch action executed")

result = {"task_id": "DEFAULT-RELAY-V2", "dimension": "system", "round": 0, "mode": "configuration_static_review_only", "timestamp": datetime.now().astimezone().isoformat(), "project_root": str(ROOT), "python": sys.version.split()[0], "manifest_path": str(MANIFEST), "manifest_sha256": digest(MANIFEST), "checks": checks, "failed_checks": [item["name"] for item in checks if not item["passed"]], "not_run": ["new_chat_creation", "workflow_simulation_or_pressure_scenarios", "old_trial_tasks", "RTL_or_model_functional_tests", "TD_build", "board_download_Flash_long_run", "commit_push_publish", "external_messages"]}
evidence = Path(__file__).with_suffix(".json")
evidence.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"checks": len(checks), "failed_checks": result["failed_checks"], "manifest_sha256": result["manifest_sha256"], "evidence": str(evidence)}, ensure_ascii=False))
sys.exit(1 if result["failed_checks"] else 0)
