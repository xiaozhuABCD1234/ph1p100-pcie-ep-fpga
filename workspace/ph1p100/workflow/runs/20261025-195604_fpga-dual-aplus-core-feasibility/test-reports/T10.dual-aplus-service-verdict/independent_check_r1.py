"""Round-1 retest recomputation for T10.dual-aplus-service-verdict (tester-side, read-only).

Same independence rule as r0: scenario / DDR / content / sensitivity / frontier rows are
recomputed from first principles (bytes, cycles, clock, tiers).  model/calc.py is imported
only in a separate -B subprocess to confirm the negative-control validators still reject.

Run: python -B independent_check_r1.py
"""
import csv
import hashlib
import json
import math
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(r"D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility\T10.dual-aplus-service-verdict\r0")
MANIFEST = ROOT / "manifest-r0.json"
MANIFEST_SHA = "5ed90500a7e9650ca17e5f269731984fea9f215d7401d555dc5633551c2436a6"
P1_MANIFEST = Path(r"D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility\T10.dual-core-resource-baseline\r0\manifest-r0.json")
P1_SHA = "228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0"
B6_CORE = Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\r0\changed-src\a1_deflate_core.v")
B6_SHA = "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb"
B6_MANIFEST = Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json")
B6_MANIFEST_SHA = "2e9fd356824084813e3415af11757c1b56f774c9b6dd45f3b2a111647ad08880"
FROZEN_SHA = "888d3f3361aada77c77fc87140d6469b052d4dac2c63466e2007cfbf973a0f59"

CLOCK = 187.5e6
CPB = 355261.0 / 153600.0
ANCHOR = 6421414.0
GATE = 0.25
TIERS = [0.0, 426385.0, 1000000.0]
TIERS_30 = [(1920, 1080), (1728, 972), (1600, 900), (1440, 810), (1280, 720), (1152, 648), (960, 540)]

FAILS = []


def ck(name, ok, detail=""):
    print("%-5s %s%s" % ("PASS" if ok else "FAIL", name, ("  | " + detail) if (detail and not ok) else ""))
    if not ok:
        FAILS.append((name, detail))


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def raw_b(w, h):
    assert w % 4 == 0 and (w * h) % 4 == 0
    return w * h * 5 // 4


def cyc_core(w, h):
    return raw_b(w, h) * CPB


def cyc_chain(w, h, overhead):
    return ANCHOR if (w, h) == (1920, 1080) else cyc_core(w, h) + overhead


def cap(raw, cyc, clock):
    return raw * clock / cyc / 1e6


def ps_cap(c, cores, streams):
    return c / 2.0 if (cores == 1 and streams == 2) else c


def gate_of(m):
    return "meets_25" if m >= GATE else ("below_25" if m >= 0 else "fails_30")


def verdict_of(cores, m_chain, marginal, cons, timing):
    if marginal > 300:
        return "infeasible"
    if m_chain < 0:
        return "infeasible"
    if cores == 2 and not timing:
        return "conditional"
    if m_chain >= GATE and cons <= 270 and timing:
        return "feasible"
    return "conditional"


# ---------------------------------------------------------------- 1. manifest / artifacts / inputs / drift
man = json.loads(MANIFEST.read_text(encoding="utf-8"))
ck("manifest_sha_new", sha(MANIFEST) == MANIFEST_SHA, sha(MANIFEST))
ck("manifest_repair_round_1", man.get("repair_round") == 1 and man.get("stopped_modifying") is True
   and man.get("active_commands") == 0 and man.get("status") == "ready_for_test")
ck("manifest_counts_23_22_18",
   len(man["artifacts"]) == 23 and len(man["inputs"]) == 22 and len(man["commands"]) == 18,
   "%d/%d/%d" % (len(man["artifacts"]), len(man["inputs"]), len(man["commands"])))
bad = [a["rel"] for a in man["artifacts"]
       if not Path(a["path"]).exists() or Path(a["path"]).stat().st_size != a["bytes"] or sha(a["path"]) != a["sha256"]]
