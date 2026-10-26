from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
OUTPUT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(OUTPUT_ROOT / "candidates/T03.trial-A/r0"))
from trial_common import PROJECT_ROOT, fresh_directory, subprocess_environment, write_json


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    arguments = parser.parse_args()
    evidence = fresh_directory(OUTPUT_ROOT / "evidence/T03.trial-A/r0/dev" / arguments.name)
    temporary_root = fresh_directory(evidence / "tmp")
    command = [sys.executable, "-B", str(OUTPUT_ROOT / "run_trial.py"), "--task", "A", "--project-root", str(PROJECT_ROOT), "--out", str(evidence / "run")]
    completed = subprocess.run(command, cwd=evidence, env=subprocess_environment(temporary_root), capture_output=True, text=True, timeout=120)
    record = {"command": command, "cwd": str(evidence), "python": sys.version, "exit_code": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr, "result": str(evidence / "run/result.json")}
    write_json(evidence / "command.json", record)
    print(json.dumps(record, ensure_ascii=False))
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
