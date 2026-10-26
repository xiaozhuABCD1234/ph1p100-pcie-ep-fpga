"""Independent configuration-only engineering checks; writes this dimension's evidence."""
from pathlib import Path
import datetime
import difflib
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from urllib.parse import unquote

ROOT = Path.cwd().resolve()
RUN = ROOT / "workflow/runs/20261016_185549_approved_workflow_default"
OUT = RUN / "test-reports/engineering-static-results.json"
MANIFEST = RUN / "candidate-manifest.json"
manifest_bytes = MANIFEST.read_bytes()
manifest = json.loads(manifest_bytes.decode("utf-8-sig"))
baseline = json.loads((RUN / "baseline-index.json").read_text(encoding="utf-8-sig"))
sys.path.insert(0, str(ROOT / "tmp/skill-validation-deps"))
sys.dont_write_bytecode = True
import yaml

validator = Path("C:/Users/czz/.codex/skills/.system/skill-creator/scripts/quick_validate.py")
spec = importlib.util.spec_from_file_location("skill_quick_validate", validator)
qv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qv)
checks = []


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def read(p):
    return p.read_text(encoding="utf-8-sig")


def record(name, ok, evidence):
    checks.append({"name": name, "ok": bool(ok), "evidence": evidence})


skills = ["fpga-design-guide", "fpga-dev", "fpga-orchestrator", "fpga-planner", "fpga-tester-engineering", "fpga-tester-functional", "fpga-tester-system"]
expected = {"AGENTS.md", "workflow/FPGA多智能体工作流_使用说明.md", "workflow/AI协作与工具接入.md", "workflow/AGENTS接入片段.md", "workflow/README.md"}
expected.update(".agents/skills/" + n + "/SKILL.md" for n in skills)
expected.update(".agents/skills/fpga-orchestrator/references/" + n + ".md" for n in ["codex-calls", "project-context", "report-contract", "relay-contract"])
record("frozen_task_identity", manifest["task_id"] == "DEFAULT-RELAY-V2" and manifest["round"] == 0 and manifest["developer_stopped_modifying"] is True and Path(manifest["project_root"]).resolve() == ROOT, {k: manifest[k] for k in ["task_id", "round", "frozen_at", "developer_stopped_modifying"]})
record("candidate_set_exactly_allowed_16", len(manifest["candidate_files"]) == 16 and {x["relative_path"] for x in manifest["candidate_files"]} == expected, sorted(expected))
snapshots = []
for key in ["candidate_files", "supporting_artifacts", "baseline_artifacts"]:
    evidence = []
    for item in manifest[key]:
        p = Path(item["path"]).resolve()
        digest = sha(p)
        ok = p.is_relative_to(ROOT) and digest == item["sha256"] and ("bytes" not in item or p.stat().st_size == item["bytes"])
        if "relative_path" in item:
            ok = ok and p == (ROOT / item["relative_path"]).resolve()
        evidence.append({"path": str(p), "sha256": digest, "bytes": p.stat().st_size, "ok": ok})
        snapshots.append((p, digest))
    record(key + "_hashes_paths_bytes", all(x["ok"] for x in evidence), evidence)

old_index = {x["path"]: x for x in baseline["config_files"]}
before_checks = []
for item in manifest["candidate_files"]:
    rel = item["relative_path"]
    bp = RUN / "baseline" / rel
    ok = item["change"] == ("modified" if rel in old_index else "added")
    ok = ok and (item["before_sha256"] == old_index[rel]["sha256"] == sha(bp) if rel in old_index else item["before_sha256"] is None and not bp.exists())
    before_checks.append({"path": rel, "ok": ok})
record("candidate_before_binding_to_baseline", all(x["ok"] for x in before_checks), before_checks)

fms = []
link_results = []
fence_results = []
for item in manifest["candidate_files"]:
    p = Path(item["path"])
    text = read(p)
    fence_results.append({"path": item["relative_path"], "balanced": len(re.findall(r"^```", text, re.M)) % 2 == 0})
    if p.name == "SKILL.md":
        match = re.match(r"\A---\n(.*?)\n---\n", text, re.S)
        fields = yaml.safe_load(match.group(1)) if match else None
        valid, message = qv.validate_skill(p.parent)
        ok = valid and isinstance(fields, dict) and set(fields) == {"name", "description"} and fields["name"] == p.parent.name and fields["description"].startswith("Use when")
        fms.append({"path": item["relative_path"], "ok": ok, "fields": fields, "quick_validate": message})
    for target in re.findall(r"(?<!!)\[[^\]\n]+\]\(([^)\n]+)\)", text):
        target = target.strip("<>").split("#", 1)[0]
        if not target or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
            continue
        resolved = (p.parent / unquote(target)).resolve()
        link_results.append({"source": item["relative_path"], "target": target, "resolved": str(resolved), "ok": resolved.exists() and resolved.is_relative_to(ROOT)})
record("seven_skills_PyYAML_and_system_quick_validate", len(fms) == 7 and all(x["ok"] for x in fms), fms)
record("utf8_and_code_fences", all(x["balanced"] for x in fence_results), fence_results)
record("all_local_markdown_links_exist_inside_project", all(x["ok"] for x in link_results), link_results)

