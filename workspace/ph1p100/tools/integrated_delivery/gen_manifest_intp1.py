#!/usr/bin/env python3
import hashlib, json, os
from pathlib import Path

ROOT = Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow" / "runs" / "20261026-2138_fpga-integrated-delivery"

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

def collect(rel):
    base = ROOT / rel
    out = []
    for dp, _, fs in os.walk(base):
        for fn in sorted(fs):
            p = Path(dp) / fn
            out.append((str(p.relative_to(ROOT)).replace("\\", "/"), p))
    return sorted(out)

src_files = collect("fpga/csi2/src/integrated_delivery")
tool_files = [x for x in collect("tools/integrated_delivery") if "__pycache__" not in x[0]]

def entry(rel, p):
    return {"path": rel, "sha256": sha(p), "size": p.stat().st_size}

man = {
    "schema": 1,
    "task_id": "INT.P1",
    "round": 1,
    "candidate_root": "fpga/csi2/src/integrated_delivery",
    "production_inputs": [entry(r, p) for r, p in src_files if not r.endswith(".v") or True],
    "tool_inputs": [entry(r, p) for r, p in tool_files],
    "test_inputs": [
        "tools/integrated_delivery/evidence/golden_input_processing.json",
        "tools/integrated_delivery/evidence/verify_report.json",
    ],
    "local_checks": {
        "raw10_pack": "tools/integrated_delivery/raw10_pack.py -> RAW10_PACK PASS",
        "verify_input_processing": "tools/integrated_delivery/verify_input_processing.py -> INT.P1_VERIFY PASS",
    },
    "stopped_modifying": True,
    "notes": [
        "INT.P1 round1 repair: D1-D5 fixed; production RTL compiles with 0 warnings.",
        "G3/G4 not applicable (software/RTL integration package, no board window).",
    ],
}

# filter test_inputs entries to existing
man["test_inputs"] = [x for x in man["test_inputs"] if (ROOT / x).is_file()]
# add sha for test inputs
man["test_input_entries"] = [entry(x, ROOT / x) for x in man["test_inputs"]]

out = RUN / "INT.P1-r1-manifest.json"
out.write_text(json.dumps(man, indent=2, ensure_ascii=False), encoding="utf-8")
print("wrote", out)
print("src_files", len(src_files), "tool_files", len(tool_files))