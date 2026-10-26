"""Generate the corrected P2 tables (CSV) + summary.json from frozen inputs and rules.

Deterministic, no randomness/network/clock reads in the model.  The only I/O is reading
inputs/frozen-inputs.json + model/rules.json and writing out/*.csv + out/summary.json.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import calc  # noqa: E402


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def write_csv(name, rows, cols):
    path = os.path.join(ROOT, "out", name)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(calc.csv_text(rows, cols))
    return path


def main():
    frozen = load(os.path.join(ROOT, "inputs", "frozen-inputs.json"))
    rules = load(os.path.join(HERE, "rules.json"))

    rows = calc.scenario_rows(frozen, rules)
    assert len(rows) == 43, len(rows)
    overhead = calc.overhead_rows(rows, frozen, rules)
    assert len(overhead) == 129, len(overhead)
    anchors = calc.anchor_rows(frozen)
    assert len(anchors) == 4
    gm = calc.gate_matrix_rows(frozen, rules)
    assert len(gm) == 24, len(gm)
    ddr = calc.ddr_rows(frozen, frozen["ddr"]["peak_MBps_main"])
    corr = calc.corrections_rows(frozen)
    assert len(corr) == 9
    front = calc.frontier_rows(rows, frozen, rules, overhead)

    # ---- gate / headline consistency guards (fail fast before any CSV is written)
    for r in rows:
        calc.validate_verdict(r["gate_G0"], r["gate_G25"], r["verdict"])
    for r in gm:
        g0 = "pass" if r["margin_G0_pct"] >= 0.0 else "fail"
        g25 = "pass" if r["margin_G25_pct"] >= 0.0 else "fail"
        calc.validate_verdict(g0, g25, r["row_verdict"])
        expect = g0 if r["gate"] == "G0" else g25
        assert r["gate_result"] == expect, (r["anchor_id"], r["gate"], r["gate_result"], expect)
        if r["cores"] == 2 and r["row_verdict"] == "feasible":
            raise calc.ModelRejected("DUAL_CORE_FEASIBLE")
    for r in overhead:
        calc.validate_tier_applied(int(r["W"]), int(r["H"]), r["applies"] == "true")

    a1 = calc.anchor_metrics(frozen, "A1")
    a2 = calc.anchor_metrics(frozen, "A2")
    a3 = calc.anchor_metrics(frozen, "A3")
    headline = calc.headline_1080p30(rules,
                                     a1["margin_0_pct"] / 100.0, a1["margin_25_pct"] / 100.0,
                                     a2["margin_0_pct"] / 100.0, a2["margin_25_pct"] / 100.0,
                                     resources_ok=True, cores=1, streams=1)
    headline_dual = calc.headline_1080p30(rules,
                                          a1["margin_0_pct"] / 100.0, a1["margin_25_pct"] / 100.0,
                                          a2["margin_0_pct"] / 100.0, a2["margin_25_pct"] / 100.0,
                                          resources_ok=True, cores=2, streams=2)
    assert headline["headline"] == "not_proven", headline
    assert headline_dual["headline"] != "feasible", headline_dual

    primary, alts = calc.recommendations(rows, frozen, overhead)
    assert primary is not None and primary["chain_anchor_id"] == "affine_comp_tier"
    nominals = calc.nominal_only_rows(rows)
    uart = calc.uart_numbers(frozen)

    tier_table = []
    for tier in frozen["overhead"]["sensitivity_tiers"]:
        cyc = calc.tier_shift_1080p(frozen, tier)
        cap = calc.capacity_from_cycles(cyc, frozen["clock_hz"])
        d = calc.demand_MBps(frozen["frame"]["raw_bytes"], 30)
        m0, m25 = calc.margin_0(cap, d), calc.margin_25(cap, d)
        tier_table.append({
            "tier_cycles": int(tier),
            "cycles_chain_per_frame": cyc,
            "capacity_MBps": cap,
            "margin_0_pct": 100.0 * m0,
            "margin_25_pct": 100.0 * m25,
            "gate_G0": calc.gate_g0(cap, d),
            "gate_G25": calc.gate_g25(cap, d),
        })

    # ---- write CSVs
    paths = []
    paths.append(write_csv("scenarios.csv", rows, calc.SCENARIO_COLS))
    paths.append(write_csv("content-anchors.csv", anchors, calc.ANCHOR_COLS))
    paths.append(write_csv("gate-matrix.csv", gm, calc.GATE_MATRIX_COLS))
    paths.append(write_csv("overhead-sensitivity.csv", overhead, calc.OVERHEAD_COLS))
    paths.append(write_csv("ddr-budget.csv", ddr, calc.DDR_COLS))
    paths.append(write_csv("corrections.csv", corr, calc.CORRECTION_COLS))
    paths.append(write_csv("frontier.csv", front, calc.FRONTIER_COLS))

    summary = {
        "counts": {
            "scenarios": len(rows),
            "overhead_rows": len(overhead),
            "gate_matrix": len(gm),
            "content_anchors": len(anchors),
            "corrections": len(corr),
            "ddr_cases": len(ddr),
            "frontier": len(front),
        },
        "headline_1080p30_per_stream": headline,
        "headline_1080p30_dual_core": headline_dual,
        "anchors": {"A1": a1, "A2": a2, "A3": a3},
        "tier_table_1080p": tier_table,
        "uart": uart,
        "ddr_main": {
            "ddr_total_MBps": ddr[0]["ddr_total_MBps"],
            "ddr_gate_25_MBps": ddr[0]["ddr_gate_25_MBps"],
            "required_eff_1333_pct": ddr[0]["required_eff_1333_pct"],
            "gate_eff_1333_pct": ddr[0]["gate_eff_1333_pct"],
            "required_eff_1600_pct": ddr[0]["required_eff_1600_pct"],
            "gate_eff_1600_pct": ddr[0]["gate_eff_1600_pct"],
        },
        "thresholds": {
            "S_ss_at_0pct_cycles": 6250000,
            "S_ss_at_25pct_cycles": 5000000,
            "capacity_at_5M_MBps": calc.capacity_from_cycles(5000000, frozen["clock_hz"]),
            "capacity_at_6p25M_MBps": calc.capacity_from_cycles(6250000, frozen["clock_hz"]),
            "demand_1080p30_MBps": frozen["gates"]["G0"]["demand_1080p30_MBps"],
            "demand_1080p30_25_MBps": frozen["gates"]["G25"]["demand_1080p30_MBps"],
        },
        "max_fps_25pct": {
            "A1": calc.max_fps(calc.anchor_cycles(frozen, "A1"), frozen["clock_hz"], 0.25),
            "A2": calc.max_fps(calc.anchor_cycles(frozen, "A2"), frozen["clock_hz"], 0.25),
        },
        "recommendation": {
            "primary": primary["scenario_id"] if primary else None,
            "primary_worst_tier_margin_pct": calc.worst_tier_margin(overhead, primary["scenario_id"]),
            "alternates": [{"scenario_id": a["scenario_id"],
                            "worst_tier_margin_pct": calc.worst_tier_margin(overhead, a["scenario_id"])}
                           for a in alts],
            "nominal_only_largest": (sorted(nominals, key=lambda r: -int(r["W"]) * int(r["H"]))[0]["scenario_id"]
                                     if nominals else None),
            "nominal_only_count": len(nominals),
        },
        "verdict_counts": {},
    }
    for r in rows:
        summary["verdict_counts"][r["verdict"]] = summary["verdict_counts"].get(r["verdict"], 0) + 1

    with open(os.path.join(ROOT, "out", "summary.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2, ensure_ascii=False)
        fh.write("\n")

    print("wrote %d CSVs" % len(paths))
    for p in paths:
        print("  %s" % os.path.relpath(p, ROOT))
    print("headline_1080p30_per_stream=%s (A1 G0=%s G25=%s | A2 G0=%s G25=%s)"
          % (headline["headline"], headline["gate_G0"], headline["gate_G25"],
             "pass" if headline["A2"]["G0"] else "fail",
             "pass" if headline["A2"]["G25"] else "fail"))
    print("verdicts=%s" % summary["verdict_counts"])
    print("primary=%s alt=%s" % (primary["scenario_id"], [a["scenario_id"] for a in alts]))
    print("A1 C_ss=%.6f MB/s margin0=%.4f%% margin25=%.4f%%" %
          (a1["capacity_MBps"], a1["margin_0_pct"], a1["margin_25_pct"]))
    print("A2 C_ss=%.6f MB/s margin0=%.4f%% margin25=%.4f%%" %
          (a2["capacity_MBps"], a2["margin_0_pct"], a2["margin_25_pct"]))
    print("A3 C_ss=%.6f MB/s margin0=%.4f%% margin25=%.4f%%" %
          (a3["capacity_MBps"], a3["margin_0_pct"], a3["margin_25_pct"]))
    print("tiers=%s" % [(t["tier_cycles"], round(t["margin_0_pct"], 4), round(t["margin_25_pct"], 4))
                        for t in tier_table])
    print("ddr=%s" % summary["ddr_main"])


if __name__ == "__main__":
    main()
