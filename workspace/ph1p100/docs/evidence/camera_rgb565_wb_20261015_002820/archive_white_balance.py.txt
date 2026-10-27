"""Freeze bounded, exact-byte WB evidence only after all offline gates pass.

No hardware access, cleanup, Git operations, or full bit/DB/netlist copies.
The explicitly selected G1 run must bind to the candidate's frozen inputs.
The eight-configuration arithmetic matrix must use this sampler revision.
Older red runs are retained as historical component evidence, with their own
frozen source identity; they do not validate a later RTL revision.
"""
import argparse
import csv
import datetime
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

from check_chipwatcher_readback import check as check_readback


ROOT = Path(__file__).resolve().parents[2]
PROJECTS = Path("D:/TD/work/csi2/prj").resolve()
VALIDATION = Path("D:/TD/work/csi2/_validation").resolve()
BASE = PROJECTS / "camera_rgb565_20261014_140836"
STAGES = {
    "build": ("RGB565_SYNTHESIS_RETURNED", "build_rgb565.tcl",
              ["camera_ddr_display_Runs/syn_1/camera_ddr_display_gate.db"]),
    "route": ("RGB565_ROUTE_RETURNED_CHECK_REPORTS_NO_BIT", "route_rgb565.tcl",
              ["csi_checked_debug_pr.db", "capture_timing.rpt", "capture_skew.rpt"]),
    "inspect": ("CAPTURE_CDC_AUDIT_EXPORTED", "inspect_rgb565.tcl",
                ["capture_routed.v", "capture_cdc_objects.txt"]),
    "audit_hdmi": ("HDMI_ROUTED_AUDIT_REPORTS_READY", "audit_hdmi_rgb565.tcl",
                   ["hdmi_clocks.rpt", "hdmi_targets.txt", "hdmi_data_paths.rpt"]),
    "bitgen": ("CAMERA_DDR_DISPLAY_CANDIDATE_GENERATED_NO_DOWNLOAD", "bitgen_rgb565.tcl",
               ["camera_ddr_display.bit", "camera_ddr_display_inst.bid"]),
    "export_debug": ("MATCHING_DISPLAY_CWC_EXPORTED_NO_DOWNLOAD", "export_matching_display_debug.tcl",
                     ["camera_ddr_display.cwc", "cw/compiled.cwc", "cw/compiled.bit"]),
}


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


def clean_sim_log(path):
    text = path.read_text(errors="replace")
    require(not re.search(r"^#?\s*\*\* (?:Error|Warning|Fatal):", text, re.M), f"simulator diagnostic: {path}")
    numbers = re.findall(r"Errors:\s*(\d+),\s*Warnings:\s*(\d+)", text)
    require(numbers and all(a == b == "0" for a, b in numbers), f"missing clean simulator summary: {path}")
    return text


def pass_check(path, red, blue, black):
    text = clean_sim_log(path)
    marker = (f"WB565_PASS gains={red},{blue} black_level={black} "
              "frames=9 outputs=1152 output_checks=1152")
    require(marker in text and "WB565_FAIL" not in text, f"missing WB pass marker: {path}")
    require("raw_levels_R=1024 raw_levels_B=1024 fixture=GBRG" in text, f"incomplete RAW10 sweep: {path}")
    return marker


def snapshot_hashes(run):
    """The historical PowerShell hash list contains explicit paths, not commands."""
    records = read_json(run / "sha256.json")
    for item in records:
        source = Path(item["Path"]).resolve()
        require(source.is_relative_to(run), "hash-list path leaves selected run")
        require(item["Algorithm"] == "SHA256" and sha(source) == item["Hash"].lower(), f"changed G1 evidence: {source}")
    return records


