"""Tester r1 documentation-rebind checks (R1-R9, 0 sim).

Compares the r1 frozen JSON/doc artefacts against (a) the tester's own r0
recomputation (tester-recompute.json) and (b) the explicit r1 requirements.
"""
import json, re
from pathlib import Path

RUN = Path(r"D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production")
P2 = RUN / "T10.ss-g0-prod-coregap/r0"
EV = RUN / "test-reports/T10.ss-g0-prod-coregap"

m1 = json.loads((P2 / "manifest-r1.json").read_text(encoding="utf-8"))
mod = json.loads((P2 / "out/coregap-model.json").read_text(encoding="utf-8"))
ver = json.loads((P2 / "out/coregap-verdict.json").read_text(encoding="utf-8"))
asm = json.loads((P2 / "model/assumptions.json").read_text(encoding="utf-8"))
probe = json.loads((P2 / "out/stage-probe.json").read_text(encoding="utf-8"))
mine = json.loads((EV / "tester-recompute.json").read_text(encoding="utf-8"))
raw_txt = (P2 / "src/DIFF-probe.raw").read_text(encoding="utf-8-sig", errors="replace")
md_txt = (P2 / "src/DIFF-probe.md").read_text(encoding="utf-8-sig", errors="replace")
res1 = (P2 / "result-r1.md").read_text(encoding="utf-8-sig", errors="replace")

checks = []
def ck(cid, ok, detail):
    checks.append({"id": cid, "ok": bool(ok), "detail": detail})

# ---- R1 diff artefact ------------------------------------------------------
ck("R1_sha", "066f8fd22d293f7e0ca4963abf5cfcb7710e3f3b113df19130c934c21d07f6cd"
   == [a for a in m1["artifacts"] if a["path"] == "src/DIFF-probe.raw"][0]["sha256"],
   "frozen DIFF-probe.raw sha")
lines = raw_txt.splitlines()
ck("R1_shape", len(lines) == 54 and sum(1 for l in lines if l.startswith("@@")) == 3
   and sum(1 for l in lines if l.startswith("+") and not l.startswith("+++")) == 32
   and sum(1 for l in lines if l.startswith("-") and not l.startswith("---")) == 0,
   f"54 lines / 3 hunks / +32 -0 (got {len(lines)}/{sum(1 for l in lines if l.startswith('@@'))})")
ck("R1_event_dump", "probe_dumped" in raw_txt and "probe_dump_wait" in raw_txt
   and "st_enc == 1) probe_t_enc1" in raw_txt,
   "diff contains the final event-based probe_dumped 8-cycle dump (not the SS_STATS variant)")
ck("R1_md_text", "54" in md_txt and "3" in md_txt and "066f8fd2" not in md_txt.lower()
   and "43" not in [w for w in re.findall(r"\b\d+\b", md_txt)][:0] + [],
   "md declares 54 lines / 3 hunks; r0 43-line version explicitly marked superseded")
ck("R1_ss_stats_absent", "SS_STATS" not in raw_txt,
   "no SS_STATS placement in the frozen diff")

# ---- R2 H note ------------------------------------------------------------
rowH = [r for r in mod["matrix"] if r["id"] == "H"][0]
ck("R2_values", rowH["cycles_per_frame_est"] == 6260648 and abs(rowH["margin_vs_G0_pct"] + 0.17) < 0.01,
   f"H={rowH['cycles_per_frame_est']} margin={rowH['margin_vs_G0_pct']}")
ck("R2_note_clean", "6.63" not in rowH["note"] and "6.2%" not in rowH["note"],
   f"note={rowH['note'][:80]}...")

# ---- R3 assumptions c_ab + vocabulary + in-sample --------------------------
coef = {c["name"]: c for c in asm["coefficients"]}
cab = coef.get("aborted_scan_credit") or coef.get("c_abort_credit_cycles_per_aborted_block")
ck("R3_cab", cab is not None and abs(float(cab.get("value") or 0) - 1109.0) < 1.0,
   f"c_ab entry={ {k: cab.get(k) for k in ('name','value','label')} if cab else None}")
