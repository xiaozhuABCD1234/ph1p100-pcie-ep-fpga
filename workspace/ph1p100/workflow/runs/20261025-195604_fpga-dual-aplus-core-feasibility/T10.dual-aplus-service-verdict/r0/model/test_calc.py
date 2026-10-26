"""Known-value / boundary / negative-control tests for model/calc.py.

Run:  python model/test_calc.py        (cwd = r0 directory)
Exit 0 only when every check passes.  Expected values are the hand-derived
thresholds from fpga-design-guide.md sections 4.1/6.4 and dev-plan.md section 3.6;
they are NOT produced by calling a second copy of the model.
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import calc  # noqa: E402

JOURNAL = "--journal" in sys.argv


def append_command(result, exit_code, timeout_s=120):
    if not JOURNAL:
        return
    rec = {"argv": ["python", "model/test_calc.py", "--journal"], "cwd": str(ROOT),
           "exit": exit_code, "timeout_s": timeout_s,
           "time_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "purpose": "known-value / boundary / 3-negative-control unit tests",
           "result": result}
    path = ROOT / "commands.jsonl"
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    rec["seq"] = len(lines) + 1
    with open(path, "a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

FROZEN = json.loads((ROOT / "inputs" / "frozen-inputs.json").read_text(encoding="utf-8"))
RULES = json.loads((HERE / "rules.json").read_text(encoding="utf-8"))

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))
    print("%-6s %s%s" % ("PASS" if ok else "FAIL", name, (" | " + detail) if detail and not ok else ""))


def close(a, b, tol):
    return abs(a - b) <= tol


def expect_reject(name, fn, code):
    try:
        fn()
    except calc.ModelRejected as exc:
        check(name, str(exc) == code, "raised %s, expected %s" % (exc, code))
        return
    except Exception as exc:  # noqa: BLE001
        check(name, False, "raised %s instead of ModelRejected(%s)" % (type(exc).__name__, code))
        return
    check(name, False, "no rejection raised; expected %s" % code)


# ---------------------------------------------------------------- geometry / bytes
check("raw_bytes_1080p", calc.raw_bytes(1920, 1080) == 2592000)
check("groups_1080p", calc.groups(1920, 1080) == 518400)
check("slot_words_1080p", calc.raw_slot_words(1920, 1080) == 129600)
check("slot_bytes_1080p", calc.raw_slot_bytes(1920, 1080) == 4147200)
check("slot_expansion_1080p_is_1p6", close(calc.raw_slot_expansion(1920, 1080), 1.6, 1e-12),
      "%.12f" % calc.raw_slot_expansion(1920, 1080))
check("content_bytes_1080p", calc.content_bytes(1920, 1080) == 2592128)
check("dma_bytes_1080p", calc.dma_bytes(1920, 1080) == 2592768)
check("cmp_payload_1080p", calc.cmp_payload_bytes(1920, 1080) == 2594706)
check("cmp_total_1080p", calc.cmp_total_bytes(1920, 1080) == 2594750)
check("slot_1728x972", calc.raw_slot_bytes(1728, 972) == 3359232,
      str(calc.raw_slot_bytes(1728, 972)))
check("slot_1600x900", calc.raw_slot_bytes(1600, 900) == 2880000)
check("slot_960x540", calc.raw_slot_bytes(960, 540) == 1036800)
check("min_tier_4x4", calc.raw_bytes(4, 4) == 20 and calc.raw_slot_bytes(4, 4) == 32)

# ---------------------------------------------------------------- anchors / rates
comp = FROZEN["anchors"]["comp"]
rand = FROZEN["anchors"]["rand"]
fg = FROZEN["anchors"]["full_grad"]
check("comp_rate_81.067159", close(calc.capacity_MBps(comp["input_bytes"], comp["cycles"], 187500000),
                                  81.067159, 1e-6), "%.9f" % calc.capacity_MBps(comp["input_bytes"], comp["cycles"], 187500000))
check("rand_rate_178.351", close(calc.capacity_MBps(rand["input_bytes"], rand["cycles"], 187500000),
                                 178.351365, 1e-5), "%.9f" % calc.capacity_MBps(rand["input_bytes"], rand["cycles"], 187500000))
check("comp_cycles_per_byte", close(calc.cycles_per_byte(153600, 355261), 2.3128971354166667, 1e-12))
core_cycles_1080p = calc.raw_bytes(1920, 1080) * calc.cycles_per_byte(153600, 355261)
check("core_cycles_1080p_5995029.375", close(core_cycles_1080p, 5995029.375, 1e-6), "%.6f" % core_cycles_1080p)
check("core_only_fps_31.276", close(187.5e6 / core_cycles_1080p, 31.276, 0.001),
      "%.6f" % (187.5e6 / core_cycles_1080p))
chain_cap = calc.capacity_MBps(2592000, 6421414, 187500000)
check("chain_cap_75.684", close(chain_cap, 75.684265, 1e-4), "%.9f" % chain_cap)
check("chain_fps_29.199", close(187.5e6 / 6421414, 29.199, 0.001), "%.6f" % (187.5e6 / 6421414))
check("implied_overhead_426384.625", close(6421414 - core_cycles_1080p, 426384.625, 1e-6),
      "%.6f" % (6421414 - core_cycles_1080p))

# ---------------------------------------------------------------- demand / margins
ds = calc.demand_MBps(2592000, 30)
check("demand_1080p30_77.76", close(ds, 77.76, 1e-12), "%.12f" % ds)
check("gate_per_stream_97.2", close(ds * 1.25, 97.2, 1e-12))
m_chain = calc.margin(chain_cap, ds)
check("chain_margin_1080p30_minus_2.67pct", close(100.0 * m_chain, -2.6695, 0.01), "%.4f" % (100.0 * m_chain))
m_core = calc.margin(81.067159, ds)
check("core_margin_1080p30_plus_4.25pct", close(100.0 * m_core, 4.2524, 0.01), "%.4f" % (100.0 * m_core))
check("core_25pct_max_fps_25.02", close(81.067159 / (2.592 * 1.25), 25.0207, 1e-3),
      "%.4f" % (81.067159 / (2.592 * 1.25)))
check("chain_25pct_max_fps_23.36", close(calc.max_fps(6421414, 187.5e6, 0.25), 23.3593, 1e-3),
      "%.4f" % calc.max_fps(6421414, 187.5e6, 0.25))
check("chain_0pct_max_fps_29.199", close(calc.max_fps(6421414, 187.5e6, 0.0), 29.1987, 1e-3))
check("clock_req_25pct_240.8MHz", close(calc.required_clock_hz(6421414, 30, 0.25) / 1e6, 240.803, 1e-3),
      "%.6f" % (calc.required_clock_hz(6421414, 30, 0.25) / 1e6))
check("clock_req_0pct_192.6MHz", close(calc.required_clock_hz(6421414, 30, 0.0) / 1e6, 192.642, 1e-3))
check("core_clock_req_25pct_224.8MHz", close(calc.required_clock_hz(core_cycles_1080p, 30, 0.25) / 1e6, 224.814, 1e-3))

# ---------------------------------------------------------------- resolution frontier
tiers = [(1920, 1080), (1728, 972), (1600, 900), (1440, 810), (1280, 720), (1152, 648), (960, 540)]
px_chain25 = calc.max_pixels_for(187.5e6, 2.3128971354166667, 426385, 30, 0.25)
px_core25 = calc.max_pixels_for(187.5e6, 2.3128971354166667, 0, 30, 0.25)
check("chain_25pct_area_1581952", close(px_chain25, 1581952, 5), "%.1f" % px_chain25)
check("chain_25pct_snaps_1600x900", calc.snap_tier(px_chain25, tiers) == (1600, 900),
      str(calc.snap_tier(px_chain25, tiers)))
check("core_25pct_area_1729432", close(px_core25, 1729432, 5), "%.1f" % px_core25)
check("core_25pct_snaps_1728x972", calc.snap_tier(px_core25, tiers) == (1728, 972),
      str(calc.snap_tier(px_core25, tiers)))
r1728 = calc.make_scenario_row(FROZEN, RULES, 1728, 972, 30, 1, 1, 187.5)
check("1728x972_chain_margin_18.32", close(r1728["margin_chain_pct"], 18.318, 0.01),
      "%.4f" % r1728["margin_chain_pct"])
check("1728x972_core_margin_28.71", close(r1728["margin_core_pct"], 28.713, 0.01),
      "%.4f" % r1728["margin_core_pct"])

# ---------------------------------------------------------------- F3: required clocks
r1600 = calc.make_scenario_row(FROZEN, RULES, 1600, 900, 30, 1, 1, 187.5)
check("required_clock_1600_chain_172.11", close(r1600["required_clock_chain_25_mhz"], 172.11, 0.02),
      "%.4f" % r1600["required_clock_chain_25_mhz"])
check("required_clock_1600_core_156.12", close(r1600["required_clock_core_25_mhz"], 156.12, 0.02))
check("required_clock_1728_chain_198.09", close(r1728["required_clock_chain_25_mhz"], 198.09, 0.02))
r20 = calc.make_scenario_row(FROZEN, RULES, 1920, 1080, 20, 1, 1, 187.5)
check("required_clock_1080p20_chain_160.54", close(r20["required_clock_chain_25_mhz"], 160.54, 0.02))
check("required_clock_1080p30_chain_240.803", close(
    calc.make_scenario_row(FROZEN, RULES, 1920, 1080, 30, 1, 1, 187.5)["required_clock_chain_25_mhz"],
    240.803, 1e-3))

# ---------------------------------------------------------------- F2: overhead tiers
row1600 = {"scenario_id": "x", "W": 1600, "H": 900, "fps": 30.0, "cores": 1, "streams": 1, "clock_mhz": 187.5}
row1440 = {"scenario_id": "x", "W": 1440, "H": 810, "fps": 30.0, "cores": 1, "streams": 1, "clock_mhz": 187.5}
row1728 = {"scenario_id": "x", "W": 1728, "H": 972, "fps": 30.0, "cores": 1, "streams": 1, "clock_mhz": 187.5}
row1080 = {"scenario_id": "x", "W": 1920, "H": 1080, "fps": 30.0, "cores": 1, "streams": 1, "clock_mhz": 187.5}
check("overhead_1600_0_50.1244", close(100 * calc.chain_margin_at(row1600, FROZEN, 0), 50.1244, 1e-3))
check("overhead_1600_426385_36.1774", close(100 * calc.chain_margin_at(row1600, FROZEN, 426385), 36.1774, 1e-3))
check("overhead_1600_1000000_21.0486", close(100 * calc.chain_margin_at(row1600, FROZEN, 1000000), 21.0486, 1e-3))
check("overhead_1440_1000000_42.9485", close(100 * calc.chain_margin_at(row1440, FROZEN, 1000000), 42.9485, 1e-3))
check("overhead_1728_1000000_6.7286", close(100 * calc.chain_margin_at(row1728, FROZEN, 1000000), 6.7286, 1e-3))
check("overhead_1080p_anchor_tier_invariant",
      calc.chain_margin_at(row1080, FROZEN, 0) == calc.chain_margin_at(row1080, FROZEN, 426385)
      == calc.chain_margin_at(row1080, FROZEN, 1000000))

# ---------------------------------------------------------------- per-stream rule
c = 81.0
check("ps_1c1s", calc.per_stream_capacity(c, 1, 1) == 81.0)
check("ps_1c2s_half", calc.per_stream_capacity(c, 1, 2) == 40.5)
check("ps_2c1s_full", calc.per_stream_capacity(c, 2, 1) == 81.0)
check("ps_2c2s_is_C_not_2C", calc.per_stream_capacity(c, 2, 2) == 81.0)

# ---------------------------------------------------------------- DDR
dmain = calc.ddr_case("main", 2, 30, 1920, 1080, 1.6, True, 6400, "")
check("ddr_main_809.034", close(dmain["ddr_total_MBps"], 809.034, 1e-6),
      "%.6f" % dmain["ddr_total_MBps"])
check("ddr_main_eff_12.64pct", close(dmain["required_eff_pct"], 12.6412, 1e-3),
      "%.4f" % dmain["required_eff_pct"])
d = calc.ddr_case("nocmp", 2, 30, 1920, 1080, 1.6, False, 6400, "")
check("ddr_no_cmp_497.664", close(d["ddr_total_MBps"], 497.664, 1e-6), "%.6f" % d["ddr_total_MBps"])
d = calc.ddr_case("tight", 2, 30, 1920, 1080, 1.0, True, 6400, "")
check("ddr_tight_622.41", close(d["ddr_total_MBps"], 622.41, 1e-6), "%.6f" % d["ddr_total_MBps"])
d = calc.ddr_case("single", 1, 30, 1920, 1080, 1.6, True, 6400, "")
check("ddr_single_404.517", close(d["ddr_total_MBps"], 404.517, 1e-6), "%.6f" % d["ddr_total_MBps"])
d = calc.ddr_case("p1600", 2, 30, 1600, 900, 1.6, True, 6400, "")
check("ddr_1600x900_561.876", close(d["ddr_total_MBps"], 561.876, 1e-6), "%.6f" % d["ddr_total_MBps"])
d = calc.ddr_case("p1080p20", 2, 20, 1920, 1080, 1.6, True, 6400, "")
check("ddr_1080p20_539.356", close(d["ddr_total_MBps"], 539.356, 1e-6), "%.6f" % d["ddr_total_MBps"])
check("ddr_gate_is_1.25x", close(dmain["ddr_gate_25_MBps"], 809.034 * 1.25, 1e-6))

# ---------------------------------------------------------------- boundaries
def raises(fn, exc_type=ValueError):
    try:
        fn()
    except exc_type:
        return True
    except Exception:  # noqa: BLE001
        return False
    return False


check("boundary_fps0_rejected", raises(lambda: calc.demand_MBps(2592000, 0)))
check("boundary_negative_fps_rejected", raises(lambda: calc.demand_MBps(2592000, -30)))
check("boundary_w_not_multiple4_rejected", raises(lambda: calc.raw_bytes(1921, 1080)))
check("boundary_1440x810_accepted", calc.raw_bytes(1440, 810) == 1458000
      and calc.groups(1440, 810) == 291600 and calc.raw_slot_bytes(1440, 810) == 2332800,
      "H=810 is not a multiple of 4, but W=1440 keeps per-row groups/stride integral")
check("boundary_streams0_rejected", raises(lambda: calc.per_stream_capacity(80.0, 1, 0)))
check("boundary_cores3_rejected", raises(lambda: calc.per_stream_capacity(80.0, 3, 1)))
check("boundary_drop_zero_capacity", close(calc.drop_rate_lb(0.0, 77.76), 1.0, 1e-12))
check("boundary_drop_never_negative", calc.drop_rate_lb(200.0, 77.76) == 0.0)
one = calc.demand_MBps(2592000, 1)
check("boundary_1fps_demand_2.592", close(one, 2.592, 1e-12))
check("boundary_margin_monotone",
      calc.margin(75.684265, 77.76) < calc.margin(81.067159, 77.76))

# ---------------------------------------------------------------- classification
check("classify_feasible_single_core",
      calc.classify(1, 0.40, 187, 187, True, RULES)[0] == "feasible")
check("classify_dual_core_never_feasible",
      calc.classify(2, 0.40, 231, 289, False, RULES)[0] == "conditional")
check("classify_dual_core_conservative_gt_270",
      calc.classify(2, 0.40, 231, 289, True, RULES)[0] == "conditional")
check("classify_below_gate_conditional",
      calc.classify(1, 0.10, 187, 187, True, RULES)[0] == "conditional")
check("classify_fails_30_infeasible",
      calc.classify(1, -0.01, 187, 187, True, RULES)[0] == "infeasible")
check("classify_marginal_over_300_infeasible",
      calc.classify(2, 0.40, 301, 301, True, RULES)[0] == "infeasible")
check("classify_conservative_over_300_not_infeasible",
      calc.classify(2, 0.40, 231, 320, True, RULES)[0] == "conditional")
check("gate_status_meets", calc.gate_status(0.25, 0.25) == "meets_25")
check("gate_status_below", calc.gate_status(0.0, 0.25) == "below_25")
check("gate_status_fails", calc.gate_status(-1e-9, 0.25) == "fails_30")

# ---------------------------------------------------------------- full grid
rows = calc.scenario_rows(FROZEN, RULES)
check("grid_row_count_43", len(rows) == 43, "got %d" % len(rows))
check("grid_ids_unique", len({r["scenario_id"] for r in rows}) == len(rows))
guide = [r for r in rows if not (r["W"] == 1920 and r["H"] == 1080 and r["cores"] == 1
                                 and r["streams"] == 1 and r["fps"] != 30)]
check("grid_guide_subset_39", len(guide) == 39, "got %d" % len(guide))
keys = {(r["W"], r["H"], r["fps"], r["cores"], r["streams"]) for r in rows}
for (w, h) in RULES["grid"]["geometry_30fps"]:
    for cores in (1, 2):
        for streams in (1, 2):
            check("grid_geom_%dx%d_c%ds%d" % (w, h, cores, streams),
                  (w, h, 30.0, cores, streams) in keys)
for fps in (25.0, 24.0, 20.0, 15.0):
    for cores in (1, 2):
        check("grid_fps_%g_c%ds2" % (fps, cores), (1920, 1080, fps, cores, 2) in keys)
for clk in (150.0, 175.0, 187.5, 200.0):
    check("grid_clock_%g" % clk, any(r["clock_mhz"] == clk and r["cores"] == 2 and r["streams"] == 2
                                     for r in rows))
check("grid_no_dual_core_feasible", not any(r["verdict"] == "feasible" and r["cores"] == 2 for r in rows))
check("grid_no_1080p30_feasible", not any(r["verdict"] == "feasible" and r["fps"] == 30
                                          and r["W"] * r["H"] == 2073600 for r in rows))
check("grid_no_feasible_below_gate", not any(r["verdict"] == "feasible" and r["margin_chain_pct"] < 25.0
                                             for r in rows))
check("grid_every_row_chain_slower_than_core", all(r["cycles_chain_per_frame"] > r["cycles_core_per_frame"]
                                                   for r in rows))
check("grid_drop_in_range", all(0.0 <= r["drop_rate_lb_pct"] < 100.0 for r in rows))
check("grid_1c2s_halves_per_stream",
      all(close(r["per_stream_capacity_chain_MBps"], r["capacity_chain_MBps"] / 2.0, 1e-9)
          for r in rows if r["cores"] == 1 and r["streams"] == 2))
check("grid_2c2s_not_double",
      all(close(r["per_stream_capacity_chain_MBps"], r["capacity_chain_MBps"], 1e-9)
          for r in rows if r["cores"] == 2 and r["streams"] == 2))
check("grid_ddr_band_1080p30",
      close(calc.ddr_case("x", 2, 30, 1920, 1080, 1.6, True, 6400, "")["ddr_total_MBps"], 809.034, 1e-6))
check("grid_not_viable_false", calc.grid_not_viable(rows) is False)

# ---------------------------------------------------------------- F1/F2: frontier + recommendation
frows = calc.frontier_rows(rows, FROZEN)
check("frontier_core_basis_same_source",
      all(close(float(x["margin_pct"]), float(x["margin_core_pct"]), 1e-9)
          and x["gate_25"] == calc.gate_status(float(x["margin_pct"]) / 100.0, 0.25)
          for x in frows if x["capacity_basis"].startswith("core_only")))
check("frontier_chain_basis_same_source",
      all(close(float(x["margin_pct"]), float(x["margin_chain_pct"]), 1e-9)
          and x["gate_25"] == calc.gate_status(float(x["margin_pct"]) / 100.0, 0.25)
          for x in frows if not x["capacity_basis"].startswith("core_only")))
check("frontier_1440_robust_row_present",
      any(x["W"] == 1440 and x["H"] == 810 and x["capacity_basis"] == "full_chain_affine"
          and x["is_recommended"] == "true" for x in frows))
primary, alts = calc.recommendations(rows, FROZEN)
check("reco_primary_1600", primary["scenario_id"] == "1600x900-30fps-c1s1-187.5MHz")
check("reco_alt_1440_first", [a["scenario_id"] for a in alts] ==
      ["1440x810-30fps-c1s1-187.5MHz", "1920x1080-20fps-c1s1-187.5MHz"])
check("reco_primary_not_robust", calc.worst_tier_margin(primary, FROZEN) < 0.25)
check("reco_alt_robust", calc.worst_tier_margin(alts[0], FROZEN) >= 0.25)

# ---------------------------------------------------------------- negative controls (3)
expect_reject("NEG-01a_raw12_profile_rejected",
              lambda: calc.validate_packing("RAW12_1.0x", 1920, 1080, 3110400, 3110400),
              "PACKING_PROFILE_REJECTED")
expect_reject("NEG-01b_raw10_1p0x_slot_rejected",
              lambda: calc.validate_packing(calc.PROFILE_OK, 1920, 1080, 2592000, 2592000),
              "PACKING_MISMATCH")
expect_reject("NEG-02a_aggregate_2C_rejected",
              lambda: calc.validate_per_stream_claim(2, 2, 162.134318, 75.684265, 77.76, "feasible", RULES),
              "AGGREGATE_CAPACITY_FOR_PER_STREAM")
expect_reject("NEG-02b_chain_margin_claim_rejected",
              lambda: calc.validate_per_stream_claim(2, 2, 75.684265, 75.684265, 77.76, "feasible", RULES),
              "FEASIBLE_CLAIM_BELOW_PER_STREAM_GATE")
expect_reject("NEG-03_synth_mixed_into_routed_rejected",
              lambda: calc.validate_resource_stage("synth"),
              "STAGE_MIX_SYNTH_IN_FIT")
check("NEG-03_routed_accepted", calc.validate_resource_stage("routed") is True)
check("NEG-01_packing_accepts_frozen_profile",
      calc.validate_packing(calc.PROFILE_OK, 1920, 1080, 2592000, 4147200) == 4147200)

# ---------------------------------------------------------------- summary
failed = [r for r in RESULTS if not r[1]]
print("TEST_SUMMARY total=%d pass=%d fail=%d" % (len(RESULTS), len(RESULTS) - len(failed), len(failed)))
append_command("TEST_SUMMARY total=%d pass=%d fail=%d"
               % (len(RESULTS), len(RESULTS) - len(failed), len(failed)), 1 if failed else 0)
sys.exit(1 if failed else 0)
