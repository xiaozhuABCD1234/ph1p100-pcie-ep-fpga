#!/usr/bin/env python3
"""mk_manifest_b12.py -- freeze the T10.b12-r1-last r0 candidate.

Writes CANDIDATE-MANIFEST-b12-r1-last-r0.json (project-relative paths) and
r0/artifact-hashes.txt.  Run it only AFTER the bitgen/CWC step: every listed
artifact must exist, otherwise the script fails instead of writing a partial
manifest.
"""
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
R0 = RUN / "T10.b12-r1-last/r0"


def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()


def rel(p):
    return pathlib.Path(p).resolve().relative_to(ROOT).as_posix()


def group(paths, optional=()):
    out = []
    for p in list(paths) + list(optional):
        p = pathlib.Path(p)
        if not p.exists():
            if p in optional:
                continue
            raise SystemExit("missing required artifact: %s" % p)
        out.append(dict(path=rel(p), sha256=sha(p), bytes=p.stat().st_size))
    return out


def globs(patterns):
    out = []
    for pat in patterns:
        out.extend(sorted(R0.glob(pat)))
    return out


CHANGED = ["a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_uart_export.v", "camera_a1_uart_top.v",
           "cam_diag_mailbox.v", "a1_frame_top.v", "a1_deflate_core.v", "p2_ddr_bridge.v",
           "p2_a1_board_top.v"]

manifest = {
    "manifest": "CANDIDATE-MANIFEST-b12-r1-last-r0",
    "task_id": "T10.b12-r1-last",
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "parent_task": "T10 (stays blocked)",
    "status": "blocked_routed_wns_below_floor",
    "build": {
        "routed_swNs_run1": 0.003,
        "routed_swNs_run2": 0.003,
        "routed_hwns": 0.020,
        "routed_violation_endpoints": 0,
        "routed_total_endpoints": 25697,
        "period_check_wns_ns": 2.200,
        "syn_swNs": 0.121,
        "eram": 72,
        "slice": 18370,
        "reg": 19539,
        "bitgen": 0,
        "cwc": 0,
        "downloads": 0,
        "reason": "Routed SWNS +0.003 < dev-plan section 6 hard floor +0.015 in two identical route runs; "
                  "worst setup path is the frozen A+ core adder (u_a1/u_core/len_r_reg -> add9), not the vendor "
                  "DDR PHY and not the R1 logic, so the observation-trim exception does not apply. build stopped, "
                  "no bitstream, no CWC, no download.",
    },
    "board": {"status": "blocked", "reason": "FTDI_0403:6042_absent", "downloads": 0, "com8_opened": 0,
              "flash": 0},
    "frozen_source_baseline": "T10.b11-aplus-read/r0 (v4 225 B + F_WAIT watchdog)",
    "r1_fix": [
        "camera_a1_uart_top.v clk_cam: sticky abort_hold on any FIFO-rejected beat",
        "camera_a1_uart_top.v A1: fifo_ready consumes an unowned stray data beat",
        "a1_ddr_slot_store.v: abort dominates same-cycle wr_last/wr_ready; abort+begin same cycle releases the old slot and starts the new frame",
    ],
    "unchanged_vs_b11": [n for n in CHANGED if n not in ("camera_a1_uart_top.v", "a1_ddr_slot_store.v")],
    "groups": {
        "changed_src": group([R0 / "changed-src" / n for n in CHANGED]),
        "repo_deps": group([ROOT / "fpga/csi2/src/a1/a1_ddr_arb2.v",
                            ROOT / "fpga/csi2/src/mem/capture_async_fifo.v"]),
        "diff_doc": group([R0 / "rtl-diff-r0.patch", R0 / "diag/r1-root-cause.md",
                           R0 / "result-r0.md", R0 / "lessons-r0.md"]),
        "td": group([R0 / "td" / n for n in
                     ("01_build.tcl", "02_bitgen.tcl", "03_cwc.tcl", "a1_board.al",
                      "p2_board.sdc", "board_p2.adc", "a1_eng_top.v", "a1_small_top.sdc",
                      "routed_qor.rpt", "routed_timing_status.rpt", "routed_timing_summary.rpt",
                      "routed_timing.rpt", "route_flow.status", "build_console_b12.log",
                      "route-run1-routed_qor.rpt", "route-run1-routed_timing_status.rpt",
                      "route-run1-build_console_b12.log", "run_build_b12.ps1")],
                    optional=[R0 / "td" / n for n in
                              ("a1_board.bit", "a1_board.cwc", "a1_board_inst.bid",
                               "cw/compiled.bit", "cw/compiled.cwc",
                               "bitgen_console_b12.log", "cwc_console_b12.log")]),
        "sim_entry": group([R0 / "sim" / n for n in
                            ("run_b12.py", "check_t7.py", "check_multi_b12.py",
                             "tb_store_r1.v", "tb_r1_sof.v", "tb_b10_multi_b12.sv",
                             "indep/tb_r1_loss.sv", "indep/check_r1.py",
                             "indep/ddr_recovery_model.sv", "indep/tb_b10_multi_strict.sv")]),
        "board": group([R0 / "board/ftdi-preflight.log"]),
    },
}

# result JSONs and captured golden streams (level files only)
sim_files = globs(["sim-results-b12-*.json"])
sim_files += globs(["cases/*/*/result.json", "cases/r1/*/result.json", "cases/multi/*/result.json"])
sim_files += globs(["caps/*.dec", "caps/*.stats"])
manifest["groups"]["sim_evidence"] = group(sorted(set(sim_files)))

(RUN / "T10.b12-r1-last/CANDIDATE-MANIFEST-b12-r1-last-r0.json").write_text(
    json.dumps(manifest, indent=2), encoding="utf-8")

lines = []
for gname, items in manifest["groups"].items():
    for it in items:
        lines.append("%s  %s  %s" % (it["sha256"], it["bytes"], it["path"]))
(R0 / "artifact-hashes.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

n = sum(len(v) for v in manifest["groups"].values())
print("MANIFEST_OK groups=%d files=%d" % (len(manifest["groups"]), n))
for it in manifest["groups"]["td"]:
    if it["path"].endswith((".bit", ".cwc", ".bid")):
        print("  %s %s" % (it["sha256"], it["path"]))
sys.exit(0)
