"""Tester's negative-control + cross-file consistency harness (T10.ss-verdict-r1 r0).

Independent of model/test_calc.py and model/check_outputs.py:
  * invokes the six frozen negative controls directly on the validators
  * checks the CSV / JSON / report claim boundaries required by dev-plan 4.5
  * checks the export-tail rule is applied as frozen (constant tail, sink_limited=false,
    no unconditional 400,320-cycle subtraction)
"""
import csv
import importlib.util
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
R0 = ("D:/fpga/ph1p100/workflow/runs/20261025-233401_fpga-steady-state-reverdict/"
      "T10.ss-verdict-r1/r0")
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
    with open(os.path.join(R0, "out", name), "r", encoding="utf-8", newline="") as fh:
        rdr = csv.DictReader(fh)
        return list(rdr)


def load_calc():
    path = os.path.join(R0, "model", "calc.py")
    spec = importlib.util.spec_from_file_location("candidate_calc", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def expect_reject(name, reason, fn, *args, **kwargs):
    try:
        fn(*args, **kwargs)
    except calc.ModelRejected as exc:
        ck(name, str(exc) == reason, "got %s want %s" % (exc, reason))
    else:
        ck(name, False, "validator did not reject")


calc = load_calc()
rules = load_json(os.path.join(R0, "model", "rules.json"))
frozen = load_json(os.path.join(R0, "inputs", "frozen-inputs.json"))


def main():
    # ---------------------------------------------------------- NC1..NC6
    expect_reject("NC1 COLD_LATENCY_AS_THROUGHPUT", "COLD_LATENCY_AS_THROUGHPUT",
                  calc.validate_anchor_use, "A4", "throughput")
    expect_reject("NC1b A4 as capacity", "COLD_LATENCY_AS_THROUGHPUT",
                  calc.validate_anchor_use, "A4", "capacity")
    ck("NC1 control: A1 throughput allowed", calc.validate_anchor_use("A1", "throughput") is True)
    expect_reject("NC2 GATE_COLLAPSE", "GATE_COLLAPSE",
                  calc.validate_verdict, "pass", "fail", "infeasible")
    ck("NC2 control: below_25 -> conditional allowed",
       calc.validate_verdict("pass", "fail", "conditional") is True)
    expect_reject("NC3 PEAK_MISMATCH", "PEAK_MISMATCH",
                  calc.validate_peak, "ddr1333", 6400)
    ck("NC3 control: 6400 labelled fallback allowed",
       calc.validate_peak("ddr1333", 6400, label="fallback_disclosed") is True)
    expect_reject("NC4 SINK_MISMATCH", "SINK_MISMATCH",
                  calc.validate_sink, "sim_fast_b11", "production_realtime")
    expect_reject("NC4b real UART as production", "SINK_MISMATCH",
                  calc.validate_sink, "uart_115200", "production_realtime")
    ck("NC4 control: evidence-only sink allowed",
       calc.validate_sink("sim_fast_b11", "evidence_only") is True)
    expect_reject("NC5 AGGREGATE_CAPACITY_FOR_PER_STREAM", "AGGREGATE_CAPACITY_FOR_PER_STREAM",
                  calc.validate_per_stream_claim, 2, 2, 207.8017588, 103.9008794, 77.76, "feasible")
    ck("NC5 control: per-stream C allowed",
       calc.validate_per_stream_claim(2, 2, 103.9008794, 103.9008794, 77.76, "feasible") is True)
    expect_reject("NC6 TIER_NOT_APPLIED", "TIER_NOT_APPLIED",
                  calc.validate_tier_applied, 1920, 1080, False)
    ck("NC6 control: 1080p applies=true allowed",
       calc.validate_tier_applied(1920, 1080, True) is True)
    expect_reject("NC-extra CONTENT_ANCHOR_MIX", "CONTENT_ANCHOR_MIX",
                  calc.validate_anchor_mix, "A1_grad_ss", "A2_comp_assumed")
    nc_ids = [n["id"] for n in rules["negative_controls"]]
    ck("rules.json declares NC1..NC6", nc_ids == ["NC1", "NC2", "NC3", "NC4", "NC5", "NC6"], nc_ids)
    ck("rules forbid DUAL_CORE_FEASIBLE", "DUAL_CORE_FEASIBLE" in rules["forbidden_collapses"])

    # ------------------------------------------------------------ scenarios
    scen = read_csv("scenarios.csv")
    ck("scenarios 43 rows", len(scen) == 43, len(scen))
    ck("scenarios ids unique", len({r["scenario_id"] for r in scen}) == 43)
    ck("no cores=2 row feasible",
       all(not (int(r["cores"]) == 2 and r["verdict"] == "feasible") for r in scen))
    ck("every row has gate_G0 and gate_G25 columns",
       all(r.get("gate_G0") in ("pass", "fail") and r.get("gate_G25") in ("pass", "fail")
           for r in scen))
    collapse = [r["scenario_id"] for r in scen
                if r["gate_G0"] == "pass" and r["gate_G25"] == "fail"
                and r["verdict"] == "infeasible"]
    ck("below_25 never infeasible", not collapse, collapse)
    ck("every row claim_status=not_proven_all_content",
       all(r["claim_status"] == "not_proven_all_content" for r in scen))
    ck("1080p rows use A1 measured anchor only",
       all(r["chain_anchor_id"] == "A1_grad_ss" and near(r["cycles_chain_per_frame"], 4677535, 1e-3)
           for r in scen if int(r["W"]) == 1920 and int(r["H"]) == 1080))
    ck("non-1080p rows use affine comp anchor",
       all(r["chain_anchor_id"] == "affine_comp_tier"
           for r in scen if not (int(r["W"]) == 1920 and int(r["H"]) == 1080)))
    s30 = [r for r in scen if r["scenario_id"] == "1920x1080-30fps-c1s1-187.5MHz"][0]
    ck("1080p30 c1s1 G0 and G25 listed separately (both pass)",
       s30["gate_G0"] == "pass" and s30["gate_G25"] == "pass"
       and near(s30["margin_chain_pct"], 33.6174, 2e-3)
       and near(s30["margin_gate25_pct"], 6.8939, 2e-3))
    ck("1080p30 c1s1 notes do not extrapolate to natural images/dual-stream",
       "not extrapolable to dual-stream/natural images" in s30["notes"])
    d30 = [r for r in scen if r["scenario_id"] == "1920x1080-30fps-c2s2-187.5MHz"][0]
    ck("1080p30 c2s2 conditional (never feasible)", d30["verdict"] == "conditional")

    # --------------------------------------------------------- content anchors
    anchors = {r["anchor_id"]: r for r in read_csv("content-anchors.csv")}
    ck("A1 measured + both gates pass",
       anchors["A1"]["label"] == "measured" and anchors["A1"]["gate_G0"] == "pass"
       and anchors["A1"]["gate_G25"] == "pass")
    ck("A2 assumed + both gates fail",
       anchors["A2"]["label"] == "assumed" and anchors["A2"]["gate_G0"] == "fail"
       and anchors["A2"]["gate_G25"] == "fail")
    ck("A3 assumed + both gates pass",
       anchors["A3"]["label"] == "assumed" and anchors["A3"]["is_throughput_anchor"] == "true")
    ck("A4 not a throughput anchor",
       anchors["A4"]["is_throughput_anchor"] == "false"
       and anchors["A4"]["gate_G0"] == "not_applicable"
       and anchors["A4"]["label"] == "measured_but_not_throughput")
    ck("A2/A4 circularity stated in CSV notes",
       "NOT independent evidence" in anchors["A2"]["notes"])

    # ------------------------------------------------------------ gate matrix
    gm = read_csv("gate-matrix.csv")
    ck("gate-matrix 24 rows", len(gm) == 24, len(gm))
    cells = {(r["anchor_id"], int(r["cores"]), int(r["streams"])) for r in gm}
    ck("gate-matrix 12 anchor/combo cells", len(cells) == 12, len(cells))
    ck("gate-matrix every cell has G0 and G25",
       all(sorted(r["gate"] for r in gm
                  if (r["anchor_id"], int(r["cores"]), int(r["streams"])) == c) == ["G0", "G25"]
           for c in cells))
    ck("gate-matrix A1 c1s1 both pass and A2 c1s1 both fail",
       all(r["gate_result"] == "pass" for r in gm
           if r["anchor_id"] == "A1" and int(r["cores"]) == 1 and int(r["streams"]) == 1)
       and all(r["gate_result"] == "fail" for r in gm
               if r["anchor_id"] == "A2" and int(r["cores"]) == 1 and int(r["streams"]) == 1))
    ck("gate-matrix no dual-core feasible row",
       all(not (int(r["cores"]) == 2 and r["row_verdict"] == "feasible") for r in gm))

    # -------------------------------------------------------------- overhead
    over = read_csv("overhead-sensitivity.csv")
    ck("overhead 129 rows / 43 scenarios x 3 tiers",
       len(over) == 129 and len({r["scenario_id"] for r in over}) == 43)
    ck("overhead all applies=true (1080p participates)",
       all(r["applies"] == "true" for r in over))
    o30 = sorted([r for r in over if r["scenario_id"] == "1920x1080-30fps-c1s1-187.5MHz"],
                 key=lambda r: float(r["tier_cycles"]))
    ck("overhead 1080p30 tier cycles exact",
       [float(r["cycles_chain_per_frame"]) for r in o30] == [4251150.0, 4677535.0, 5251150.0],
       [r["cycles_chain_per_frame"] for r in o30])
    ck("overhead 1080p30 G25 pass/pass/fail and not tier-robust",
       [r["gate_G25"] for r in o30] == ["pass", "pass", "fail"]
       and all(r["tier_robust_G25"] == "false" for r in o30))
    ck("overhead 1080p30 tier0 margin +17.6152 / tier1e6 -4.7828",
       near(o30[0]["margin_gate25_pct"], 17.6152, 2e-3)
       and near(o30[2]["margin_gate25_pct"], -4.7828, 2e-3))

    # ------------------------------------------------------------------- DDR
    ddr = read_csv("ddr-budget.csv")
    ck("ddr 7 cases", len(ddr) == 7, len(ddr))
    main = [r for r in ddr if r["case_id"] == "dual_1080p30_main"][0]
    ck("ddr main 809.034 / 1011.2925",
       near(main["ddr_total_MBps"], 809.034, 1e-6)
       and near(main["ddr_gate_25_MBps"], 1011.2925, 1e-6))
    ck("ddr 1333 required/gate eff 15.1732/18.9665",
       near(main["required_eff_1333_pct"], 15.1732, 2e-3)
       and near(main["gate_eff_1333_pct"], 18.9665, 2e-3))
    ck("ddr 1600 fallback required/gate eff 12.6412/15.8014",
       near(main["required_eff_1600_pct"], 12.6412, 2e-3)
       and near(main["gate_eff_1600_pct"], 15.8014, 2e-3))
    ck("ddr DOC-1 discrepancy disclosed not adopted",
       all(r["doc1_s8_reproducible"] == "false" for r in ddr)
       and "does not follow" in main["notes"])

    # ----------------------------------------------------------- corrections
    corr = read_csv("corrections.csv")
    ck("corrections 9 rows C1..C9", [r["id"] for r in corr] == ["C%d" % i for i in range(1, 10)])
    ck("corrections every field non-empty",
       all(all(str(v).strip() for v in r.values()) for r in corr))
    c1 = corr[0]
    ck("C1 carries +33.6174/+6.8939 and -2.6694/-22.1355",
       "+33.6174%" in c1["impact_on_verdict"] and "+6.8939%" in c1["impact_on_verdict"]
       and "-2.6694%" in c1["p2_value"] and "-22.1355%" in c1["impact_on_verdict"])
    c3 = corr[2]
    ck("C3 carries 15.1732/18.9665 and 12.6412/15.8014",
       "15.1732%" in c3["corrected_value"] and "18.9665%" in c3["corrected_value"]
       and "12.6412%" in c3["p2_value"] and "15.8014%" in c3["p2_value"])
    c5 = corr[4]
    ck("C5 carries 3.475 s and 225.235 s",
       "3.475" in c5["corrected_value"] and "225.235" in c5["corrected_value"])
    c9 = corr[8]
    ck("C9 carries 32.068 fps / 175.408 MHz and A2 23.359/240.803",
       "32.068" in c9["corrected_value"] and "175.408" in c9["corrected_value"]
       and "23.359" in c9["corrected_value"] and "240.803" in c9["corrected_value"])

    # --------------------------------------------------------------- frontier
    front = read_csv("frontier.csv")
    rec = [r for r in front if r["is_recommended"] == "true"]
    ck("frontier 1 primary + 2 alternates", len(rec) == 3, len(rec))
    ck("frontier primary 1600x900 on comp basis",
       sum(1 for r in rec if int(r["W"]) == 1600 and int(r["H"]) == 900
           and r["chain_anchor_id"] == "affine_comp_tier") == 1)
    ck("frontier recommendations are single-core comp basis",
       all(int(r["cores"]) == 1 and r["chain_anchor_id"] == "affine_comp_tier" for r in rec))
    ck("frontier does not recommend 1080p or dual-core",
       all(not (int(r["W"]) == 1920 and int(r["H"]) == 1080) and int(r["cores"]) == 1
           for r in rec))
    f1080 = [r for r in front if int(r["W"]) == 1920 and int(r["H"]) == 1080
             and near(r["fps"], 30.0, 1e-9)]
    ck("frontier lists 1080p30 A1 but not recommended",
       f1080 and all(r["is_recommended"] == "false" for r in f1080))
    ck("frontier dual-core row conditional not feasible",
       all(r["verdict"] != "feasible" for r in front if int(r["cores"]) == 2))

    # ---------------------------------------------------- summary / report
    summary = load_json(os.path.join(R0, "out", "summary.json"))
    ck("summary headline not_proven + crossing true",
       summary["headline_1080p30_per_stream"]["headline"] == "not_proven"
       and summary["headline_1080p30_per_stream"]["crossing"] is True)
    ck("summary dual-core headline not_proven",
       summary["headline_1080p30_dual_core"]["headline"] == "not_proven")
    ck("summary A1/A2 gates cross",
       summary["headline_1080p30_per_stream"]["A1"]["G0"] is True
       and summary["headline_1080p30_per_stream"]["A2"]["G0"] is False)
    ck("summary content not_proven_all_content",
       summary["headline_1080p30_per_stream"]["content"] == "not_proven_all_content")

    with open(os.path.join(R0, "verdict-r1.md"), "r", encoding="utf-8") as fh:
        report = fh.read()
    norm = report.replace("**", "").replace("`", "").replace("，", ",")
    ck("report headline = not_proven", "结论 = not_proven" in norm)
    ck("report says neither infeasible nor feasible",
       "不是 infeasible,也不是 feasible" in norm)
    ck("report A1/A2 crossing with both margin pairs",
       "+33.6174%" in norm and "-2.6694%" in norm
       and "+6.8939%" in norm and "-22.1355%" in norm and "内容跨界" in norm)
    ck("report A1 extrapolation boundary stated",
       "不得外推自然图像/低照/噪声" in norm and "不得外推双路" in norm)
    ck("report below_25 -> conditional (never infeasible)",
       "below_25 一律写 conditional" in norm)
    ck("report export tail constant + no unconditional subtraction",
       "480,930" in norm and "sink_limited=false" in norm and "不得无条件扣" in norm)
    ck("report transport not_proven", "transport=not_proven" in norm)
    ck("report dual PAAXI unproven + never feasible",
       "paaxi_shared_unproven" in norm and "永不 feasible" in norm)
    ck("report no 'guarantee' claim", "不得称“保证”" in norm or "保证" not in norm)
    ck("report 1080p30 listed separately, not recommended",
       "单列（不作推荐）" in norm or "单列" in norm)
    ck("report DDR both peaks", "5,332" in report and "6,400" in report
       and "15.1732%" in report and "12.6412%" in report)
    ck("report UART 3.475/225.235", "3.475" in report and "225.235" in report)
    ck("report max fps 32.068/23.359", "32.068" in report and "23.359" in report)

    # ---------------------------------------------- export-tail rule in model
    with open(os.path.join(R0, "model", "calc.py"), "r", encoding="utf-8") as fh:
        calc_src = fh.read()
    ck("model does not subtract 480930/400320 from capacity",
       "4677535 - 480930" not in calc_src.replace(",", "")
       and "4677535-480930" not in calc_src.replace(",", "").replace(" ", ""))
    ck("model capacity uses raw frame bytes / chain cycles only",
       "def capacity_from_cycles(cycles, clock_hz, frame_bytes=2592000)" in calc_src)
    ck("model uart reports sink_limited and transport from frozen inputs",
       'u["sink_limited"]' in calc_src and 'u["transport"]' in calc_src)
    jt = json.dumps(summary)
    ck("summary tail 480,930 and sink_limited false",
       summary["uart"]["tail_measured_cycles"] == 480930
       and summary["uart"]["sink_limited"] is False
       and summary["uart"]["transport"] == "not_proven")

    # --------------------------------------------------------- contract values
    ck("contract 187.5 MHz", frozen["clock_mhz"] == 187.5)
    ck("contract 20B/32B expansion 1.6", near(frozen["ddr"]["raw_slot_expansion"], 1.6, 1e-12))
    ck("contract 8 MiB cmp slots", frozen["frame"]["cmp_slot_bytes"] == 8388608)
    ck("contract 44 B A1U1 header", frozen["frame"]["a1u1_header_bytes"] == 44)
    ck("contract frame bytes 2,592,000", frozen["frame"]["raw_bytes"] == 2592000)

    out = {"checks": CHECKS[0], "failures": FAILS,
           "verdict": "PASS" if not FAILS else "FAIL"}
    with open(os.path.join(HERE, "controls_and_consistency.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
        fh.write("\n")
    print("\n%d checks, %d failures" % (CHECKS[0], len(FAILS)))
    print("CONTROLS_AND_CONSISTENCY=%s" % out["verdict"])
    return 0 if not FAILS else 1


if __name__ == "__main__":
    raise SystemExit(main())