ck("artifacts_23_sha_bytes", not bad, str(bad))
bad_in = [i["id"] for i in man["inputs"]
          if not Path(i["path"]).exists() or Path(i["path"]).stat().st_size != i["bytes"] or sha(i["path"]) != i["sha256"]]
ck("inputs_22_sha_bytes_no_drift", not bad_in, str(bad_in))
ck("drift_p1_and_b6",
   sha(P1_MANIFEST) == P1_SHA and P1_MANIFEST.stat().st_size == 23644
   and sha(B6_CORE) == B6_SHA and B6_CORE.stat().st_size == 80196
   and sha(B6_MANIFEST) == B6_MANIFEST_SHA)
ck("frozen_inputs_unchanged", sha(ROOT / "inputs" / "frozen-inputs.json") == FROZEN_SHA)
ck("manifest_tools_all_zero", all(v == 0 for k, v in man["tools"].items() if k != "python"),
   json.dumps(man["tools"]))
bad_ext = [str(p) for p in ROOT.rglob("*") if p.is_file()
           and p.suffix.lower() in {".bit", ".cwc", ".bid", ".dcp", ".sdc", ".sof", ".sta"}]
ck("no_td_bit_artifacts", not bad_ext, str(bad_ext[:5]))
ck("manifest_no_td_command",
   not [c for c in man["commands"] if any("td" in str(x).lower() for x in c["argv"])])