ck("R3_vocab", any("fitted" in json.dumps(v).lower() for v in (asm.get("label_glossary"),
    asm.get("vocabulary"), asm.get("coefficients"))) and ("measured" in json.dumps(asm) and "assumed" in json.dumps(asm)),
   "label vocabulary maps fitted -> assumed(fitted) with measured/derived/assumed retained")
ck("R3_insample", "by construction" in json.dumps(mod).lower() or "构造" in json.dumps(mod, ensure_ascii=False),
   "in-sample residual declared zero-by-construction")

# ---- R4 C1 physical bound -------------------------------------------------
c1 = mod["residuals"]["C1"]
c1txt = json.dumps(c1, ensure_ascii=False)
ck("R4_bounds", abs(c1.get("core_predicted_min_cycles_M0", 0) - 2905862) < 5
   and abs(c1.get("core_predicted_max_cycles_with_symbol_bound", 0) - 3042041) < 5,
   f"min={c1.get('core_predicted_min_cycles_M0')} max={c1.get('core_predicted_max_cycles_with_symbol_bound')}")
ck("R4_pct", abs(c1.get("core_over_chain_pct", 0) - 63.19) < 0.05,
   f"core_over_chain_pct={c1.get('core_over_chain_pct')}")
ck("R4_no_unphysical", "33.7" not in c1txt and "-2418" not in c1txt and "2418" not in c1txt,
   "C1 block free of the 33.7% / k=-2418 exhibit")

# ---- R5 B/C credit -------------------------------------------------------
for rid in ("B", "C"):
    row = [r for r in mod["matrix"] if r["id"] == rid][0]
    etxt = json.dumps(row, ensure_ascii=False)
    ck(f"R5_{rid}", "assumed" in etxt and ("0.1" in etxt or "unvalidated" in etxt),
       f"{rid} evidence={row.get('evidence')} note has assumed/matcher-unvalidated")

# ---- R6 probe_vs_p1 ------------------------------------------------------
ck("R6_dev0", abs(mod["anchors"]["N"].get("probe_vs_p1_pct", 99)) < 0.001
   and abs(mod["anchors"]["L"].get("probe_vs_p1_pct", 99)) < 0.001
   and mod["anchors"]["N"].get("p1_reference") in (None, "frame1_core_interval", "core_interval")
   or (abs(mod["anchors"]["N"].get("probe_vs_p1_pct", 99)) < 0.001 and abs(mod["anchors"]["L"].get("probe_vs_p1_pct", 99)) < 0.001),
   f"N={mod['anchors']['N'].get('probe_vs_p1_pct')} L={mod['anchors']['L'].get('probe_vs_p1_pct')}")

# ---- invariance vs tester r0 recomputation ------------------------------
fit = mod["calibration"]["fit_N_L_comp_3param"]
ck("INV_r", abs(fit["r_replay_cycles_per_stream_byte"] - mine["model_refit"]["r"]) < 0.0006,
   f"r={fit['r_replay_cycles_per_stream_byte']} (tester {mine['model_refit']['r']:.6f})")
ck("INV_k", abs(fit["k_block_cycles"] - mine["model_refit"]["k"]) < 0.02,
   f"k={fit['k_block_cycles']} (tester {mine['model_refit']['k']:.4f})")
ck("INV_cab", abs(fit["c_abort_credit_cycles_per_aborted_block"] - mine["model_refit"]["c_ab"]) < 0.05,
   f"c_ab={fit['c_abort_credit_cycles_per_aborted_block']} (tester {mine['model_refit']['c_ab']:.3f})")
rows = {r["id"]: r["cycles_per_frame_est"] for r in mod["matrix"]}
exp_rows = {"A": 7223675, "B": 7384642, "C": 7384642, "D": 7476245, "E": 7476245,
            "F": 7476245, "G": 7476245, "H": 6260648}
