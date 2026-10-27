"""Read-only configuration checks; outputs are confined to this run directory."""
from pathlib import Path
import difflib
import hashlib
import json
import re
import sys
from urllib.parse import unquote

RUN = Path(__file__).resolve().parent
ROOT = RUN.parents[2]
BASELINE = json.loads((RUN / "baseline-index.json").read_text(encoding="utf-8-sig"))
EXTRA = ".agents/skills/fpga-orchestrator/references/relay-contract.md"
FILES = [entry["path"] for entry in BASELINE["config_files"]] + [EXTRA]
checks = []


def record(name, ok, detail):
    checks.append({"name": name, "ok": bool(ok), "detail": detail})


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def section(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


def content(path):
    return path.read_text(encoding="utf-8-sig")


record("actual_project_root", str(ROOT).replace("\\", "/") == BASELINE["project_root"].replace("\\", "/"), str(ROOT))
record("all_candidate_paths_stay_in_project", all((ROOT / p).resolve().is_relative_to(ROOT) for p in FILES), FILES)
marker = "## 后续任务的默认工作流".encode("utf-8")
original = (RUN / "baseline/AGENTS.md").read_bytes()
current = (ROOT / "AGENTS.md").read_bytes()
old_prefix = original.split(marker, 1)[0]
new_prefix = current.split(marker, 1)[0]
record("AGENTS_protected_prefix_byte_identical", old_prefix == new_prefix, {"before_sha256": hashlib.sha256(old_prefix).hexdigest(), "after_sha256": hashlib.sha256(new_prefix).hexdigest()})

protected = []
for entry in BASELINE["protected_existing_dirty"]:
    item = {"path": entry["path"], "before_sha256": entry["sha256"], "after_sha256": digest(ROOT / entry["path"])}
    item["unchanged"] = item["before_sha256"] == item["after_sha256"]
    protected.append(item)
record("existing_dirty_outside_scope_unchanged", all(p["unchanged"] for p in protected), protected)

frontmatter = []
for rel in FILES:
    path = ROOT / rel
    text = content(path)
    record("utf8_and_balanced_fences:" + rel, text.count("```") % 2 == 0, {"bytes": path.stat().st_size})
    if path.name == "SKILL.md":
        match = re.match(r"\A---\n(.*?)\n---\n", text, re.S)
        fields = dict(re.findall(r"^([a-z_-]+):\s*(.+)$", match.group(1), re.M)) if match else {}
        ok = bool(match and fields.get("name") == path.parent.name and re.fullmatch(r"[a-z0-9-]+", fields.get("name", "")) and fields.get("description", "").startswith("Use when") and len(match.group(1)) <= 1024)
        frontmatter.append({"path": rel, "ok": ok, "fields": sorted(fields)})
record("seven_skill_frontmatters", len(frontmatter) == 7 and all(x["ok"] for x in frontmatter), frontmatter)

links = []
for rel in FILES:
    path = ROOT / rel
    for raw in re.findall(r"(?<!!)\[[^\]\n]+\]\(([^)\n]+)\)", content(path)):
        target = raw.strip("<>").split("#", 1)[0]
        if not target or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
            continue
        resolved = (path.parent / unquote(target)).resolve()
        links.append({"source": rel, "target": raw, "exists": resolved.exists(), "resolved": str(resolved)})
record("local_markdown_links_resolve", all(x["exists"] for x in links), links)

call_text = content(ROOT / ".agents/skills/fpga-orchestrator/references/codex-calls.md")
examples = [json.loads(block) for block in re.findall(r"```json\n(.*?)\n```", call_text, re.S)]
record("tool_example_json_matches_actual_schema", len(examples) == 2 and set(examples[0]) == {"task_name", "fork_turns", "message"} and examples[0]["fork_turns"] == "none" and set(examples[1]) == {"target", "message"}, examples)

old_readme = content(RUN / "baseline/workflow/README.md")
new_readme = content(ROOT / "workflow/README.md")
record("README_G_layer_contract_unchanged", section(old_readme, "## 4. 六层验证", "## 5. 每次验证") == section(new_readme, "## 4. 六层验证", "## 5. 每次验证"), "All G0-G5 definitions, evidence boundaries and thresholds retained.")
old_gate = section(old_readme, "### 5.1", "## 6.")
new_gate = section(new_readme, "### 5.1", "## 6.")
record("README_5_1_only_role_item_6_changed", re.sub(r"^6\..*$", "", old_gate, flags=re.M) == re.sub(r"^6\..*$", "", new_gate, flags=re.M), "Hardware gate items 1-5 and 7-8 retained verbatim.")
old_ai = content(RUN / "baseline/workflow/AI协作与工具接入.md")
new_ai = content(ROOT / "workflow/AI协作与工具接入.md")
record("AI_DeepSeek_and_execution_boundary_sections_unchanged", section(old_ai, "## 2.", "## 3.") == section(new_ai, "## 2.", "## 3.") and old_ai.split("## 6.", 1)[1] == new_ai.split("## 6.", 1)[1], "Sections 2 and 6 retained verbatim.")

diffs = []
changed = []
for rel in FILES:
    before_path = RUN / "baseline" / rel
    before = content(before_path) if before_path.exists() else ""
    after = content(ROOT / rel)
    if before != after:
        changed.append(rel)
        diffs.extend(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True), fromfile="before/" + rel, tofile="after/" + rel))
record("expected_configuration_changes_only", len(changed) == 16 and set(changed) == set(FILES), changed)
result = {"task_id": "DEFAULT-RELAY-V2", "mode": "configuration_static_self_check_only", "python": sys.version.split()[0], "cwd": str(ROOT), "checks": checks, "failed_checks": [c["name"] for c in checks if not c["ok"]], "candidate_files": [{"path": rel, "sha256": digest(ROOT / rel)} for rel in FILES], "not_run": ["workflow_behavior_simulation", "new_chat_creation", "old_trial_tasks", "RTL_or_TD_or_board_tests", "git_commit_push_or_publish"]}
(RUN / "static-check-results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(RUN / "configuration.diff").write_text("".join(diffs), encoding="utf-8")
print(json.dumps({"checks": len(checks), "failed_checks": result["failed_checks"], "candidate_files": len(FILES), "local_links": len(links), "protected_files": len(protected)}, ensure_ascii=False))
raise SystemExit(1 if result["failed_checks"] else 0)
