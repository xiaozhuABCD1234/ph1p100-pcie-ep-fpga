"""Freeze the task artefacts into manifest-r0.json (SHA256 + bytes per file).

Run last, after every other artefact is written and no command is running.
"""

import hashlib
import json
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # .../T10.ss-g0-prod-coregap/r0
RUN = ROOT.parents[1]                               # .../<run dir>
P1 = RUN / "T10.ss-g0-prod-content" / "r0"

STATE = Path(__file__).with_name("manifest_state.json")


def sha(p: Path):
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    files = []
    for p in sorted(ROOT.rglob("*")):
        if p.is_dir() or p.name == "manifest-r0.json":
            continue
        files.append({"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p), "bytes": p.stat().st_size})
    verdict = json.loads((ROOT / "out" / "coregap-verdict.json").read_text(encoding="utf-8"))
    inputs = []
    for rel in ("content/raw40_n.hex", "content/raw40_l.hex", "content/raw_n.bin",
                "content/raw_l.bin", "src/a1_deflate_core.v", "src/a1_frame_top.v",
                "src/tb_ss_4run_wd.v", "manifest-r1.json"):
        p = P1 / rel
        if p.exists():
            inputs.append({"path": f"T10.ss-g0-prod-content/r0/{rel}", "sha256": sha(p),
                           "bytes": p.stat().st_size})
    cmds = []
    cj = ROOT / "sim" / "commands.jsonl"
    if cj.exists():
        for line in cj.read_text(encoding="utf-8").splitlines():
            if line.strip():
                cmds.append(json.loads(line))
    man = {
        "task": "T10.ss-g0-prod-coregap",
        "run": RUN.name,
        "round": 0,
        "role": "fpga-dev",
        "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "write_scope": [f"workflow/runs/{RUN.name}/T10.ss-g0-prod-coregap/**",
                        "%TEMP%/opencode/ss-g0-prod-coregap/**"],
        "stopped_modifying": True,
        "active_commands": 0,
        "verdict": {"closable_at_187_5": verdict["closable_at_187_5"],
                    "headline": verdict["headline"],
                    "P2_answer": verdict["P2_answer"]},
        "evidence_rounds": {"stage_probe_frames": 2, "vsim_full_size_runs": 3,
                            "td": 0, "board": 0, "network": 0},
        "readonly_inputs": inputs,
        "commands": cmds,
        "artifacts": files,
    }
    (ROOT / "manifest-r0.json").write_text(json.dumps(man, indent=2), encoding="utf-8")
    STATE.write_text(json.dumps({"artifacts": len(files), "inputs": len(inputs),
                                 "commands": len(cmds)}, indent=2), encoding="utf-8")
    print(json.dumps({"artifacts": len(files), "inputs": len(inputs), "commands": len(cmds),
                      "manifest": str(ROOT / "manifest-r0.json")}, indent=2))


if __name__ == "__main__":
    main()
