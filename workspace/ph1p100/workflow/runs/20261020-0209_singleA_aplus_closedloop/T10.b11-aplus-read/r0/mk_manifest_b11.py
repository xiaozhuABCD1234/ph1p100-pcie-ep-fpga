#!/usr/bin/env python3
"""mk_manifest_b11.py -- freeze the T10.b11-aplus-read r0 candidate.

Writes:
    r0/CANDIDATE-MANIFEST-b11-aplus-read-r0.json
    r0/artifact-hashes.txt
Every listed file must exist (missing -> MISSING marker, non-zero exit) so the
manifest can never silently describe a file that is not there.
"""
import hashlib
import json
import pathlib
import sys
import datetime

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read"
R0 = RUN / "r0"

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
    R0 / "td/a1_board.bit", R0 / "td/a1_board.cwc", R0 / "td/a1_board_inst.bid",
    R0 / "td/routed_qor.rpt", R0 / "td/routed_timing_status.rpt",
    R0 / "td/route_flow.status", R0 / "td/build_console_b11.log",
    R0 / "td/bitgen_console_b11.log", R0 / "td/cwc_console_b11.log",
    R0 / "td/cw/compiled.bit", R0 / "td/cw/compiled.cwc",
]
SIM = [
    R0 / "sim/run_b11.py", R0 / "sim/tb_b11_read.sv", R0 / "sim/tb_status_v4.v",
    R0 / "sim/tb_b11_full.v", R0 / "sim/tb_p1_chain.v",
    R0 / "sim/p2_paxi_model_b11.v", R0 / "sim/a1_ddr_model.v",
    R0 / "sim/sim-results-b11.json",
]
BOARD = [
    R0 / "board/parse_status_v4.py", R0 / "board/capture_com8.py",
    R0 / "board/decode_frame.py",
]
DOCS = [
    R0 / "diag/read-stall-analysis.md",
    R0 / "result-r0.md", R0 / "lessons-r0.md",
]
BASE = [
    ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix/r0/artifact-hashes-r1.txt",
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
    out = {"manifest": "CANDIDATE-MANIFEST-b11-aplus-read-r0",
           "task_id": "T10.b11-aplus-read", "run_id": "20261020-0209_singleA_aplus_closedloop",
           "created": datetime.datetime.now().isoformat(timespec="seconds"),
           "status": "diagnosis_only",
           "parent_task": "T10 (stays blocked)",
           "notes": [
               "W1 could not attribute the deterministic 1176-word read stop to the A1 RTL;",
               "the full-scale real-RTL read bench reads 129600/129600 words with zero mismatches,",
               "so no guessed functional fix was made (dev-plan section 5, diagnosis_only branch).",
               "v4 status packet (225 B, LEN 0xE1, VER 4) + F_WAIT watchdog are the deliverables.",
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
    (R0 / "CANDIDATE-MANIFEST-b11-aplus-read-r0.json").write_text(
        json.dumps(out, indent=2), encoding="utf-8")
    print("files=%d missing=%d" % (sum(len(v) for v in groups.values()), len(missing)))
    for m in missing:
        print("  MISSING", m)
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