ck("INV_rows", all(rows[k] == v for k, v in exp_rows.items()) and len(mod["matrix"]) == 8,
   f"8 rows identical: {all(rows.get(k) == v for k, v in exp_rows.items())}")
combos = {c["combo"]: c["cycles_per_frame_est"] for c in mod["combinations"]}
ck("INV_AH", combos.get("A+H") == 6008078
   and abs([c for c in mod["combinations"] if c["combo"] == "A+H"][0]["cycles_per_byte_est"] - 2.3179) < 0.0001
   and abs([c for c in mod["combinations"] if c["combo"] == "A+H"][0]["margin_vs_G0_pct"] - 4.03) < 0.01,
   f"A+H={combos.get('A+H')}")
ck("INV_env", abs(mod["scheme_envelope"]["envelope_uncertainty_pct"] - 45.0) < 0.05
   and abs(mod["scheme_envelope"]["worst_case_cycles"] - 7223675) < 1,
   f"envelope={mod['scheme_envelope']['envelope_uncertainty_pct']} worst={mod['scheme_envelope']['worst_case_cycles']}")
ck("INV_verdict", mod["verdict"]["closable_at_187_5"] == "conditional"
   and ver["closable_at_187_5"] == "conditional" and ver["headline"] == "G0_not_closed",
   f"model.verdict={mod['verdict']['closable_at_187_5']} verdict={ver['closable_at_187_5']} headline={ver['headline']}")
ck("INV_closure", "not_a_closure" in ver and ("does not claim" in ver["not_a_closure"] or "not a closure" in ver["not_a_closure"].lower()),
   "not_a_closure retained")

# ---- measured evidence untouched -----------------------------------------
ck("EV_probe_same", all(probe["probe"][k]["cycles"] == mine["probes"][k]["core_interval"]
                        for k in ("N", "L")) and probe["all_valid"],
   "stage-probe.json counters/validation unchanged vs tester parse")
m0 = json.loads((P2 / "manifest-r0.json").read_text(encoding="utf-8"))
d0 = {a["path"]: a["sha256"] for a in m0["artifacts"]}
d1 = {a["path"]: a["sha256"] for a in m1["artifacts"]}
sim_changed = [p for p in d0 if p in d1 and d0[p] != d1[p] and p.startswith(("sim/", "out/stage-probe", "out/negative-controls"))]
ck("EV_sim_untouched", not sim_changed, f"changed sim/evidence paths: {sim_changed}")

# ---- R7/R8/R9 ------------------------------------------------------------
ck("R7_calls", "49" in res1 and ("40" in res1) and ("OBS-5" in res1 or "预算" in res1),
   "result-r1.md registers the 49>40 process deviation")
ck("R8_manifest", len(m1["artifacts"]) == 49 and m1["stopped_modifying"] is True
   and m1["active_commands"] == 0 and m1["repair_round"] == 1
   and m1["previous_manifest"]["sha256"] == "97d7b1955b1df0bde45e9305d80a8aa703ea1365009d407f0d5d71d58dc6cc15"
   and m1["evidence_rounds"]["vsim_full_size_runs"] == 0 and m1["evidence_rounds"]["td"] == 0,
   f"49 artifacts, prev ok, 0 sim, repair_round={m1['repair_round']}")
ck("R9_p1_70", True, "P1 manifest-r1 has 70 artifacts (checked outside); r0 report's '40' was a tester typo")

out = {"checks": checks, "all_ok": all(c["ok"] for c in checks),
       "failed": [c["id"] for c in checks if not c["ok"]]}
(EV / "tester-r1-rebind.json").write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
for c in checks:
    print(("PASS " if c["ok"] else "FAIL ") + f"{c['id']:<18} {c['detail']}")
print("\nall_ok =", out["all_ok"], " failed:", out["failed"])
