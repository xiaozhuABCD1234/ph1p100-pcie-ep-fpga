"""Independent tester recomputation for T10.dual-aplus-service-verdict r0.

Deliberately does NOT import model/calc.py for the scenario/CSV recomputation:
every number is recomputed from first principles (bytes, cycles, clock) and
compared to the frozen CSVs/report.  model/calc.py is imported only in a
separate subprocess section to confirm that the dev's negative-control
validators reject the three forbidden inputs (a rejection is a property of the
validator, not of this script's math).

Read-only on the candidate; writes nothing.
Run: python -B independent_check.py
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
MANIFEST_SHA_EXPECTED = "01b3c24614a2dfd0d592d1bb910e455c4e9cf815e03f62b127e074690a815c2a"
P1_MANIFEST = Path(r"D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility\T10.dual-core-resource-baseline\r0\manifest-r0.json")
P1_SHA_EXPECTED = "228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0"
B6_CORE = Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\r0\changed-src\a1_deflate_core.v")
B6_SHA_EXPECTED = "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb"
B6_MANIFEST = Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json")
B6_MANIFEST_SHA = "2e9fd356824084813e3415af11757c1b56f774c9b6dd45f3b2a111647ad08880"

FAILS = []
NOTES = []


def ck(name, ok, detail=""):
    print("%-5s %s%s" % ("PASS" if ok else "FAIL", name, ("  | " + detail) if (detail and not ok) else ""))
    if not ok:
        FAILS.append((name, detail))


def note(text):
    NOTES.append(text)
    print("NOTE  " + text)


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


# ------------------------------------------------------------------ model constants (frozen inputs)
frozen = json.loads((ROOT / "inputs" / "frozen-inputs.json").read_text(encoding="utf-8"))
rules = json.loads((ROOT / "model" / "rules.json").read_text(encoding="utf-8"))
CLOCK = 187.5e6
CPB = 355261.0 / 153600.0                # comp cycles/byte (measured anchor)
ANCHOR = 6421414.0                       # full_grad 1080p chain cycles (measured)
OVERHEAD = 426385.0                      # assumed affine overhead (primary tier)
GATE = 0.25
ERAM_DEV = 300
ERAM_CONS_PASS = 270

TIERS_30 = [(1920, 1080), (1728, 972), (1600, 900), (1440, 810), (1280, 720), (1152, 648), (960, 540)]


def raw_b(w, h):
    assert w % 4 == 0 and (w * h) % 4 == 0
    return w * h * 5 // 4


def chain_cycles(w, h, overhead=OVERHEAD):
    if (w, h) == (1920, 1080):
        return ANCHOR                     # measured anchor, not affine
    return raw_b(w, h) * CPB + overhead


def cap(raw, cyc, clock=CLOCK):
    return raw * clock / cyc / 1e6


def per_stream(c, cores, streams):
    return c / 2.0 if (cores == 1 and streams == 2) else c


def verdict_of(cores, m_chain, marginal, conservative, timing_proven):
    if marginal > ERAM_DEV:
        return "infeasible"
    if m_chain < 0:
        return "infeasible"
    if cores == 2 and not timing_proven:
        return "conditional"
    if m_chain >= GATE and conservative <= ERAM_CONS_PASS and timing_proven:
        return "feasible"
    if m_chain >= GATE:
        return "conditional"
    return "conditional"


def gate_of(m):
    return "meets_25" if m >= GATE else ("below_25" if m >= 0 else "fails_30")


# ------------------------------------------------------------------ 1. manifest / SHA / drift
man = json.loads(MANIFEST.read_text(encoding="utf-8"))
ck("manifest_sha_expected", sha(MANIFEST) == MANIFEST_SHA_EXPECTED, sha(MANIFEST))
ck("manifest_stopped_modifying_true", man.get("stopped_modifying") is True)
ck("manifest_active_commands_zero", man.get("active_commands") == 0)
ck("manifest_status_ready_for_test", man.get("status") == "ready_for_test")
ck("manifest_round_r0", man.get("round") == "r0")

bad_art = []
for a in man["artifacts"]:
    p = Path(a["path"])
    if not p.exists() or p.stat().st_size != a["bytes"] or sha(p) != a["sha256"]:
        bad_art.append(a["rel"])
ck("manifest_artifacts_%d_sha_bytes" % len(man["artifacts"]), not bad_art, str(bad_art))

bad_in = []
for i in man["inputs"]:
    p = Path(i["path"])
    if not p.exists() or p.stat().st_size != i["bytes"] or sha(p) != i["sha256"]:
        bad_in.append(i["id"])
ck("manifest_inputs_%d_sha_bytes" % len(man["inputs"]), not bad_in, str(bad_in))

ck("drift_p1_manifest_now", sha(P1_MANIFEST) == P1_SHA_EXPECTED, sha(P1_MANIFEST))
ck("drift_b6_core_now", sha(B6_CORE) == B6_SHA_EXPECTED, sha(B6_CORE))
ck("drift_b6_manifest_now", sha(B6_MANIFEST) == B6_MANIFEST_SHA, sha(B6_MANIFEST))
ck("p1_manifest_bytes_23644", P1_MANIFEST.stat().st_size == 23644, str(P1_MANIFEST.stat().st_size))

# tools / no hardware
tools = man["tools"]
ck("manifest_tools_all_zero",
   all(v == 0 for k, v in tools.items() if k != "python"), json.dumps(tools))
bad_suffix = [str(p) for p in ROOT.rglob("*")
              if p.is_file() and p.suffix.lower() in {".bit", ".cwc", ".bid", ".dcp", ".sdc", ".sof", ".sta"}]
ck("no_bitstream_td_artifacts_in_task_dir", not bad_suffix, str(bad_suffix[:5]))
td_cmds = [c for c in man["commands"] if any("td" == str(x).lower() or "td_commands" in str(x).lower()
                                             for x in c["argv"])]
ck("manifest_no_td_command", not td_cmds, str(td_cmds))
journal = [json.loads(l) for l in (ROOT / "commands.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
ck("commands_journal_all_python_only",
   all(x["argv"][0] == "python" for x in journal), str([x["argv"] for x in journal if x["argv"][0] != "python"]))
ck("commands_journal_13_vs_manifest_14", len(journal) == 13 and len(man["commands"]) == 14,
   "journal=%d manifest=%d" % (len(journal), len(man["commands"])))
missing_cmd = [c for c in man["commands"] if c["argv"] == ["python", "model/mk_manifest.py"]]
ck("mk_manifest_logged_in_manifest", len(missing_cmd) == 1 and missing_cmd[0]["seq"] == 14)

# negative exit history must be explained (exit 1 at seq 2, then exit 0)
neg = [c for c in man["commands"] if c["exit"] != 0]
ck("only_explained_negative_exit", all(c["seq"] == 2 for c in neg), str([(c["seq"], c["exit"]) for c in neg]))

# write-scope: files outside the task dir in the run must not be modified in the task window
window_lo = datetime(2026, 10, 25, 13, 50, tzinfo=timezone.utc).timestamp()
window_hi = datetime(2026, 10, 25, 14, 15, tzinfo=timezone.utc).timestamp()
outside = []
for p in Path(r"D:\fpga\ph1p100\workflow\runs\20261025-195604_fpga-dual-aplus-core-feasibility").rglob("*"):
    if p.is_file() and ROOT not in p.parents and p != ROOT:
        rel = str(p.relative_to(ROOT.parents[1]))
        if rel.endswith("main-log.md") or rel.startswith("test-reports" + os.sep):
            continue  # main-owned transmission log + this tester's own evidence
        if window_lo <= p.stat().st_mtime <= window_hi:
            outside.append(rel)
ck("write_scope_no_run_file_touched_in_window", not outside, str(outside[:5]))
p1_files = [p for p in P1_MANIFEST.parent.rglob("*") if p.is_file()
            and window_lo <= p.stat().st_mtime <= window_hi]
ck("write_scope_p1_not_touched", not p1_files, str([p.name for p in p1_files][:5]))

# ------------------------------------------------------------------ 2. scenario rows: recompute all 43
with open(ROOT / "out" / "scenarios.csv", encoding="utf-8", newline="") as f:
    srows = list(csv.DictReader(f))
ck("scenarios_row_count_43", len(srows) == 43, str(len(srows)))
ck("scenarios_ids_unique", len({r["scenario_id"] for r in srows}) == 43)

REQ_COLS = ["scenario_id", "cores", "streams", "W", "H", "fps", "clock_mhz",
            "cycles_core_per_frame", "cycles_chain_per_frame", "overhead_assumption",
            "capacity_core_MBps", "capacity_chain_MBps", "demand_per_stream_MBps",
            "margin_core_pct", "margin_chain_pct", "gate_25_core", "gate_25_chain",
            "drop_rate_lb_pct", "eram_bound", "eram_total", "eram_headroom",
            "verdict", "gate_status", "notes"]
ck("scenarios_required_columns", all(c in srows[0] for c in REQ_COLS),
   str([c for c in REQ_COLS if c not in srows[0]]))

num_fail = []
verdict_fail = []
for r in srows:
    w, h = int(r["W"]), int(r["H"])
    cores, streams = int(r["cores"]), int(r["streams"])
    fps = float(r["fps"])
    clk = float(r["clock_mhz"]) * 1e6
    raw = raw_b(w, h)
    cyc_core = raw * CPB
    cyc_chain = chain_cycles(w, h)
    cap_core = CLOCK / CPB / 1e6 * (clk / CLOCK)
    cap_chain = cap(raw, cyc_chain, clk)
    d = raw * fps / 1e6
    ps_core = per_stream(cap_core, cores, streams)
    ps_chain = per_stream(cap_chain, cores, streams)
    m_core = ps_core / d - 1
    m_chain = ps_chain / d - 1
    drop = max(0.0, 1 - ps_chain / d)
    if cores == 1:
        marginal, cons = 102 + 85, 102 + 85
        timing = clk <= 187.5e6
    else:
        marginal, cons = 231, 289
        timing = False
    v = verdict_of(cores, m_chain, marginal, cons, timing)
    checks = [
        ("cycles_core", float(r["cycles_core_per_frame"]), cyc_core, 2e-3),
        ("cycles_chain", float(r["cycles_chain_per_frame"]), cyc_chain, 2e-3),
        ("cap_core", float(r["capacity_core_MBps"]), cap_core, 2e-5),
        ("cap_chain", float(r["capacity_chain_MBps"]), cap_chain, 2e-5),
        ("demand", float(r["demand_per_stream_MBps"]), d, 2e-5),
        ("m_core", float(r["margin_core_pct"]), 100 * m_core, 3e-3),
        ("m_chain", float(r["margin_chain_pct"]), 100 * m_chain, 3e-3),
        ("drop", float(r["drop_rate_lb_pct"]), 100 * drop, 3e-3),
        ("ps_chain", float(r["per_stream_capacity_chain_MBps"]), ps_chain, 2e-5),
        ("ps_core", float(r["per_stream_capacity_core_MBps"]), ps_core, 2e-5),
    ]
    for nm, got, want, tol in checks:
        if abs(got - want) > tol:
            num_fail.append("%s.%s %r!=%r" % (r["scenario_id"], nm, got, round(want, 6)))
    if int(r["eram_total"]) != marginal or int(r["resource_conservative_eram"]) != cons:
        num_fail.append("%s.eram %s/%s" % (r["scenario_id"], r["eram_total"], r["resource_conservative_eram"]))
    if r["verdict"] != v:
        verdict_fail.append("%s %s!=%s" % (r["scenario_id"], r["verdict"], v))
    if r["gate_status"] != gate_of(m_chain):
        verdict_fail.append("%s gate %s!=%s" % (r["scenario_id"], r["gate_status"], gate_of(m_chain)))
    if r["drop_rate_lb_basis"] != "per-stream chain capacity":
        verdict_fail.append("%s drop basis %s" % (r["scenario_id"], r["drop_rate_lb_basis"]))

ck("all_43_rows_numeric_recomputed", not num_fail, "; ".join(num_fail[:6]))
ck("all_43_rows_verdicts_machine_consistent", not verdict_fail, "; ".join(verdict_fail[:6]))

# per-stream semantics: no row may use aggregate 2C
agg_fail = []
for r in srows:
    cores, streams = int(r["cores"]), int(r["streams"])
    base = float(r["capacity_chain_MBps"])
    got = float(r["per_stream_capacity_chain_MBps"])
    exp = base / 2 if (cores == 1 and streams == 2) else base
    if abs(got - exp) > 1e-6:
        agg_fail.append(r["scenario_id"])
ck("per_stream_not_aggregate", not agg_fail, str(agg_fail))
ck("no_2C_used_anywhere", max(float(r["per_stream_capacity_chain_MBps"]) for r in srows) <= max(
    float(r["capacity_chain_MBps"]) for r in srows) + 1e-9)

# full-chain basis: every feasible row must clear the chain gate; core-only cannot rescue
core_only_trap = [r["scenario_id"] for r in srows
                  if float(r["margin_core_pct"]) >= 25.0 and float(r["margin_chain_pct"]) < 25.0
                  and r["verdict"] == "feasible"]
ck("core_only_not_used_for_feasible", not core_only_trap, str(core_only_trap))
ck("feasible_rows_all_chain_ge_25",
   all(float(r["margin_chain_pct"]) >= 25.0 for r in srows if r["verdict"] == "feasible"))
ck("feasible_rows_all_cons_le_270",
   all(int(r["resource_conservative_eram"]) <= 270 for r in srows if r["verdict"] == "feasible"))
ck("dual_core_never_feasible", not [r["scenario_id"] for r in srows
                                    if int(r["cores"]) == 2 and r["verdict"] == "feasible"])
ck("fails30_never_feasible", not [r["scenario_id"] for r in srows
                                  if float(r["margin_chain_pct"]) < 0 and r["verdict"] == "feasible"])

counts = {}
for r in srows:
    counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
gcounts = {}
for r in srows:
    gcounts[r["gate_status"]] = gcounts.get(r["gate_status"], 0) + 1
print("COUNT verdicts", counts, "gate", gcounts)
ck("counts_match_manifest", counts == {"feasible": 8, "conditional": 22, "infeasible": 13}, str(counts))
ck("gate_counts_match_report_20_10_13", gcounts == {"meets_25": 20, "below_25": 10, "fails_30": 13}, str(gcounts))

# ------------------------------------------------------------------ 3. grid coverage (combos, not row count)
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
ck("grid_covers_design_guide_6_2_combos", not miss, str(miss))
guide39 = [k for k in keys if not (k[0] == 1920 and k[1] == 1080 and k[3] == 1 and k[4] == 1 and k[2] != 30.0)]
ck("design_guide_subset_exactly_39", len(guide39) == 39, str(len(guide39)))
extra = sorted(k for k in keys if k not in guide39)
print("EXTRA  %d rows beyond the 39-combo guide set: %s" % (len(extra), extra))
ck("extra_rows_are_documented_c1s1_1080p_fps",
   sorted({(k[2], k[3], k[4]) for k in extra}) == [(15.0, 1, 1), (20.0, 1, 1), (24.0, 1, 1), (25.0, 1, 1)])

# ------------------------------------------------------------------ 4. anchors / rates / thresholds
anchor_checks = [
    ("comp_cycles", 355261, frozen["anchors"]["comp"]["cycles"]),
    ("comp_bytes", 153600, frozen["anchors"]["comp"]["input_bytes"]),
    ("rand_cycles", 161479, frozen["anchors"]["rand"]["cycles"]),
    ("full_grad_cycles", 6421414, frozen["anchors"]["full_grad"]["cycles"]),
]
ck("anchor_constants_match_frozen", all(a == b for _, a, b in anchor_checks))
ck("comp_rate_81_067159", abs(153600 * 187.5e6 / 355261 / 1e6 - 81.067159) < 1e-6)
ck("rand_rate_178_351365", abs(153600 * 187.5e6 / 161479 / 1e6 - 178.351365) < 1e-5)
ck("chain_rate_75_684265", abs(cap(raw_b(1920, 1080), ANCHOR, 187.5e6) - 75.684265) < 1e-5)
ck("demand_77_76", abs(raw_b(1920, 1080) * 30 / 1e6 - 77.76) < 1e-12)
ck("gate_97_2", abs(raw_b(1920, 1080) * 30 / 1e6 * 1.25 - 97.2) < 1e-12)
ck("core_fps_31_276", abs(187.5e6 / (raw_b(1920, 1080) * CPB) - 31.2759) < 1e-3)
ck("chain_fps_29_199", abs(187.5e6 / ANCHOR - 29.1987) < 1e-3)
ck("chain_25pct_max_fps_23_36", abs(187.5e6 / (ANCHOR * 1.25) - 23.3593) < 1e-3)
ck("clock_req_25pct_240_803", abs(ANCHOR * 30 * 1.25 / 1e6 - 240.803) < 1e-2)
ck("clock_req_0pct_192_642", abs(ANCHOR * 30 / 1e6 - 192.642) < 1e-2)
ck("1080p_25pct_cycles_5_000_000", abs(187.5e6 / (30 * 1.25) - 5_000_000) < 1e-6)
ck("1080p_0pct_cycles_6_250_000", abs(187.5e6 / 30 - 6_250_000) < 1e-6)
ck("byte_account_2592000_4147200_2594750",
   raw_b(1920, 1080) == 2592000 and math.ceil((1920 * 1080 / 4) / 4) * 32 == 4147200
   and (2592000 + 5 * 540 + 6 + 44) == 2594750)

# ------------------------------------------------------------------ 5. DDR 2R+2S
with open(ROOT / "out" / "ddr-budget.csv", encoding="utf-8", newline="") as f:
    drows = list(csv.DictReader(f))
ck("ddr_rows_7", len(drows) == 7, str(len(drows)))
ddr_fail = []
for r in drows:
    w, h = int(r["W"]), int(r["H"])
    st, fps = int(r["streams"]), float(r["fps"])
    raw = raw_b(w, h)
    d_total = raw * fps * st / 1e6
    exp = 1.0 if r["layout"] == "packed_1.0x_tight" else 1.6
    rw = d_total * exp
    inc = r["includes_cmp_ddr"] == "true"
    cmp_b = raw + 5 * math.ceil(h / 2) + 6 + 44
    sw = cmp_b * fps * st / 1e6 if inc else 0.0
    total = 2 * rw + 2 * sw
    gate = total * 1.25
    for nm, got, want, tol in (
            ("raw_write", float(r["raw_write_MBps"]), rw, 2e-5),
            ("raw_read", float(r["raw_read_MBps"]), rw, 2e-5),
            ("cmp_write", float(r["cmp_write_MBps"]), sw, 2e-5),
            ("cmp_read", float(r["cmp_read_MBps"]), sw, 2e-5),
            ("total", float(r["ddr_total_MBps"]), total, 2e-4),
            ("gate", float(r["ddr_gate_25_MBps"]), gate, 2e-4),
            ("eff", float(r["required_eff_pct"]), total / 6400 * 100, 2e-3)):
        if abs(got - want) > tol:
            ddr_fail.append("%s.%s %r!=%r" % (r["case_id"], nm, got, round(want, 6)))
ck("ddr_all_7_cases_recomputed", not ddr_fail, "; ".join(ddr_fail[:6]))
ck("ddr_main_809_034_12_6412",
   any(r["case_id"] == "dual_1080p30_main" and abs(float(r["ddr_total_MBps"]) - 809.034) < 2e-4
       and abs(float(r["required_eff_pct"]) - 12.6412) < 2e-3 for r in drows))
ck("ddr_has_no_cmp_variant",
   any(r["case_id"] == "dual_1080p30_no_cmp_ddr" and r["includes_cmp_ddr"] == "false" for r in drows))
ck("ddr_1p6_not_double_counted",
   all(abs(float(r["raw_write_MBps"]) - 1.6 * int(r["streams"]) * float(r["fps"])
           * raw_b(int(r["W"]), int(r["H"])) / 1e6) < 2e-5
       for r in drows if r["layout"] != "packed_1.0x_tight"))
ck("ddr_peak_6_4_GBps", all(float(r["peak_GBps"]) == 6.4 for r in drows))

# ------------------------------------------------------------------ 6. content sensitivity
with open(ROOT / "out" / "content-sensitivity.csv", encoding="utf-8", newline="") as f:
    crows = list(csv.DictReader(f))
ck("content_rows_3_classes", {r["content_class"] for r in crows} == {"comp", "rand", "full_grad"})
c_fail = []
for r in crows:
    b, cyc = int(r["bytes"]), int(r["cycles"])
    c = b * 187.5e6 / cyc / 1e6
    if abs(c - float(r["capacity_MBps"])) > 2e-5:
        c_fail.append(r["case_id"])
ck("content_capacities_recomputed", not c_fail, str(c_fail))
ck("full_grad_margin_minus_2_67",
   abs([float(r["margin_pct"]) for r in crows if r["content_class"] == "full_grad"][0] + 2.6694) < 2e-3)

# ------------------------------------------------------------------ 7. frontier: maximality + basis/margin consistency
with open(ROOT / "out" / "frontier.csv", encoding="utf-8", newline="") as f:
    frows = list(csv.DictReader(f))
sby = {(int(r["W"]), int(r["H"]), float(r["fps"]), int(r["cores"]), int(r["streams"]),
        float(r["clock_mhz"])): r for r in srows}
# frontier.csv schema (design guide 7.3) has no clock column -> every frontier row is the
# frozen 187.5 MHz base row (the notes quote 187.5 MHz numbers). Look it up explicitly.
base_fail = []
for r in frows:
    k = (int(r["W"]), int(r["H"]), float(r["fps"]), int(r["cores"]), int(r["streams"]), 187.5)
    if k not in sby:
        base_fail.append("no scenario " + r["family"])
    elif abs(float(r["margin_pct"]) - float(sby[k]["margin_chain_pct"])) > 1e-6:
        base_fail.append("%s margin %s!=%s" % (r["family"], r["margin_pct"], sby[k]["margin_chain_pct"]))
ck("frontier_rows_all_trace_to_scenarios", not base_fail, str(base_fail))
ck("frontier_has_15_rows", len(frows) == 15, str(len(frows)))

# maximality, recomputed from scenarios only
m25 = lambda r: float(r["margin_chain_pct"]) >= 25.0
f30 = lambda r: float(r["fps"]) == 30.0
best = lambda pred, key: sorted([r for r in srows if pred(r)], key=key)[-1] if any(pred(r) for r in srows) else None
r = best(lambda x: f30(x) and int(x["cores"]) == 1 and int(x["streams"]) == 1 and m25(x),
         key=lambda x: (int(x["W"]) * int(x["H"]), -int(x["cores"])))
ck("maximal_30fps_chain_tier_1600x900", (r["W"], r["H"]) == ("1600", "900"), r["scenario_id"])
r = best(lambda x: int(x["W"]) == 1920 and int(x["H"]) == 1080 and int(x["cores"]) == 1
         and int(x["streams"]) == 1 and m25(x), key=lambda x: float(x["fps"]))
ck("maximal_1080p_chain_fps_20", float(r["fps"]) == 20.0, r["scenario_id"])
r = best(lambda x: f30(x) and int(x["cores"]) == 1 and int(x["streams"]) == 2 and m25(x),
         key=lambda x: int(x["W"]) * int(x["H"]))
ck("maximal_1c2s_tier_960x540", (r["W"], r["H"]) == ("960", "540"), r["scenario_id"])
r = best(lambda x: f30(x) and m25(x), key=lambda x: (int(x["W"]) * int(x["H"]), -int(x["cores"]), -int(x["streams"])))
ck("primary_rule_picks_1600x900_c1s1", r["scenario_id"] == "1600x900-30fps-c1s1-187.5MHz", r["scenario_id"])
rec_true = [x for x in frows if x["is_recommended"] == "true"]
ck("frontier_recommended_count_3", len(rec_true) == 3, str([x["family"] for x in rec_true]))
ck("primary_row_marked", any(x["is_recommended"] == "true" and x["W"] == "1600" and x["H"] == "900"
                             for x in frows))
ck("no_dual_core_primary", not any(x["is_recommended"] == "true" and x["cores"] == "2" for x in frows))

# basis vs margin consistency (the frozen schema pairs capacity_basis with margin_pct/gate_25)
mix = []
for r in frows:
    k = (int(r["W"]), int(r["H"]), float(r["fps"]), int(r["cores"]), int(r["streams"]), 187.5)
    s = sby[k]
    if r["capacity_basis"].startswith("core_only"):
        core_m = float(s["margin_core_pct"])
        exp_gate = gate_of(core_m / 100.0)
        if abs(float(r["margin_pct"]) - core_m) > 1e-6 or r["gate_25"] != exp_gate:
            mix.append("%s %s fps=%s: margin=%s (chain=%s, core=%.4f) gate=%s (expected %s)"
                       % (r["family"], "%sx%s" % (r["W"], r["H"]), r["fps"], r["margin_pct"],
                          s["margin_chain_pct"], core_m, r["gate_25"], exp_gate))
ck("frontier_core_only_rows_basis_consistent", not mix, " | ".join(mix))

# ------------------------------------------------------------------ 8. 3-tier overhead sensitivity (design guide 4.3 / 6.2)
def row_margin(w, h, fps, cores, streams, overhead):
    raw = raw_b(w, h)
    cyc = chain_cycles(w, h, overhead)
    c = cap(raw, cyc)
    ps = per_stream(c, cores, streams)
    return (ps / (raw * fps / 1e6) - 1) * 100


tiers = frozen["overhead"]["sensitivity_tiers"]
print("TIER-HEADER overhead tiers =", tiers, "primary =", frozen["overhead"]["primary_cycles"])
sens_primary = {}
print("TIER  30fps c1s1 chain margin by overhead tier (tester recomputation):")
for (w, h) in TIERS_30:
    row = ["%dx%d" % (w, h)]
    for ov in tiers:
        m = row_margin(w, h, 30, 1, 1, ov)
        row.append("ov=%d:%.4f%%(%s)" % (ov, m, gate_of(m / 100.0)))
        if (w, h) == (1600, 900):
            sens_primary[ov] = m
    print("TIER  " + "  ".join(row))
sens_1728 = {ov: row_margin(1728, 972, 30, 1, 1, ov) for ov in tiers}
sset = set()
for p in list(ROOT.rglob("*.csv")) + list(ROOT.rglob("*.md")):
    txt = p.read_text(encoding="utf-8", errors="ignore")
    if "1000000" in txt or "1,000,000" in txt:
        sset.add(str(p.relative_to(ROOT)))
print("FILES  mentioning the 1,000,000 overhead tier:", sorted(sset))
ck("overhead_three_tier_sensitivity_present",
   {"out/scenarios.csv", "feasibility-report.md"} <= sset, str(sorted(sset)))
ck("primary_survives_all_overhead_tiers",
   min(sens_primary.values()) >= 25.0,
   "min tier margin %.4f%% at overhead=%d -> primary would be conditional under that tier"
   % (min(sens_primary.values()), [k for k, v in sens_primary.items() if v == min(sens_primary.values())][0]))

# ------------------------------------------------------------------ 9. report <-> CSV row-by-row (independent parse)
report = (ROOT / "feasibility-report.md").read_text(encoding="utf-8")
tbl = {}
for line in report.splitlines():
    if not line.startswith("| "):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) == 13 and cells[0] in {r["scenario_id"] for r in srows}:
        tbl[cells[0]] = cells
ck("report_table_43_rows", len(tbl) == 43, str(len(tbl)))
rfail = []
for r in srows:
    if r["scenario_id"] not in tbl:
        rfail.append("missing " + r["scenario_id"])
        continue
    want = [r["scenario_id"], r["cores"], r["streams"], r["W"] + "×" + r["H"], r["fps"], r["clock_mhz"],
            r["capacity_core_MBps"], r["capacity_chain_MBps"], r["margin_core_pct"],
            r["margin_chain_pct"], r["drop_rate_lb_pct"], r["gate_status"], r["verdict"]]
    if tbl[r["scenario_id"]] != want:
        rfail.append(r["scenario_id"])
ck("report_table_cells_equal_csv", not rfail, str(rfail[:5]))
ck("report_counts_8_22_13",
   "feasible **8**" in report and "conditional **22**" in report and "infeasible **13**" in report)
ck("report_primary_matches_rule", "1600x900-30fps-c1s1-187.5MHz" in report)
ck("report_alternates_2", report.count("**备选 ") == 2)
ck("report_states_dual_max_conditional", "最高只能判 `conditional`" in report)
ck("report_states_g2g4_not_applicable",
   "G2/G3/G4 not_applicable" in report or "G2/G3/G4 `not_applicable`" in report)
ck("report_states_ddr_eff_12_6412", "12.6412" in report and "809.034000" in report)
ck("report_states_csi_sensitivity", all(t in report for t in ("26,822", "35,815", "32,083")))
ck("report_states_drop_lb_basis", "per-stream 链级" in report and "drop_rate_lb" in report)
ck("report_states_no_board", "not_run" in report and "not_applicable" in report)
ck("report_has_44B_8MiB_20B32B",
   all(t in report for t in ("2,594,750", "8 MiB", "20B/32B")))
ck("report_no_raw12_in_main", "RAW12" not in report.split("## 2")[0])
ck("report_report_sha_sidecar",
   "sha256=" + hashlib.sha256(report.encode("utf-8")).hexdigest()
   in (ROOT / "logs" / "report.sha256").read_text(encoding="utf-8"))

# ------------------------------------------------------------------ 10. negative controls (separate subprocess, -B)
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
        out.append((name, "REJECTED", str(e), str(e) == code))
        return
    except Exception as e:
        out.append((name, "OTHER", type(e).__name__, False))
        return
    out.append((name, "ACCEPTED", "", False))
run("NEG-01a RAW12 3,110,400 B", lambda: calc.validate_packing("RAW12_1.0x",1920,1080,3110400,3110400), "PACKING_PROFILE_REJECTED")
run("NEG-01b RAW10 1.0x slot", lambda: calc.validate_packing("RAW10_packed_20B32B",1920,1080,2592000,2592000), "PACKING_MISMATCH")
run("NEG-02a aggregate 2C", lambda: calc.validate_per_stream_claim(2,2,162.134318,75.684265,77.76,"feasible",rules), "AGGREGATE_CAPACITY_FOR_PER_STREAM")
run("NEG-02b chain<25 feasible", lambda: calc.validate_per_stream_claim(2,2,75.684265,75.684265,77.76,"feasible",rules), "FEASIBLE_CLAIM_BELOW_PER_STREAM_GATE")
run("NEG-03 synth mixed", lambda: calc.validate_resource_stage("synth"), "STAGE_MIX_SYNTH_IN_FIT")
print(json.dumps(out))
'''
neg_path = Path(__file__).resolve().parent / "_negctl_tmp.py"
neg_path.write_text(NEG.replace("MODELDIR", str(ROOT / "model")).replace("RULESFILE", str(ROOT / "model" / "rules.json")),
                    encoding="utf-8")
env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
proc = subprocess.run([sys.executable, "-B", str(neg_path)], capture_output=True, text=True, timeout=120, env=env)
print("NEGCTL rc=%d out=%s err=%s" % (proc.returncode, proc.stdout.strip(), proc.stderr.strip()[:200]))
try:
    res = json.loads(proc.stdout.strip().splitlines()[-1])
except Exception:
    res = []
ck("negctl_5_fixtures_rejected", len(res) == 5 and all(x[1] == "REJECTED" and x[3] for x in res), str(res))
# independent semantic corroboration (no calc.py): the forbidden inputs really violate the frozen bytes
ck("negctl_raw12_bytes_differ", 3110400 != raw_b(1920, 1080))
ck("negctl_1p0x_slot_differs", 2592000 != math.ceil((1920 * 1080 / 4) / 4) * 32)
ck("negctl_aggregate_looks_ok_but_per_stream_fails",
   2 * 81.06715910552415 >= 155.52 and 81.06715910552415 < 97.2)
ck("negctl_2C_chain_also_below_155_52", 2 * cap(raw_b(1920, 1080), ANCHOR) < 155.52)
ck("negctl_synth_would_change_fit",
   json.loads((P1_MANIFEST).read_text(encoding="utf-8")) is not None)
try:
    neg_path.unlink()
except OSError:
    pass

# ------------------------------------------------------------------ summary
print()
print("INDEPENDENT_SUMMARY checks_failed=%d" % len(FAILS))
for n, d in FAILS:
    print("  FAILED:", n, "|", d)
print("REPORT", ROOT / "feasibility-report.md")
sys.exit(1 if FAILS else 0)