def pipeline_check(project, run):
    """Check reviewed +1-cycle sampler/verdict/packer equivalence evidence."""
    require(run.parent == VALIDATION, f"pipeline run outside expected directory: {run}")
    result = read_json(run / "result.json")
    require(result.get("schema") == "wb565_pipeline_v1" and result.get("ok") is True and
            result.get("status") == "pass", "pipeline G1 did not pass reviewed schema")
    require(Path(result["project"]).resolve() == project and
            result.get("input_manifest_sha256", result.get("manifest_sha256")) == sha(project / "input_manifest.json"),
            "pipeline G1 lacks actual candidate/manifest binding")
    require(result.get("hardware_verified") is False and result["core_sha256"] == sha(project / "f9p_camera_display_core.v") and
            result["actual_core_parameters"] == {"SW": 960, "SH": 540, "BAYER_PHASE": 3,
                                                  "WB_R_GAIN_Q10": 2400, "WB_B_GAIN_Q10": 2062, "WB_BLACK_LEVEL": 50} and
            result["core_verdict_wiring_checked"] is True, "pipeline G1 core/verdict wiring identity differs")
    core = (project / "f9p_camera_display_core.v").read_text(encoding="utf-8")
    selected_core = re.findall(r"bayer565_capture\s*#\((.*?)\)\s+u_cam_preview\s*\((.*?)\);", core, re.S)
    require(len(selected_core) == 1, "ambiguous actual pipeline instance")
    ports = dict(re.findall(r"\.(\w+)\((\w+)\)", selected_core[0][1]))
    require(ports.get("clk") == "w_a_byte_clk" and ports.get("rst_n") == "w_a_rst_out", "pipeline clock/reset binding differs")
    for kind in ("end", "good", "abort"):
        require(core.count(f".O_frame_{kind}(raw_a_frame_{kind})") == 1 and
                ports.get(f"frame_{kind}") == f"raw_a_frame_{kind}" and
                ports.get(f"out_frame_{kind}") == f"cap_frame_{kind}", "pipeline raw/delayed verdict wiring differs")
    inputs = result["inputs"]
    require(set(inputs) == {"rtl", "tb", "packer", "reference"}, "unexpected pipeline inputs")
    files = {"result.json": run / "result.json"}
    require(sha(run / "runner.py.snapshot") == result["runner_sha256"], "pipeline runner snapshot changed")
    files["runner.py.snapshot"] = run / "runner.py.snapshot"

    def selected(entry, filename, candidate_name):
        source = Path(entry["path"]).resolve()
        require(source.is_relative_to(run) and source.parent == run, "pipeline snapshot path leaves selected run")
        require(Path(entry["source_path"]).resolve() == (project / candidate_name).resolve(), "pipeline input source is not the actual frozen candidate")
        require(sha(source) == entry["sha256"] == sha(project / candidate_name), f"pipeline input differs: {filename}")
        files[filename] = source
        return source

    selected(inputs["rtl"], "bayer565_capture.v", "bayer565_capture.v")
    tb = selected(inputs["tb"], "tb_bayer565_pipeline.sv", "frozen_tb_bayer565_pipeline.sv")
    selected(inputs["packer"], "rgb565_frame_pack_guarded.v", "rgb565_frame_pack_guarded.v")
    reference = inputs["reference"]
    original = selected(reference["original"], "old_bayer565_capture.v", "frozen_unpipelined_bayer565_capture.v")
    require(reference["original"]["sha256"] == "362509c9b56113a64685b5d7059c89c284891dcbce7f8265b8f022f8aa620586",
            "pipeline oracle changed from reviewed unpipelined revision")
    transformed = Path(reference["path"]).resolve()
    require(transformed.parent == run and sha(transformed) == reference["sha256"], "changed renamed reference")
    original_bytes = original.read_bytes()
    require(original_bytes.count(b"module bayer565_capture") == 1 and
            transformed.read_bytes() == original_bytes.replace(b"module bayer565_capture", b"module bayer565_reference", 1),
            "reference transformation changed more than the module name")
    files["bayer565_reference.v"] = transformed
    tb_text = tb.read_text(encoding="utf-8")
    for name, value in (("BAYER_PHASE", 3), ("WB_R_GAIN_Q10", 2400), ("WB_B_GAIN_Q10", 2062), ("WB_BLACK_LEVEL", 50)):
        require(len(re.findall(r"\." + name + r"\(" + str(value) + r"\)", tb_text)) == 2,
                f"pipeline DUT/reference parameters differ: {name}")
    expected_counts = {"cases": 14, "pixel_checks": 437, "latency_checks": 3218, "verdict_checks": 3218,
                       "stat_checks": 3218, "pack_checks": 2878, "starts": 15, "words": 20, "footers": 7,
                       "aborts": 7, "stalls": 24, "reset_inflight": 1, "restart_pending": 1}
    require(result["counts"] == expected_counts, "pipeline check coverage differs from reviewed fixture")
    log_keys = {"compile", "run", "simulator", "fault_compile", "fault_run", "fault_simulator"}
    require(set(result["logs"]) == log_keys, "incomplete pipeline native logs")
    log_texts = {}
    for name, path in result["logs"].items():
        source = Path(path).resolve()
        require(source.parent == run, "pipeline log path leaves selected run")
        log_texts[name] = clean_sim_log(source)
        files[name + ".log"] = source
    green, fault = result["green"], result["fault"]
    require(green["errors"] == green["warnings"] == 0 and green["pass_marker"] == "BAYER565_PIPELINE_PASS",
            "pipeline native GREEN diagnostic failure")
    require(green["pass_line"] in log_texts["run"] and green["pass_line"] in log_texts["simulator"] and
            "BAYER565_PIPELINE_FAIL" not in log_texts["run"], "pipeline GREEN marker missing or fault present")
    for name, value in expected_counts.items():
        require(re.search(r"\b" + name + "=" + str(value) + r"\b", green["pass_line"]), "pipeline pass line/count mismatch")
    require(fault["detected"] is True and fault["kind"] == "frozen_zero_stage_sampler_as_DUT" and
            fault["dut_sha256"] == reference["original"]["sha256"] and fault["errors"] == fault["warnings"] == 0 and
            fault["fail_marker"] == "BAYER565_PIPELINE_FAIL", "pipeline latency negative control not established")
    require(fault["fail_line"] in log_texts["fault_run"] and fault["fail_line"] in log_texts["fault_simulator"] and
            "display delay" in fault["fail_line"] and "BAYER565_PIPELINE_PASS" not in log_texts["fault_run"],
            "pipeline old-DUT negative marker missing")
    command_path = Path(result["commands"]).resolve()
    require(command_path.parent == run, "pipeline command record leaves selected run")
    commands = read_json(command_path)
    require(len(commands) == 6, "incomplete pipeline native command record")
    command_results = result["command_results"]
    require(len(command_results) == len(commands), "incomplete pipeline command results")
    for command, record in zip(commands, command_results):
        require(record["command"] == [command["executable"], *command["arguments"]] and record["exit_code"] == 0 and
                not any(record["errors"]) and not any(record["warnings"]), "pipeline native command/result failure")
        log_path = inside(run, record["log"])
        require(log_path.parent == run, "pipeline command log leaves selected run")
        if Path(command["executable"]).name.lower() != "vlib.exe":
            clean_sim_log(log_path)
        if log_path not in files.values():
            files[log_path.name] = log_path
    compile_args = [item["arguments"] for item in commands if Path(item["executable"]).name.lower() == "vlog.exe"]
    require(len(compile_args) == 2 and any("+define+PIPELINE_VERDICT_PORTS" in args and "bayer565_capture.v" in args for args in compile_args) and
            any("+define+PIPELINE_VERDICT_PORTS" not in args and "old_bayer565_capture.v" in args for args in compile_args),
            "pipeline GREEN/RED DUT compilation identities differ")
    files["commands.json"] = command_path
    return result, files


