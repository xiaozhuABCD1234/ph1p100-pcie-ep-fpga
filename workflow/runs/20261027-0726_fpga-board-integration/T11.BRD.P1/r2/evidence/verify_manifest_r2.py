#!/usr/bin/env python3
"""T11.BRD.P1 r2 — post-freeze manifest verification (local, read-only).

Runs AFTER `gen_manifest_r2.py`. Recomputes every SHA in
`manifest-brd-p1-r2.json` and checks the frozen metadata the dispatch requires:

  stopped_modifying = true, drift_count = 0
  parent_manifest_sha256 = 304A2FF0... (r1)
  source_count = 78 = filelist entries
  bits.local_bit / local_cwc / b20_bit = null
  G2p = not_run / teammate_required ; G3_G4 = not_run / awaiting_hardware
  round2_delta rtl/constraints/filelist = 0
  the handoff copies of the manifest/result are byte-identical to the originals

This script's own log is NOT bound by the manifest (by design: it is written
after freezing).
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
R2 = HERE.parent
REPO = R2.parents[4]
PKG = REPO / "handoff" / "brd-p1-r2-20261027"
MAN = R2 / "manifest-brd-p1-r2.json"
R1_MAN = R2.parent / "r1" / "manifest-brd-p1-r1.json"
R1_SHA = "304A2FF08DA88B6F129577D710A5B077B9FCF0A71F205E72BFB03412616CCC05"

fails = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (("  [" + detail + "]") if detail else ""))
    if not cond:
        fails.append(name)


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


m = json.loads(MAN.read_text(encoding="utf-8"))

bad = []
for row in m["files"]:
    p = REPO / row["path"]
    if not p.exists():
        bad.append("missing " + row["path"])
    elif sha(p) != row["sha256"].upper():
        bad.append("drift " + row["path"])
check("manifest_hash_100pct", not bad, f"{len(m['files'])} files, bad={bad[:3]}")
check("file_count_matches_list", m["file_count"] == len(m["files"]), f"{m['file_count']} / {len(m['files'])}")
check("no_duplicate_paths", len({r['path'] for r in m['files']}) == len(m['files']))
check("stopped_modifying", m.get("stopped_modifying") is True)
check("drift_count_zero", m.get("drift_count") == 0, str(m.get("drift_count")))
check("status_ready_for_test", m.get("status") == "ready_for_test", str(m.get("status")))
check("round_is_2", m.get("round") == 2, str(m.get("round")))
check("parent_manifest_sha256", m.get("parent_manifest_sha256") == R1_SHA, str(m.get("parent_manifest_sha256")))
check("r1_manifest_still_matches_parent", R1_MAN.exists() and sha(R1_MAN) == R1_SHA)
check("source_count_78", m.get("source_count") == 78, str(m.get("source_count")))

fl = json.loads((PKG / "build" / "filelist-sha256.json").read_text(encoding="utf-8"))
bound = {r["path"] for r in m["files"]}
missing_src = [r["path"] for r in fl["files"] if r["path"] not in bound]
check("all_78_sources_bound", not missing_src, str(missing_src[:3]))
check("source_count_equals_filelist", m["source_count"] == len(fl["files"]))

bits = m.get("bits", {})
check("bits_null", all(bits.get(k) is None for k in ("local_bit", "local_cwc", "b20_bit")), str(bits))
g = m.get("gates", {})
check("g2p_teammate_required",
      g.get("G2p_real_top_sta", {}).get("status") == "teammate_required" and
      g.get("G2p_real_top_sta", {}).get("result") == "not_run")
check("g3g4_awaiting_hardware",
      g.get("G3_G4", {}).get("status") == "awaiting_hardware" and
      g.get("G3_G4", {}).get("result") == "not_run")
check("g0_pass_static", g.get("G0_ports_clocks_resets_cdc", {}).get("result") == "pass_static_local")
check("g1_pass_local_sim", g.get("G1_scaled_top_simulation", {}).get("result") == "pass_local_sim")
check("g5_pass_static", g.get("G5_build_entry", {}).get("result") == "pass_local_static")

d = m.get("round2_delta", {})
check("delta_all_zero", d.get("rtl_delta") == 0 and d.get("constraints_delta") == 0 and d.get("filelist_delta") == 0)
check("dut_not_modified", d.get("dut_modified_to_fit_golden") is False)
check("criteria_not_weakened", d.get("criteria_weakened") is False)

check("d7_wording_present", "legal RFC1950" in m.get("d7_adler", {}).get("wording", ""))
check("d7_reopen_condition", "reproduces the r0 condition" in
      m.get("d7_adler", {}).get("reopen_condition", ""))
check("a1_alias_flags",
      m.get("a1_core_fix01", {}).get("alias_of_b20") is True and
      m.get("a1_core_fix01", {}).get("behavioral_variant") is False and
      m.get("a1_core_fix01", {}).get("filelist_included") is False)

# package copies
pm, pr = PKG / "manifest-brd-p1-r2.json", PKG / "result-r2.md"
check("package_manifest_copy_identical", pm.exists() and sha(pm) == sha(MAN))
check("package_result_copy_identical", pr.exists() and (R2 / "result-r2.md").exists() and
      sha(pr) == sha(R2 / "result-r2.md"))

# P4 statement must stay warning and nothing spliced
check("p4_warning_kept", "warning" in json.dumps(m.get("round1_inherited", {})).lower()
      or "warning" in json.dumps(m.get("notes", [])).lower())
check("no_bit_cwc_files", not list(R2.rglob("*.bit")) and not list(R2.rglob("*.cwc")) and
      not list(PKG.rglob("*.bit")) and not list(PKG.rglob("*.cwc")))

print(f"\nFAILS={len(fails)}")
print("VERIFY_MANIFEST_R2=" + ("PASS" if not fails else "FAIL " + ",".join(fails)))
sys.exit(0 if not fails else 1)
