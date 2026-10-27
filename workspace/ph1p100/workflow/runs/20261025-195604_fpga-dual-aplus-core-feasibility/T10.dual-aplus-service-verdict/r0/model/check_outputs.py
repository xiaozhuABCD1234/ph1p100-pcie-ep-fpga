"""Independent consistency checks for the P2 outputs.

- regenerates the four CSVs from the frozen inputs and compares byte-for-byte
- recomputes 6 sampled rows with hand-written arithmetic (not the builder path)
- re-checks grid coverage / verdict invariants / frontier maximality
- verifies the report hash sidecar and every row of the 43-row report table against the CSV
- re-runs the 3 negative controls
Exit 0 only if every check passes.
"""
import csv
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import calc  # noqa: E402

FROZEN = json.loads((ROOT / "inputs" / "frozen-inputs.json").read_text(encoding="utf-8"))
RULES = json.loads((HERE / "rules.json").read_text(encoding="utf-8"))
JOURNAL = "--journal" in sys.argv

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print("%-6s %s%s" % ("PASS" if ok else "FAIL", name, (" | " + detail) if detail and not ok else ""))


def close(a, b, tol):
    return abs(float(a) - float(b)) <= tol


def sha_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def append_command(result, exit_code, timeout_s=120):
    if not JOURNAL:
        return
    rec = {"argv": ["python", "model/check_outputs.py"] + (["--journal"] if JOURNAL else []), "cwd": str(ROOT), "exit": exit_code,
           "timeout_s": timeout_s, "time_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "purpose": "independent CSV/report consistency + frontier + negative controls", "result": result}
    path = ROOT / "commands.jsonl"
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    rec["seq"] = len(lines) + 1
    with open(path, "a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def load_csv(name):
    with open(ROOT / "out" / name, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def csv_text(name, cols, rows):
    body = ",".join(cols) + "\n" + "".join(calc.row_to_csv(r, cols) + "\n" for r in rows)
    return body


def main():
    # ---------------------------------------------------------------- input drift re-check
    p1m = Path("D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/"
               "T10.dual-core-resource-baseline/r0/manifest-r0.json")
    core = Path("D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/"
                "T10.b6-a1-htab-nw/r0/changed-src/a1_deflate_core.v")
    check("drift_p1_manifest", sha_file(p1m) == "228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0")
    check("drift_b6_core", sha_file(core) == "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb")

    verified = json.loads((ROOT / "input-verified.json").read_text(encoding="utf-8"))
    check("input_verified_zero_mismatch", verified.get("mismatch_count") == 0,
          str(verified.get("mismatch_count")))
    check("input_verified_all_assertions_pass",
          all(a["status"] == "pass" for a in verified.get("assertions", [])))

    # ---------------------------------------------------------------- CSV regeneration
    rows = calc.scenario_rows(FROZEN, RULES)
    content = calc.content_rows(FROZEN)
    ddr = calc.ddr_rows(FROZEN)
    frontier = calc.frontier_rows(rows, FROZEN)
    sens = calc.overhead_sensitivity_rows(rows, FROZEN, RULES)
    for name, cols, built in (("scenarios.csv", calc.SCENARIO_COLS, rows),
                              ("content-sensitivity.csv", calc.CONTENT_COLS, content),
                              ("ddr-budget.csv", calc.DDR_COLS, ddr),
                              ("frontier.csv", calc.FRONTIER_COLS, frontier),
                              ("overhead-sensitivity.csv", calc.OVERHEAD_COLS, sens)):
        disk = (ROOT / "out" / name).read_text(encoding="utf-8")
        check("csv_regenerated_%s" % name, disk == csv_text(name, cols, built),
              "on-disk CSV differs from the frozen-input regeneration")

    # ---------------------------------------------------------------- hand arithmetic on 6 rows
    with open(ROOT / "out" / "scenarios.csv", encoding="utf-8", newline="") as f:
        srows = {r["scenario_id"]: r for r in csv.DictReader(f)}
    f = FROZEN["clock_hz"]
    cpb = 355261 / 153600
    anchor = 6421414
    overhead = 426385
    samples = [
        ("1920x1080-30fps-c1s1-187.5MHz", 1920, 1080, 30.0, 187.5, 1, 1),
        ("1920x1080-30fps-c2s2-187.5MHz", 1920, 1080, 30.0, 187.5, 2, 2),
        ("1728x972-30fps-c1s1-187.5MHz", 1728, 972, 30.0, 187.5, 1, 1),
        ("960x540-30fps-c1s2-187.5MHz", 960, 540, 30.0, 187.5, 1, 2),
        ("1920x1080-30fps-c2s2-200MHz", 1920, 1080, 30.0, 200.0, 2, 2),
        ("1920x1080-20fps-c1s1-187.5MHz", 1920, 1080, 20.0, 187.5, 1, 1),
    ]
    for sid, w, h, fps, clk, cores, streams in samples:
        r = srows[sid]
        raw = w * h * 5 // 4
        cyc_core = raw * cpb
        cyc_chain = float(anchor) if (w, h) == (1920, 1080) else cyc_core + overhead
        cap_core = f / cpb / 1e6 * (clk / 187.5)
        cap_chain = raw * (clk * 1e6) / cyc_chain / 1e6
        d = raw * fps / 1e6
        ps_core = cap_core / 2 if (cores == 1 and streams == 2) else cap_core
        ps_chain = cap_chain / 2 if (cores == 1 and streams == 2) else cap_chain
        m_core = (ps_core / d - 1) * 100
        m_chain = (ps_chain / d - 1) * 100
        drop = max(0.0, 1 - ps_chain / d) * 100
        tag = sid
        check("hand_%s_cycles_chain" % tag, close(r["cycles_chain_per_frame"], cyc_chain, 1e-3),
              "%s vs %.3f" % (r["cycles_chain_per_frame"], cyc_chain))
        check("hand_%s_cap_chain" % tag, close(r["capacity_chain_MBps"], cap_chain, 1e-5))
        check("hand_%s_cap_core" % tag, close(r["capacity_core_MBps"], cap_core, 1e-5))
        check("hand_%s_margin_chain" % tag, close(r["margin_chain_pct"], m_chain, 1e-4))
        check("hand_%s_margin_core" % tag, close(r["margin_core_pct"], m_core, 1e-4))
        check("hand_%s_drop" % tag, close(r["drop_rate_lb_pct"], drop, 1e-4))
        expected_verdict = ("infeasible" if m_chain < 0 or int(r["eram_total"]) > 300
                            else ("conditional" if (cores == 2 or m_chain < 25.0) else "feasible"))
        check("hand_%s_verdict" % tag, r["verdict"] == expected_verdict,
              "%s vs %s" % (r["verdict"], expected_verdict))

    # ---------------------------------------------------------------- F3: required clocks
    check("clock_1600_chain_25_172.1100",
          close(srows["1600x900-30fps-c1s1-187.5MHz"]["required_clock_chain_25_mhz"], 172.1100, 1e-3),
          srows["1600x900-30fps-c1s1-187.5MHz"]["required_clock_chain_25_mhz"])
    check("clock_1600_core_25_156.1206",
          close(srows["1600x900-30fps-c1s1-187.5MHz"]["required_clock_core_25_mhz"], 156.1206, 1e-3))
    check("clock_1440_chain_25_142.4471",
          close(srows["1440x810-30fps-c1s1-187.5MHz"]["required_clock_chain_25_mhz"], 142.4471, 1e-3))
    check("clock_1080p20_chain_25_160.5353",
          close(srows["1920x1080-20fps-c1s1-187.5MHz"]["required_clock_chain_25_mhz"], 160.5353, 1e-3))
    check("clock_1080p30_chain_25_240.8030",
          close(srows["1920x1080-30fps-c1s1-187.5MHz"]["required_clock_chain_25_mhz"], 240.8030, 1e-3))
    check("clock_required_consistent_with_cycles",
          all(close(r["required_clock_chain_25_mhz"],
                    float(r["cycles_chain_per_frame"]) * float(r["fps"]) * 1.25 / 1e6, 1e-3) for r in rows))

    # ---------------------------------------------------------------- F1: frontier basis/margin same source
    frows = load_csv("frontier.csv")
    scen_rows = load_csv("scenarios.csv")
    by_key = {(int(r["W"]), int(r["H"]), float(r["fps"]), int(r["cores"]), int(r["streams"]),
               float(r["clock_mhz"])): r for r in scen_rows}
    core_rows = [x for x in frows if x["capacity_basis"].startswith("core_only")]
    chain_rows = [x for x in frows if not x["capacity_basis"].startswith("core_only")]
    check("frontier_core_only_margin_same_source",
          all(close(x["margin_pct"], x["margin_core_pct"], 1e-9)
              and x["gate_25"] == calc.gate_status(float(x["margin_pct"]) / 100.0, 0.25) for x in core_rows))
    check("frontier_chain_margin_same_source",
          all(close(x["margin_pct"], x["margin_chain_pct"], 1e-9)
              and x["gate_25"] == calc.gate_status(float(x["margin_pct"]) / 100.0, 0.25) for x in chain_rows))
    check("frontier_margins_match_scenarios",
          all(close(x["margin_chain_pct"],
                    by_key[(int(x["W"]), int(x["H"]), float(x["fps"]), int(x["cores"]), int(x["streams"]),
                            float(x["clock_mhz"]))]["margin_chain_pct"], 1e-9)
              and close(x["margin_core_pct"],
                        by_key[(int(x["W"]), int(x["H"]), float(x["fps"]), int(x["cores"]), int(x["streams"]),
                                float(x["clock_mhz"]))]["margin_core_pct"], 1e-9)
              for x in frows))
    core_vals = {(int(x["W"]), int(x["H"]), float(x["fps"])): float(x["margin_pct"]) for x in core_rows}
    check("frontier_core_margins_25_1036_28_7074_4_2530",
          close(core_vals[(1920, 1080, 25.0)], 25.1036, 1e-3)
          and close(core_vals[(1728, 972, 30.0)], 28.7074, 1e-3)
          and close(core_vals[(1920, 1080, 30.0)], 4.2530, 1e-3))
    check("frontier_core_gate_no_contradiction",
          all(not (float(x["margin_pct"]) >= 25.0 and x["gate_25"] != "meets_25") for x in core_rows)
          and all(x["gate_25"] == "meets_25" for x in core_rows
                  if float(x["margin_pct"]) >= 25.0))

    # ---------------------------------------------------------------- F2: overhead sensitivity
    def sm(sid, ov):
        for r in sens:
            if r["scenario_id"] == sid and int(round(float(r["overhead_tier_cycles"]))) == int(ov):
                return float(r["margin_chain_pct"])
        raise KeyError((sid, ov))

    check("overhead_rows_43x3_129", len(sens) == 129, str(len(sens)))
    check("overhead_1600_1m_21.0486", close(sm("1600x900-30fps-c1s1-187.5MHz", 1000000), 21.0486, 1e-3),
          "%.4f" % sm("1600x900-30fps-c1s1-187.5MHz", 1000000))
    check("overhead_1600_0_50.1244", close(sm("1600x900-30fps-c1s1-187.5MHz", 0), 50.1244, 1e-3))
    check("overhead_1440_1m_42.9485", close(sm("1440x810-30fps-c1s1-187.5MHz", 1000000), 42.9485, 1e-3))
    check("overhead_1728_1m_6.7286", close(sm("1728x972-30fps-c1s1-187.5MHz", 1000000), 6.7286, 1e-3))
    check("overhead_1080p_tier_invariant",
          sm("1920x1080-30fps-c1s1-187.5MHz", 0) == sm("1920x1080-30fps-c1s1-187.5MHz", 426385)
          == sm("1920x1080-30fps-c1s1-187.5MHz", 1000000))
    check("overhead_1600_primary_feasible_conservative_conditional",
          sm("1600x900-30fps-c1s1-187.5MHz", 426385) >= 25.0
          and sm("1600x900-30fps-c1s1-187.5MHz", 1000000) < 25.0)
    check("overhead_1440_feasible_all_tiers",
          all(sm("1440x810-30fps-c1s1-187.5MHz", ov) >= 25.0
              for ov in FROZEN["overhead"]["sensitivity_tiers"])
          and all(r["verdict"] == "feasible" for r in sens
                  if r["scenario_id"] == "1440x810-30fps-c1s1-187.5MHz"))
    check("overhead_verdict_mechanical",
          all(r["verdict"] == calc.classify(int(r["cores"]), float(r["margin_chain_pct"]) / 100.0,
                                            int(by_key[(int(r["W"]), int(r["H"]), float(r["fps"]),
                                                        int(r["cores"]), int(r["streams"]),
                                                        float(r["clock_mhz"]))]["eram_total"]),
                                            int(by_key[(int(r["W"]), int(r["H"]), float(r["fps"]),
                                                        int(r["cores"]), int(r["streams"]),
                                                        float(r["clock_mhz"]))]["resource_conservative_eram"]),
                                            by_key[(int(r["W"]), int(r["H"]), float(r["fps"]),
                                                    int(r["cores"]), int(r["streams"]),
                                                    float(r["clock_mhz"]))]["timing_status"] == "proven_at_187.5",
                                            RULES)[0]
              for r in sens))
    check("overhead_tier_best_1728_then_1600_then_1440",
          max([r for r in sens if int(r["overhead_tier_cycles"]) == 0 and r["applies"] == "true"
               and float(r["fps"]) == 30 and int(r["cores"]) == 1 and int(r["streams"]) == 1
               and float(r["margin_chain_pct"]) >= 25.0], key=lambda r: int(r["W"]) * int(r["H"]))["W"] == 1728
          and max([r for r in sens if int(r["overhead_tier_cycles"]) == 426385 and r["applies"] == "true"
                   and float(r["fps"]) == 30 and int(r["cores"]) == 1 and int(r["streams"]) == 1
                   and float(r["margin_chain_pct"]) >= 25.0], key=lambda r: int(r["W"]) * int(r["H"]))["W"] == 1600
          and max([r for r in sens if int(r["overhead_tier_cycles"]) == 1000000 and r["applies"] == "true"
                   and float(r["fps"]) == 30 and int(r["cores"]) == 1 and int(r["streams"]) == 1
                   and float(r["margin_chain_pct"]) >= 25.0], key=lambda r: int(r["W"]) * int(r["H"]))["W"] == 1440)

    # ---------------------------------------------------------------- recommendations (rule-derived)
    primary, alts = calc.recommendations(rows, FROZEN)
    check("reco_primary_1600x900", primary["scenario_id"] == "1600x900-30fps-c1s1-187.5MHz",
          primary["scenario_id"])
    check("reco_alts_1440_and_1080p20",
          [a["scenario_id"] for a in alts] == ["1440x810-30fps-c1s1-187.5MHz",
                                               "1920x1080-20fps-c1s1-187.5MHz"],
          str([a["scenario_id"] for a in alts]))
    check("reco_primary_tier_dependent",
          calc.worst_tier_margin(primary, FROZEN) < 0.25)
    check("reco_alt_robust_all_tiers",
          calc.worst_tier_margin(alts[0], FROZEN) >= 0.25)

    # ---------------------------------------------------------------- grid / rules invariants
    check("grid_43_rows", len(rows) == 43, str(len(rows)))
    check("grid_ids_unique", len({r["scenario_id"] for r in rows}) == len(rows))
    check("grid_39_row_design_subset",
          len([r for r in rows if not (r["W"] == 1920 and r["H"] == 1080 and r["cores"] == 1
                                       and r["streams"] == 1 and r["fps"] != 30)]) == 39)
    check("no_dual_feasible", not any(r["verdict"] == "feasible" and r["cores"] == 2 for r in rows))
    check("no_1080p30_feasible", not any(r["verdict"] == "feasible" and r["fps"] == 30
                                         and r["W"] * r["H"] == 2073600 for r in rows))
    check("no_feasible_below_25", not any(r["verdict"] == "feasible" and float(r["margin_chain_pct"]) < 25.0 for r in rows))
    check("no_conditional_above_25_single_core",
          all(r["verdict"] != "conditional" for r in rows
              if r["cores"] == 1 and float(r["margin_chain_pct"]) >= 25.0 and r["resource_conservative_eram"] <= 270))
    check("verdict_enum", {r["verdict"] for r in rows} <= {"feasible", "conditional", "infeasible"})
    check("gate_consistent_with_margin",
          all((r["gate_status"] == "meets_25") == (float(r["margin_chain_pct"]) >= 25.0) for r in rows))
    check("1c2s_half", all(close(r["per_stream_capacity_chain_MBps"], r["capacity_chain_MBps"] / 2, 1e-9)
                           for r in rows if r["cores"] == 1 and r["streams"] == 2))
    check("2c2s_single_core_capacity",
          all(close(r["per_stream_capacity_chain_MBps"], r["capacity_chain_MBps"], 1e-9)
              for r in rows if r["cores"] == 2 and r["streams"] == 2))
    check("drop_monotone_zero_capacity", calc.drop_rate_lb(0.0, 77.76) == 1.0)
    check("ddr_1p6_used", all(close(float(r["raw_write_MBps"]),
                                     float(r["streams"]) * float(r["fps"]) * 2592000 / 1e6 * 1.6, 1e-6)
                              for r in ddr if r["case_id"].startswith("dual_1080p") and "tight" not in r["case_id"]))
    check("ddr_cmp_44B_header", all(close(float(r["cmp_write_MBps"]),
                                          (2592000 + 5 * 540 + 6 + 44) * float(r["fps"]) * float(r["streams"]) / 1e6, 1e-6)
                                     for r in ddr if r["case_id"] == "dual_1080p30_main"))

    # ---------------------------------------------------------------- frontier maximality
    def max_px(pred):
        cand = [r for r in rows if pred(r)]
        return max(cand, key=lambda r: r["W"] * r["H"]) if cand else None

    def max_fps(pred):
        cand = [r for r in rows if pred(r)]
        return max(cand, key=lambda r: r["fps"]) if cand else None

    m25 = lambda r: float(r["margin_chain_pct"]) >= 25.0
    c25 = lambda r: float(r["margin_core_pct"]) >= 25.0
    r = max_px(lambda x: x["fps"] == 30 and x["cores"] == 1 and x["streams"] == 1 and m25(x))
    check("frontier_30fps_res_chain_max", r is not None and (r["W"], r["H"]) == (1600, 900),
          "" if r is None else "%dx%d" % (r["W"], r["H"]))
    r = max_px(lambda x: x["fps"] == 30 and x["cores"] == 1 and x["streams"] == 2 and m25(x))
    check("frontier_30fps_1c2s_max", r is not None and (r["W"], r["H"]) == (960, 540))
    r = max_fps(lambda x: x["W"] == 1920 and x["H"] == 1080 and x["cores"] == 1 and x["streams"] == 1 and m25(x))
    check("frontier_1080p_fps_chain_max", r is not None and r["fps"] == 20.0, "" if r is None else str(r["fps"]))
    r = max_fps(lambda x: x["W"] == 1920 and x["H"] == 1080 and x["cores"] == 1 and x["streams"] == 1 and c25(x))
    check("frontier_1080p_fps_core_max", r is not None and r["fps"] == 25.0, "" if r is None else str(r["fps"]))
    r = max_px(lambda x: x["fps"] == 30 and x["cores"] == 1 and x["streams"] == 1 and c25(x))
    check("frontier_30fps_core_res_max", r is not None and (r["W"], r["H"]) == (1728, 972))
    frows = load_csv("frontier.csv")
    check("frontier_recommended_rows_3",
          len([x for x in frows if x["is_recommended"] == "true"]) == 3,
          str(len([x for x in frows if x["is_recommended"] == "true"])))
    check("frontier_primary_row_present",
          any(x["is_recommended"] == "true" and x["W"] == "1600" and x["H"] == "900" for x in frows))

    # ---------------------------------------------------------------- report checks
    report = (ROOT / "feasibility-report.md").read_text(encoding="utf-8")
    side = ROOT / "logs" / "report.sha256"
    side_txt = side.read_text(encoding="utf-8") if side.exists() else ""
    m = re.search(r"sha256=([0-9a-f]{64})", side_txt)
    check("report_hash_sidecar_matches", m is not None and m.group(1) == hashlib.sha256(
        report.encode("utf-8")).hexdigest(), side_txt.strip())
    table_rows = {}
    for line in report.splitlines():
        if not line.startswith("| "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 13 and cells[0] in srows:
            table_rows[cells[0]] = cells
            r = srows[cells[0]]
            want = [r["scenario_id"], r["cores"], r["streams"], r["W"] + "×" + r["H"], r["fps"],
                    r["clock_mhz"], r["capacity_core_MBps"], r["capacity_chain_MBps"],
                    r["margin_core_pct"], r["margin_chain_pct"], r["drop_rate_lb_pct"],
                    r["gate_status"], r["verdict"]]
            if cells != want:
                check("report_row_%s" % cells[0], False, "%r != %r" % (cells, want))
    check("report_table_has_all_43_rows", len(table_rows) == 43, str(len(table_rows)))
    for sid in srows:
        if sid not in table_rows:
            check("report_missing_row_%s" % sid, False)
    counts = {}
    for r in rows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    check("report_counts_line",
          ("feasible **%d**" % counts.get("feasible", 0)) in report
          and ("conditional **%d**" % counts.get("conditional", 0)) in report
          and ("infeasible **%d**" % counts.get("infeasible", 0)) in report)
    check("report_mentions_231_and_289", "231" in report and "289" in report)
    check("report_mentions_csi_sensitivity",
          all(t in report for t in ["26,822", "35,815", "32,083"]))
    check("report_mentions_dual_core_conditional", "最高只能判 `conditional`" in report)
    check("report_mentions_ddr_required_eff", "所需效率" in report and "809.034" in report)
    check("report_mentions_per_stream_trap", "aggregate 陷阱" in report)
    check("report_mentions_core_only_trap", "core-only 陷阱" in report)
    check("report_mentions_not_board", "not_applicable" in report and "not_run" in report)
    check("report_mentions_overhead_tiers",
          all(t in report for t in ["21.0486", "42.9485", "6.7286", "overhead-sensitivity.csv"]))
    check("report_primary_conditional_wording", "带条件" in report and "不是无条件 feasible" in report)
    check("report_robust_1440", "1440×810" in report and "三档稳健" in report)
    check("report_required_clocks",
          all(t in report for t in ["172.1100", "156.1206", "142.4471", "160.5353"]))
    check("report_c1s2_eram_caveat", "208/300" in report and "1 核 2 路 ERAM 口径" in report)
    check("report_frontier_table_has_clock_and_worst",
          "worst tier" in report and "req chain clk" in report)

    # ---------------------------------------------------------------- negative controls (3)
    def rejected(fn, code):
        try:
            fn()
        except calc.ModelRejected as exc:
            return str(exc) == code
        except Exception:  # noqa: BLE001
            return False
        return False

    check("NEG-01_raw12_and_1p0x_rejected",
          rejected(lambda: calc.validate_packing("RAW12_1.0x", 1920, 1080, 3110400, 3110400),
                   "PACKING_PROFILE_REJECTED")
          and rejected(lambda: calc.validate_packing(calc.PROFILE_OK, 1920, 1080, 2592000, 2592000),
                       "PACKING_MISMATCH"))
    check("NEG-02_aggregate_2C_rejected",
          rejected(lambda: calc.validate_per_stream_claim(2, 2, 162.134318, 75.684265, 77.76, "feasible", RULES),
                   "AGGREGATE_CAPACITY_FOR_PER_STREAM")
          and rejected(lambda: calc.validate_per_stream_claim(2, 2, 75.684265, 75.684265, 77.76, "feasible", RULES),
                       "FEASIBLE_CLAIM_BELOW_PER_STREAM_GATE"))
    check("NEG-03_synth_mixed_rejected", rejected(lambda: calc.validate_resource_stage("synth"),
                                                  "STAGE_MIX_SYNTH_IN_FIT"))

    # ---------------------------------------------------------------- no TD/hardware artifacts
    bad = [p.name for p in ROOT.rglob("*")
           if p.is_file() and p.suffix.lower() in {".bit", ".cwc", ".bid", ".dcp", ".sdc"}]
    check("no_td_or_bitstream_artifacts", not bad, str(bad[:5]))

    failed = [r for r in RESULTS if not r[1]]
    print("CHECK_SUMMARY total=%d pass=%d fail=%d" % (len(RESULTS), len(RESULTS) - len(failed), len(failed)))
    append_command("CHECK_OK total=%d fail=%d" % (len(RESULTS), len(failed)) if not failed
                   else "CHECK_FAIL fails=%d" % len(failed), 0 if not failed else 1)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