def full_frame_check(project, run):
    """Bind the two-frame 960x540 sampler/packer check to frozen build inputs."""
    require(run.parent == VALIDATION, f"full-frame run outside expected directory: {run}")
    result = read_json(run / "result.json")
    expected_params = {"SW": 960, "SH": 540, "BAYER_PHASE": 3,
                       "WB_R_GAIN_Q10": 2400, "WB_B_GAIN_Q10": 2062, "WB_BLACK_LEVEL": 50}
    require(result.get("schema") == "wb565_full_frame_v1" and result.get("accepted") is True and
            result.get("hardware_verified") is False, "full-frame G1 did not pass reviewed offline schema")
    require(Path(result["project"]).resolve() == project and result["manifest_sha256"] == sha(project / "input_manifest.json") and
            result["manifest_entries_verified"] == 220 and result["selected_core_sha256"] == sha(project / "f9p_camera_display_core.v") and
            result["actual_core_parameters"] == expected_params and result["core_verdict_wiring_checked"] is True,
            "full-frame G1 lacks candidate/core/manifest binding")
    inputs = result["inputs"]
    require(set(inputs) == {"bayer565_capture.v", "rgb565_frame_pack_guarded.v", "selected_core.v.snapshot",
                            "input_manifest.json.snapshot", "tb_bayer565_full_frame.sv", "runner.py.snapshot", "golden.json", "golden_crc.hex"},
            "unexpected full-frame evidence inputs")
    files = {"result.json": run / "result.json"}
    for name, digest in inputs.items():
        source = inside(run, name)
        require(source.parent == run and sha(source) == digest, f"changed full-frame input: {name}")
        files[name] = source
    for snapshot, candidate_name in (("bayer565_capture.v", "bayer565_capture.v"),
                                     ("rgb565_frame_pack_guarded.v", "rgb565_frame_pack_guarded.v"),
                                     ("selected_core.v.snapshot", "f9p_camera_display_core.v"),
                                     ("input_manifest.json.snapshot", "input_manifest.json")):
        require(inputs[snapshot] == sha(project / candidate_name), f"full-frame source differs from frozen build: {snapshot}")
    require(read_json(run / "input_manifest.json.snapshot") == read_json(project / "input_manifest.json"), "full-frame manifest content differs")
    # The verification-only full-frame bench is deliberately outside the 220
    # synthesis inputs; its own immutable run snapshot/hash is archived instead.
    core = (run / "selected_core.v.snapshot").read_text(encoding="utf-8")
    selected_core = re.findall(r"bayer565_capture\s*#\((.*?)\)\s+u_cam_preview\s*\((.*?)\);", core, re.S)
    require(len(selected_core) == 1 and
            {name: int(value) for name, value in re.findall(r"\.(\w+)\((\d+)\)", selected_core[0][0])} == expected_params,
            "full-frame selected core parameters differ")
    ports = dict(re.findall(r"\.(\w+)\((\w+)\)", selected_core[0][1]))
    for kind in ("end", "good", "abort"):
        require(core.count(f".O_frame_{kind}(raw_a_frame_{kind})") == 1 and
                ports.get(f"frame_{kind}") == f"raw_a_frame_{kind}" and ports.get(f"out_frame_{kind}") == f"cap_frame_{kind}",
                "full-frame raw/delayed core verdict wiring differs")
    golden = read_json(run / "golden.json")
    require(golden == result["golden"] and len(golden) == 2, "full-frame golden JSON differs")
    crcs = ("1da3ba2a", "059b4883")
    payload_digests = ("1edd721d28148edef70a4cd8f287fa9d01d269db16bd5fc596459fbfd757e360",
                       "fa4f7cefbd9ca34a0815e4fca0d778c66dc9589ec7a80fb44cf5145ab36c20a5")
    stats = ([265758464, 265234688, 265222400, 265238912], [265863168, 265132544, 265106944, 265237632])
    for index, frame in enumerate(golden):
        require(frame["frame_id"] == index + 1 and frame["pixels"] == 518400 and frame["bytes"] == 1036800 and
                frame["crc32"] == crcs[index] and frame["payload_sha256"] == payload_digests[index] and
                frame["raw_stats_abcd"] == stats[index] and frame["raw_levels_per_channel"] == [1024] * 4,
                "full-frame independent golden values differ")
    require((run / "golden_crc.hex").read_text(encoding="ascii").split() == list(crcs), "full-frame golden CRC file differs")
    expected_pass = ("WB565_FULL_FRAME_PASS frames=2 width=960 height=540 outputs=1036800 payload_words=64800 "
                     "starts=2 footers=2 stats_checks=2 raw_levels_per_channel_per_frame=1024 high_x=760320 high_y=545280 "
                     "gaps=16056 crc0=1da3ba2a crc1=059b4883")
    require(result["pass_line"] == expected_pass, "full-frame coverage/pass marker differs")
    commands = result["commands"]
    require(len(commands) == 3, "incomplete full-frame native commands")
    for index, command in enumerate(commands):
        require(command["exit_code"] == 0 and not any(command["errors"]) and not any(command["warnings"]), "full-frame native command failed")
        log = Path(command["log"]).resolve()
        require(log.parent == run, "full-frame command log leaves selected run")
        require(Path(command["command"][0]).name.lower() == ("vlib.exe", "vlog.exe", "vsim.exe")[index], "unexpected full-frame native command")
        if index:
            clean_sim_log(log)
        files[log.name] = log
    require(commands[1]["command"][1:] == ["-sv", "bayer565_capture.v", "rgb565_frame_pack_guarded.v", "tb_bayer565_full_frame.sv"],
            "full-frame compile sources differ")
    require(all(f"-g{name}={value}" in commands[2]["command"] for name, value in
                (("R_GAIN", 2400), ("B_GAIN", 2062), ("BLACK_LEVEL", 50))), "full-frame simulated gains differ")
    for log in (Path(commands[2]["log"]).resolve(), run / "simulator.log"):
        text = clean_sim_log(log)
        require(expected_pass in text and "WB565_FULL_FRAME_FAIL" not in text, "full-frame GREEN marker missing/fault present")
        files[log.name] = log
    return result, files


