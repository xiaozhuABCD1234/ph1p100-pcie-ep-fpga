"""Archive exact-byte evidence for the bounded DDR-ready timing experiment.

Exploratory archives preserve a completed build/route experiment, including a
missed objective, and never authorize a delivery. Full archives require the
six native stages, candidate-bound G1 runs and the explicit 0.3 ns objective.
No hardware, TD, Git, cleanup, bit, DB or full-netlist copies are performed.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from check_chipwatcher_readback import check as check_readback
from check_timing_margin import measure


ROOT = Path(__file__).resolve().parents[2]
PROJECTS = Path("D:/TD/work/csi2/prj").resolve()
VALIDATION = Path("D:/TD/work/csi2/_validation").resolve()
BASE = PROJECTS / "camera_rgb565_wb_20261015_002820"
BASE_MANIFEST_SHA = "8f8e4efe9b9320cbc595f94e337395744dbd957630576123576ee2c357f9a1c8"
BASE_BIT_SHA = "4d591c31da9a71b9c261972e5089930af3e441c2096ed37736c8d2340ddd8865"
GUARD_CLOCKS = ["ddr_user", "mipi_a_byte_clk", "pclkx1"]
RTL = ("capture_async_fifo.v", "ddr_frame_store.v", "rgb565_frame_pack_guarded.v",
       "rgb565_display_read.v", "rgb565_display_pixels.v", "camera_rgb565_display_guarded.v")
STAGES = {
    "build": ("RGB565_SYNTHESIS_RETURNED", "build_rgb565.tcl",
              ("camera_ddr_display_Runs/syn_1/camera_ddr_display_gate.db",)),
    "route": ("RGB565_ROUTE_RETURNED_CHECK_REPORTS_NO_BIT", "route_rgb565.tcl",
              ("csi_checked_debug_pr.db", "capture_timing.rpt", "capture_skew.rpt",
               "capture_ignored.rpt", "capture_abnormal.rpt", "capture.area")),
    "inspect": ("CAPTURE_CDC_AUDIT_EXPORTED", "inspect_rgb565.tcl",
                ("capture_routed.v", "capture_cdc_objects.txt")),
    "audit_hdmi": ("HDMI_ROUTED_AUDIT_REPORTS_READY", "audit_hdmi_rgb565.tcl",
                   ("hdmi_clocks.rpt", "hdmi_targets.txt", "hdmi_data_paths.rpt")),
    "bitgen": ("CAMERA_DDR_DISPLAY_CANDIDATE_GENERATED_NO_DOWNLOAD", "bitgen_rgb565.tcl",
               ("camera_ddr_display.bit", "camera_ddr_display_inst.bid", "candidate_timing.rpt",
                "candidate_skew.rpt", "candidate_abnormal.rpt", "candidate_ignored.rpt")),
    "export_debug": ("MATCHING_DISPLAY_CWC_EXPORTED_NO_DOWNLOAD", "export_matching_display_debug.tcl",
                     ("camera_ddr_display.cwc", "cw/compiled.cwc", "cw/compiled.bit")),
}
REPORTS = ("capture_timing.rpt", "capture_skew.rpt", "capture_ignored.rpt",
           "capture_abnormal.rpt", "capture.area")
FINAL_REPORTS = ("candidate_timing.rpt", "candidate_skew.rpt", "candidate_ignored.rpt",
                 "candidate_abnormal.rpt", "hdmi_clocks.rpt", "hdmi_targets.txt",
                 "hdmi_data_paths.rpt", "hdmi_selected_audit.json", "hdmi_pad_excerpt.v.txt",
                 "rgb565_connections.json", "rgb565_connections_excerpt.v.txt",
                 "u_fifo_cdc_audit.json", "u_display_fifo_cdc_audit.json",
                 "display_cdc_functions.json", "cdc_reset_clock_review.txt",
                 "u_fifo_cdc_excerpt.v", "u_display_fifo_cdc_excerpt.v")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_bytes())


def inside(directory, relative):
    target = (directory / relative).resolve()
    require(target.is_relative_to(directory.resolve()), f"path leaves directory: {relative}")
    return target


def manifest_check(project, count):
    manifest = read_json(project / "input_manifest.json")
    require(isinstance(manifest, dict) and len(manifest) == count, f"expected {count} frozen inputs")
    for relative, digest in manifest.items():
        require(sha(inside(project, relative)) == digest, f"changed frozen input: {relative}")
    return manifest


def guarded_route_bytes(raw):
    """The two reviewed implementation-only insertions, with original endings."""
    newline = b"\r\n" if b"\r\n" in raw else b"\n"
    before = b" insert_debugger" + newline + b" place" + newline
    applied = ''' insert_debugger
 # SWUG200 PDF19: user uncertainty adds to the default jitter allowance.
 # Implementation-only reserve; no PLL/clock period/SDC/pin changes.
 foreach clock_name {ddr_user mipi_a_byte_clk pclkx1} {
  set reserve_clock [get_clocks $clock_name]
  if {[llength $reserve_clock] != 1} {error "Reserve clock missing/ambiguous: $clock_name"}
  set_clock_uncertainty -setup 0.300 $reserve_clock
 }
 puts "IMPLEMENTATION_SETUP_RESERVE_APPLIED_NS_0.300"
 place
'''.replace("\n", newline.decode()).encode()
    require(raw.count(before) == 1, "ambiguous guard placement insertion")
    raw = raw.replace(before, applied, 1)
    before = b" update_timing -mode final" + newline + b" report_timing_summary -file ./capture_timing.rpt" + newline
    cleared = ''' update_timing -mode final
 report_timing_summary -file ./implementation_guard_timing.rpt
 # Restore the original user setup uncertainty (0); keep default jitter.
 foreach clock_name {ddr_user mipi_a_byte_clk pclkx1} {
  set reserve_clock [get_clocks $clock_name]
  if {[llength $reserve_clock] != 1} {error "Nominal clock missing/ambiguous: $clock_name"}
  set_clock_uncertainty -setup 0.000 $reserve_clock
 }
 puts "IMPLEMENTATION_SETUP_RESERVE_CLEARED_FOR_NOMINAL_SIGNOFF"
 update_timing -mode final
 report_timing_summary -file ./capture_timing.rpt
'''.replace("\n", newline.decode()).encode()
    require(raw.count(before) == 1, "ambiguous guard nominal restoration insertion")
    return raw.replace(before, cleared, 1)


def frozen_check(project):
    require(sha(BASE / "input_manifest.json") == BASE_MANIFEST_SHA, "baseline manifest differs")
    require(sha(BASE / "camera_ddr_display.bit") == BASE_BIT_SHA, "baseline bit differs")
    baseline = manifest_check(BASE, 220)
    manifest = manifest_check(project, 221)
    require(set(manifest) == set(baseline) | {"frozen_prepare_rgb565_timing.py"}, "unexpected added/removed inputs")
    overlay = read_json(project / "timing_overlay.json")
    require(Path(overlay["base"]).resolve() == BASE and overlay["baseline_manifest_sha256"] == BASE_MANIFEST_SHA,
            "wrong optimization baseline")
    require(overlay["input_count"] == 221 and overlay["required_setup_ns"] == 0.3 and
            overlay["hardware_verified"] is False and overlay["hardware_download"] is False, "wrong overlay scope")
    strategy = overlay.get("physical_strategy", "TimingHigh")
    require(strategy in ("TimingHigh", "TimingUltra"), "unsupported physical strategy")
    reserve = overlay.get("implementation_setup_reserve_ns", 0)
    require(type(reserve) in (int, float) and reserve in (0, 0.3), "unsupported implementation setup reserve")
    require(overlay.get("implementation_guard_clocks", []) == (GUARD_CLOCKS if reserve else []), "implementation guard clocks differ")
    allowed_changes = {"camera_rgb565_display_guarded.v", "camera_ddr_capture_top.v"}
    if strategy == "TimingUltra":
        allowed_changes.add("build_rgb565.tcl")
        before = (BASE / "build_rgb565.tcl").read_bytes()
        old = b"set_strategy -run phy_1 TimingHigh"
        require(before.count(old) == 1 and (project / "build_rgb565.tcl").read_bytes() ==
                before.replace(old, b"set_strategy -run phy_1 TimingUltra", 1),
                "TimingUltra changed more than the one physical strategy command")
    if reserve:
        allowed_changes.add("route_rgb565.tcl")
        require((project / "route_rgb565.tcl").read_bytes() == guarded_route_bytes((BASE / "route_rgb565.tcl").read_bytes()),
                "implementation guard changed more than the two reviewed route insertions")
    actual = {name for name in baseline if baseline[name] != manifest[name]}
    require(actual == set(overlay["changes"]) == allowed_changes,
            "only wrapper, ROM path and declared implementation strategy/reserve may differ")
    for relative, entry in overlay["changes"].items():
        require(entry["before_sha256"] == baseline[relative] and entry["sha256"] == manifest[relative],
                f"overlay identity differs: {relative}")
    name = "camera_ddr_capture_top.v"
    before = (BASE / name).read_bytes()
    require(before.count(BASE.as_posix().encode()) > 0 and (project / name).read_bytes() ==
            before.replace(BASE.as_posix().encode(), project.as_posix().encode()),
            "ROM relocation changed more than the frozen directory string")
    require(overlay["unchanged_constraints"] == {name: manifest[name] for name in ("board.adc", "timing.sdc")},
            "clock or pin constraints differ")
    return manifest, overlay


def run_check(project, run, manifest):
    require(run.parent == VALIDATION and run.name.startswith("rgb565_ready_"), "unsupported G1 run path")
    result = read_json(run / "result.json")
    require(result.get("accepted") is True and result.get("hardware_verified") is False, "G1 not accepted/offline")
    require(Path(result["project"]).resolve() == project and result["manifest_sha256"] == sha(project / "input_manifest.json")
            and result["manifest_inputs"] == len(manifest), "G1 candidate/manifest differs")
    suite, production, fault = result["suite"], result["production"], result["fault"]
    require(suite in ("ready", "ddr") and type(production) is bool and fault in ("none", "ready-reset-bypass"),
            "unsupported G1 case")
    require(not production or suite == "ddr", "production geometry is DDR only")
    require(fault == "none" or suite == "ready", "negative control must use ready suite")
    top = "tb_rgb565_ready_timing" if suite == "ready" else "tb_rgb565_ddr_display"
    names = (top + ".sv", *RTL)
    require(set(result["sources"]) == set(result["executed_inputs"]) == set(names), "G1 source set differs")
    files = {"result.json": run / "result.json", "runner.py.snapshot": run / "runner.py.snapshot",
             "golden_crc.txt": run / "golden_crc.txt"}
    require(sha(files["runner.py.snapshot"]) == result["runner_sha256"], "G1 runner snapshot differs")
    for name in names:
        snapshot, entry = inside(run, name), result["sources"][name]
        require(snapshot.parent == run and sha(snapshot) == result["executed_inputs"][name], f"executed G1 source differs: {name}")
        if name in RTL:
            original = project / name
            require(Path(entry["path"]).resolve() == original and entry["sha256"] == manifest[name],
                    f"G1 source is not selected frozen RTL: {name}")
            expected = original.read_bytes()
            if fault != "none" and name == "camera_rgb565_display_guarded.v":
                old = b"wire run_rst_n=rst_n&&ddr_ready;"
                require(expected.count(old) == 1, "ambiguous reset negative-control source")
                expected = expected.replace(old, b"wire run_rst_n=rst_n;", 1)
            require(snapshot.read_bytes() == expected, f"G1 source transformation differs: {name}")
        else:
            require(Path(entry["path"]).resolve() == (ROOT / "fpga/csi2/tb" / name).resolve() and
                    entry["sha256"] == sha(snapshot) == sha(ROOT / "fpga/csi2/tb" / name), "G1 testbench identity differs")
        files[name] = snapshot
    require(result["golden"]["sha256"] == sha(files["golden_crc.txt"]) and
            [int(word, 16) for word in files["golden_crc.txt"].read_text(encoding="ascii").split()] == result["golden"]["values"],
            "G1 golden CRC identity differs")
    parameters = ["-gSW=960", "-gSH=540", "-gPRODUCTION=1"] if production else []
    expected_args = [["work"], ["-sv", "+define+GUARDED", *names],
                     ["-c", *parameters, "work." + top, "-do", "run -all; quit -f"]]
    require(len(result["commands"]) == 3, "incomplete G1 native commands")
    texts = []
    for index, entry in enumerate(result["commands"]):
        command = entry["command"]
        require(Path(command[0]).resolve() == Path("D:/intelFPGA/18.1/modelsim_ase/win32aloem") /
                ("vlib.exe", "vlog.exe", "vsim.exe")[index] and command[1:] == expected_args[index],
                "G1 native invocation differs")
        require(entry["exit_code"] == 0 and not any(entry["errors"]) and not any(entry["warnings"]), "G1 native command failed")
        log = inside(run, entry["log"])
        require(log.parent == run and log.name == f"{index}.log" and sha(log) == entry["sha256"], "G1 log identity differs")
        text = log.read_text(errors="replace")
        require(not re.search(r"\*\*\s*(?:Error|Fatal|Warning)\b", text), "G1 native diagnostic present")
        errors = [int(value) for value in re.findall(r"\bErrors:\s*(\d+)", text)]
        warnings = [int(value) for value in re.findall(r"\bWarnings:\s*(\d+)", text)]
        require(errors == entry["errors"] and warnings == entry["warnings"], "G1 diagnostic record differs from log")
        if index:
            require(errors == warnings == [0], "G1 missing clean native summary")
        texts.append(text)
        files[log.name] = log
    prefix = "RGB565_READY" if suite == "ready" else "RGB565_DDR"
    markers = re.findall(prefix + r"_(?:PASS|FAIL)[^\r\n]*", texts[-1])
    require(markers == result["simulation_markers"] and len(markers) == 1, "G1 simulator marker differs/missing")
    if fault == "none":
        require(markers[0].startswith(prefix + "_PASS "), "G1 DUT did not pass")
    else:
        require(markers[0].startswith("RGB565_READY_FAIL ready pulse must flush prior epoch") and
                "RGB565_READY_PASS" not in texts[-1], "negative control not rejected as expected")
    return {"run": str(run), "kind": [suite, production, fault], "dut_passed": fault == "none",
            "negative_control_rejected": fault != "none", "result": result}, files


def native_check(project, stages, manifest_digest, exploratory, reserve=0):
    records = {}
    for stage in stages:
        marker, script, required_artifacts = STAGES[stage]
        if stage == "route" and reserve:
            required_artifacts += ("implementation_guard_timing.rpt",)
        record = read_json(project / f"native_{stage}.json")
        log = project / f"native_{stage}.txt"
        require(record["stage"] == stage and Path(record["cwd"]).resolve() == project, "native project/stage differs")
        require(record["exit_code"] == 0 and not record.get("timed_out") and record["hardware_download"] is False,
                f"native command failed/unfinished: {stage}")
        require(type(record["accepted"]) is bool and (record["accepted"] or exploratory and stage == "route"),
                f"native stage not accepted: {stage}")
        require(record["expected_marker"] == marker and record["marker_present"] is True and
                marker in log.read_text(errors="replace") and record["log_sha256"] == sha(log), f"native marker/log differs: {stage}")
        require(record["command"] == ["D:/downlaod/bin/td_commands_prompt.exe", "./" + script] and
                record["script_sha256"] == sha(project / script) and record["input_manifest_sha256"] == manifest_digest,
                f"native invocation/input identity differs: {stage}")
        require(set(record["artifacts"]) == set(required_artifacts), f"native artifact set differs: {stage}")
        for relative, digest in record["artifacts"].items():
            source = inside(project, relative)
            require(digest and source.stat().st_size > 0 and sha(source) == digest, f"native artifact changed: {relative}")
        records[stage] = record
    db_digest = sha(project / "csi_checked_debug_pr.db")
    require(all(record["selected_db_sha256"] == db_digest for stage, record in records.items() if stage != "build"),
            "native stages selected different routed DBs")
    return records, db_digest


def objective_check(report, expected_endpoint_groups):
    result = measure(report, expected_endpoint_groups)
    result["expected_endpoint_groups"] = expected_endpoint_groups
    result["required_setup_ns"] = 0.3
    result["accepted"] = (result["setup_ns"] >= 0.3 and result["setup_tns_ns"] == result["hold_tns_ns"] == 0 and
                          min(result["hold_ns"], result["period_ns"]) >= 0 and result["violating_endpoints"] == 0)
    return result


def setup_uncertainties(text, user_ns):
    rows = {clock: [] for clock in GUARD_CLOCKS}
    for block in re.split(r"(?m)^Slack +: ", text)[1:]:
        if not re.search(r"(?m)^Check Type +: setup\s*$", block):
            continue
        endpoint = re.search(r"(?m)^End Point +: [^\r\n]*triggered by clock (\S+)", block)
        if endpoint and endpoint[1] in rows:
            match = re.search(r"Clock Uncertainty +: ([-+0-9.]+)ns \(sdc uncertainty: ([-+0-9.]+)ns, default uncertainty: ([-+0-9.]+)ns\)", block)
            require(match, "guard path lacks user/default uncertainty attributes")
            total, user, default = map(float, match.groups())
            require(abs(user - user_ns) < 0.0005 and default >= 0 and abs(total - user - default) <= 0.001,
                    "guard setup uncertainty was not additive/restored as declared")
            rows[endpoint[1]].append((total, user, default))
    require(all(rows.values()), "missing setup uncertainty paths for a guard clock")
    return {clock: {"setup_paths_checked": len(values), "total_ns": sorted({row[0] for row in values}),
                    "user_ns": sorted({row[1] for row in values}), "default_ns": sorted({row[2] for row in values})}
            for clock, values in rows.items()}


def guard_check(project, expected_endpoint_groups, exploratory):
    log = (project / "native_route.txt").read_text(errors="replace").splitlines()
    markers = ("IMPLEMENTATION_SETUP_RESERVE_APPLIED_NS_0.300",
               "IMPLEMENTATION_SETUP_RESERVE_CLEARED_FOR_NOMINAL_SIGNOFF",
               "RGB565_ROUTE_RETURNED_CHECK_REPORTS_NO_BIT")
    lines = [line.strip() for line in log]
    require(all(lines.count(marker) == 1 for marker in markers) and
            lines.index(markers[0]) < lines.index(markers[1]) < lines.index(markers[2]), "guard applied/cleared/route markers missing or out of order")
    guard_path, nominal_path = (project / name for name in ("implementation_guard_timing.rpt", "capture_timing.rpt"))
    guarded, nominal = measure(guard_path, expected_endpoint_groups), measure(nominal_path, expected_endpoint_groups)
    guard_attrs = setup_uncertainties(guard_path.read_text(errors="replace"), 0.3)
    nominal_attrs = setup_uncertainties(nominal_path.read_text(errors="replace"), 0)
    require(all(guard_attrs[clock]["default_ns"] == nominal_attrs[clock]["default_ns"] for clock in GUARD_CLOCKS),
            "default uncertainty differs between guard and nominal reports")
    delta = nominal["setup_ns"] - guarded["setup_ns"]
    require(abs(delta - 0.3) <= 0.00200001, "guard/nominal setup difference is not 0.300 +/- 0.002 ns")
    guard_pass = (min(guarded["setup_ns"], guarded["hold_ns"], guarded["period_ns"]) >= 0 and
                  guarded["setup_tns_ns"] == guarded["hold_tns_ns"] == 0 and guarded["violating_endpoints"] == 0)
    if not exploratory:
        require(guard_pass and objective_check(nominal_path, expected_endpoint_groups)["accepted"], "implementation guard failed or nominal setup misses objective")
        setup_uncertainties((project / "candidate_timing.rpt").read_text(errors="replace"), 0)
    return {"reserve_ns": 0.3, "clocks": GUARD_CLOCKS, "expected_endpoint_groups": expected_endpoint_groups,
            "guard": guarded, "nominal": nominal, "nominal_minus_guard_setup_ns": round(delta, 6),
            "guard_accepted": guard_pass, "guard_setup_uncertainties": guard_attrs,
            "nominal_setup_uncertainties": nominal_attrs, "applied_and_cleared_markers_checked": True,
            "boundary": "User setup uncertainty adds to TD default uncertainty (SWUG200 PDF page 19); nominal signoff and selected DB restore user uncertainty to zero without changing SDC, ADC, clock frequencies or RTL."}


def reuse_check(project, manifest):
    """Index prior verified sampler evidence; do not call it a new G1 run."""
    summary_path = ROOT / "docs/evidence/camera_rgb565_wb_20261015_002820.json"
    prior = read_json(summary_path)
    require(Path(prior["project"]).resolve() == BASE and prior["input_manifest_sha256"] == BASE_MANIFEST_SHA and
            prior["input_count"] == 220 and prior["bit"]["sha256"] == BASE_BIT_SHA, "prior WB archive identity differs")
    unchanged_names = ("bayer565_capture.v", "f9p_camera_display_core.v", "rgb565_frame_pack_guarded.v",
                       "frozen_tb_bayer565_white_balance.sv", "frozen_tb_bayer565_pipeline.sv",
                       "frozen_unpipelined_bayer565_capture.v", "frozen_white_balance_stats.json",
                       "camera/uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v", "board.adc", "timing.sdc")
    baseline = read_json(BASE / "input_manifest.json")
    require(all(manifest[name] == baseline[name] for name in unchanged_names), "prior sampler G1 reuse boundary changed")
    g1 = prior["g1"]
    require(g1["candidate"]["accepted"] is True and g1["pipeline"]["ok"] is True and
            g1["full_frame"]["accepted"] is True and g1["matrix_source_matches_candidate"] is True and
            g1["matrix_testbench_matches_candidate"] is True and
            len(g1["arithmetic_matrix"]) == 8 and all(row["Result"] == "PASS" for row in g1["arithmetic_matrix"]),
            "prior sampler G1 checks not accepted")
    prior_folder = summary_path.with_suffix("")
    for relative, entry in prior["artifacts"].items():
        require(sha(inside(prior_folder, relative)) == entry["sha256"], f"prior raw archive changed: {relative}")
    return {"summary": str(summary_path), "summary_sha256": sha(summary_path),
            "raw_archive": str(prior_folder), "raw_artifact_count_verified": len(prior["artifacts"]),
            "reused_sections": ["g1.candidate", "g1.arithmetic_matrix", "g1.pipeline", "g1.full_frame", "g1.full_frame_hardening_faults"],
            "unchanged_input_sha256": {name: manifest[name] for name in unchanged_names},
            "rerun_this_experiment": False,
            "scope": "Prior arithmetic, sampler pipeline and two-frame 960x540 sampler/packer G1 only. New G1 runs cover ready/reset and DDR backend with a modeled response-flush contract; neither validates real CSI reception or the physical DDR controller."}


def audits_check(project, net_digest):
    connections = read_json(project / "rgb565_connections.json")
    require(connections["netlist_sha256"] == net_digest and connections["sampled_bits"] == 16 and
            len(connections["rows"]) == 16 and {row["bit"] for row in connections["rows"]} == set(range(16)), "RGB565 connection audit differs")
    for fifo in ("u_fifo", "u_display_fifo"):
        audit = read_json(project / (fifo + "_cdc_audit.json"))
        require(audit["sha256"] == net_digest and audit["q_drivers"] == 54 and audit["same_bit_stage_links"] == 36,
                f"CDC Q/link audit differs: {fifo}")
    functions = read_json(project / "display_cdc_functions.json")
    require(functions["netlist_sha256"] == net_digest and functions["checked_sync_ff_functions"] == 72 and
            len(functions["rows"]) == 72 and functions["negative_truth_table_rejected"] is True, "CDC function audit differs")
    origins = (project / "cdc_reset_clock_review.txt").read_text(errors="replace")
    require(origins.startswith("NETLIST_SHA256=" + net_digest + "\n") and "BOUNDARY:" in origins, "CDC origins identity differs")
    hdmi = read_json(project / "hdmi_selected_audit.json")
    require(hdmi["netlist_sha256"] == net_digest and hdmi["report_sha256"] == sha(project / "hdmi_data_paths.rpt"), "HDMI audit identity differs")
    require((hdmi["paths"], hdmi["endpoints"], hdmi["pads"], hdmi["channels"], hdmi["bits_per_channel"], hdmi["iotype"], hdmi["serializer"])
            == (68, 34, 4, 3, 10, "LVDS33_E", "DDRX5") and hdmi["min_parallel_slack_ns"] >= 0, "HDMI parallel audit failed/incomplete")
    require(not re.search(r"End Point\s*:", (project / "candidate_abnormal.rpt").read_text(errors="replace")), "abnormal timing endpoints")
    skew = (project / "candidate_skew.rpt").read_text(errors="replace")
    slacks = [float(value) for value in re.findall(r"^Slack +: ([-+0-9.]+)ns", skew, re.M)]
    require(len(re.findall(r"^[0-9]+,  set_path_skew", skew, re.M)) == 4 and len(slacks) >= 4 and min(slacks) >= 0,
            "Gray-bus skew failed/incomplete")
    bit, cwc, bid = (project / name for name in ("camera_ddr_display.bit", "camera_ddr_display.cwc", "camera_ddr_display_inst.bid"))
    require(bit.read_bytes() == (project / "cw/compiled.bit").read_bytes(), "compiled bit differs")
    require(cwc.read_bytes() == (project / "cw/compiled.cwc").read_bytes(), "compiled CWC differs")
    instances = check_readback(ET.parse(cwc).getroot(), ET.parse(bid).getroot())
    require(len(instances) == 3 and {item["name"] for item in instances} ==
            {"auto_created_cwc1", "auto_created_cwc2", "auto_created_cwc3"}, "debug core identities differ")
    return {"connections": connections, "hdmi": hdmi, "gray_skew_ns": slacks,
            "compiled_bit_identical": True, "debug_instances": instances}


def archive(project, runs, expected_endpoint_groups, exploratory=False, check_only=False):
    require(__debug__, "run this validator without Python -O")
    require(type(expected_endpoint_groups) is int and expected_endpoint_groups >= 2 and expected_endpoint_groups % 2 == 0,
            "expected endpoint groups must be a positive even integer")
    project = project.resolve()
    require(project.parent == PROJECTS and project.name.startswith("camera_rgb565_timing_"), "unsupported candidate path")
    destination = ROOT / "docs/evidence" / project.name
    summary_path = destination.with_suffix(".json")
    require(destination.resolve().is_relative_to(ROOT) and not destination.exists() and not summary_path.exists(),
            "refusing to overwrite or leave project evidence directory")
    manifest, overlay = frozen_check(project)
    reuse = reuse_check(project, manifest)
    manifest_digest = sha(project / "input_manifest.json")
    stages = ("build", "route") if exploratory else tuple(STAGES)
    reserve = overlay.get("implementation_setup_reserve_ns", 0)
    native, db_digest = native_check(project, stages, manifest_digest, exploratory, reserve)
    objective = objective_check(project / ("capture_timing.rpt" if exploratory else "candidate_timing.rpt"), expected_endpoint_groups)
    guard = guard_check(project, expected_endpoint_groups, exploratory) if reserve else None
    if not exploratory:
        require(objective["accepted"], "final routed timing misses 0.3 ns objective or has violations")
    run_evidence, run_files, kinds = [], {}, set()
    require(runs and len({run.resolve() for run in runs}) == len(runs), "provide nonduplicate explicit G1 runs")
    for run in runs:
        run = run.resolve()
        evidence, files = run_check(project, run, manifest)
        run_evidence.append(evidence)
        kinds.add(tuple(evidence["kind"]))
        run_files[run.name] = files
    if not exploratory:
        require({("ready", False, "none"), ("ready", False, "ready-reset-bypass"),
                 ("ddr", False, "none"), ("ddr", True, "none")}.issubset(kinds), "incomplete G1 ready/negative/compact/production coverage")
    audits = None
    net_digest = None
    if not exploratory:
        net_digest = sha(project / "capture_routed.v")
        audits = audits_check(project, net_digest)
    payloads, artifacts, external = {}, {}, {}

    def retain(source, relative):
        require(relative not in payloads and inside(destination, relative).is_relative_to(destination.resolve()), "duplicate/invalid archive path")
        data = source.read_bytes()
        payloads[relative] = data
        artifacts[relative] = {"source": str(source), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

    # Explicit names only: never glob arbitrary outputs into the archive.
    for stage in stages:
        for suffix in ("json", "txt"):
            name = f"native_{stage}.{suffix}"
            retain(project / name, "g2/" + name)
        script = STAGES[stage][1]
        retain(project / script, "g2/scripts/" + script)
        for name, digest in native[stage]["artifacts"].items():
            path = inside(project, name)
            external[name] = {"path": str(path), "bytes": path.stat().st_size, "sha256": digest}
    for name in REPORTS + (() if exploratory else FINAL_REPORTS):
        retain(project / name, "g2/" + name)
    if reserve:
        retain(project / "implementation_guard_timing.rpt", "g2/implementation_guard_timing.rpt")
    retain(project / "camera_ddr_display_Runs/syn_1/run.log", "g2/synthesis_worker.txt")
    for name in ("input_manifest.json", "timing_overlay.json", "frozen_prepare_rgb565_timing.py",
                 "camera_ddr_capture_top.v", "f9p_camera_display_core.v", "board.adc", "timing.sdc", *RTL):
        retain(project / name, "source/" + name)
    for name in ("inspect_rgb332_body.tcl", "bitgen_rgb332_body.tcl"):
        if name in manifest:
            retain(project / name, "g2/scripts/" + name)
    if not exploratory:
        for name in ("camera_ddr_display.cwc", "camera_ddr_display_inst.bid"):
            retain(project / name, "debug/" + name)
        for name in ("audit_display_cdc.py", "review_display_cdc_functions.py", "review_display_cdc_origins.py",
                     "audit_rgb565_connections.py", "audit_display_hdmi_pad.py"):
            retain(ROOT / "tools/td" / name, "g2/checkers/" + name + ".txt")
    for run_name, files in run_files.items():
        for name, source in files.items():
            retain(source, "g1/" + run_name + "/" + name)
    retain(BASE / "input_manifest.json", "baseline/input_manifest.json")
    retain(BASE / "candidate_timing.rpt", "baseline/candidate_timing.rpt")
    retain(BASE / "camera_rgb565_display_guarded.v", "baseline/camera_rgb565_display_guarded.v")
    retain(Path(__file__), "archive_rgb565_timing.py.txt")
    retain(Path(__file__).with_name("check_timing_margin.py"), "check_timing_margin.py.txt")
    retain(Path(__file__).with_name("check_chipwatcher_readback.py"), "check_chipwatcher_readback.py.txt")
    baseline_timing = objective_check(BASE / "candidate_timing.rpt", 66)
    summary = {"schema": "rgb565_timing_archive_v1", "recorded_at": datetime.datetime.now().astimezone().isoformat(),
               "project": str(project), "base_project": str(BASE), "exploratory": exploratory,
               "deliverable": not exploratory, "archive_validation_passed": True,
               "input_count": len(manifest), "input_manifest_sha256": manifest_digest, "overlay": overlay,
               "physical_strategy": overlay.get("physical_strategy", "TimingHigh"),
               "implementation_setup_reserve_ns": reserve,
               "expected_endpoint_groups": expected_endpoint_groups,
               "baseline": {"manifest_sha256": BASE_MANIFEST_SHA, "bit_sha256": BASE_BIT_SHA, "timing": baseline_timing},
               "g1": run_evidence, "g1_reuse": reuse, "g2": {"native_stages": native, "selected_db_sha256": db_digest,
                                          "routed_netlist_sha256": net_digest, "objective": objective, "implementation_guard": guard, "audits": audits},
               "external_artifacts": external, "artifacts": artifacts, "hardware_download": False,
               "g3": "not_run", "g4": "not_run",
               "limits": ["Exploratory means preserved experiment only; it does not satisfy full delivery gates.",
                          "G1 uses a DDR response-flush model and does not validate the hardware DDR controller.",
                          "Unchanged frozen sampler/core/clock/constraint identities preserve the prior WB revision; new color hardware acceptance remains pending.",
                          "Selected CDC audits and parallel HDMI STA do not prove all-system CDC or serial electrical/thermal operation.",
                          "Sparkles, long-run stability and actual corrected color are not resolved by offline timing evidence."]}
    # Validate and cache every byte first; no output exists on a rejected gate.
    require(frozen_check(project)[0] == manifest and sha(project / "input_manifest.json") == manifest_digest, "inputs changed during archive")
    require(sha(Path(reuse["summary"])) == reuse["summary_sha256"], "prior WB archive index changed during validation")
    for entry in (*artifacts.values(), *external.values()):
        require(sha(Path(entry.get("source", entry.get("path")))) == entry["sha256"], "archive source changed during validation")
    if check_only:
        print(json.dumps({"accepted": True, "check_only": True, "deliverable": not exploratory,
                          "project": str(project), "artifacts": len(payloads), "objective": objective}, indent=2))
        return
    destination.mkdir()
    for relative, data in payloads.items():
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)
        require(sha(target) == artifacts[relative]["sha256"], f"archive byte mismatch: {relative}")
    with summary_path.open("xb") as stream:
        stream.write((json.dumps(summary, indent=2, ensure_ascii=False) + "\n").encode())
    print(json.dumps({"accepted": True, "deliverable": not exploratory, "summary": str(summary_path),
                      "artifacts": len(artifacts), "objective": objective}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--run", required=True, action="append", type=Path, help="Explicit candidate-bound rgb565_ready_* run; repeat as needed")
    parser.add_argument("--expected-endpoint-groups", required=True, type=int, help="Explicit reviewed report shape; positive even integer")
    parser.add_argument("--exploratory", action="store_true", help="Archive completed build/route without claiming full delivery")
    parser.add_argument("--check-only", action="store_true", help="Validate without creating any archive")
    args = parser.parse_args()
    if args.expected_endpoint_groups < 2 or args.expected_endpoint_groups % 2:
        parser.error("Expected endpoint groups must be a positive even integer")
    try:
        archive(args.project, args.run, args.expected_endpoint_groups, args.exploratory, args.check_only)
    except (AssertionError, ValueError, KeyError, TypeError, OSError, ET.ParseError) as error:
        print(json.dumps({"accepted": False, "reason": str(error)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