journal = [json.loads(l) for l in (ROOT / "commands.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
ck("commands_journal_17_vs_manifest_18", len(journal) == 17,
   "journal=%d manifest=%d" % (len(journal), len(man["commands"])))


def read_text_any(p):
    b = Path(p).read_bytes()
    for enc in ("utf-8-sig", "utf-16", "utf-8"):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            continue
    return b.decode("latin-1")


ck("repair_commands_seq14_18_present",
   [c["seq"] for c in man["commands"]][-5:] == [14, 15, 16, 17, 18])
ck("only_historical_seq2_nonzero_exit",
   [c["seq"] for c in man["commands"] if c["exit"] != 0] == [2],
   str([(c["seq"], c["exit"]) for c in man["commands"] if c["exit"] != 0]))
ck("repair_logs_ok",
   "TEST_SUMMARY total=146 pass=146 fail=0" in read_text_any(ROOT / "logs" / "test_calc.out.txt")
   and "CHECK_SUMMARY total=117 pass=117 fail=0" in read_text_any(ROOT / "logs" / "check_outputs.out.txt"))
iv = json.loads((ROOT / "input-verified.json").read_text(encoding="utf-8"))
ck("input_verified_zero_mismatch_97", iv.get("mismatch_count") == 0 and len(iv.get("assertions", [])) == 97
   and all(a["status"] == "pass" for a in iv["assertions"]))
ck("input_verified_regenerated_after_fix", iv.get("generated_utc", "").startswith("2026-10-25T14:36"))

# write scope: repair window 14:00-14:45Z, outside the task dir (main-log + own test-reports excepted)
lo = datetime(2026, 10, 25, 14, 0, tzinfo=timezone.utc).timestamp()
hi = datetime(2026, 10, 25, 14, 45, tzinfo=timezone.utc).timestamp()
outside = []
for p in Path(r"D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility").rglob("*"):
    if p.is_file() and ROOT not in p.parents and p != ROOT:
        rel = str(p.relative_to(ROOT.parents[1]))
        if rel.endswith("main-log.md") or rel.startswith("test-reports" + os.sep):
            continue
        if lo <= p.stat().st_mtime <= hi:
            outside.append(rel)
ck("write_scope_no_run_file_touched", not outside, str(outside[:5]))
ck("write_scope_p1_untouched",
   not [p.name for p in P1_MANIFEST.parent.rglob("*") if p.is_file() and lo <= p.stat().st_mtime <= hi])

# ---------------------------------------------------------------- 2. scenarios regression + new required clocks
with open(ROOT / "out" / "scenarios.csv", encoding="utf-8", newline="") as f:
    srows = list(csv.DictReader(f))
ck("scenarios_43_rows_unique", len(srows) == 43 and len({r["scenario_id"] for r in srows}) == 43)
need = ["required_clock_chain_25_mhz", "required_clock_core_25_mhz", "required_clock_chain_0_mhz"]
ck("scenarios_required_clock_columns", all(c in srows[0] for c in need))

num_fail, verdict_fail, clock_fail = [], [], []
for r in srows:
    w, h = int(r["W"]), int(r["H"])
    cores, streams = int(r["cores"]), int(r["streams"])
    fps, clk = float(r["fps"]), float(r["clock_mhz"]) * 1e6
    raw = raw_b(w, h)
    cc, cch = cyc_core(w, h), cyc_chain(w, h, 426385.0)
    capc, capch = CLOCK / CPB / 1e6 * (clk / CLOCK), cap(raw, cch, clk)
    d = raw * fps / 1e6
    psc, psch = ps_cap(capc, cores, streams), ps_cap(capch, cores, streams)
    mc, mch = psc / d - 1, psch / d - 1
    drop = max(0.0, 1 - psch / d)
    marginal, cons = (102 + 85, 102 + 85) if cores == 1 else (231, 289)
    timing = clk <= 187.5e6
    for nm, got, want, tol in (
            ("cyc_core", float(r["cycles_core_per_frame"]), cc, 2e-3),
            ("cyc_chain", float(r["cycles_chain_per_frame"]), cch, 2e-3),
            ("cap_core", float(r["capacity_core_MBps"]), capc, 2e-5),
            ("cap_chain", float(r["capacity_chain_MBps"]), capch, 2e-5),
            ("demand", float(r["demand_per_stream_MBps"]), d, 2e-5),
            ("m_core", float(r["margin_core_pct"]), 100 * mc, 3e-3),
            ("m_chain", float(r["margin_chain_pct"]), 100 * mch, 3e-3),
            ("drop", float(r["drop_rate_lb_pct"]), 100 * drop, 3e-3),
            ("ps_chain", float(r["per_stream_capacity_chain_MBps"]), psch, 2e-5)):
        if abs(got - want) > tol:
            num_fail.append("%s.%s" % (r["scenario_id"], nm))
    if int(r["eram_total"]) != marginal or int(r["resource_conservative_eram"]) != cons:
        num_fail.append(r["scenario_id"] + ".eram")
    if r["verdict"] != verdict_of(cores, mch, marginal, cons, timing):
        verdict_fail.append(r["scenario_id"])
    if r["gate_status"] != gate_of(mch):
        verdict_fail.append(r["scenario_id"] + ".gate")
    # required clock definition (rules.json required_clock = cycles*fps*1.25)
    if abs(float(r["required_clock_chain_25_mhz"]) - cch * fps * 1.25 / 1e6) > 1e-3:
        clock_fail.append(r["scenario_id"] + ".ch25")
    if abs(float(r["required_clock_core_25_mhz"]) - cc * fps * 1.25 / 1e6) > 1e-3:
        clock_fail.append(r["scenario_id"] + ".co25")
    if abs(float(r["required_clock_chain_0_mhz"]) - cch * fps / 1e6) > 1e-3:
        clock_fail.append(r["scenario_id"] + ".ch0")
ck("scenarios_all_43_numeric", not num_fail, str(num_fail[:6]))
ck("scenarios_all_43_verdicts", not verdict_fail, str(verdict_fail[:6]))
ck("scenarios_required_clocks_match_definition", not clock_fail, str(clock_fail[:6]))

counts = {}
for r in srows:
    counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
ck("regression_counts_8_22_13", counts == {"feasible": 8, "conditional": 22, "infeasible": 13}, str(counts))
ck("regression_no_dual_feasible", not [r["scenario_id"] for r in srows
                                       if int(r["cores"]) == 2 and r["verdict"] == "feasible"])
ck("regression_no_1080p30_feasible", not [r["scenario_id"] for r in srows
                                          if float(r["fps"]) == 30 and int(r["W"]) * int(r["H"]) == 2073600
                                          and r["verdict"] == "feasible"])
ck("per_stream_not_aggregate",
   all(abs(float(r["per_stream_capacity_chain_MBps"])
           - (float(r["capacity_chain_MBps"]) / 2 if (int(r["cores"]) == 1 and int(r["streams"]) == 2)
              else float(r["capacity_chain_MBps"]))) < 1e-6 for r in srows))
ck("feasible_all_chain_ge_25_and_cons_le_270",
   all(float(r["margin_chain_pct"]) >= 25 and int(r["resource_conservative_eram"]) <= 270
       for r in srows if r["verdict"] == "feasible"))
ck("core_only_never_used_for_feasible",
   not [r["scenario_id"] for r in srows if float(r["margin_core_pct"]) >= 25
        and float(r["margin_chain_pct"]) < 25 and r["verdict"] == "feasible"])

keys = {(int(r["W"]), int(r["H"]), float(r["fps"]), int(r["cores"]), int(r["streams"]),
         float(r["clock_mhz"])) for r in srows}
miss = []
for w, h in TIERS_30:
    for c in (1, 2):
        for s in (1, 2):
            if (w, h, 30.0, c, s, 187.5) not in keys:
                miss.append("%dx%d c%ds%d" % (w, h, c, s))
for fps in (30.0, 25.0, 24.0, 20.0, 15.0):
    for c in (1, 2):
        if (1920, 1080, fps, c, 2, 187.5) not in keys:
            miss.append("1080p %g c%ds2" % (fps, c))
for clk in (150.0, 175.0, 187.5, 200.0):
    if (1920, 1080, 30.0, 2, 2, clk) not in keys:
        miss.append("1080p30 c2s2 %gMHz" % clk)
ck("grid_still_complete_39", not miss, str(miss))

# ---------------------------------------------------------------- 3. DDR + content unchanged
with open(ROOT / "out" / "ddr-budget.csv", encoding="utf-8", newline="") as f:
    drows = list(csv.DictReader(f))
ddr_fail = []
for r in drows:
    w, h, st, fps = int(r["W"]), int(r["H"]), int(r["streams"]), float(r["fps"])
    raw = raw_b(w, h)
    d_total = raw * fps * st / 1e6
    exp = 1.0 if r["layout"] == "packed_1.0x_tight" else 1.6
    inc = r["includes_cmp_ddr"] == "true"
    cmp_b = raw + 5 * math.ceil(h / 2) + 6 + 44
    total = 2 * d_total * exp + (2 * cmp_b * fps * st / 1e6 if inc else 0.0)
    if abs(float(r["ddr_total_MBps"]) - total) > 2e-4 or abs(float(r["required_eff_pct"]) - total / 64) > 2e-3:
        ddr_fail.append(r["case_id"])
ck("ddr_7_cases_recomputed", len(drows) == 7 and not ddr_fail, str(ddr_fail))
ck("ddr_main_809_034_12_6412", any(r["case_id"] == "dual_1080p30_main"
                                    and abs(float(r["ddr_total_MBps"]) - 809.034) < 2e-4
                                    and abs(float(r["required_eff_pct"]) - 12.6412) < 2e-3 for r in drows))
with open(ROOT / "out" / "content-sensitivity.csv", encoding="utf-8", newline="") as f:
    crows = list(csv.DictReader(f))
ck("content_3_classes_recomputed",
   len(crows) == 3 and all(abs(float(r["capacity_MBps"])
                               - int(r["bytes"]) * 187.5e6 / int(r["cycles"]) / 1e6) < 2e-5 for r in crows)
   and {r["content_class"] for r in crows} == {"comp", "rand", "full_grad"})

# ---------------------------------------------------------------- 4. F2: overhead sensitivity (129 rows)
with open(ROOT / "out" / "overhead-sensitivity.csv", encoding="utf-8", newline="") as f:
    orows = list(csv.DictReader(f))
ck("sensitivity_129_rows", len(orows) == 129, str(len(orows)))
ck("sensitivity_43x3_coverage",
   sorted({(r["scenario_id"], float(r["overhead_tier_cycles"])) for r in orows})
   == sorted({(s["scenario_id"], t) for s in srows for t in TIERS})
   and len({r["scenario_id"] for r in orows}) == 43)
os_fail = []
by_sid = {}
for r in orows:
    by_sid.setdefault(r["scenario_id"], {})[float(r["overhead_tier_cycles"])] = r
    w, h = int(r["W"]), int(r["H"])
    cores, streams = int(r["cores"]), int(r["streams"])
    fps, clk, tier = float(r["fps"]), float(r["clock_mhz"]) * 1e6, float(r["overhead_tier_cycles"])
    anchor_geom = (w, h) == (1920, 1080)
    cc, cch = cyc_core(w, h), cyc_chain(w, h, tier)
    capch = cap(raw_b(w, h), cch, clk)
    d = raw_b(w, h) * fps / 1e6
    psch = ps_cap(capch, cores, streams)
    m = psch / d - 1
    marginal, cons = (187, 187) if cores == 1 else (231, 289)
    timing = clk <= 187.5e6
    if abs(float(r["cycles_chain_per_frame"]) - cch) > 2e-3:
        os_fail.append("%s@%d cycles" % (r["scenario_id"], tier))
    if abs(float(r["margin_chain_pct"]) - 100 * m) > 3e-3:
        os_fail.append("%s@%d margin" % (r["scenario_id"], tier))
    if r["gate_25"] != gate_of(m) or r["verdict"] != verdict_of(cores, m, marginal, cons, timing):
        os_fail.append("%s@%d gate/verdict" % (r["scenario_id"], tier))
    if anchor_geom and (r["applies"] != "false" or abs(float(r["cycles_chain_per_frame"]) - ANCHOR) > 2e-3):
        os_fail.append("%s@%d anchor" % (r["scenario_id"], tier))
    if not anchor_geom and r["applies"] != "true":
        os_fail.append("%s@%d applies" % (r["scenario_id"], tier))
ck("sensitivity_all_129_rows_recomputed", not os_fail, str(os_fail[:6]))
ck("sensitivity_1080p_tier_invariant",
   all(len({(x["cycles_chain_per_frame"], x["margin_chain_pct"]) for x in v.values()}) == 1
       for sid, v in by_sid.items()
       if (int(v[TIERS[0]]["W"]), int(v[TIERS[0]]["H"])) == (1920, 1080)))
# material values
ck("sensitivity_1600x900_36_18_21_05",
   abs(float(by_sid["1600x900-30fps-c1s1-187.5MHz"][426385.0]["margin_chain_pct"]) - 36.1774) < 2e-3
   and abs(float(by_sid["1600x900-30fps-c1s1-187.5MHz"][1000000.0]["margin_chain_pct"]) - 21.0486) < 2e-3
   and by_sid["1600x900-30fps-c1s1-187.5MHz"][1000000.0]["verdict"] == "conditional")
ck("sensitivity_1440x810_worst_42_95",
   abs(float(by_sid["1440x810-30fps-c1s1-187.5MHz"][1000000.0]["margin_chain_pct"]) - 42.9485) < 2e-3
   and all(x["verdict"] == "feasible" for x in by_sid["1440x810-30fps-c1s1-187.5MHz"].values()))
ck("sensitivity_1728_6_73",
   abs(float(by_sid["1728x972-30fps-c1s1-187.5MHz"][1000000.0]["margin_chain_pct"]) - 6.7286) < 2e-3)

# ---------------------------------------------------------------- 5. F1/F3: frontier same-source + clocks + worst tier
with open(ROOT / "out" / "frontier.csv", encoding="utf-8", newline="") as f:
    frows = list(csv.DictReader(f))
ck("frontier_16_rows", len(frows) == 16, str(len(frows)))
sby = {(int(r["W"]), int(r["H"]), float(r["fps"]), int(r["cores"]), int(r["streams"]),
        float(r["clock_mhz"])): r for r in srows}
f_fail = []
for r in frows:
    k = (int(r["W"]), int(r["H"]), float(r["fps"]), int(r["cores"]), int(r["streams"]), 187.5)
    s = sby.get(k)
    if s is None:
        f_fail.append("no scenario %s" % r["family"])
        continue
    basis = r["capacity_basis"]
    n_cores, n_streams = int(r["cores"]), int(r["streams"])
    cyc_c, cyc_ch = cyc_core(int(r["W"]), int(r["H"])), float(s["cycles_chain_per_frame"])
    fps = float(r["fps"])
    # same-source margin + gate (F1)
    if basis.startswith("core_only"):
        if abs(float(r["margin_pct"]) - float(s["margin_core_pct"])) > 1e-6 \
           or abs(float(r["margin_pct"]) - float(r["margin_core_pct"])) > 1e-6:
            f_fail.append("%s margin not core-source" % r["family"])
    else:
        if abs(float(r["margin_pct"]) - float(s["margin_chain_pct"])) > 1e-6:
            f_fail.append("%s margin not chain-source" % r["family"])
    if r["gate_25"] != gate_of(float(r["margin_pct"]) / 100.0):
        f_fail.append("%s gate mismatch" % r["family"])
    if abs(float(r["margin_chain_pct"]) - float(s["margin_chain_pct"])) > 1e-6 \
       or abs(float(r["margin_core_pct"]) - float(s["margin_core_pct"])) > 1e-6:
        f_fail.append("%s dual margin cols" % r["family"])
    # required clocks (F3) per rules definition
    if abs(float(r["required_clock_chain_25_mhz"]) - cyc_ch * fps * 1.25 / 1e6) > 1e-3 \
       or abs(float(r["required_clock_core_25_mhz"]) - cyc_c * fps * 1.25 / 1e6) > 1e-3:
        f_fail.append("%s required clock" % r["family"])
    # worst tier = min over tiers (anchor-fixed for 1080p); core-only rows use the tier-independent core margin
    if basis.startswith("core_only"):
        worst = float(s["margin_core_pct"]) / 100.0
    else:
        worst = min(ps_cap(cap(raw_b(int(r["W"]), int(r["H"])), cyc_chain(int(r["W"]), int(r["H"]), t),
                                CLOCK), n_cores, n_streams)
                    / (raw_b(int(r["W"]), int(r["H"])) * fps / 1e6) - 1 for t in TIERS)
    if abs(float(r["worst_tier_margin_pct"]) - 100 * worst) > 3e-3 \
       or r["worst_tier_gate"] != gate_of(worst):
        f_fail.append("%s worst tier" % r["family"])
    # verdict at primary tier (core-only rows are labelled upper-bound, not a verdict)
    if not basis.startswith("core_only"):
        marginal, cons = (187, 187) if n_cores == 1 else (231, 289)
        if r["verdict"] != verdict_of(n_cores, float(s["margin_chain_pct"]) / 100.0, marginal, cons, True):
            f_fail.append("%s verdict" % r["family"])
ck("frontier_all_16_rows_consistent", not f_fail, str(f_fail[:8]))
ck("frontier_core_only_no_contradiction",
   all(not (r["capacity_basis"].startswith("core_only") and r["margin_pct"] in ("16.7967", "18.3184"))
       for r in frows))
ck("frontier_1600_900_worst_21_0486_below",
   any(r["W"] == "1600" and r["H"] == "900" and abs(float(r["worst_tier_margin_pct"]) - 21.0486) < 2e-3
       and r["worst_tier_gate"] == "below_25" for r in frows))
rec_true = [r for r in frows if r["is_recommended"] == "true"]
ck("frontier_3_recommended", len(rec_true) == 3, str([(r["W"], r["H"], r["fps"]) for r in rec_true]))
ck("frontier_primary_1600x900",
   any(r["is_recommended"] == "true" and r["W"] == "1600" and r["H"] == "900" for r in frows))
ck("frontier_alternates_1440_1080p20",
   {(r["W"], r["H"], r["fps"]) for r in rec_true} == {("1600", "900", "30"), ("1440", "810", "30"),
                                                       ("1920", "1080", "20")})
ck("frontier_no_dual_recommended", not [r for r in rec_true if r["cores"] == "2"])
ck("frontier_robust_alt_1440_all_tiers",
   all(float(x) >= 25.0 for x in (42.9485, 64.5348, 85.3387)))

# maximality, independent
m25 = lambda r: float(r["margin_chain_pct"]) >= 25.0
best = lambda pred, key: sorted([r for r in srows if pred(r)], key=key)[-1]
r = best(lambda x: float(x["fps"]) == 30 and int(x["cores"]) == 1 and int(x["streams"]) == 1 and m25(x),
         key=lambda x: int(x["W"]) * int(x["H"]))
ck("maximal_30fps_chain_1600x900", (r["W"], r["H"]) == ("1600", "900"), r["scenario_id"])
r = best(lambda x: int(x["W"]) == 1920 and int(x["H"]) == 1080 and int(x["cores"]) == 1
         and int(x["streams"]) == 1 and m25(x), key=lambda x: float(x["fps"]))
ck("maximal_1080p_fps_20", float(r["fps"]) == 20.0, r["scenario_id"])
r = best(lambda x: float(x["fps"]) == 30 and int(x["cores"]) == 1 and int(x["streams"]) == 2 and m25(x),
         key=lambda x: int(x["W"]) * int(x["H"]))
ck("maximal_1c2s_960x540", (r["W"], r["H"]) == ("960", "540"), r["scenario_id"])
# largest 25%-at-all-tiers 30fps c1s1 tier = 1440x810
def all_tier_ok(w, h):
    return all(ps_cap(cap(raw_b(w, h), cyc_chain(w, h, t), CLOCK), 1, 1)
               / (raw_b(w, h) * 30 / 1e6) - 1 >= GATE for t in TIERS)
ck("robust_tier_1440x810_is_largest", all_tier_ok(1440, 810) and not all_tier_ok(1600, 900)
   and not all_tier_ok(1728, 972))

# ---------------------------------------------------------------- 6. report <-> CSV and disclosures
report = (ROOT / "feasibility-report.md").read_text(encoding="utf-8")
tbl = {}
for line in report.splitlines():
    if not line.startswith("| "):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) == 13 and cells[0] in {x["scenario_id"] for x in srows}:
        tbl[cells[0]] = cells
ck("report_table_43_rows", len(tbl) == 43, str(len(tbl)))
rfail = []
for x in srows:
    if x["scenario_id"] not in tbl:
        rfail.append("missing " + x["scenario_id"])
        continue
    want = [x["scenario_id"], x["cores"], x["streams"], x["W"] + "×" + x["H"], x["fps"], x["clock_mhz"],
            x["capacity_core_MBps"], x["capacity_chain_MBps"], x["margin_core_pct"],
            x["margin_chain_pct"], x["drop_rate_lb_pct"], x["gate_status"], x["verdict"]]
    if tbl[x["scenario_id"]] != want:
        rfail.append(x["scenario_id"])
ck("report_table_cells_equal_csv", not rfail, str(rfail[:5]))
# section 9 frontier table (16 columns)
ftbl = {}
for line in report.splitlines():
    if not line.startswith("| "):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) == 16 and cells[0] in {x["family"] for x in frows}:
        ftbl[(cells[0], cells[1], cells[2], cells[3], cells[4], cells[5])] = cells
