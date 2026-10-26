"""r1 doc-refreeze: verify the regenerated model JSON and patch coregap-verdict.json.

0 sim.  Touches only the C1 statement, the LOO note wording and audit metadata in
out/coregap-verdict.json; never the matrix numbers, the envelope, `conditional` or G0.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "out"

# ---------------------------------------------------------------- verify model
m = json.loads((OUT / "coregap-model.json").read_text(encoding="utf-8"))
cal = m["calibration"]["fit_N_L_comp_3param"]
checks = {
    "r": round(cal["r_replay_cycles_per_stream_byte"], 6),
    "k": round(cal["k_block_cycles"], 4),
    "c_ab": round(cal["c_abort_credit_cycles_per_aborted_block"], 2),
    "H_cycles": [r["cycles_per_frame_est"] for r in m["matrix"] if r["id"] == "H"][0],
    "A_cycles": [r["cycles_per_frame_est"] for r in m["matrix"] if r["id"] == "A"][0],
    "A_plus_H": [c["cycles_per_frame_est"] for c in m["combinations"] if c["combo"] == "A+H"][0],
    "envelope_pct": m["scheme_envelope"]["envelope_uncertainty_pct"],
    "verdict": m["verdict"]["closable_at_187_5"],
    "N_probe_vs_p1_pct": m["anchors"]["N"]["probe_vs_p1_pct"],
    "L_probe_vs_p1_pct": m["anchors"]["L"]["probe_vs_p1_pct"],
    "N_probe_vs_p1_ss_pct": round(m["anchors"]["N"]["probe_vs_p1_ss_pct"], 4),
    "H_note": [r["note"] for r in m["matrix"] if r["id"] == "H"][0],
    "B_evidence": [r["evidence"] for r in m["matrix"] if r["id"] == "B"][0],
    "C1": m["residuals"]["C1"],
}
expected = {"r": 1.9007, "k": 293.63, "c_ab": 1109.0, "H_cycles": 6260648,
            "A_cycles": 7223675, "A_plus_H": 6008078, "envelope_pct": 45.0,
            "verdict": "conditional", "N_probe_vs_p1_pct": 0.0, "L_probe_vs_p1_pct": 0.0}
tol = {"r": 5e-4, "k": 0.05, "c_ab": 0.5}
bad = [k for k, v in expected.items()
       if ((abs(checks[k] - v) > tol.get(k, 0.0)) if isinstance(v, (int, float)) else (checks[k] != v))]
print("INVARIANT", "OK" if not bad else "MISMATCH " + str(bad), json.dumps({k: checks[k] for k in expected}, ensure_ascii=False))
print("H_note:", checks["H_note"])
print("B_evidence:", checks["B_evidence"][:160])
print("C1:", json.dumps(checks["C1"], indent=1, ensure_ascii=False)[:900])
print("N_ss_pct(ref only):", checks["N_probe_vs_p1_ss_pct"])
assert not bad, bad
assert "6.63" not in checks["H_note"] and "6.2%" not in checks["H_note"]
assert "assumed" in checks["B_evidence"]
assert checks["C1"]["core_predicted_min_cycles_M0"] == 2905862
assert checks["C1"]["core_estimate_over_chain_pct"] == 63.19
assert "1,441,559" not in json.dumps(checks["C1"])

# ---------------------------------------------------------------- patch verdict
vp = OUT / "coregap-verdict.json"
v = json.loads(vp.read_text(encoding="utf-8"))
v["repair_round"] = 1
v["r1_doc_refreeze"] = {
    "sim_runs": 0, "td": 0, "board": 0, "network": 0,
    "scope": "documentation / labels / references only; model arithmetic, matrix numbers, "
             "envelope 45.034%, closable_at_187_5 = conditional and the G0 headline are unchanged",
    "changes": [
        "R1 src/DIFF-probe.raw regenerated from the final probe TB (git diff --no-index --unified=2); "
        "src/DIFF-probe.md line/hunk/text corrected",
        "R2 coregap-model.json row H note -> 6,260,648 / -0.17% (stale 6.63M / 6.2% removed)",
        "R3 model/assumptions.json: c_ab = 1,109 added, fitted mapped into measured/derived/assumed, "
        "in-sample = 0 declared constructive",
        "R4 coregap-model.json residuals.C1 + this file: physical coefficients 2,905,862..3,042,041 "
        "(est 2,956,095 = 63.19% of the chain); the 1,441,559..1,577,737 (33.7%) k = -2418 basis withdrawn",
        "R5 rows B/C: the -0.02*scan credit labelled assumed; matcher not validated + <0.1% evidence kept",
        "R6 anchors.{N,L}.probe_vs_p1_pct now reference the P1 r1 frame-1 core_interval (0.000%); the "
        "4-frame S_ss comparison is kept separately as probe_vs_p1_ss_pct",
        "R7 OBS-5 (dev calls ~49 > 40) registered as a process deviation in result-r1.md and manifest-r1 notes",
        "R8 manifest-r1.json (repair_round = 1, previous_manifest = manifest-r0.json 97d7b195..)"
    ],
    "tester_r0_obs": {
        "OBS-1": "closed by R1 (regenerated diff: 54 lines, 3 hunks, +32/-0, SHA in manifest-r1; the "
                 "tester's own unified=3 copy is 60 lines / 3 hunks, same hunk bodies)",
        "OBS-2": "closed by R2", "OBS-3": "closed by R3", "OBS-4": "closed by R4",
        "OBS-5": "registered (R7), not reworked", "OBS-6": "closed by R5", "OBS-7": "closed by R6"
    }
}
v["model"]["residuals"]["C1"] = (
    "not_applicable_core_level: with the physical fitted coefficients (r=1.900712, k=293.6313) the C1 "
    "core-level bound is 2,905,862 (M=0) .. 3,042,041 (M <= stream/3), estimate 2,956,095 = 63.19% of the "
    "4,677,970-cycle chain interval; the chain interval therefore contains capture/feed/export work and "
    "cannot be a core anchor. The r0 statement 1,441,559..1,577,737 (33.7%), computed with the "
    "non-physical k = -2418 cycles/block from the 2-parameter {N,L} fold, is withdrawn.")
v["model"]["c1_physical_bounds"] = {
    "cycles_M0_floor": 2905862, "cycles_symbol_bound": 3042041,
    "cycles_estimate": 2956095, "pct_of_chain_interval": 63.19,
    "chain_interval_cycles": 4677970,
    "coefficients": {"r": 1.900712, "k": 293.6313},
    "label": "derived (physical coefficients) - C1 stays excluded from the fit"
}
v["model"]["leave_one_out"]["fit_N_L_k0_predict_comp"]["note"] = (
    "the unconstrained 2-parameter {N,L} fold returns k = -2418 cycles/block, which is unphysical; "
    "it is quoted only to justify the third parameter (per-abort credit) and is NOT used for any C1 "
    "or matrix statement")
vp.write_text(json.dumps(v, indent=2, ensure_ascii=False), encoding="utf-8")
print("verdict patched:", vp, "closable=", v["closable_at_187_5"], "headline=", v["headline"])
