#!/usr/bin/env python3
"""Round1 output consistency check.  Writes out/check-outputs.json."""
import hashlib
import json
import pathlib
import sys

sys.dont_write_bytecode = True
R0 = pathlib.Path(__file__).resolve().parent.parent
OUT = R0 / "out"
FROZEN_TB = "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0"
LEGACY_TB = "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e"
IN_META = "e98c9a1c3e0fe621c9aa65aaadbcacbef13c2437a0bbbafcde17d2ff471f80fe"


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


checks = []


def add(cid, ok, detail):
    checks.append({"id": cid, "pass": bool(ok), "detail": detail})


runs = json.loads((OUT / "runs.json").read_text())
verdict = json.loads((OUT / "g0-verdict.json").read_text())
proxy = json.loads((OUT / "content-proxy.json").read_text())
neg = json.loads((OUT / "negative-controls.json").read_text())
iv = json.loads((R0 / "input-verified.json").read_text())
r3 = runs.get("r3f") or {}
vec = r3.get("ss_vec_match") or {}
hdr = r3.get("header_check") or {}
add("C01_r3f_present", bool(r3), "r3f S_ss=%s" % r3.get("S_ss"))
add("C02_r3f_vec_bad0", vec.get("bad") == 0 and vec.get("checked") == 518400,
    "bad=%s checked=%s drv=%s" % (vec.get("bad"), vec.get("checked"), vec.get("drv_groups")))
add("C03_r3f_header_crc", bool(hdr.get("pass")), json.dumps(hdr.get("got", {}))[:160])
add("C04_r3f_stable", (r3.get("S_ss_spread_pct") or 1) <= 2.0 and r3.get("frames") == 4,
    "band=%s spread=%s" % (r3.get("S_band_cycles"), r3.get("S_ss_spread_pct")))
add("C05_r3f_same_as_r0", runs.get("r3", {}).get("S_ss") == r3.get("S_ss"),
    "legacy=%s frozen=%s" % (runs.get("r3", {}).get("S_ss"), r3.get("S_ss")))
add("C06_counts", all(r3.get("counters", {}).get(k) in (0, 4, 518400) for k in
                     ("raw_drop", "cmp_drop", "dup", "geom", "err", "wd")),
    json.dumps(r3.get("counters", {}))[:160])
add("C07_tb_frozen", sha(R0 / "src/tb_ss_g0.v") == FROZEN_TB, sha(R0 / "src/tb_ss_g0.v"))
legacy = R0 / "src/legacy/tb_ss_g0_89948303.v"
add("C08_legacy_archived", legacy.exists() and sha(legacy) == LEGACY_TB,
    "%s %s" % (legacy.exists(), sha(legacy) if legacy.exists() else None))
add("C09_in_meta", proxy["inputs"]["in.meta"]["bytes"] == 330
    and proxy["inputs"]["in.meta"]["sha256"] == IN_META,
    json.dumps(proxy["inputs"]["in.meta"]))
add("C10_proxy_raw_vec", proxy["outputs"]["raw_bytes"] == 2592000
    and proxy["transform"]["mismatch_bytes"] == 0,
    "raw=%s mismatch=%s" % (proxy["outputs"]["raw_bytes"], proxy["transform"]["mismatch_bytes"]))
add("C11_verdict_g0", verdict.get("verdict") in
    ("G0_feasible_for_scope", "G0_not_closed", "G0_not_proven"),
    verdict.get("verdict"))
add("C12_g25_ref", verdict.get("g25_used_for_headline") is False
    and verdict.get("not_downgraded") is True, "g25 ref only / no downgrade")
add("C13_r4_assumed", "assumed" in verdict.get("r4", "") and verdict.get("runs", {}).get("r4") is None,
    verdict.get("r4"))
add("C14_a1_note", "4 cycles" in verdict.get("a1_overlapped_note", ""),
    verdict.get("a1_overlapped_note"))
add("C15_scope", all(s in verdict.get("scope", "") for s in ("93.75", "77.84", "proxy_not_worst", "slot-free")),
    verdict.get("scope", "")[:180])
add("C16_neg_controls", neg.get("all_rejected") is True,
    "all_rejected=%s" % neg.get("all_rejected"))
add("C17_protected_drift", not iv.get("protected_drift") and not iv.get("copied_src_mismatch"),
    "drift=%s mismatch=%s" % (iv.get("protected_drift"), iv.get("copied_src_mismatch")))
rows = (OUT / "g0-table.csv").read_text().strip().splitlines()
add("C18_g0_table_rows", len(rows) == 33 and "gate_G25_ref_only" in rows[0],
    "lines=%d header=%s" % (len(rows), rows[0][:100]))
add("C19_sink_table", (OUT / "sink-needs.csv").exists(), "sink-needs.csv")
man_path = R0 / "manifest-r2.json"
if man_path.exists():
    man = json.loads(man_path.read_text())
    art = {a["path"]: a for a in man["artifacts"]}
    bad = [p for p, a in art.items() if not (R0 / p).exists() or sha(R0 / p) != a["sha256"]]
    add("C20_manifest_hashes", not bad and man.get("stopped_modifying") is True
        and man.get("active_commands") == 0,
        "artifacts=%d bad=%s" % (len(art), bad[:5]))
    add("C21_manifest_binding", art.get("src/tb_ss_g0.v", {}).get("sha256") == FROZEN_TB
        and art.get("src/legacy/tb_ss_g0_89948303.v", {}).get("sha256") == LEGACY_TB
        and "manifest-r0.json" in art and "manifest-r1.json" in art,
        "frozen+legacy+manifest-r0+r1 bound")
    add("C22_full_frame_count", man.get("budget", {}).get("full_frame_vsim_runs") == 5,
        "full_frame=%s" % man.get("budget", {}).get("full_frame_vsim_runs"))
    add("C23_manifest_r3_S_ss", man.get("verdict", {}).get("r3_S_ss") == 5928286.0
        and man.get("verdict", {}).get("r3_S_ss") == verdict["runs"]["r3f"]["S_ss"],
        "manifest=%s verdict=%s" % (man.get("verdict", {}).get("r3_S_ss"),
                                    verdict["runs"]["r3f"]["S_ss"]))
    add("C24_budget_override", man.get("budget", {}).get("sim_wall_limit_min") == 112
        and abs(man.get("budget", {}).get("sim_wall_seconds") - 6532.4) < 0.1,
        "limit=%s actual=%s" % (man.get("budget", {}).get("sim_wall_limit_min"),
                                man.get("budget", {}).get("sim_wall_seconds")))
    add("C25_r3_vs_r0", verdict.get("r3_vs_r0", {}).get("legacy_S_ss") == 5928286.0
        and verdict.get("r3_vs_r0", {}).get("frozen_S_ss") == 5928286.0,
        json.dumps(verdict.get("r3_vs_r0", {})))
else:
    add("C20_manifest_hashes", False, "manifest-r1.json missing (pending freeze)")

res = {"checks": checks, "total": len(checks),
       "passed": sum(1 for c in checks if c["pass"]),
       "all_pass": all(c["pass"] for c in checks)}
(OUT / "check-outputs.json").write_text(json.dumps(res, indent=2) + "\n")
print("checks=%d passed=%d all_pass=%s" % (res["total"], res["passed"], res["all_pass"]))
for c in checks:
    if not c["pass"]:
        print("FAIL", c["id"], c["detail"])