ck("report_frontier_table_16_rows", len(ftbl) == 16, str(len(ftbl)))
ffail = []
for x in frows:
    key = (x["family"], x["cores"], x["streams"], x["W"] + "×" + x["H"], x["fps"], x["clock_mhz"])
    if key not in ftbl:
        ffail.append(str(key))
        continue
    c = ftbl[key]
    if (c[7], c[8], c[11], c[12], c[13], c[14]) != (x["margin_pct"], x["gate_25"], x["verdict"],
                                                    x["is_recommended"], x["required_clock_chain_25_mhz"],
                                                    x["required_clock_core_25_mhz"]):
        ffail.append(str(key))
ck("report_frontier_cells_equal_csv", not ffail, str(ffail[:5]))
ck("report_discloses_21_0486", "21.0486" in report and "conditional" in report)
ck("report_discloses_robust_1440_42_9485", "1440×810" in report and "42.9485" in report)
ck("report_primary_conditional_wording",
   "主推荐（带条件）" in report and "不是无条件 feasible" in report)
ck("report_required_clocks_present",
   all(t in report for t in ("172.1100", "156.1206", "142.4471", "126.4577", "160.5353", "149.8757")))
ck("report_tier_table_3_tiers",
   all(t in report for t in ("| 0 cycles |", "| 426385 cycles |", "| 1000000 cycles |")))
