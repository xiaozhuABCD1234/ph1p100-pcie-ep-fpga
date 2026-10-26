from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
from datetime import datetime, timezone

sys.dont_write_bytecode = True
OUTPUT_ROOT = Path(__file__).resolve().parent.parent


def fresh_json(path: Path, value: object) -> None:
    resolved = path.resolve()
    if not resolved.is_relative_to(OUTPUT_ROOT) or resolved == OUTPUT_ROOT:
        raise ValueError("audit output escapes OUTPUT_DIR")
    if path.exists() or path.is_symlink():
        raise FileExistsError(str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True)
        stream.write("\n")


def git_state(root: Path) -> dict:
    environment = dict(os.environ, GIT_OPTIONAL_LOCKS="0", PYTHONDONTWRITEBYTECODE="1")
    results = {}
    commands = {
        "head": ["git", "rev-parse", "HEAD"],
        "branch": ["git", "branch", "--show-current"],
        "status_raw": ["git", "status", "--short", "--untracked-files=all"],
    }
    for name, command in commands.items():
        completed = subprocess.run(command, cwd=root, env=environment, capture_output=True, text=True, encoding="utf-8", errors="strict")
        if completed.returncode:
            raise RuntimeError(f"git {name}: {completed.stderr}")
        results[name] = completed.stdout
    return results


def scan_tree(root: Path) -> dict:
    entries = []
    errors = []

    def visit(directory: Path) -> None:
        try:
            children = sorted(os.scandir(directory), key=lambda child: child.name.casefold())
        except OSError as error:
            errors.append({"path": str(directory), "error": str(error)})
            return
        visible = []
        for child in children:
            path = Path(child.path)
            if child.name == ".git" or path == OUTPUT_ROOT:
                continue
            visible.append(child)
        entries.append({"absolute_path": str(directory), "relative_path": directory.relative_to(root).as_posix(), "type": "directory", "empty": not visible})
        for child in visible:
            path = Path(child.path)
            base = {"absolute_path": str(path), "relative_path": path.relative_to(root).as_posix()}
            try:
                before = path.lstat()
                reparse = bool(getattr(before, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
                if reparse or stat.S_ISLNK(before.st_mode):
                    target = os.readlink(path)
                    entries.append(dict(base, type="link", bytes=before.st_size, target=target))
                elif stat.S_ISDIR(before.st_mode):
                    visit(path)
                elif stat.S_ISREG(before.st_mode):
                    digest = hashlib.sha256()
                    with path.open("rb") as stream:
                        for block in iter(lambda: stream.read(1024 * 1024), b""):
                            digest.update(block)
                    after = path.lstat()
                    if (before.st_size, before.st_mtime_ns, before.st_ino) != (after.st_size, after.st_mtime_ns, after.st_ino):
                        raise RuntimeError("file changed during read")
                    entries.append(dict(base, type="file", bytes=after.st_size, sha256=digest.hexdigest()))
                else:
                    raise RuntimeError("unsupported file type")
            except (OSError, RuntimeError) as error:
                errors.append(dict(base, error=str(error)))

    visit(root)
    return {"root": str(root), "entries": entries, "errors": errors, "git": git_state(root)}


def snapshot(project_root: Path, codec_root: Path) -> dict:
    return {
        "schema": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "excluded_output": str(OUTPUT_ROOT),
        "git_internal_excluded": True,
        "links_followed": False,
        "trees": [scan_tree(project_root.resolve()), scan_tree(codec_root.resolve())],
    }


def compare(baseline: dict, current: dict) -> dict:
    differences = []
    for original, observed in zip(baseline["trees"], current["trees"], strict=True):
        if original["root"] != observed["root"]:
            raise ValueError("root mismatch")
        first = {entry["relative_path"]: entry for entry in original["entries"]}
        second = {entry["relative_path"]: entry for entry in observed["entries"]}
        for relative in sorted(first.keys() | second.keys()):
            if first.get(relative) != second.get(relative):
                differences.append({"root": original["root"], "path": relative, "before": first.get(relative), "after": second.get(relative)})
        for field in ("head", "branch"):
            if original["git"][field] != observed["git"][field]:
                differences.append({"root": original["root"], "git_field": field, "before": original["git"][field], "after": observed["git"][field]})
        root = Path(original["root"])
        excluded_prefix = OUTPUT_ROOT.relative_to(root).as_posix() + "/" if OUTPUT_ROOT.is_relative_to(root) else None
        def protected_status(tree: dict) -> list[str]:
            return [line for line in tree["git"]["status_raw"].splitlines() if not excluded_prefix or not line[3:].lstrip('"').startswith(excluded_prefix)]
        if protected_status(original) != protected_status(observed):
            differences.append({"root": original["root"], "git_field": "protected_status", "before": protected_status(original), "after": protected_status(observed)})
    errors = [error for tree in baseline["trees"] + current["trees"] for error in tree["errors"]]
    return {"status": "unchanged" if not differences and not errors else "blocked_concurrent_change", "differences": differences, "errors": errors, "git_status_note": "Raw status is retained in snapshots; OUTPUT_DIR changes are excluded from content comparisons."}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--codec-root", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--diff-out", type=Path)
    arguments = parser.parse_args()
    observed = snapshot(arguments.project_root, arguments.codec_root)
    fresh_json(arguments.out, observed)
    if arguments.baseline:
        if not arguments.diff_out:
            raise ValueError("--diff-out required")
        result = compare(json.loads(arguments.baseline.read_text(encoding="utf-8")), observed)
        fresh_json(arguments.diff_out, result)
    else:
        result = {"status": "baseline_created", "errors": [error for tree in observed["trees"] for error in tree["errors"]]}
    print(json.dumps({"marker": "PROTECTED_AUDIT_DONE", "status": result["status"], "errors": len(result["errors"]), "entries": [len(tree["entries"]) for tree in observed["trees"]]}, sort_keys=True))
    return 0 if not result["errors"] and result["status"] in ("unchanged", "baseline_created") else 1


if __name__ == "__main__":
    raise SystemExit(main())
