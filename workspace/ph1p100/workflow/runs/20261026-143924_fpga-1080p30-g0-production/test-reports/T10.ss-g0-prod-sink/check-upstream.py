#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Upstream integrity check for T10.ss-g0-prod-sink r0.

Read-only: verifies every artifact of the frozen P1 manifest-r1 (70) and the
frozen P2 manifest-r0, plus the two manifest SHA256 values the dispatch pins.
Writes test-reports/T10.ss-g0-prod-sink/upstream-integrity.json only.
"""

import hashlib
import json
from pathlib import Path

RUN = Path(r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production")
OUT = Path(__file__).resolve().parent / "upstream-integrity.json"
TARGETS = [
    ("P1", RUN / "T10.ss-g0-prod-content" / "r0" / "manifest-r1.json",
     "e306ed42ed47dbcec6127bf2faee88925a9a88ae8a5ef07ecbda8dda91fe1fd9"),
    ("P2", RUN / "T10.ss-g0-prod-coregap" / "r0" / "manifest-r0.json",
     "97d7b1955b1df0bde45e9305d80a8aa703ea1365009d407f0d5d71d58dc6cc15"),
]


def sha(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for c in iter(lambda: fh.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


out = {"targets": [], "all_ok": True}
for name, mp, expect in TARGETS:
    m = json.loads(mp.read_text(encoding="utf-8"))
    man_sha = sha(mp)
    bad = []
    for a in m.get("artifacts", []):
        p = Path(a["path"])
        if not p.is_absolute():
            p = mp.parent / p
        if not p.is_file():
            bad.append({"path": str(p), "reason": "missing"})
            continue
        if sha(p) != a["sha256"] or p.stat().st_size != a["bytes"]:
            bad.append({"path": str(p), "reason": "hash/bytes drift"})
    row = {
        "target": name,
        "manifest": str(mp),
        "manifest_sha256": man_sha,
        "expected_manifest_sha256": expect,
        "manifest_sha_ok": man_sha == expect,
        "artifact_count": len(m.get("artifacts", [])),
        "bad": bad,
        "ok": man_sha == expect and not bad,
    }
    out["targets"].append(row)
    out["all_ok"] = out["all_ok"] and row["ok"]

OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
for t in out["targets"]:
    print(t["target"], t["artifact_count"], "artifacts;", "manifest_ok=" + str(t["manifest_sha_ok"]),
          "bad=" + str(len(t["bad"])), "->", "OK" if t["ok"] else "FAIL")
print("ALL_OK", out["all_ok"])
