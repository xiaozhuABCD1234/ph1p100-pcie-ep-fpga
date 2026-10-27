#!/usr/bin/env python3
"""Post-freeze verifier for manifest-r3.json.

Recomputes every bound hash after freezing, checks the file/source counts, the
parent binding, the handoff copies, and that the manifest does not bind itself.
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
R3 = HERE.parent
REPO = R3.parents[2]
PKG = REPO / "handoff" / "brd-p1-r3-20261027"
MAN = R3 / "manifest-r3.json"

fails = []
checks = 0


def check(name, cond, detail=""):
    global checks
    checks += 1
    print(("PASS " if cond else "FAIL ") + name + (f"  [{detail}]" if detail else ""))
    if not cond:
        fails.append(name)


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


m = json.loads(MAN.read_text(encoding="utf-8"))
rows = m["files"]
paths = [r["path"] for r in rows]
check("file_count_matches", m["file_count"] == len(rows) and len(rows) >= 230,
      f"{m['file_count']}/{len(rows)}")
check("source_count_78", m["source_count"] == 78, str(m["source_count"]))
check("no_duplicate_paths", len(paths) == len(set(paths)), f"{len(paths)}/{len(set(paths))}")

bad = []
for r in rows:
    p = REPO / r["path"]
    if not p.exists():
        bad.append("missing " + r["path"])
    elif sha(p) != r["sha256"].upper():
        bad.append("drift " + r["path"])
    elif p.stat().st_size != r["size"]:
        bad.append("size " + r["path"])
check("all_bound_files_exist_and_match", not bad, f"bad={bad[:5]}")

self_paths = {str(MAN.relative_to(REPO)).replace("\\", "/"),
              str((PKG / "manifest-r3.json").relative_to(REPO)).replace("\\", "/")}
check("manifest_does_not_bind_itself", not (self_paths & set(paths)), str(self_paths & set(paths)))
check("handoff_manifest_copy_identical", sha(PKG / "manifest-r3.json") == sha(MAN))
check("handoff_result_copy_identical", sha(PKG / "result-r3.md") == sha(R3 / "result-r3.md"))

parent = REPO / m["parent_manifest"]
check("parent_manifest_present", parent.exists())
check("parent_manifest_sha", parent.exists() and sha(parent) == m["parent_manifest_sha256"].upper(),
      sha(parent) if parent.exists() else "missing")

fl = json.loads((PKG / "build" / "filelist-sha256.json").read_text(encoding="utf-8"))
fl_paths = {r["path"] for r in fl["files"]}
missing = fl_paths - set(paths)
check("all_78_sources_bound", not missing, str(sorted(missing)[:5]))
src_rows = {r["path"]: r["sha256"].upper() for r in rows}
fl_bad = [p for p in fl_paths if src_rows.get(p) != next(
    r["sha256"].upper() for r in fl["files"] if r["path"] == p)]
check("source_hashes_match_filelist", not fl_bad, str(fl_bad[:5]))

check("stopped_modifying", m.get("stopped_modifying") is True)
check("drift_count_zero", m.get("drift_count") == 0)
check("status_ready_for_test", m.get("status") == "ready_for_test")
check("local_boundary_sim_only", "No TD synthesis" in m.get("local_boundary", ""))
check("g2p_not_run", m["gates"]["G2p_real_top_sta"]["result"] == "not_run")
check("g3g4_not_run", m["gates"]["G3_G4"]["result"] == "not_run")
check("bits_none", m["bits"]["local_bit"] is None and m["bits"]["local_cwc"] is None)

print(f"\nCHECKS={checks} FAILS={len(fails)}")
print("VERIFY_MANIFEST_R3=" + ("PASS" if not fails else "FAIL " + ",".join(fails)))
print("MANIFEST_SHA256=" + sha(MAN))
sys.exit(0 if not fails else 1)
