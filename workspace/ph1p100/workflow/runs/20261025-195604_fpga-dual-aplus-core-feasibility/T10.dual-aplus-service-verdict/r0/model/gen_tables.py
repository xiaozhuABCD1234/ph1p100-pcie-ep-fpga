"""Freeze/verify inputs, then generate the scenario / DDR / frontier CSVs.

Writes only inside this task's r0 directory.  No TD, no RTL, no board, no network.
Exit 0 = 0 anchor mismatches and all CSVs written; exit 2 = BLOCKED (nothing written).
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

PROJ = Path("D:/fpga/ph1p100")
RUN = PROJ / "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility"
P1 = RUN / "T10.dual-core-resource-baseline/r0"
B6 = PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw"
B10 = PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix"
B11 = PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read"
B5 = PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe"
DUAL = PROJ / "workflow/runs/20261025-180900_fpga-dual-offline-closure"

FROZEN = json.loads((ROOT / "inputs" / "frozen-inputs.json").read_text(encoding="utf-8"))
RULES = json.loads((HERE / "rules.json").read_text(encoding="utf-8"))
JOURNAL = "--journal" in sys.argv

ANCHORS = [
    ("p1_manifest", P1 / "manifest-r0.json", 23644,
     "228531e7c16bca1a14898966c150b31bce464d7413f58078ae0bd724e894bdd0"),
    ("p1_dual_core_budget", P1 / "dual-core-budget.csv", 3684,
     "f62c9b03ff911e4fb77888abea5cad2710693cae3b5b1c13de569c39312ab76d"),
    ("p1_resource_baseline", P1 / "resource-baseline.md", 17322,
     "7bb108e32af930f5a6188e48ecdef10666cecceb93ea998a4c027b37669cf07a"),
    ("p1_resource_table", P1 / "resource-table.csv", 16125,
     "4375f0721c7e33c33131c14cdc74308ae156e6494acfb5114dbc28b7d538153f"),
    ("p1_result", P1 / "result-r0.md", 8084,
     "d52054c74a81fab507e713f12e44e657b1634c787c0d8eb7777659746e32d877"),
    ("p1_tester_report", RUN / "test-reports/T10.dual-core-resource-baseline-r1-integrated.md", 13627,
     "6d85a7fd71aca3a42c7d7837ccd047369c6a0f93c7a00612ca09a32f338196a7"),
    ("b6_core", B6 / "r0/changed-src/a1_deflate_core.v", 80196,
     "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb"),
    ("b6_manifest", B6 / "CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json", 24443,
     "2e9fd356824084813e3415af11757c1b56f774c9b6dd45f3b2a111647ad08880"),
    ("b6_tester_report", PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/"
     "T10.b6-a1-htab-nw-r0-integrated.md", 20624,
     "53f7fa65d0e073c911ca4b7475d6456f157fb5abf1c94cc5589c22d1f758a21f"),
    ("b10_result_r1", B10 / "result-r1.md", 14270,
     "675da40c225c508674a4ca41fcbb12c75206fcdeaa13ed0fbd1987ca8072e614"),
    ("device_doc", PROJ / "docs/双目首版_整链路方案与团队交付.md", 26083,
     "c4b2b89d1752f7b7346eba1c6c53b58aafe12689e8e13ce33ceb6fb05b7a762d"),
]

SNAPSHOTS = [
    ("b11_result_r0", B11 / "r0/result-r0.md"),
    ("t08_result_r0", DUAL / "T08.dual-local-closure/result-r0.md"),
    ("t10_result_r0", DUAL / "T10.dual-aplus-scheduler/result-r0.md"),
    ("c180900_design_guide", DUAL / "fpga-design-guide.md"),
    ("p2_request", RUN / "request.md"),
    ("p2_input_index", RUN / "input-index.md"),
    ("p2_design_guide", RUN / "fpga-design-guide.md"),
    ("p2_dev_plan", RUN / "dev-plan.md"),
    ("b5_full_grad_stats", B5 / "r0/sim/captures/full_grad.stats"),
    ("tb_camera_a1_uart_top", PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/"
     "T10.b1-a1-uart-integ/r0/sim/tb_camera_a1_uart_top.v"),
    ("ddr_doc", PROJ / "docs/DDR1333集成与1333vs1600对比_2026-10-17.md"),
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def append_command(purpose, result, exit_code, timeout_s=120):
    if not JOURNAL:
        return
    rec = {
        "seq": None,
        "argv": ["python", "model/gen_tables.py"],
        "cwd": str(ROOT),
        "exit": exit_code,
        "timeout_s": timeout_s,
        "time_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "purpose": purpose,
        "result": result,
    }
    path = ROOT / "commands.jsonl"
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    rec["seq"] = len(lines) + 1
    with open(path, "a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def read_text(path):
    return Path(path).read_text(encoding="utf-8", errors="replace")


def write_csv(path, cols, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(",".join(cols) + "\n")
        for r in rows:
            f.write(calc.row_to_csv(r, cols) + "\n")


def main():
    assertions = []
    inputs = []
    snapshots_drift = []

    def A(aid, expected, actual, source, tol=None, label=""):
        if tol is None:
            ok = expected == actual
        else:
            ok = abs(float(expected) - float(actual)) <= tol
        assertions.append({
            "id": aid, "expected": expected, "actual": actual, "status": "pass" if ok else "fail",
            "tolerance": tol, "source": str(source), "label": label,
        })
        if not ok:
            print("ASSERT_FAIL %s expected=%r actual=%r source=%s" % (aid, expected, actual, source))
        return ok

    for aid, path, nbytes, sha in ANCHORS:
        if not path.is_file():
            print("BLOCKED missing input %s (%s)" % (aid, path))
            append_command("freeze inputs", "BLOCKED missing %s" % aid, 2)
            return 2
        inputs.append({"id": aid, "path": str(path), "bytes": path.stat().st_size,
                       "sha256": sha256_file(path), "role": "anchor"})
        A(aid + "_sha256", sha, inputs[-1]["sha256"], path, label="anchor")
        A(aid + "_bytes", nbytes, inputs[-1]["bytes"], path, label="anchor")

    for aid, path in SNAPSHOTS:
        if not path.is_file():
            snapshots_drift.append({"id": aid, "status": "missing", "path": str(path)})
            continue
        rec = {"id": aid, "path": str(path), "bytes": path.stat().st_size,
               "sha256": sha256_file(path), "role": "snapshot"}
        inputs.append(rec)
        snapshots_drift.append({"id": aid, "status": "recorded", "sha256": rec["sha256"],
                                "bytes": rec["bytes"]})

    p1_manifest = json.loads((P1 / "manifest-r0.json").read_text(encoding="utf-8"))
    A("p1_task_id", "T10.dual-core-resource-baseline", p1_manifest.get("task_id"), P1 / "manifest-r0.json")
    A("p1_stopped_modifying", True, p1_manifest.get("stopped_modifying"), P1 / "manifest-r0.json")
    A("p1_active_commands", 0, p1_manifest.get("active_commands"), P1 / "manifest-r0.json")
    lc = p1_manifest.get("local_checks", {})
    A("p1_marginal_eram_total", 231, lc.get("marginal_eram_total"), P1 / "manifest-r0.json")
    A("p1_conservative_eram_total", 289, lc.get("conservative_eram_total"), P1 / "manifest-r0.json")
    A("p1_marginal_lut6", 25709, lc.get("marginal_lut6_td"), P1 / "manifest-r0.json")
    A("p1_dual_core_timing", "unproven", lc.get("dual_core_timing"), P1 / "manifest-r0.json")
    A("p1_td_invocations", 0, p1_manifest.get("tools", {}).get("td_invocations"), P1 / "manifest-r0.json")
    A("p1_artifact_budget_sha", "f62c9b03ff911e4fb77888abea5cad2710693cae3b5b1c13de569c39312ab76d",
      next((a["sha256"] for a in p1_manifest.get("artifacts", [])
            if a.get("rel") == "dual-core-budget.csv"), None), P1 / "manifest-r0.json")

    with open(P1 / "dual-core-budget.csv", encoding="utf-8", newline="") as f:
        budget = {row["column"]: row for row in csv.DictReader(f)}
    for col, field, expected in [
        ("marginal", "ERAM_total", "231"), ("marginal", "ERAM_headroom", "69"),
        ("marginal", "fit_300", "pass"), ("marginal", "fit_210_logic", "pass"),
        ("marginal", "LUT6_total", "25709"), ("marginal", "LUT4_equiv_upper", "51418"),
        ("marginal", "REG_total", "34341"), ("marginal", "SLICE_total", "30733"),
        ("conservative", "ERAM_total", "289"), ("conservative", "ERAM_headroom", "11"),
        ("conservative", "fit_300", "conditional"), ("conservative", "LUT6_total", "39390"),
        ("conservative", "REG_total", "56008"), ("conservative", "SLICE_total", "48736"),
        ("marginal_2ddr", "ERAM_total", "316"), ("conservative_2ddr", "ERAM_total", "374"),
    ]:
        A("p1_budget_%s_%s" % (col, field), expected, budget[col][field], P1 / "dual-core-budget.csv")

    p1_base_text = read_text(P1 / "resource-baseline.md")
    for token in ["26,822", "35,815", "32,083", "u_csi_b", "unproven", "231/300", "289/300"]:
        A("p1_baseline_contains_%s" % re.sub(r"[^A-Za-z0-9]", "_", token), True,
          token in p1_base_text, P1 / "resource-baseline.md")

    b6_report_text = read_text(PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/"
                               "test-reports/T10.b6-a1-htab-nw-r0-integrated.md")
    for token in ["355,261", "161,479", "6,421,414", "81.067", "178.351"]:
        A("b6_report_contains_%s" % token.replace(",", "").replace(".", "_"), True,
          token in b6_report_text, "b6 tester report")

    comp = FROZEN["anchors"]["comp"]
    rand = FROZEN["anchors"]["rand"]
    fg = FROZEN["anchors"]["full_grad"]
    A("comp_cycles", 355261, comp["cycles"], "b6 report")
    A("comp_bytes", 153600, comp["input_bytes"], "b6 report")
    A("comp_rate_MBps", 81.067159, calc.capacity_MBps(comp["input_bytes"], comp["cycles"], 187500000),
      "b6 report (derived)", tol=1e-6)
    A("rand_cycles", 161479, rand["cycles"], "b6 manifest")
    A("rand_rate_MBps", 178.351365, calc.capacity_MBps(rand["input_bytes"], rand["cycles"], 187500000),
      "b6 manifest (derived)", tol=1e-5)
    A("full_grad_cycles", 6421414, fg["cycles"], "b6 P1 STAT")
    A("full_grad_cycles_in_b6_report", True, "6,421,414" in b6_report_text, "b6 tester report")

    stats_text = read_text(B5 / "r0/sim/captures/full_grad.stats")
    m = re.search(r"cycles=(\d+)", stats_text)
    A("b5_full_grad_cycles", 6421438, int(m.group(1)) if m else None, B5 / "r0/sim/captures/full_grad.stats")
    m = re.search(r"read_words=(\d+)", stats_text)
    A("full_grad_read_words_129600", 129600, int(m.group(1)) if m else None,
      B5 / "r0/sim/captures/full_grad.stats", label="1080p 20B/32B RAW-slot geometry evidence")
    m = re.search(r"cap_bytes=(\d+)", stats_text)
    A("full_grad_cap_bytes_40076", 40076, int(m.group(1)) if m else None,
      B5 / "r0/sim/captures/full_grad.stats")
    tb_text = read_text(PROJ / "workflow/runs/20261020-0209_singleA_aplus_closedloop/"
                        "T10.b1-a1-uart-integ/r0/sim/tb_camera_a1_uart_top.v")
    A("tb_default_W_1920", True, re.search(r"parameter\s+integer\s+W\s*=\s*1920", tb_text) is not None,
      "tb_camera_a1_uart_top.v")
    A("tb_default_H_1080", True, re.search(r"parameter\s+integer\s+H\s*=\s*1080", tb_text) is not None,
      "tb_camera_a1_uart_top.v")
    A("tb_dec_capture_is_decimal_text", True, '$fwrite(fd, "%0d\\n", dbg_byte)' in tb_text,
      "tb_camera_a1_uart_top.v",
      label="explains why full_grad.dec is 180,425 B for 40,076 captured bytes")

    fr = FROZEN["frame"]
    A("raw_bytes_2592000", 2592000, calc.raw_bytes(1920, 1080), "design guide 2.1")
    A("raw_slot_bytes_4147200", 4147200, calc.raw_slot_bytes(1920, 1080), "design guide 2.1")
    A("raw_slot_words_129600", 129600, calc.raw_slot_words(1920, 1080), "design guide 2.1")
    A("cmp_total_bytes_2594750", 2594750, calc.cmp_total_bytes(1920, 1080), "design guide 2.1")
    A("cmp_payload_bytes_2594706", 2594706, calc.cmp_payload_bytes(1920, 1080), "design guide 2.1")
    A("content_bytes_2592128", 2592128, calc.content_bytes(1920, 1080), "design guide 2.1")
    A("dma_bytes_2592768", 2592768, calc.dma_bytes(1920, 1080), "design guide 2.1")
    A("cmp_slot_bytes_8MiB", 8388608, fr["cmp_slot_bytes"], "design guide 2.1")
    A("a1u1_header_44", 44, fr["a1u1_header_bytes"], "design guide 2.1")
    A("clock_187p5", 187.5e6, FROZEN["clock_hz"], "design guide 1")
    A("design_margin_25pct", 0.25, FROZEN["design_margin"], "design guide 1")
    A("slot_expansion_1p6", 1.6, calc.raw_slot_expansion(1920, 1080), "design guide 5.1")
    tier_pack = [(w, h) for (w, h) in RULES["grid"]["geometry_30fps"]
                 if w % 4 == 0 and (w * h) % 4 == 0 and calc.raw_bytes(w, h) == w * h * 5 // 4]
    A("all_7_tiers_pack_integral", 7, len(tier_pack), "design guide 6.2 tier list")
    A("tier_1440x810_groups", 291600, calc.groups(1440, 810), "design guide 6.2 tier list",
      label="H=810 is not a multiple of 4; W=1440 keeps the row groups/stride integral")

    dg = read_text(RUN / "fpga-design-guide.md")
    for token in ["4,147,200", "2,594,750", "8 MiB", "44 B", "187.5 MHz", "25%"]:
        A("design_guide_contains_%s" % re.sub(r"[^A-Za-z0-9]", "_", token), True, token in dg,
          RUN / "fpga-design-guide.md")

    A("device_eram_300", 300, FROZEN["device"]["eram20k"], "device doc")
    A("device_lut4_129024", 129024, FROZEN["device"]["lut4"], "device doc")
    A("device_dff_143360", 143360, FROZEN["device"]["dff"], "device doc")
    A("device_dsp_220", 220, FROZEN["device"]["dsp"], "device doc")
    A("device_pll_12", 12, FROZEN["device"]["pll"], "device doc")

    mism = [a for a in assertions if a["status"] != "pass"]
    print("ASSERTIONS total=%d pass=%d fail=%d" % (len(assertions), len(assertions) - len(mism), len(mism)))
    if mism:
        print("BLOCKED mismatch_count=%d" % len(mism))
        append_command("freeze inputs", "BLOCKED mismatch_count=%d" % len(mism), 2)
        return 2

    verified = {
        "schema_version": 1,
        "task_id": "T10.dual-aplus-service-verdict",
        "run_id": "20261025-195604_fpga-dual-aplus-core-feasibility",
        "generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generator": "model/gen_tables.py",
        "python": sys.version.split()[0],
        "mismatch_count": 0,
        "assertions": assertions,
        "inputs": inputs,
        "snapshot_status": snapshots_drift,
        "boundary_notes": [
            "full_grad is a 1920x1080 full frame: TB defaults W=1920/H=1080, STAT read_words=129600 (1080p 20B/32B RAW slot).",
            "b5 full_grad.dec is 180,425 B because the TB writes one decimal byte per line for 40,076 captured bytes; it is not the payload size.",
            "full_grad cycles include capture->RAW slot store->DDR read->core->UART export on the b6 small top (behavioral DDR), not a PAXI/DDR-MC timing model.",
            "P1 manifest 228531e7...bdd0 and all P1 routed resource rows are re-hashed here; the P2 model consumes only these frozen values.",
            "1440x810 is a frozen tier although H=810 is not a multiple of 4: W=1440 gives a 1,800 B row stride and 291,600 integral 4-pixel groups, so no padding is needed. The design-guide statement that every tier's W and H are both divisible by 4 does not hold for 810; the model enforces the actual requirement (W%4==0 and W*H%4==0).",
        ],
        "labels": {"measured": "b6/b10 routed reports, b6 STAT, P1 artifacts",
                   "derived": "computed by model/calc.py", "assumed": "overhead constancy, slice scaling, shared PHY, CSI delta",
                   "unproven": "dual-core Routed, DDR sustained, natural-image content, 200 MHz"},
    }
    (ROOT / "input-verified.json").write_text(json.dumps(verified, ensure_ascii=False, indent=2) + "\n",
                                              encoding="utf-8", newline="\n")

    rows = calc.scenario_rows(FROZEN, RULES)
    content = calc.content_rows(FROZEN)
    ddr = calc.ddr_rows(FROZEN)
    frontier = calc.frontier_rows(rows, FROZEN)
    sens = calc.overhead_sensitivity_rows(rows, FROZEN, RULES)
    if len(rows) != RULES["grid"]["expected_rows"]:
        print("BLOCKED grid_rows=%d expected=%d" % (len(rows), RULES["grid"]["expected_rows"]))
        append_command("freeze inputs", "BLOCKED grid_rows=%d" % len(rows), 2)
        return 2
    # F2 regression: the three overhead tiers must exist and match the tester's reference values.
    sens_by = {(s["scenario_id"], int(s["overhead_tier_cycles"])): s for s in sens}
    tier_checks = [
        ("1600x900-30fps-c1s1-187.5MHz", 0, 50.1244),
        ("1600x900-30fps-c1s1-187.5MHz", 426385, 36.1774),
        ("1600x900-30fps-c1s1-187.5MHz", 1000000, 21.0486),
        ("1440x810-30fps-c1s1-187.5MHz", 1000000, 42.9485),
        ("1728x972-30fps-c1s1-187.5MHz", 1000000, 6.7286),
    ]
    sens_ok = len(sens) == len(rows) * len(FROZEN["overhead"]["sensitivity_tiers"])
    for sid, ov, expected in tier_checks:
        actual = sens_by[(sid, ov)]["margin_chain_pct"]
        if abs(float(actual) - expected) > 1e-3:
            print("TIER_ASSERT_FAIL %s ov=%s expected=%.4f actual=%.4f" % (sid, ov, expected, actual))
            sens_ok = False
    anchor_id = "1920x1080-30fps-c1s1-187.5MHz"
    anchor_vals = [sens_by[(anchor_id, ov)]["margin_chain_pct"] for ov in FROZEN["overhead"]["sensitivity_tiers"]]
    if not (anchor_vals[0] == anchor_vals[1] == anchor_vals[2]):
        print("TIER_ASSERT_FAIL 1080p anchor not tier-invariant: %r" % (anchor_vals,))
        sens_ok = False
    if not sens_ok:
        print("BLOCKED overhead sensitivity regression (rows=%d)" % len(sens))
        append_command("freeze inputs", "BLOCKED overhead sensitivity rows=%d" % len(sens), 2)
        return 2
    write_csv(ROOT / "out/scenarios.csv", calc.SCENARIO_COLS, rows)
    write_csv(ROOT / "out/content-sensitivity.csv", calc.CONTENT_COLS, content)
    write_csv(ROOT / "out/ddr-budget.csv", calc.DDR_COLS, ddr)
    write_csv(ROOT / "out/frontier.csv", calc.FRONTIER_COLS, frontier)
    write_csv(ROOT / "out/overhead-sensitivity.csv", calc.OVERHEAD_COLS, sens)

    primary, alts = calc.recommendations(rows, FROZEN)
    print("GEN_OK inputs=%d assertions=%d mismatch=0 scenarios=%d content=%d ddr=%d frontier=%d sens=%d"
          % (len(inputs), len(assertions), len(rows), len(content), len(ddr), len(frontier), len(sens)))
    print("PRIMARY %s margin_chain=%.4f%% verdict=%s" % (primary["scenario_id"], primary["margin_chain_pct"],
                                                          primary["verdict"]))
    for a in alts:
        print("ALTERNATE %s margin_chain=%.4f%% verdict=%s" % (a["scenario_id"], a["margin_chain_pct"],
                                                                a["verdict"]))
    append_command("freeze inputs + generate CSVs",
                   "GEN_OK scenarios=%d content=%d ddr=%d frontier=%d mismatch=0" % (len(rows), len(content),
                                                                                    len(ddr), len(frontier)), 0)
    return 0


if __name__ == "__main__":
    try:
        code = main()
    except Exception as exc:  # noqa: BLE001 - keep the failure journaled
        print("BLOCKED_UNEXPECTED %s: %s" % (type(exc).__name__, exc))
        append_command("freeze inputs + generate CSVs", "EXCEPTION %s" % type(exc).__name__, 2)
        code = 2
    sys.exit(code)
