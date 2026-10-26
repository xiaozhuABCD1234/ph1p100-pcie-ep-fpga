"""Validate the corrected tables against the report, the frozen inputs and the rules.

Checks (all must pass for exit 0):
  1. out/scenarios.csv      43 rows, gate/verdict re-derived, no gate collapse, no dual-core feasible
  2. out/content-anchors.csv A1..A4 labels, A2/A4 circularity, anchor arithmetic
  3. out/gate-matrix.csv    24 rows (4 combos x 3 anchors x 2 gates)
  4. out/overhead-sensitivity.csv 43x3, 1080p participates, tier shift exact, 1080p30 not tier-robust
  5. out/ddr-budget.csv     5332 + 6400 columns, required_eff/gate_eff, DOC-1 disclosure
  6. out/corrections.csv    C1..C9 complete
  7. out/frontier.csv       unique primary, 2 alternates, comp content basis, 1080p not recommended
  8. verdict-r1.md          key-figure rows + headline/boundary statements
  9. out/legacy-regression.json  PASS with 0 mismatch

Expected values are recomputed here from the frozen constants with the design-guide formulas
and compared with the CSVs.  Tolerances follow the CSV print precision (cycles .3f, MB/s .6f,
percent .4f), so they test the arithmetic, not the rounding.
"""
import csv
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import calc  # noqa: E402
import render_report as rr  # noqa: E402

CLOCK = 187.5e6
RAW = 2592000.0
D0 = RAW * 30.0 / 1e6
D25 = 1.25 * D0
TOL_PCT = 2e-3
TOL_MB = 1e-3
TOL_CAP = 2e-5
CHECKS = [0]
FAILS = []


def ck(name, cond, detail=""):
    CHECKS[0] += 1
    if not cond:
        FAILS.append(name)
        print("FAIL  %s  %s" % (name, detail))


def near(a, b, tol):
    return abs(float(a) - float(b)) <= tol


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def read_csv(name):
    path = os.path.join(ROOT, "out", name)
    with open(path, "r", encoding="utf-8", newline="") as fh:
        rdr = csv.DictReader(fh)
        return list(rdr), rdr.fieldnames


def f(row, key):
    return float(row[key])


def i(row, key):
    return int(round(float(row[key])))


def cap_from(cycles):
    return RAW * CLOCK / float(cycles) / 1e6


def m0_from(cycles):
    return 100.0 * (cap_from(cycles) / D0 - 1.0)


def m25_from(cycles):
    return 100.0 * (cap_from(cycles) / D25 - 1.0)


