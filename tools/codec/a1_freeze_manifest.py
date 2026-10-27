#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Freeze the T10.a1-format-ref candidate manifest (P1).

Lists every task artifact (absolute path, size, SHA256), every new code file,
the lessons file, and the read-only inputs with their SHA256/declared version.
Then re-reads and re-hashes everything listed to prove 0 mismatches.

The manifest itself is excluded from its own artifact list (it cannot contain
its own stable hash); all other files are included.
"""
import argparse
import datetime
import hashlib
import json
import os
import platform
import sys
import zlib
from pathlib import Path

sys.dont_write_bytecode = True

TASK_ID = "T10.a1-format-ref"
RUN_ID = "20261020-0209_singleA_aplus_closedloop"
MANIFEST_NAME = "CANDIDATE-MANIFEST.json"

CODE_ARTIFACTS = [
    "upstream/ph1p100-pcie-ep-fpga/tools/codec/a1_ref.py",
    "upstream/ph1p100-pcie-ep-fpga/tools/codec/a1_inflate_strict.py",
    "upstream/ph1p100-pcie-ep-fpga/tools/codec/a1_sample_check.py",
    "upstream/ph1p100-pcie-ep-fpga/tools/codec/a1_vectors.py",
    "upstream/ph1p100-pcie-ep-fpga/tools/codec/a1_p1_verify.py",
    "upstream/ph1p100-pcie-ep-fpga/tools/codec/a1_freeze_manifest.py",
]

INPUTS = [
    ("workflow/runs/20261020-0209_singleA_aplus_closedloop/role-rules.md", "role rules reconstructed by planner 2026-10-20"),
    ("workflow/runs/20261020-0209_singleA_aplus_closedloop/dev-plan.md", "frozen plan 2026-10-20"),
    ("workflow/runs/20261020-0209_singleA_aplus_closedloop/fpga-design-guide.md", "frozen design guide 2026-10-20"),
    ("workflow/runs/20261020-0209_singleA_aplus_closedloop/input-index.md", "planner input index 2026-10-20"),
    ("workflow/runs/20261020-0209_singleA_aplus_closedloop/dispatch.json", "dispatch/write-scope 2026-10-20"),
    ("docs/planning/2026-10-20-fpga-priorities/01_OpenCode启动需求_单A_Aplus闭环.md", "user requirement 2026-10-20"),
    ("upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/ph1p_pcie_ep_top.v", "upstream baseline HEAD b0282d2 (declared in input-index.md §2; .git metadata incomplete, not re-verified)"),
    ("upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/ddr/cam_r10f_writer.v", "upstream baseline HEAD b0282d2 (declared in input-index.md §2; not re-verified)"),
    ("upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/cam/csi_rx_10bit_unpack.v", "upstream baseline HEAD b0282d2 (declared in input-index.md §2; not re-verified)"),
    ("upstream/ph1p100-pcie-ep-fpga/tools/pcie_integration/r10f_strict.py", "upstream baseline HEAD b0282d2 (declared in input-index.md §2; not re-verified)"),
    ("workflow/runs/20261019-2117_runD_batch2_continue/test-reports/T02.codex-singleA-board-r0-recovery03-integrated.md", "read-only historical board report (T02 recovery03)"),
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel_posix(path, root):
    return Path(path).resolve().relative_to(Path(root).resolve()).as_posix()


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", required=True)
    ap.add_argument("--task-dir", required=True)
    ap.add_argument("--lessons", required=True)
    args = ap.parse_args(argv)

    root = Path(args.project_root).resolve()
    task = Path(args.task_dir).resolve()
    lessons = Path(args.lessons).resolve()
    manifest_path = task / MANIFEST_NAME

    artifacts = []
    volatile = {manifest_path, (task / "p1" / "logs" / "run-manifest.log").resolve()}
    for p in sorted(task.rglob("*")):
        if not p.is_file():
            continue
        if p.resolve() in volatile:
            continue
        artifacts.append({
            "path": rel_posix(p, task),
            "abs_path": str(p.resolve()),
            "size": p.stat().st_size,
            "sha256": sha256_file(p),
        })

    code = []
    for rel in CODE_ARTIFACTS:
        p = root / rel
        code.append({
            "path": rel,
            "abs_path": str(p.resolve()),
            "size": p.stat().st_size,
            "sha256": sha256_file(p),
        })

    inputs = []
    for rel, version in INPUTS:
        p = root / rel
        inputs.append({
            "path": rel,
            "abs_path": str(p.resolve()),
            "exists": p.exists(),
            "size": p.stat().st_size if p.exists() else None,
            "sha256": sha256_file(p) if p.exists() else None,
            "declared_version": version,
        })

    lessons_entry = {
        "path": rel_posix(lessons, root),
        "abs_path": str(lessons),
        "size": lessons.stat().st_size,
        "sha256": sha256_file(lessons),
    }

    verify_path = task / "p1" / "verify-report.json"
    verify = json.loads(verify_path.read_text(encoding="utf-8")) if verify_path.exists() else {}
    verification = {
        "verdict": verify.get("verdict"),
        "positives": verify.get("positives"),
        "positives_passed": verify.get("positives_passed"),
        "mismatch_count": verify.get("mismatch_count"),
        "negatives": verify.get("negatives"),
        "negatives_rejected": verify.get("negatives_rejected"),
        "three_way_equal_vectors": verify.get("three_way_equal_vectors"),
        "report": str(verify_path.resolve()),
        "report_sha256": sha256_file(verify_path) if verify_path.exists() else None,
    }

    doc = {
        "schema": "a1t1-candidate-manifest-v1",
        "task_id": TASK_ID,
        "run_id": RUN_ID,
        "candidate": "T10.a1-* pure-additive codec source set (P1 format/reference only; not a production candidate)",
        "marker": "test-only; synthetic vectors; declared RGGB phase=0; no board/production claim",
        "created_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "verification": verification,
        "artifacts": artifacts,
        "code_artifacts": code,
        "lessons": lessons_entry,
        "inputs": inputs,
        "write_scope": {
            "new_files_only": True,
            "upstream_new_dirs": [
                "upstream/ph1p100-pcie-ep-fpga/tools/codec/**"
            ],
            "run_output_only": [
                "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-format-ref/**",
                "workflow/runs/20261020-0209_singleA_aplus_closedloop/lessons/T10.a1-format-ref-lessons.md"
            ],
            "not_modified": [
                "production top / .al / build.tcl / SDC / compile_checked.f",
                "three algorithms, camera/CSI, DDR writer, pusher, PCIe, RK",
                "old runs, frozen manifests, bit/CWC/BID, docs/protocol, workflow/tasks.json"
            ],
            "no_download": True,
            "no_flash": True,
            "no_push": True,
        },
        "tool_versions": {
            "python": platform.python_version(),
            "zlib": zlib.ZLIB_VERSION,
            "platform": platform.platform(),
        },
        "manifest_self_excluded": True,
        "excluded_volatile": [
            str(manifest_path),
            str((task / "p1" / "logs" / "run-manifest.log").resolve()),
        ],
    }

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # self-check: re-read and re-hash every listed file
    loaded = json.loads(manifest_path.read_text(encoding="utf-8"))
    mismatch = 0
    checked = 0
    for group in ("artifacts", "code_artifacts", "inputs"):
        for e in loaded[group]:
            if group == "inputs" and not e.get("exists"):
                continue
            checked += 1
            if sha256_file(Path(e["abs_path"])) != e["sha256"]:
                mismatch += 1
                print("HASH_MISMATCH %s" % e["abs_path"])
    if sha256_file(Path(loaded["lessons"]["abs_path"])) != loaded["lessons"]["sha256"]:
        mismatch += 1
        print("HASH_MISMATCH %s" % loaded["lessons"]["abs_path"])
    else:
        checked += 1

    print("MANIFEST %s" % manifest_path)
    print("MANIFEST checks: artifacts=%d code=%d inputs=%d lessons=1 mismatches=%d"
          % (len(artifacts), len(code), len(inputs), mismatch))
    if mismatch:
        return 1
    print("MANIFEST_OK files=%d mismatch=0" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
