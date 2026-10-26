#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T09.rk-align-algo manifest freezer + self-check.

Hashes every frozen artifact (RTL, tools, testbenches, vectors, TD scripts) and
writes algo/candidate-manifest.json plus algo/manifest-selfcheck.json (re-read
and re-hash consistency).  Run it as the LAST step before handing over.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUN = ROOT / "workflow" / "runs" / "20261017-011744-rk-fpga-align"
ALGO = RUN / "algo"

RTL = [
    "algo_rowwin_reader.v", "algo_rowwin3.v", "algo_obuf.v",
    "bayer_raw10_demosaic4.v", "gray8_gaussian3x3_stream.v",
    "gray8_he_cdfmin_frame.v", "rgb8_gray_stream.v",
    "gray8_gaussian3x3_frame.v", "img_algo_parallel_top.v", "img_algo_top_g2.v",
]
TOOLS = [
    "oracle_algo.py", "gen_algo_vectors.py", "gen_ref_vectors.py", "run_g1.py",
    "freeze_manifest.py", "run_td_algo.ps1",
]
TBS = [
    "tb_img_algo_core.sv", "tb_img_algo_rate.sv", "tb_rgb8_gray_stream.sv",
    "tb_gray8_gaussian3x3_frame.sv",
]
TD = ["00_all.tcl", "img_algo_top.sdc", "img_algo_top.adc"]
REF = ["worktree_refs/verify_gray.py", "worktree_refs/verify_gaussian.py"]
VECTORS = ["algo_core.vec", "algo_core.lut.hex", "algo_core.meta.json",
           "gray_mod.vec", "gauss_frame.vec"]


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    entries = []
    missing = []
    for rel in RTL:
        p = ROOT / "fpga" / "csi2" / "src" / "img" / rel
        if not p.exists():
            missing.append(str(p)); continue
        entries.append({"kind": "rtl", "path": str(p.relative_to(ROOT)), "sha256": sha(p)})
    for rel in TOOLS:
        p = ROOT / "tools" / "algo" / rel
        if not p.exists():
            missing.append(str(p)); continue
        entries.append({"kind": "tool", "path": str(p.relative_to(ROOT)), "sha256": sha(p)})
    for rel in TBS:
        p = ROOT / "tools" / "algo" / "tb" / rel
        if not p.exists():
            missing.append(str(p)); continue
        entries.append({"kind": "tb", "path": str(p.relative_to(ROOT)), "sha256": sha(p)})
    for rel in TD:
        p = ROOT / "tools" / "algo" / "td" / rel
        if not p.exists():
            missing.append(str(p)); continue
        entries.append({"kind": "td", "path": str(p.relative_to(ROOT)), "sha256": sha(p)})
    for rel in REF:
        p = ROOT / "tools" / "algo" / rel
        if not p.exists():
            missing.append(str(p)); continue
        entries.append({"kind": "worktree_ref", "path": str(p.relative_to(ROOT)), "sha256": sha(p)})
    for rel in VECTORS:
        p = ALGO / "vectors" / rel
        if not p.exists():
            missing.append(str(p)); continue
        entries.append({"kind": "vector", "path": str(p.relative_to(ROOT)), "sha256": sha(p)})
    for rel in ["change-report.md", "source-provenance.json", "build-entry.md",
                "actual-commands.json", "lessons-learned.md", "dev-result.json"]:
        p = ALGO / rel
        if p.exists():
            entries.append({"kind": "report", "path": str(p.relative_to(ROOT)), "sha256": sha(p)})

    manifest = {
        "task_id": "T09.rk-align-algo",
        "run_id": "20261017-011744-rk-fpga-align",
        "frozen": True,
        "note": ("Frozen after the last RTL edit; the G1 core testbench still "
                 "reports mismatches in the multi-frame HE/abort region and the "
                 "G2 small-top build shows a setup violation - see dev-result.json. "
                 "This manifest records identities, not verdicts."),
        "entries": entries,
        "missing": missing,
    }
    mp = ALGO / "candidate-manifest.json"
    mp.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    # self-check: re-read and re-hash
    back = json.loads(mp.read_text(encoding="utf-8"))
    bad = []
    for e in back["entries"]:
        p = ROOT / e["path"]
        if not p.exists() or sha(p) != e["sha256"]:
            bad.append(e["path"])
    sc = {
        "manifest": str(mp.relative_to(ROOT)),
        "manifest_sha256": sha(mp),
        "entries": len(back["entries"]),
        "missing": len(back["missing"]),
        "mismatch": bad,
        "ok": (not bad) and (not back["missing"]),
    }
    (ALGO / "manifest-selfcheck.json").write_text(json.dumps(sc, indent=2), encoding="utf-8")
    print(json.dumps(sc, indent=2))
    return 0 if sc["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
