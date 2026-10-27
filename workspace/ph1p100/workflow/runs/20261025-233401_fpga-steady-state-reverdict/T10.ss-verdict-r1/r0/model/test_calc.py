"""Known-value / boundary / negative-control tests for model/calc.py (corrected model).

Run: python model/test_calc.py   (exit 0 = all checks pass)
No file writes except stdout.  Every expected number below is a frozen cross-check value
from dev-plan.md section 4.6 (planning-round hand arithmetic), not a copy of the model's
own output; a mismatch means a formula/unit error, never a threshold change.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import calc  # noqa: E402

FAILS = []
COUNT = [0]


def check(name, cond, detail=""):
    COUNT[0] += 1
    if cond:
        print("PASS  %s" % name)
    else:
        print("FAIL  %s  %s" % (name, detail))
        FAILS.append(name)


def close(a, b, tol):
    return abs(float(a) - float(b)) <= tol


def expect_reject(name, reason, fn, *args, **kwargs):
    try:
        fn(*args, **kwargs)
    except calc.ModelRejected as exc:
        check(name, str(exc) == reason, "got %s, want %s" % (exc, reason))
    else:
        check(name, False, "validator did not reject")


def load(name):
    with open(os.path.join(ROOT, "inputs", name), "r", encoding="utf-8") as fh:
        return json.load(fh)


def main():
    frozen = load("frozen-inputs.json")
    with open(os.path.join(HERE, "rules.json"), "r", encoding="utf-8") as fh:
        rules = json.load(fh)

    # ---------------------------------------------------------------- known values
    a1 = calc.anchor_metrics(frozen, "A1")
    check("A1 cycles = 4,677,535 (P1 measured S_ss)", a1["cycles_per_frame"] == 4677535)
    check("A1 C_ss = 103.9009 MB/s", close(a1["capacity_MBps"], 103.9008794, 1e-6), a1["capacity_MBps"])
    check("A1 fps = 40.0852", close(a1["fps_30_equiv"], 40.0852158, 1e-6), a1["fps_30_equiv"])
    check("A1 margin_0 = +33.6174%", close(a1["margin_0_pct"], 33.6173861, 1e-6), a1["margin_0_pct"])
    check("A1 margin_25 = +6.8939%", close(a1["margin_25_pct"], 6.8939089, 1e-6), a1["margin_25_pct"])
    check("A1 f_req_0 = 140.326 MHz", close(calc.required_clock_MHz(4677535, 30, 0.0), 140.32605, 1e-9))
    check("A1 f_req_25 = 175.408 MHz", close(calc.required_clock_MHz(4677535, 30, 0.25), 175.4075625, 1e-9))
    check("A1 G0/G25 both pass", a1["gate_G0"] == "pass" and a1["gate_G25"] == "pass")

    a2 = calc.anchor_metrics(frozen, "A2")
    check("A2 cycles = 6,421,414.375", close(a2["cycles_per_frame"], 6421414.375, 1e-9))
    check("A2 C_ss = 75.6843 MB/s", close(a2["capacity_MBps"], 75.6842609, 1e-5), a2["capacity_MBps"])
    check("A2 margin_0 = -2.6694%", close(a2["margin_0_pct"], -2.6694, 1e-4), a2["margin_0_pct"])
    check("A2 margin_25 = -22.1355%", close(a2["margin_25_pct"], -22.1355, 1e-4), a2["margin_25_pct"])
    check("A2 G0/G25 both fail", a2["gate_G0"] == "fail" and a2["gate_G25"] == "fail")

    a3 = calc.anchor_metrics(frozen, "A3")
    check("A3 cycles = 3,151,346.5", close(a3["cycles_per_frame"], 3151346.5, 1e-9))
    check("A3 C_ss = 154.2198 MB/s", close(a3["capacity_MBps"], 154.219791, 1e-5), a3["capacity_MBps"])
    check("A3 margin_0 = +98.3279%", close(a3["margin_0_pct"], 98.3279, 1e-4), a3["margin_0_pct"])
    check("A3 margin_25 = +58.6623%", close(a3["margin_25_pct"], 58.6623, 1e-4), a3["margin_25_pct"])

    check("A2 - A4 = 0.375 cycles (circular definition disclosed)",
          close(6421414.375 - 6421414, 0.375, 1e-9))
    check("A4 is not a throughput anchor",
          frozen["anchors_1080p"]["A4"]["is_throughput_anchor"] is False)

    # ------------------------------------------------------------- gate thresholds
    c_0 = calc.capacity_from_cycles(6250000, frozen["clock_hz"])
    c_25 = calc.capacity_from_cycles(5000000, frozen["clock_hz"])
    check("S=6,250,000 -> 77.76 MB/s (exactly 0%)", close(c_0, 77.76, 1e-12), c_0)
    check("S=5,000,000 -> 97.20 MB/s (exactly 25%)", close(c_25, 97.2, 1e-12), c_25)
    check("demand 1080p30 = 77.76 MB/s", close(calc.demand_MBps(2592000, 30), 77.76, 1e-12))
    check("G0 boundary: exactly 0% counts as pass",
          calc.gate_g0(77.76, 77.76) == "pass")
    check("G25 boundary: exactly 25% counts as pass",
          calc.gate_g25(97.2, 77.76) == "pass")
    check("G25 just below 25% fails", calc.gate_g25(97.19, 77.76) == "fail")

    # boundary verdicts
    v, why = calc.classify_row(frozen, rules, 1, 1, 0.0, -0.20, 187, 187, True)
    check("m0 == 0% -> below_25 (conditional), never infeasible", v == "conditional" and why == "BELOW_25")
    v, why = calc.classify_row(frozen, rules, 1, 1, 0.25, 0.0, 187, 187, True)
    check("m0 == 25% -> feasible", v == "feasible")
    v, why = calc.classify_row(frozen, rules, 1, 1, -1e-9, -0.2, 187, 187, True)
    check("m0 < 0 -> infeasible MISSES_NOMINAL", v == "infeasible" and why == "MISSES_NOMINAL")
    v, why = calc.classify_row(frozen, rules, 2, 2, 0.5, 0.2, 231, 289, False)
    check("dual-core with G25 met -> conditional, never feasible", v == "conditional")
    v, why = calc.classify_row(frozen, rules, 1, 1, 0.5, 0.2, 301, 289, True)
    check("marginal ERAM > 300 -> infeasible (resource)", v == "infeasible")

    # per-stream rules
    check("1c2s per-stream = C/2", close(calc.per_stream_capacity(103.9008794, 1, 2), 51.9504397, 1e-6))
    check("2c2s per-stream = C, never 2C",
          close(calc.per_stream_capacity(103.9008794, 2, 2), 103.9008794, 1e-9))
    check("c1s2 A1 margin_0 = -33.1913%",
          close(calc.margin_0(51.9504397, 77.76) * 100.0, -33.1913, 1e-4))

    # max fps
    check("A1 25% max fps = 32.068",
          close(calc.max_fps(4677535, frozen["clock_hz"], 0.25), 32.0684, 1e-3))
    check("A2 25% max fps = 23.359",
          close(calc.max_fps(6421414.375, frozen["clock_hz"], 0.25), 23.3593, 1e-3))
    check("A2 f_req_25 = 240.803 MHz",
          close(calc.required_clock_MHz(6421414.375, 30, 0.25), 240.8030, 1e-4))

    # tier shift (1080p participates)
    check("tier 0 -> 4,251,150 cycles", calc.tier_shift_1080p(frozen, 0) == 4251150)
    check("tier primary -> 4,677,535 cycles", calc.tier_shift_1080p(frozen, 426385) == 4677535)
    check("tier 1e6 -> 5,251,150 cycles", calc.tier_shift_1080p(frozen, 1000000) == 5251150)
    for tier, m0, m25 in ((0, 47.0190, 17.6152), (426385, 33.6174, 6.8939), (1000000, 19.0215, -4.7827)):
        cap = calc.capacity_from_cycles(calc.tier_shift_1080p(frozen, tier), frozen["clock_hz"])
        d = calc.demand_MBps(2592000, 30)
        check("tier %d margin_0 = %+.4f%%" % (tier, m0),
              close(calc.margin_0(cap, d) * 100.0, m0, 1e-4))
        check("tier %d margin_25 = %+.4f%%" % (tier, m25),
              close(calc.margin_25(cap, d) * 100.0, m25, 1e-4))

    # DDR
    row = calc.ddr_case("main", 2, 30, 1920, 1080, 1.6, True, 5332, "")
    check("DDR 2R+2S total = 809.034 MB/s", close(row["ddr_total_MBps"], 809.034, 1e-6), row["ddr_total_MBps"])
    check("DDR gate 1.25x = 1,011.2925 MB/s", close(row["ddr_gate_25_MBps"], 1011.2925, 1e-6))
    check("required_eff @5332 = 15.1732%", close(row["required_eff_pct"], 15.1732, 1e-4))
    check("gate_eff @5332 = 18.9665%", close(row["gate_eff_pct"], 18.9665, 1e-4))
    row6 = calc.ddr_case("main", 2, 30, 1920, 1080, 1.6, True, 6400, "")
    check("required_eff @6400 = 12.6412%", close(row6["required_eff_pct"], 12.6412, 1e-4))
    check("gate_eff @6400 = 15.8014%", close(row6["gate_eff_pct"], 15.8014, 1e-4))
    check("peak 1333 formula = 1333e6*32/8/1e6 = 5332", close(1333e6 * 32 / 8 / 1e6, 5332, 1e-9))

    # UART
    u = calc.uart_numbers(frozen)
    check("UART 40,032 B @11,520 B/s = 3.475 s", close(u["export_s_payload"], 3.475, 1e-9))
    check("UART frame 2,594,706 B = 225.235 s", close(u["export_s_frame"], 225.2349, 1e-3), u["export_s_frame"])
    check("UART payload vs 33.333 ms = 104.2x", close(u["payload_vs_period_x"], 104.25, 0.01))
    check("UART frame vs 33.333 ms = 6,757x", close(u["frame_vs_period_x"], 6757.05, 0.1))
    check("export ideal cost = 400,320 cycles", u["tail_ideal_cycles"] == 400320)
    check("measured export_tail = 480,930 cycles, constant, sink_limited=false",
          u["tail_measured_cycles"] == 480930 and u["sink_limited"] is False)
    check("b11 sink 2.135 ms for 40,032 B", close(u["b11_sink_ms_40032"], 2.13504, 1e-5))
    check("b6 sink 0.400 ms for 40,032 B", close(u["b6_sink_ms_40032"], 0.40032, 1e-6))
    check("sim sink vs real 115200 = 1,628x", close(u["sim_sink_vs_real_x"], 1627.6, 0.1))

    # headline
    hl = calc.headline_1080p30(rules, a1["margin_0_pct"] / 100, a1["margin_25_pct"] / 100,
                               a2["margin_0_pct"] / 100, a2["margin_25_pct"] / 100, True)
    check("1080p30 per-stream headline = not_proven (content crossing)", hl["headline"] == "not_proven")
    check("headline keeps G0/G25 separate",
          hl["gate_G0"] == "pass" and hl["gate_G25"] == "pass")
    hl_dual = calc.headline_1080p30(rules, a1["margin_0_pct"] / 100, a1["margin_25_pct"] / 100,
                                    a2["margin_0_pct"] / 100, a2["margin_25_pct"] / 100, True,
                                    cores=2, streams=2)
    check("dual-core headline is never feasible", hl_dual["headline"] != "feasible")
    hl_inf = calc.headline_1080p30(rules, -0.1, -0.2, -0.2, -0.3, True)
    check("both content bases below G0 -> infeasible", hl_inf["headline"] == "infeasible")

    # 43-row grid and mapping
    rows = calc.scenario_rows(frozen, rules)
    check("scenario grid = 43 rows", len(rows) == 43, len(rows))
    check("scenario ids unique", len({r["scenario_id"] for r in rows}) == 43)
    bad = [r for r in rows if r["cores"] == 2 and r["verdict"] == "feasible"]
    check("no dual-core row is feasible", not bad, [r["scenario_id"] for r in bad])
    collapse = [r for r in rows if r["gate_G0"] == "pass" and r["gate_G25"] == "fail"
                and r["verdict"] == "infeasible"]
    check("no G25-miss row collapsed to infeasible", not collapse,
          [r["scenario_id"] for r in collapse])
    mixed = [r for r in rows if (r["W"], r["H"]) == (1920, 1080)
             and r["chain_anchor_id"] != "A1_grad_ss"]
    check("all 1080p rows use the A1 anchor", not mixed)
    check("all 1080p rows carry claim_status=not_proven_all_content",
          all(r["claim_status"] == "not_proven_all_content"
              for r in rows if (r["W"], r["H"]) == (1920, 1080)))
    check("all rows carry claim_status=not_proven_all_content",
          all(r["claim_status"] == "not_proven_all_content" for r in rows))

    # ------------------------------------------------------- 6 negative controls
    expect_reject("NC1 cold latency as throughput", "COLD_LATENCY_AS_THROUGHPUT",
                  calc.validate_anchor_use, "A4", "throughput")
    check("NC1 control: A1 throughput use is allowed",
          calc.validate_anchor_use("A1", "throughput") is True)
    expect_reject("NC2 G25 miss -> infeasible", "GATE_COLLAPSE",
                  calc.validate_verdict, "pass", "fail", "infeasible")
    check("NC2 control: below_25 -> conditional is allowed",
          calc.validate_verdict("pass", "fail", "conditional") is True)
    expect_reject("NC3 ddr1333 quoted with 6400 peak", "PEAK_MISMATCH",
                  calc.validate_peak, "ddr1333", 6400)
    check("NC3 control: 6400 labelled fallback is allowed",
          calc.validate_peak("ddr1333", 6400, label="fallback_disclosed") is True)
    expect_reject("NC4 sim fast sink as production", "SINK_MISMATCH",
                  calc.validate_sink, "sim_fast_b11", "production_realtime")
    check("NC4 control: sim sink as evidence-only is allowed",
          calc.validate_sink("sim_fast_b11", "evidence_only") is True)
    expect_reject("NC5 aggregate 2C as per-stream capacity", "AGGREGATE_CAPACITY_FOR_PER_STREAM",
                  calc.validate_per_stream_claim, 2, 2, 207.8017588, 103.9008794, 77.76, "feasible")
    check("NC5 control: per-stream C is allowed",
          calc.validate_per_stream_claim(2, 2, 103.9008794, 103.9008794, 77.76, "feasible") is True)
    expect_reject("NC6 1080p with tier applies=false", "TIER_NOT_APPLIED",
                  calc.validate_tier_applied, 1920, 1080, False)
    check("NC6 control: 1080p with applies=true is allowed",
          calc.validate_tier_applied(1920, 1080, True) is True)
    expect_reject("extra: A1 cycles with A2 demand anchor", "CONTENT_ANCHOR_MIX",
                  calc.validate_anchor_mix, "A1_grad_ss", "A2_comp_assumed")

    print("\n%d checks, %d failures" % (COUNT[0], len(FAILS)))
    if FAILS:
        print("FAILED: %s" % FAILS)
        return 1
    print("TEST_CALC=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