def hardening_faults_check(run):
    """Optionally retain the full-frame bench's three explicit X-value controls."""
    source = run / "hardening_faults.json"
    if not source.exists():
        return None, {}
    result = read_json(source)
    require(result.get("schema") == "wb565_full_frame_hardening_faults_v1" and result.get("accepted") is True,
            "full-frame hardening controls did not pass reviewed schema")
    require(Path(result["green_result"]).resolve() == run / "result.json" and
            result["green_result_sha256"] == sha(run / "result.json") and
            result["tb_sha256"] == sha(run / "tb_bayer565_full_frame.sv") and
            result["runner_sha256"] == sha(run / "runner.py.snapshot"), "hardening controls differ from GREEN inputs")
    reasons = {"unknown_pack_valid": "unknown packer valid", "unknown_token": "unknown packer token type",
               "unknown_sampler_control": "unknown sampler control"}
    require(len(result["faults"]) == 3 and {item["case"] for item in result["faults"]} == set(reasons),
            "incomplete X-value hardening controls")
    files = {"hardening_faults.json": source}
    for item in result["faults"]:
        log = Path(item["log"]).resolve()
        require(log.parent == run and item["detected"] is True and item["sha256"] == sha(log) and
                item["expected_reason"] == reasons[item["case"]], "changed/undetected X-value control")
        text = clean_sim_log(log)
        require(re.search(r"WB565_FULL_FRAME_FAIL[^\n]*" + re.escape(item["expected_reason"]), text) and
                "WB565_FULL_FRAME_PASS" not in text, "X-value rejection marker missing")
        files[log.name] = log
    return result, files


def cdc_controls_check(project, run):
    """Check one positive fixture and four rejected routed-netlist mutations."""
    require(run.parent == VALIDATION, f"CDC controls outside expected directory: {run}")
    result = read_json(run / "result.json")
    require(Path(result["source"]).resolve() == project and result["source_sha256"] == sha(project / "capture_routed.v"),
            "CDC controls are not bound to the selected routed netlist")
    checkers = ("audit_display_cdc.py", "review_display_cdc_functions.py", "review_display_cdc_origins.py")
    require(set(result["checker_hashes"]) == set(checkers), "unexpected CDC checker identities")
    files = {"result.json": run / "result.json"}
    for name, digest in result["checker_hashes"].items():
        require(sha(run / name) == sha(ROOT / "tools/td" / name) == digest, f"CDC checker snapshot changed: {name}")
        files["checkers/" + name] = run / name
    # The harness itself is recorded as a current reviewed snapshot, not as a
    # retroactively asserted execution hash (the legacy result has no such field).
    harness = ROOT / "tools/td/test_rgb565_cdc.py"
    files["checkers/test_rgb565_cdc.py.snapshot"] = harness
    cases = result["cases"]
    expected_cases = {"valid": 4, "wrong_truth": 3, "wrong_bit": 1,
                      "wrong_reset_domain": 4, "wrong_byte_clock_selector": 4}
    require(len(cases) == 5 and {item["case"] for item in cases} == set(expected_cases), "incomplete CDC controls")
    require(len({item["mutated_net_sha256"] for item in cases}) == 5, "CDC control netlists are not distinct")
    stages = ((checkers[0], ["--fifo", "u_fifo"], "CAPTURE_CDC_Q_BOUNDARIES 54 SAME_BIT_LINKS 36"),
              (checkers[0], ["--fifo", "u_display_fifo"], "CAPTURE_CDC_Q_BOUNDARIES 54 SAME_BIT_LINKS 36"),
              (checkers[1], [], "DISPLAY_CDC_FUNCTIONS 72 NEGATIVE_TRUTH_REJECTED"),
              (checkers[2], [], "BOUNDARY_REVIEW_PASS"))
    for case in cases:
        label = case["case"]
        case_dir = inside(run, label)
        require(case_dir.parent == run and case["accepted"] is True and
                case["expected"] == ("pass" if label == "valid" else "rejection"), "CDC case acceptance differs")
        mutated = case_dir / "capture_routed.v"
        require(sha(mutated) == case["mutated_net_sha256"], "CDC mutant identity changed")
        if label == "valid":
            require(mutated.read_bytes() == (project / "capture_routed.v").read_bytes().replace(b"\r\n", b"\n"),
                    "positive CDC fixture differs beyond newline normalization")
        require(len(case["runs"]) == expected_cases[label], "CDC control stage count differs")
        for index, entry in enumerate(case["runs"]):
            checker, args, marker = stages[index]
            command = entry["command"]
            require(command[1:3] == ["-X", "utf8"] and Path(command[3]).resolve() == run / checker and
                    Path(command[4]).resolve() == case_dir and command[5:] == args, "CDC checker command/fixture differs")
            log = inside(run, entry["log"])
            require(log.parent == case_dir, "CDC control log leaves selected case")
            text = log.read_text(encoding="utf-8", errors="replace")
            rejection = label != "valid" and index == len(case["runs"]) - 1
            if rejection:
                require(entry["exit_code"] != 0 and "AssertionError" in text, "CDC mutant was not rejected by assertion")
            else:
                require(entry["exit_code"] == 0 and marker in text and "Traceback" not in text and "AssertionError" not in text,
                        "CDC positive prefix failed/incomplete")
            files[entry["log"]] = log
    return {**result, "current_harness_snapshot_sha256": sha(harness)}, files


