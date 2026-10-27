#!/usr/bin/env python3
"""mk_manifest_b12.py -- freeze the T10.b12-r1-last r0 candidate.

Writes r0/CANDIDATE-MANIFEST-b12-r1-last-r0.json and r0/artifact-hashes.txt.
Every listed file must exist (missing -> MISSING marker, non-zero exit).
"""
import datetime
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b12-r1-last"
R0 = RUN / "r0"
B11 = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/r0"
GAP = ROOT / "work/b10-gap-sim-20261025-132023"

SRC = [
    R0 / "changed-src/a1_raw_crop.v",
    R0 / "changed-src/a1_ddr_slot_store.v",
    R0 / "changed-src/a1_uart_export.v",
    R0 / "changed-src/camera_a1_uart_top.v",
    R0 / "changed-src/cam_diag_mailbox.v",
    R0 / "changed-src/a1_frame_top.v",
    R0 / "changed-src/a1_deflate_core.v",
    R0 / "changed-src/p2_ddr_bridge.v",
    R0 / "changed-src/p2_a1_board_top.v",
]
REPO = [
    ROOT / "fpga/csi2/src/a1/a1_ddr_arb2.v",
    ROOT / "fpga/csi2/src/mem/capture_async_fifo.v",
]
TD = [
    R0 / "td/01_build.tcl", R0 / "td/02_bitgen.tcl", R0 / "td/03_cwc.tcl",
    R0 / "td/a1_board.al", R0 / "td/p2_board.sdc", R0 / "td/board_p2.adc",
    R0 / "td/a1_eng_top.v", R0 / "td/a1_small_top.sdc",
    R0 / "td/run_build_b12.ps1",
    R0 / "td/a1_board.bit", R0 / "td/a1_board.cwc", R0 / "td/a1_board_inst.bid",
    R0 / "td/cw/compiled.bit", R0 / "td/cw/compiled.cwc",
    R0 / "td/routed_qor.rpt", R0 / "td/routed_timing_status.rpt",
    R0 / "td/route_flow.status", R0 / "td/place_flow.status",
    R0 / "td/routed_timing_summary.rpt", R0 / "td/routed_area.rpt",
    R0 / "td/build_console_b12.log", R0 / "td/bitgen_console_b12.log",
    R0 / "td/cwc_console_b12.log",
]
SIM = [
    R0 / "sim/run_r1.py", R0 / "sim/run_b12.py", R0 / "sim/run_t7.py",
    R0 / "sim/tb_store_r1.v", R0 / "sim/tb_r1_sof.sv", R0 / "sim/check_t7.py",
    R0 / "sim/tb_p1_chain.v", R0 / "sim/tb_b11_read.sv", R0 / "sim/tb_status_v4.v",
    R0 / "sim/tb_b11_full.v", R0 / "sim/tb_raw_store.v",
    R0 / "sim/p2_paxi_model.v", R0 / "sim/p2_paxi_model_b11.v", R0 / "sim/a1_ddr_model.v",
    R0 / "sim/r1-b11/tb_r1_loss.sv", R0 / "sim/r1-b11/check_r1.py",
    R0 / "sim/r1-b11/ddr_recovery_model.sv",
    R0 / "sim/r1-b12/tb_r1_loss.sv", R0 / "sim/r1-b12/check_r1.py",
    R0 / "sim/r1-b12/ddr_recovery_model.sv",
    R0 / "sim/T10/run_multi_b12.py", R0 / "sim/T10/tb_b10_multi_strict.sv",
    R0 / "sim/T10/check_strict.py", R0 / "sim/T10/check_v4_frames.py",
    R0 / "sim/T10/a1_pattern_reference.py",
    R0 / "sim/sim-results-b12.json",
    R0 / "sim/run-b11/summary.json", R0 / "sim/run-b11/loss/result.json",
    R0 / "sim/run-b12/summary.json", R0 / "sim/run-b12/loss/result.json",
    R0 / "sim/run-t7/case2/result.json", R0 / "sim/run-t7/summary.json",
    R0 / "sim/T10/summary.json", R0 / "sim/T10/triple/result.json",
    R0 / "sim/T10/control/result.json",
]
BOARD = [
    R0 / "board/ftdi-preflight.log",
]
DOCS = [
    R0 / "diag/r1-root-cause.md", R0 / "rtl-diff-r0.patch",
    R0 / "result-r0.md", R0 / "lessons-r0.md",
]
BASE = [
    B11 / "CANDIDATE-MANIFEST-b11-aplus-read-r0.json", B11 / "result-r0.md",
    B11 / "changed-src/camera_a1_uart_top.v", B11 / "changed-src/a1_ddr_slot_store.v",
    B11 / "diag/read-stall-analysis.md",
    GAP / "README.md", GAP / "r1-loss/result.md", GAP / "r1-loss/check_r1.py",
    GAP / "multi-frame/result.md",
    RUN / "dispatch.json", RUN / "dev-plan.md", RUN / "handoff.md",
]


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def rel(p):
    try:
        return str(pathlib.Path(p).relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(p).replace("\\", "/")


def main():
    missing = []
    groups = {"changed_src": SRC, "repo_deps": REPO, "td": TD, "sim": SIM,
              "board": BOARD, "docs": DOCS, "baseline": BASE}
    out = {"manifest": "CANDIDATE-MANIFEST-b12-r1-last-r0",
           "task_id": "T10.b12-r1-last",
           "run_id": "20261020-0209_singleA_aplus_closedloop",
           "created": datetime.datetime.now().isoformat(timespec="seconds"),
           "status": "ready_for_test",
           "parent_task": "T10 (stays blocked; this package does not close T10)",
           "only_changed_source": [
               "changed-src/camera_a1_uart_top.v",
               "changed-src/a1_ddr_slot_store.v",
           ],
           "unchanged_source_verified_against_b11": [
               "changed-src/a1_uart_export.v", "changed-src/a1_frame_top.v",
               "changed-src/a1_deflate_core.v", "changed-src/a1_raw_crop.v",
               "changed-src/cam_diag_mailbox.v", "changed-src/p2_ddr_bridge.v",
               "changed-src/p2_a1_board_top.v",
           ],
           "notes": [
               "R1 fix only: clk_cam sticky loss-abort on any FIFO-rejected beat, A1 stray-beat consumption, store abort dominance + abort/begin same-cycle handover.",
               "v4 225 B / 55 fields / single-edge snapshot untouched; b11 read-path diagnosis untouched.",
               "Board was not downloaded: FTDI 0403:6042 absent at preflight (board=blocked, 0 downloads, 0 COM8).",
               "1176-word read stop remains H2/H4 and is not addressed here.",
           ], "groups": {}}
    lines = []
    for g, files in groups.items():
        out["groups"][g] = []
        for f in files:
            h = sha(f)
            if h == "MISSING":
                missing.append(rel(f))
            out["groups"][g].append({"path": rel(f), "sha256": h,
                                     "bytes": f.stat().st_size if f.exists() else 0})
            lines.append("%s  %s" % (h, rel(f)))
    (R0 / "artifact-hashes.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (RUN / "CANDIDATE-MANIFEST-b12-r1-last-r0.json").write_text(
        json.dumps(out, indent=2), encoding="utf-8")
    print("files=%d missing=%d" % (sum(len(v) for v in groups.values()), len(missing)))
    for m in missing:
        print("  MISSING", m)
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