calls = read(ROOT / ".agents/skills/fpga-orchestrator/references/codex-calls.md")
examples = [json.loads(x) for x in re.findall(r"```json\n(.*?)\n```", calls, re.S)]
example_ok = len(examples) == 2 and set(examples[0]) == {"task_name", "message", "fork_turns"} and examples[0]["fork_turns"] == "none" and bool(re.fullmatch(r"[a-z0-9_]+", examples[0]["task_name"])) and isinstance(examples[0]["message"], str) and set(examples[1]) == {"target", "message"} and all(isinstance(v, str) for v in examples[1].values())
record("tool_JSON_examples_match_current_spawn_followup_schema", example_ok, examples)

prefix_marker = "## 后续任务的默认工作流".encode("utf-8")
old = (RUN / "baseline/AGENTS.md").read_bytes()
new = (ROOT / "AGENTS.md").read_bytes()
old_prefix = old.split(prefix_marker, 1)[0]
new_prefix = new.split(prefix_marker, 1)[0]
record("root_AGENTS_protected_prefix_byte_identical", old.count(prefix_marker) == 1 and new.count(prefix_marker) == 1 and old_prefix == new_prefix, {"before_sha256": hashlib.sha256(old_prefix).hexdigest(), "after_sha256": hashlib.sha256(new_prefix).hexdigest(), "protected_bytes": len(old_prefix)})
protected = [{"path": x["path"], "before_sha256": x["sha256"], "actual_sha256": sha(ROOT / x["path"])} for x in baseline["protected_existing_dirty"]]
record("eight_existing_dirty_protected_files_unchanged", all(x["before_sha256"] == x["actual_sha256"] for x in protected), protected)

def section(text, start, stop):
    return text.split(start, 1)[1].split(stop, 1)[0]

old_readme = read(RUN / "baseline/workflow/README.md")
new_readme = read(ROOT / "workflow/README.md")
record("README_G0_G5_contract_verbatim", section(old_readme, "## 4.", "## 5.") == section(new_readme, "## 4.", "## 5."), "Entire G0-G5 section compared with baseline.")
record("README_5_1_hardware_gates_verbatim_except_role_item6", re.sub(r"^6\..*$", "", section(old_readme, "### 5.1", "## 6."), flags=re.M) == re.sub(r"^6\..*$", "", section(new_readme, "### 5.1", "## 6."), flags=re.M), "Items 1-5 and 7-8 and surrounding text unchanged; item 6 role attribution reviewed manually.")
old_ai = read(RUN / "baseline/workflow/AI协作与工具接入.md")
new_ai = read(ROOT / "workflow/AI协作与工具接入.md")
record("DeepSeek_context_and_execution_boundary_verbatim", section(old_ai, "## 2.", "## 3.") == section(new_ai, "## 2.", "## 3.") and old_ai.split("## 6.", 1)[1] == new_ai.split("## 6.", 1)[1], "AI document sections 2 and 6 unchanged; full root worker block covered by byte prefix check.")

diff = []
for item in manifest["candidate_files"]:
    rel = item["relative_path"]
    bp = RUN / "baseline" / rel
    before = read(bp) if bp.exists() else ""
    diff.extend(difflib.unified_diff(before.splitlines(keepends=True), read(ROOT / rel).splitlines(keepends=True), fromfile="before/" + rel, tofile="after/" + rel))
record("configuration_diff_exactly_reproduced_from_baseline", "".join(diff) == read(RUN / "configuration.diff"), {"lines": len("".join(diff).splitlines()), "files": len(manifest["candidate_files"])})

git_version = subprocess.run(["git", "--version"], text=True, capture_output=True, check=True).stdout.strip()
git_commit = subprocess.run(["git", "rev-parse", "HEAD"], text=True, capture_output=True, check=True).stdout.strip()
tracked = subprocess.run(["git", "-c", "core.quotepath=false", "status", "--porcelain=v1", "-uno"], text=True, encoding="utf-8", capture_output=True, check=True).stdout.splitlines()
prior_tracked = {x[3:]: x[:2] for x in baseline["git_status"] if not x.startswith("??")}
tracked_outside = [x for x in tracked if x[3:] not in expected]
record("tracked_dirty_changes_outside_scope_match_baseline_status", all(x[3:] in prior_tracked and x[:2] == prior_tracked[x[3:]] for x in tracked_outside) and {x[3:] for x in tracked_outside} == set(prior_tracked) - expected, tracked)
record("all_frozen_inputs_still_unchanged_at_check_end", MANIFEST.read_bytes() == manifest_bytes and all(sha(p) == digest for p, digest in snapshots), "Manifest and all candidate/support/baseline inputs rehashed at end.")
result = {"task_id": "DEFAULT-RELAY-V2", "dimension": "engineering", "round": 0, "mode": "configuration_static_review_only", "checked_at": datetime.datetime.now().astimezone().isoformat(), "cwd": str(ROOT), "git_commit": git_commit, "git_dirty": True, "manifest_path": str(MANIFEST), "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(), "tools": {"python": sys.version, "PyYAML": yaml.__version__, "PyYAML_path": yaml.__file__, "git": git_version, "quick_validate_path": str(validator), "quick_validate_sha256": sha(validator)}, "checks": checks, "failed_checks": [x["name"] for x in checks if not x["ok"]], "counts": {"candidate_files": len(manifest["candidate_files"]), "supporting_artifacts": len(manifest["supporting_artifacts"]), "baseline_artifacts": len(manifest["baseline_artifacts"]), "skills": len(fms), "local_links": len(link_results), "protected_dirty_files": len(protected)}}
OUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"completed": True, "checks": len(checks), "failed_checks": result["failed_checks"], "counts": result["counts"], "manifest_sha256": result["manifest_sha256"], "evidence": str(OUT)}, ensure_ascii=False))
raise SystemExit(1 if result["failed_checks"] else 0)