def archive(project, g1_run, pipeline_run, full_frame_run, cdc_controls_run, matrix_run, red_run, check_only=False):
    require(__debug__, "run this validator without Python -O")
    project, g1_run, pipeline_run = project.resolve(), g1_run.resolve(), pipeline_run.resolve()
    full_frame_run = full_frame_run.resolve()
    cdc_controls_run = cdc_controls_run.resolve()
    matrix_run, red_run = matrix_run.resolve(), red_run.resolve()
    require(project.parent == PROJECTS and project.name.startswith("camera_rgb565_wb_"), "unsupported candidate path")
    for run in (g1_run, pipeline_run, full_frame_run, cdc_controls_run, matrix_run, red_run):
        require(run.parent == VALIDATION, f"validation run outside expected directory: {run}")
    destination = ROOT / "docs/evidence" / project.name
    summary_path = destination.with_suffix(".json")
    require(not destination.exists() and not summary_path.exists(), "refusing to overwrite an evidence archive")
    overlay = read_json(project / "white_balance_overlay.json")
    require(overlay["input_count"] == 220, "expected 220-input pipeline candidate; old failed candidate is unsupported")
    manifest = manifest_check(project, overlay["input_count"])
    manifest_digest = sha(project / "input_manifest.json")
    require(Path(overlay["base"]).resolve() == BASE and overlay["input_count"] == len(manifest), "wrong candidate base/count")
    expected = {"SW": 960, "SH": 540, "BAYER_PHASE": 3,
                "WB_R_GAIN_Q10": 2400, "WB_B_GAIN_Q10": 2062, "WB_BLACK_LEVEL": 50}
    require((overlay["phase"], overlay["R_gain_Q10"], overlay["B_gain_Q10"], overlay["black_level"]) ==
            (3, 2400, 2062, 50), "unexpected calibration")
    core = (project / "f9p_camera_display_core.v").read_text(encoding="utf-8")
    chosen = re.findall(r"bayer565_capture\s*#\((.*?)\)\s*\w+\s*\(", core, re.S)
    require(len(chosen) == 1, "ambiguous selected sampler instance")
    params = {name: int(value) for name, value in re.findall(r"\.(\w+)\((\d+)\)", chosen[0])}
    require(params == expected, "actual selected sampler parameters differ")
    for relative, entry in overlay["changes"].items():
        require(manifest.get(relative) == entry["sha256"], f"overlay/input mismatch: {relative}")
    require(overlay["measurement_sha256"] == sha(project / "frozen_white_balance_stats.json"), "measurement mismatch")

    # Stage acceptance is checked again against current bytes; exit 0 alone is insufficient.
    phases = {}
    for stage, (marker, script, required_artifacts) in STAGES.items():
        record = read_json(project / f"native_{stage}.json")
        log = project / f"native_{stage}.txt"
        require(record.get("stage") == stage and Path(record["cwd"]).resolve() == project, f"wrong native identity: {stage}")
        require(record.get("accepted") is True and record.get("exit_code") == 0 and not record.get("timed_out"), f"native stage failed: {stage}")
        require(record.get("hardware_download") is False, f"unexpected hardware stage: {stage}")
        require(record.get("expected_marker") == marker and record.get("marker_present") is True, f"wrong marker record: {stage}")
        require(marker in log.read_text(errors="replace") and record["log_sha256"] == sha(log), f"native log changed: {stage}")
        require(record["script_sha256"] == sha(project / script), f"native script changed: {stage}")
        require(record["input_manifest_sha256"] == manifest_digest, f"native inputs differ: {stage}")
        artifacts = record.get("artifacts", {})
        require(all(name in artifacts for name in required_artifacts), f"missing required native artifact: {stage}")
        for relative, digest in artifacts.items():
            source = inside(project, relative)
            require(digest and source.stat().st_size and sha(source) == digest, f"native artifact changed/missing: {stage}/{relative}")
        phases[stage] = record

    db_digest = sha(project / "csi_checked_debug_pr.db")
    require(phases["route"]["artifacts"]["csi_checked_debug_pr.db"] == db_digest, "selected DB differs from route DB")
    require(all(record.get("selected_db_sha256") == db_digest for stage, record in phases.items() if stage != "build"),
            "native stages did not use the same selected DB")
    final_reports = {"candidate_timing.rpt", "candidate_skew.rpt", "candidate_ignored.rpt", "candidate_abnormal.rpt"}
    require(final_reports.issubset(phases["bitgen"]["artifacts"]), "bitgen record omits final timing report identities")
    net_digest = sha(project / "capture_routed.v")
    timing = (project / "candidate_timing.rpt").read_text(errors="replace")
    setup = re.search(r"SWNS:\s*([-+0-9.]+)ns, STNS:\s*([-+0-9.]+)ns", timing)
    hold = re.search(r"HWNS:\s*([-+0-9.]+)ns, HTNS:\s*([-+0-9.]+)ns", timing)
    period = re.search(r"Period Check WNS:\s*([-+0-9.]+)ns", timing)
    require(setup and hold and period, "missing final STA summaries")
    slacks = {"setup_ns": float(setup[1]), "hold_ns": float(hold[1]), "period_ns": float(period[1])}
    require(min(slacks.values()) >= 0 and float(setup[2]) == float(hold[2]) == 0, "final STA failed")
    violations = [int(value) for value in re.findall(r"(\d+)\s+Viol Endpoints", timing)]
    require(violations and max(violations) == 0, "final STA has violating endpoints or missing counts")
    require(not re.search(r"End Point\s*:", (project / "candidate_abnormal.rpt").read_text(errors="replace")), "abnormal timing endpoints")
    skew_text = (project / "candidate_skew.rpt").read_text(errors="replace")
    skews = [float(value) for value in re.findall(r"^Slack +: ([-+0-9.]+)ns", skew_text, re.M)]
    require(len(re.findall(r"^[0-9]+,  set_path_skew", skew_text, re.M)) == 4 and len(skews) >= 4 and min(skews) >= 0, "Gray-bus skew failed/incomplete")

    connections = read_json(project / "rgb565_connections.json")
    require(connections["netlist_sha256"] == net_digest and connections["sampled_bits"] == 16, "routed RGB565 width audit differs")
    require(len(connections["rows"]) == 16 and {row["bit"] for row in connections["rows"]} == set(range(16)), "incomplete routed RGB565 bits")
    cdc = [read_json(project / (fifo + "_cdc_audit.json")) for fifo in ("u_fifo", "u_display_fifo")]
    require(all(item["sha256"] == net_digest for item in cdc), "CDC audit netlist differs")
    require(all(item["q_drivers"] == 54 and item["same_bit_stage_links"] == 36 for item in cdc), "incomplete CDC Q/link audit")
    functions = read_json(project / "display_cdc_functions.json")
    require(functions["netlist_sha256"] == net_digest and functions["checked_sync_ff_functions"] == 72 and
            len(functions["rows"]) == 72 and functions["negative_truth_table_rejected"] is True, "incomplete CDC function audit")
    origins = (project / "cdc_reset_clock_review.txt").read_text(errors="replace")
    require(origins.startswith("NETLIST_SHA256=" + net_digest + "\n") and "BOUNDARY:" in origins, "CDC origins review netlist differs")
    hdmi = read_json(project / "hdmi_selected_audit.json")
    require(hdmi["netlist_sha256"] == net_digest and hdmi["report_sha256"] == sha(project / "hdmi_data_paths.rpt"), "HDMI audit source differs")
    require((hdmi["paths"], hdmi["endpoints"], hdmi["pads"], hdmi["channels"], hdmi["bits_per_channel"],
             hdmi["iotype"], hdmi["serializer"]) == (68, 34, 4, 3, 10, "LVDS33_E", "DDRX5") and
            hdmi["min_parallel_slack_ns"] >= 0, "incomplete/failed HDMI parallel audit")

    bit = project / "camera_ddr_display.bit"
    cwc = project / "camera_ddr_display.cwc"
    bid = project / "camera_ddr_display_inst.bid"
    require(bit.read_bytes() == (project / "cw/compiled.bit").read_bytes(), "debug setup changed compiled bit")
    require(cwc.read_bytes() == (project / "cw/compiled.cwc").read_bytes(), "root and compiled CWC differ")
    instances = check_readback(ET.parse(cwc).getroot(), ET.parse(bid).getroot())
    require(len(instances) == 3 and {entry["name"] for entry in instances} ==
            {"auto_created_cwc1", "auto_created_cwc2", "auto_created_cwc3"}, "wrong runtime debug cores")

    g1 = read_json(g1_run / "result.json")
    require(g1.get("accepted") is True and g1.get("hardware_verified") is False, "candidate G1 not accepted/offline")
    require(Path(g1["project"]).resolve() == project and g1["manifest_sha256"] == manifest_digest and
            g1["selected_core_sha256"] == sha(project / "f9p_camera_display_core.v") and
            g1["actual_core_parameters"] == expected, "candidate G1 not bound to actual parameters")
    require(g1["inputs"]["bayer565_capture.v"] == sha(project / "bayer565_capture.v") and
            g1["inputs"]["tb_bayer565_white_balance.sv"] == sha(project / "frozen_tb_bayer565_white_balance.sv") and
            g1["inputs"]["selected_core.v.snapshot"] == sha(project / "f9p_camera_display_core.v"), "candidate G1 input version differs")
    require(set(g1["inputs"]) == {"bayer565_capture.v", "tb_bayer565_white_balance.sv", "selected_core.v.snapshot", "runner.py.snapshot"},
            "unexpected candidate G1 payloads")
    for relative, digest in g1["inputs"].items():
        require(sha(inside(g1_run, relative)) == digest, f"candidate G1 frozen source changed: {relative}")
    require(len(g1["commands"]) == 3, "incomplete candidate simulator commands")
    for command in g1["commands"]:
        require(command["exit_code"] == 0 and not any(command["errors"]) and not any(command["warnings"]), "candidate simulator command failed")
        clean_sim_log(inside(g1_run, command["log"])) if command["log"] != "0.log" else None
    simulation_command = g1["commands"][-1]["command"]
    require(all(f"-g{name}={value}" in simulation_command for name, value in
                (("R_GAIN", 2400), ("B_GAIN", 2062), ("BLACK_LEVEL", 50))), "actual G1 invocation gains differ")
    pass_check(g1_run / g1["commands"][-1]["log"], 2400, 2062, 50)
    pipeline, pipeline_files = pipeline_check(project, pipeline_run)
    full_frame, full_frame_files = full_frame_check(project, full_frame_run)
    hardening, hardening_files = hardening_faults_check(full_frame_run)
    cdc_controls, cdc_control_files = cdc_controls_check(project, cdc_controls_run)

    snapshot_hashes(matrix_run)
    snapshot_hashes(red_run)
    matrix = list(csv.DictReader(io.StringIO((matrix_run / "summary.csv").read_text(encoding="utf-8-sig"))))
    expected_cases = {"measured_bl50", "unity_bl0", "unity_bl50", "unity_bl1023", "maximum_bl50",
                      "asymmetric_bl0", "zero_bl50", "negative_half_tie_bl50"}
    require(len(matrix) == 8 and {row["Case"] for row in matrix} == expected_cases, "incomplete arithmetic matrix")
    clean_sim_log(matrix_run / "compile.log")
    require(sha(matrix_run / "bayer565_capture.v") == sha(project / "bayer565_capture.v") and
            sha(matrix_run / "tb_bayer565_white_balance.sv") == sha(project / "frozen_tb_bayer565_white_balance.sv"),
            "arithmetic matrix must cover the current pipeline sampler and testbench")
    for row in matrix:
        require(row["Result"] == "PASS" and row["Frames"] == "9" and row["Outputs"] == row["OutputChecks"] == "1152" and
                row["RLevels"] == row["BLevels"] == "1024", "failed/incomplete arithmetic matrix case")
        pass_check(matrix_run / (row["Case"] + "_run.log"), int(row["R"]), int(row["B"]), int(row["BlackLevel"]))
    clean_sim_log(red_run / "compile.log")
    for name, expected_output in (("legacy_red_run.log", "4944"), ("calibrated_red_run.log", "6144")):
        text = clean_sim_log(red_run / name)
        require("WB565_FAIL color frame=0 index=0 got=3143 expected=" + expected_output in text and "WB565_PASS" not in text,
                "historical old-RTL negative control no longer fails as expected")
    pass_check(red_run / "unity50_run.log", 1024, 1024, 50)

    base_manifest = manifest_check(BASE, 215)
    prior_summary = ROOT / "docs/evidence/rgb565_20261014.json"
    prior = read_json(prior_summary)
    require(Path(prior["project"]).resolve() == BASE and prior["input_manifest_sha256"] == sha(BASE / "input_manifest.json"), "backend reference manifest differs")
    require(prior["bit"]["sha256"] == sha(BASE / "camera_ddr_display.bit"), "backend reference bit differs")
    unchanged = overlay["unchanged_hashes"]
    required_unchanged = {"rgb565_frame_pack_guarded.v", "rgb565_display_read.v", "rgb565_display_pixels.v",
                          "camera_rgb565_display_guarded.v", "camera_ddr_display_top.v", "ddrmc_display_top.v",
                          "ddr_frame_store.v", "capture_async_fifo.v", "board.adc", "timing.sdc",
                          "camera/uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v",
                          "camera/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack_checked.v",
                          "camera/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v",
                          "camera/uisrc/01_rtl/raw10_display60_clocks.v"}
    require(required_unchanged.issubset(unchanged), "missing backend reuse boundaries")
    for relative, digest in unchanged.items():
        require(base_manifest.get(relative) == manifest.get(relative) == digest, f"backend reuse input differs: {relative}")

    # Plan and read every archive payload before creating any destination.
    # Cached bytes prevent a concurrent source edit producing a mixed archive.
    payloads = {}
    artifacts = {}

    def retain(source, relative):
        require(relative not in payloads, f"duplicate archive path: {relative}")
        target = inside(destination, relative)
        require(target.is_relative_to(destination), "invalid archive target")
        require(source.is_file(), f"missing archive source: {source}")
        data = source.read_bytes()
        payloads[relative] = data
        artifacts[relative] = {"source": str(source), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

    for stage in STAGES:
        for suffix in ("json", "txt"):
            name = f"native_{stage}.{suffix}"
            retain(project / name, "g2/" + name)
    retain(project / "camera_ddr_display_Runs/syn_1/run.log", "g2/synthesis_worker.txt")
    report_names = ["candidate_timing.rpt", "candidate_ignored.rpt", "candidate_abnormal.rpt", "candidate_skew.rpt",
                    "capture_timing.rpt", "capture_skew.rpt", "capture.area", "hdmi_clocks.rpt", "hdmi_targets.txt",
                    "hdmi_data_paths.rpt", "hdmi_selected_audit.json", "hdmi_pad_excerpt.v.txt", "rgb565_connections.json",
                    "rgb565_connections_excerpt.v.txt", "u_fifo_cdc_audit.json", "u_display_fifo_cdc_audit.json",
                    "display_cdc_functions.json", "cdc_reset_clock_review.txt", "u_fifo_cdc_excerpt.v", "u_display_fifo_cdc_excerpt.v"]
    for name in report_names:
        retain(project / name, "g2/" + name)
    for name in ("input_manifest.json", "white_balance_overlay.json", "frozen_white_balance_stats.json",
                 "frozen_prepare_rgb565_white_balance.py", "frozen_tb_bayer565_white_balance.sv", "bayer565_capture.v",
                 "frozen_tb_bayer565_pipeline.sv", "frozen_unpipelined_bayer565_capture.v",
                 "f9p_camera_display_core.v", "camera_ddr_display_top.v", "ddrmc_display_top.v", "board.adc", "timing.sdc"):
        retain(project / name, "source/" + name)
    for _, script, _ in STAGES.values():
        retain(project / script, "g2/scripts/" + script)
    for name in ("inspect_rgb332_body.tcl", "bitgen_rgb332_body.tcl"):
        retain(project / name, "g2/scripts/" + name)
    retain(cwc, "debug/camera_ddr_display.cwc")
    retain(bid, "debug/camera_ddr_display_inst.bid")
    for name in ("result.json", *g1["inputs"], *(item["log"] for item in g1["commands"])):
        retain(g1_run / name, "g1/candidate/" + name)
    for name, source in pipeline_files.items():
        retain(source, "g1/pipeline/" + name)
    for name, source in full_frame_files.items():
        retain(source, "g1/full_frame/" + name)
    for name, source in hardening_files.items():
        retain(source, "g1/full_frame/" + name)
    for name, source in cdc_control_files.items():
        retain(source, "g2/controls/" + name)
    for kind, run in (("arithmetic_matrix", matrix_run), ("historical_red", red_run)):
        for source in sorted(run.iterdir()):
            if source.is_file() and (source.suffix in (".log", ".json", ".csv", ".v", ".sv", ".ps1") or source.name.endswith("_command.txt")):
                retain(source, "g1/" + kind + "/" + source.name)
    retain(BASE / "input_manifest.json", "reuse/base_input_manifest.json")
    retain(prior_summary, "reuse/rgb565_20261014.json")
    retain(Path(__file__), "archive_white_balance.py.txt")
    report_digests = {name: sha(project / name) for name in report_names}
    summary = {
        "recorded_at": datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        "project": str(project), "base_project": str(BASE), "input_count": len(manifest),
        "input_manifest_sha256": manifest_digest, "calibration": expected,
        "bit": {"path": str(bit), "bytes": bit.stat().st_size, "sha256": sha(bit)},
        "selected_db": {"path": str(project / "csi_checked_debug_pr.db"), "sha256": db_digest},
        "routed_netlist_sha256": net_digest,
        "debug": {"cwc_sha256": sha(cwc), "bid_sha256": sha(bid), "compiled_bit_identical": True, "instances": instances},
        "format": {"preview": [960, 540], "display": [1920, 1080, 60], "camera_fps": 30, "pixel": "RGB565 little-endian"},
        "g1": {"candidate": g1, "pipeline": pipeline, "full_frame": full_frame, "arithmetic_matrix": matrix,
               "full_frame_hardening_faults": hardening,
               "matrix_source_matches_candidate": sha(matrix_run / "bayer565_capture.v") == sha(project / "bayer565_capture.v"),
               "matrix_testbench_matches_candidate": sha(matrix_run / "tb_bayer565_white_balance.sv") == sha(project / "frozen_tb_bayer565_white_balance.sv"),
               "historical_red_negative_controls_rejected_old_rtl": True,
               "boundary": "Fresh candidate G1 binds actual sampler/core/parameters at reduced 16x8 geometry. Pipeline equivalence binds the frozen sampler/packer/reference and uses a 16x2 fixture. Full-frame G1 covers two 960x540 sampler/packer frames only, with its verification-only TB outside the synthesis manifest; no CSI, DDR, HDMI or timing simulation claim. The matrix covers this sampler revision; historical red evidence covers its own frozen source only."},
        "backend_reuse": {"reference": "reuse/rgb565_20261014.json", "reference_summary_sha256": sha(prior_summary),
                          "unchanged_hashes": unchanged, "boundary": "Reuse only for these unchanged backend/clock/constraint inputs; no reuse of prior placement or timing results."},
        "g2": {"accepted": True, "phases": phases, **slacks, "tns_zero": True, "skew_groups": 4, "skew_ns": skews,
               "report_sha256": report_digests, "q_drivers": 108, "same_bit_stage_links": 72,
               "sync_functions": 72, "connections": connections, "hdmi": hdmi, "fault_controls": cdc_controls},
        "g3": "not_run", "g4": "not_run", "hardware_download": False,
        "limits": ["Phase3 and fixed white-balance gains are measured-scene candidates; corrected colors require new-bit board acceptance.",
                   "The nominal RAW10 pedestal 50 is programmed/documented, not measured dark offsets or I2C readback.",
                   "No automatic white balance, calibrated gamma/color matrix or full-resolution ISP.",
                   "Activity sparkles remain deferred and unresolved; long-run/temperature stability is unverified.",
                   "HDMI parallel STA does not qualify 1485 Mbps serial electrical/thermal operation; timing coverage gaps and local-clock warnings require separate assessment.",
                   "Selected structural CDC/reset checks do not prove all-system CDC, metastability MTBF or reset recovery/removal."],
        "artifacts": artifacts,
    }
    # Recheck sources after validation and payload collection; then write once.
    for entry in artifacts.values():
        require(sha(Path(entry["source"])) == entry["sha256"], f"source changed during archive: {entry['source']}")
    require(manifest_check(project, 220) == manifest and sha(project / "input_manifest.json") == manifest_digest,
            "frozen inputs changed during archive")
    require(sha(bit) == summary["bit"]["sha256"] and sha(project / "csi_checked_debug_pr.db") == db_digest and
            sha(project / "capture_routed.v") == net_digest, "large identity changed during archive")
    if check_only:
        print(json.dumps({"accepted": True, "check_only": True, "project": str(project), "artifacts": len(payloads), **slacks}, indent=2))
        return
    destination.mkdir()
    for relative, data in payloads.items():
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as stream:
            stream.write(data)
        require(sha(target) == artifacts[relative]["sha256"], f"archive copy mismatch: {relative}")
    with summary_path.open("xb") as stream:
        stream.write((json.dumps(summary, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
    print(json.dumps({"accepted": True, "evidence": str(destination), "summary": str(summary_path),
                      "raw_artifacts": len(artifacts), "bit": summary["bit"], **slacks, "g3": "not_run"}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path)
    parser.add_argument("--g1", required=True, type=Path, help="Fresh candidate-bound G1 run")
    parser.add_argument("--pipeline", required=True, type=Path, help="Fresh candidate-bound pipeline equivalence G1 run")
    parser.add_argument("--full-frame", required=True, type=Path, help="Fresh candidate-bound two-frame 960x540 sampler/packer G1 run")
    parser.add_argument("--cdc-controls", required=True, type=Path, help="One positive and four rejected CDC netlist controls for this route")
    parser.add_argument("--matrix", required=True, type=Path, help="Eight-configuration arithmetic matrix for this sampler revision")
    parser.add_argument("--red", type=Path, default=VALIDATION / "wb565_blacklevel_red_20261014_01")
    parser.add_argument("--check-only", action="store_true", help="Validate all gates without creating output")
    args = parser.parse_args()
    try:
        archive(args.project, args.g1, args.pipeline, args.full_frame, args.cdc_controls, args.matrix, args.red, args.check_only)
    except (AssertionError, ValueError, KeyError, TypeError, OSError, ET.ParseError) as error:
        print(json.dumps({"accepted": False, "reason": str(error)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