def main():
    frozen = load_json(os.path.join(ROOT, "inputs", "frozen-inputs.json"))
    rules = load_json(os.path.join(HERE, "rules.json"))

    # ---------------------------------------------------------------- 1. scenarios
    scen, cols = read_csv("scenarios.csv")
    ck("scenarios: 43 rows", len(scen) == 43, len(scen))
    required = ["scenario_id", "cores", "streams", "W", "H", "fps", "clock_mhz",
                "cycles_core_per_frame", "cycles_chain_per_frame", "chain_anchor_id",
                "content_label", "capacity_chain_MBps", "per_stream_capacity_chain_MBps",
                "demand_per_stream_MBps", "margin_chain_pct", "gate_G0", "gate_G25",
                "verdict", "claim_status", "drop_rate_lb_pct", "eram_bound", "eram_total",
                "eram_headroom", "timing_status", "required_clock_0_mhz",
                "required_clock_25_mhz", "notes"]
    missing = [c for c in required if c not in cols]
    ck("scenarios: required columns present", not missing, missing)
    ck("scenarios: ids unique", len({r["scenario_id"] for r in scen}) == len(scen))
    n_margin = n_clock = n_gate = n_verdict = 0
    for r in scen:
        cap = f(r, "capacity_chain_MBps")
        ps = f(r, "per_stream_capacity_chain_MBps")
        dem = f(r, "demand_per_stream_MBps")
        if not near(ps, calc.per_stream_capacity(cap, i(r, "cores"), i(r, "streams")), 1e-4):
            n_margin += 1
        if not near(f(r, "margin_chain_pct"), 100.0 * (ps / dem - 1.0), TOL_PCT):
            n_margin += 1
        if r["gate_G0"] != ("pass" if f(r, "margin_chain_pct") >= 0.0 else "fail"):
            n_gate += 1
        if r["gate_G25"] != ("pass" if f(r, "margin_gate25_pct") >= 0.0 else "fail"):
            n_gate += 1
        if not near(f(r, "required_clock_25_mhz"),
                    f(r, "cycles_chain_per_frame") * f(r, "fps") * 1.25 / 1e6, TOL_MB):
            n_clock += 1
        if not near(f(r, "required_clock_0_mhz"),
                    f(r, "cycles_chain_per_frame") * f(r, "fps") / 1e6, TOL_MB):
            n_clock += 1
        timing = r["timing_status"] == "proven_at_187.5"
        verdict, reason = calc.classify_row(
            frozen, rules, i(r, "cores"), i(r, "streams"),
            f(r, "margin_chain_pct") / 100.0, f(r, "margin_gate25_pct") / 100.0,
            i(r, "eram_total"), i(r, "resource_conservative_eram"), timing)
        if r["verdict"] != verdict or r["verdict_reason"] != reason:
            n_verdict += 1
        ck("scenarios: no gate collapse %s" % r["scenario_id"],
           not (r["gate_G0"] == "pass" and r["gate_G25"] == "fail" and r["verdict"] == "infeasible"))
        ck("scenarios: claim_status enum %s" % r["scenario_id"],
           r["claim_status"] in ("proven_for_measured_content", "not_proven_all_content"))
        if i(r, "W") == 1920 and i(r, "H") == 1080:
            ck("scenarios: 1080p anchor A1 %s" % r["scenario_id"],
               r["chain_anchor_id"] == "A1_grad_ss" and near(f(r, "cycles_chain_per_frame"), 4677535, 1e-3))
        else:
            ck("scenarios: non-1080p affine %s" % r["scenario_id"],
               r["chain_anchor_id"] == "affine_comp_tier")
        if i(r, "cores") == 2:
            ck("scenarios: dual-core not feasible %s" % r["scenario_id"], r["verdict"] != "feasible")
    ck("scenarios: per-stream rule + margins consistent (%d bad)" % n_margin, n_margin == 0)
    ck("scenarios: gate columns consistent (%d bad)" % n_gate, n_gate == 0)
    ck("scenarios: required clock consistent (%d bad)" % n_clock, n_clock == 0)
    ck("scenarios: verdict mapping consistent (%d bad)" % n_verdict, n_verdict == 0)
    a1_30 = [r for r in scen if r["scenario_id"] == "1920x1080-30fps-c1s1-187.5MHz"][0]
    ck("scenarios: 1080p30 c1s1 G0+G25 pass", a1_30["gate_G0"] == "pass" and a1_30["gate_G25"] == "pass")
    ck("scenarios: 1080p30 c1s1 claim not_proven", a1_30["claim_status"] == "not_proven_all_content")
    ck("scenarios: 1080p30 c1s1 margin G0", near(f(a1_30, "margin_chain_pct"), 33.6174, TOL_PCT))
    ck("scenarios: 1080p30 c2s2 not feasible",
       [r for r in scen if r["scenario_id"] == "1920x1080-30fps-c2s2-187.5MHz"][0]["verdict"] != "feasible")

    # ------------------------------------------------------------ 2. content anchors
    anchors, acols = read_csv("content-anchors.csv")
    ck("anchors: 4 rows", len(anchors) == 4, len(anchors))
    by = {r["anchor_id"]: r for r in anchors}
    ck("anchors: ids A1..A4", set(by) == {"A1", "A2", "A3", "A4"})
    ck("anchors: A1 measured 4,677,535", by["A1"]["label"] == "measured"
       and near(f(by["A1"], "cycles_per_frame"), 4677535, 1e-3))
    ck("anchors: A2 assumed 6,421,414.375", by["A2"]["label"] == "assumed"
       and near(f(by["A2"], "cycles_per_frame"), 6421414.375, 1e-3))
    ck("anchors: A3 assumed 3,151,346.5", by["A3"]["label"] == "assumed"
       and near(f(by["A3"], "cycles_per_frame"), 3151346.5, 1e-3))
    ck("anchors: A4 not a throughput anchor",
       by["A4"]["is_throughput_anchor"] == "false" and by["A4"]["gate_G0"] == "not_applicable")
    ck("anchors: A2-A4 circularity 0.375",
       near(f(by["A2"], "cycles_per_frame") - f(by["A4"], "cycles_per_frame"), 0.375, 1e-6))
    for aid, cyc in (("A1", 4677535), ("A2", 6421414.375), ("A3", 3151346.5)):
        ck("anchors: %s capacity" % aid, near(f(by[aid], "capacity_MBps"), cap_from(cyc), TOL_CAP))
        ck("anchors: %s G0 margin" % aid, near(f(by[aid], "margin_G0_pct"), m0_from(cyc), TOL_PCT))
        ck("anchors: %s G25 margin" % aid, near(f(by[aid], "margin_G25_pct"), m25_from(cyc), TOL_PCT))

    # -------------------------------------------------------------- 3. gate matrix
    gm, gcols = read_csv("gate-matrix.csv")
    ck("gate-matrix: 24 rows", len(gm) == 24, len(gm))
    combos = {(r["anchor_id"], i(r, "cores"), i(r, "streams")) for r in gm}
    ck("gate-matrix: 12 anchor/combo cells", len(combos) == 12, len(combos))
    bad_gate = 0
    for r in gm:
        expect = "pass" if f(r, "margin_vs_gate_pct") >= 0.0 else "fail"
        if r["gate_result"] != expect:
            bad_gate += 1
        gd = f(r, "gate_demand_per_stream_MBps")
        if not near(gd, D0 if r["gate"] == "G0" else D25, 1e-6):
            bad_gate += 1
        if i(r, "cores") == 2 and r["row_verdict"] == "feasible":
            bad_gate += 1
    ck("gate-matrix: results/demands/dual-core consistent (%d bad)" % bad_gate, bad_gate == 0)
    for key in combos:
        gates = sorted(r["gate"] for r in gm
                       if (r["anchor_id"], i(r, "cores"), i(r, "streams")) == key)
        ck("gate-matrix: G0+G25 per combo %s" % (key,), gates == ["G0", "G25"])
    ck("gate-matrix: A1 c1s1 both pass",
       all(r["gate_result"] == "pass" for r in gm
           if r["anchor_id"] == "A1" and i(r, "cores") == 1 and i(r, "streams") == 1))
    ck("gate-matrix: A2 c1s1 both fail",
       all(r["gate_result"] == "fail" for r in gm
           if r["anchor_id"] == "A2" and i(r, "cores") == 1 and i(r, "streams") == 1))

    # ---------------------------------------------------------------- 4. overhead
    over, ocols = read_csv("overhead-sensitivity.csv")
    ck("overhead: 129 rows", len(over) == 129, len(over))
    ids = {r["scenario_id"] for r in over}
    ck("overhead: 43 scenarios x 3 tiers", len(ids) == 43 and len(over) == 3 * len(ids))
    ck("overhead: all applies=true", all(r["applies"] == "true" for r in over))
    tiers = sorted({int(round(float(r["tier_cycles"]))) for r in over})
    ck("overhead: tiers 0/426385/1000000", tiers == [0, 426385, 1000000], tiers)
    bad_shift = bad_m = 0
    for r in over:
        if i(r, "W") == 1920 and i(r, "H") == 1080:
            t = int(round(float(r["tier_cycles"])))
            if not near(f(r, "cycles_chain_per_frame"), 4677535 + (t - 426385), 1e-3):
                bad_shift += 1
            if r["chain_source"] != "A1_grad_ss_tier_shift":
                bad_shift += 1
        cap = f(r, "capacity_chain_MBps")
        ps = calc.per_stream_capacity(cap, i(r, "cores"), i(r, "streams"))
        if not near(f(r, "margin_chain_pct"), 100.0 * (ps / f(r, "demand_per_stream_MBps") - 1.0), TOL_PCT):
            bad_m += 1
    ck("overhead: 1080p tier shift exact (%d bad)" % bad_shift, bad_shift == 0)
    ck("overhead: margins consistent (%d bad)" % bad_m, bad_m == 0)
    p30 = [r for r in over if r["scenario_id"] == "1920x1080-30fps-c1s1-187.5MHz"]
    ck("overhead: 1080p30 has 3 tiers", len(p30) == 3)
    t1e6 = [r for r in p30 if int(round(float(r["tier_cycles"]))) == 1000000][0]
    ck("overhead: 1080p30 tier 1e6 misses G25", t1e6["gate_G25"] == "fail")
    ck("overhead: 1080p30 not tier-robust", all(r["tier_robust_G25"] == "false" for r in p30))
    t0 = [r for r in p30 if int(round(float(r["tier_cycles"]))) == 0][0]
    ck("overhead: 1080p30 tier0 G25 margin", near(f(t0, "margin_gate25_pct"), m25_from(4251150), TOL_PCT))

    # --------------------------------------------------------------------- 5. DDR
    ddr, dcols = read_csv("ddr-budget.csv")
    ck("ddr: 7 cases", len(ddr) == 7, len(ddr))
    main_row = [r for r in ddr if r["case_id"] == "dual_1080p30_main"][0]
    total = 2 * (RAW * 30 * 2 / 1e6 * 1.6) + 2 * (2594750.0 * 30 * 2 / 1e6)
    ck("ddr: total 809.034", near(f(main_row, "ddr_total_MBps"), total, 1e-5), f(main_row, "ddr_total_MBps"))
    ck("ddr: gate 1011.2925", near(f(main_row, "ddr_gate_25_MBps"), 1.25 * total, 1e-5))
    ck("ddr: required_eff 5332", near(f(main_row, "required_eff_1333_pct"), total / 5332.0 * 100.0, TOL_PCT))
    ck("ddr: gate_eff 5332", near(f(main_row, "gate_eff_1333_pct"), 1.25 * total / 5332.0 * 100.0, TOL_PCT))
    ck("ddr: required_eff 6400", near(f(main_row, "required_eff_1600_pct"), total / 6400.0 * 100.0, TOL_PCT))
    ck("ddr: gate_eff 6400", near(f(main_row, "gate_eff_1600_pct"), 1.25 * total / 6400.0 * 100.0, TOL_PCT))
    ck("ddr: both peaks labelled", near(f(main_row, "peak_main_1333_MBps"), 5332, 1e-6)
       and near(f(main_row, "peak_fallback_1600_MBps"), 6400, 1e-6))
    ck("ddr: doc1 disclosed not adopted", all(r["doc1_s8_reproducible"] == "false" for r in ddr)
       and near(f(main_row, "doc1_s8_1333_GBps"), 2.33, 1e-9))
    ck("ddr: peak formulas", near(1333e6 * 32 / 8 / 1e6, 5332, 1e-9) and near(1600e6 * 32 / 8 / 1e6, 6400, 1e-9))

    # --------------------------------------------------------------- 6. corrections
    corr, ccols = read_csv("corrections.csv")
    ck("corrections: 9 rows", len(corr) == 9, len(corr))
    ck("corrections: ids C1..C9", [r["id"] for r in corr] == ["C%d" % n for n in range(1, 10)])
    for r in corr:
        empty = [k for k, v in r.items() if v is None or str(v).strip() == ""]
        ck("corrections: %s complete" % r["id"], not empty, empty)

    # ------------------------------------------------------------------ 7. frontier
    front, fcols = read_csv("frontier.csv")
    rec = [r for r in front if r["is_recommended"] == "true"]
    ck("frontier: 3 recommended rows", len(rec) == 3, len(rec))
    ck("frontier: primary unique 1600x900",
       len([r for r in rec if i(r, "W") == 1600 and i(r, "H") == 900]) == 1)
    ck("frontier: recommended are comp basis",
       all(r["chain_anchor_id"] == "affine_comp_tier" for r in rec))
    ck("frontier: no 1080p/dual-core recommended",
       all(i(r, "W") != 1920 and i(r, "cores") == 1 for r in rec))
    cand = [r for r in scen if f(r, "fps") == 30.0 and r["chain_anchor_id"] == "affine_comp_tier"
            and r["gate_G25"] == "pass" and r["verdict"] in ("feasible", "conditional")]
    best = max(cand, key=lambda r: i(r, "W") * i(r, "H"))
    ck("frontier: primary is grid-maximal", (i(best, "W") * i(best, "H")) == 1600 * 900, best["scenario_id"])
    ck("frontier: 1080p30 A1 row listed but not recommended",
       any(i(r, "W") == 1920 and near(f(r, "fps"), 30.0, 1e-9) and r["is_recommended"] == "false"
           for r in front))
    ck("frontier: alternates are tier-robust",
       all(r["worst_tier_gate_G25"] == "pass" for r in rec if i(r, "W") * i(r, "H") < 1600 * 900))

    # ------------------------------------------------------- 8. report consistency
    with open(os.path.join(ROOT, "verdict-r1.md"), "r", encoding="utf-8") as fh:
        report = fh.read()
    rows = calc.scenario_rows(frozen, rules)
    overhead = calc.overhead_rows(rows, frozen, rules)
    figs = rr.key_figures(frozen, rows, overhead)
    absent = [lab for lab, val, tag, src in figs if ("| %s | %s |" % (lab, val)) not in report]
    ck("report: every key-figure row present", not absent, absent[:6])
    expected_strings = [
        "103.9009", "+33.6174%", "+6.8939%", "75.6843", "-2.6694%", "-22.1355%",
        "154.2198", "+98.3279%", "+58.6623%", "4,677,535", "6,766,434", "5,722,994",
        "480,930", "400,320", "4,251,150", "5,251,150", "+17.6152%", "-4.7828%",
        "175.408", "240.803", "32.068", "23.359", "77.76", "97.20", "5,332", "6,400",
        "15.1732%", "18.9665%", "12.6412%", "15.8014%", "809.034", "11,520", "3.475",
        "225.235", "1628", "not_proven", "not_proven_all_content", "assumed_from_single_core",
        "paaxi_shared_unproven", "sink_limited=false", "export_tail",
    ]
    missing_s = [s for s in expected_strings if s not in report]
    ck("report: key numbers present", not missing_s, missing_s)
    for phrase in ("不是 `infeasible`，也不是 `feasible`", "内容跨界", "未放宽",
                   "A2 与 A4", "band", "tier 依赖", "会改变结论", "梯度", "双路 1080p30"):
        ck("report: statement present: %s" % phrase, phrase in report)
    bad_lines = [ln for ln in report.split("\n") if "below_25" in ln and "infeasible" in ln
                 and "不得" not in ln]
    ck("report: no below_25 -> infeasible statement", not bad_lines, bad_lines[:2])
    ck("report: headline not_proven stated", "结论 = `not_proven`" in report)

    # ------------------------------------------------------- 9. legacy regression
    lr = load_json(os.path.join(ROOT, "out", "legacy-regression.json"))
    ck("legacy: verdict PASS", lr.get("verdict") == "PASS", lr.get("verdict"))
    ck("legacy: 43 rows 0 mismatch", lr["scenarios_csv"]["mismatch_count"] == 0
       and lr["scenarios_csv"]["rows"] == 43)
    ck("legacy: 129 overhead rows 0 mismatch", lr["overhead_sensitivity_csv"]["mismatch_count"] == 0
       and lr["overhead_sensitivity_csv"]["rows"] == 129)
    ck("legacy: hashes match P2", lr.get("legacy_hashes_match_p2") is True)

    print("\n%d checks, %d failures" % (CHECKS[0], len(FAILS)))
    if FAILS:
        print("FAILED: %s" % FAILS[:10])
        return 1
    print("CHECK_OUTPUTS=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