ck("report_overhead_tier_thresholds", "836785" in report and "1627796" in report)
ck("report_1c2s_eram_disclosure", "208/300" in report and "bridge 15" in report)
ck("report_counts_8_22_13",
   "feasible **8**" in report and "conditional **22**" in report and "infeasible **13**" in report)
ck("report_dual_max_conditional", "最高只能判 `conditional`" in report)
ck("report_g2g4_not_applicable", "G2/G3/G4 not_applicable" in report)
ck("report_drop_and_ddr", "drop_rate_lb" in report and "809.034000" in report and "12.6412" in report)
ck("report_csi_sensitivity", all(t in report for t in ("26,822", "35,815", "32,083")))
ck("report_sidecar_hash",
   hashlib.sha256(report.encode("utf-8")).hexdigest()
   == re.search(r"sha256=([0-9a-f]{64})", (ROOT / "logs" / "report.sha256").read_text(encoding="utf-8")).group(1))

# ---------------------------------------------------------------- 7. negative controls (still rejected)
NEG = r'''
import json, sys
sys.dont_write_bytecode = True
sys.path.insert(0, r"MODELDIR")
import calc
rules = json.load(open(r"RULESFILE", encoding="utf-8"))
out = []
def run(name, fn, code):
    try:
        fn()
    except calc.ModelRejected as e:
        out.append((name, "REJECTED", str(e), str(e) == code)); return
    except Exception as e:
        out.append((name, "OTHER", type(e).__name__, False)); return
    out.append((name, "ACCEPTED", "", False))
run("NEG-01a", lambda: calc.validate_packing("RAW12_1.0x",1920,1080,3110400,3110400), "PACKING_PROFILE_REJECTED")
run("NEG-01b", lambda: calc.validate_packing("RAW10_packed_20B32B",1920,1080,2592000,2592000), "PACKING_MISMATCH")
run("NEG-02a", lambda: calc.validate_per_stream_claim(2,2,162.134318,75.684265,77.76,"feasible",rules), "AGGREGATE_CAPACITY_FOR_PER_STREAM")
run("NEG-02b", lambda: calc.validate_per_stream_claim(2,2,75.684265,75.684265,77.76,"feasible",rules), "FEASIBLE_CLAIM_BELOW_PER_STREAM_GATE")
run("NEG-03", lambda: calc.validate_resource_stage("synth"), "STAGE_MIX_SYNTH_IN_FIT")
print(json.dumps(out))
'''
import re  # noqa: E402  (used above)
neg = Path(__file__).resolve().parent / "_negctl_r1_tmp.py"
neg.write_text(NEG.replace("MODELDIR", str(ROOT / "model")).replace("RULESFILE", str(ROOT / "model" / "rules.json")),
               encoding="utf-8")
proc = subprocess.run([sys.executable, "-B", str(neg)], capture_output=True, text=True, timeout=120,
                      env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
try:
    res = json.loads(proc.stdout.strip().splitlines()[-1])
except Exception:
    res = []
print("NEGCTL rc=%d %s" % (proc.returncode, proc.stdout.strip()))
ck("negative_controls_5_rejected", len(res) == 5 and all(x[1] == "REJECTED" and x[3] for x in res), str(res))
ck("negctl_semantic_raw12_1p0x", 3110400 != raw_b(1920, 1080) and 2592000 != math.ceil((1920 * 1080 / 4) / 4) * 32)
ck("negctl_semantic_aggregate", 2 * 81.067159 >= 155.52 and 2 * cap(raw_b(1920, 1080), ANCHOR, CLOCK) < 155.52)
try:
    neg.unlink()
except OSError:
    pass

print()
print("INDEPENDENT_R1_SUMMARY checks_failed=%d" % len(FAILS))
for n, d in FAILS:
    print("  FAILED:", n, "|", d)
sys.exit(1 if FAILS else 0)
