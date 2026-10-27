#!/usr/bin/env python3
"""mk_manifest.py -- T10.b8-crop-geom r0 candidate manifest + artifact hashes.

Hashes every file that the frozen package binds (inputs, changed RTL, sim
vectors/results, TD reports, bit/CWC/BID, board evidence) and writes
  r0/artifact-hashes.txt
  CANDIDATE-MANIFEST-b8-crop-geom-r0.json
Run after the last write to the package.
"""
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
PKG = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b8-crop-geom"
R0 = PKG / "r0"
B7 = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag/r0"

GROUPS = {
    "inputs_task": [
        PKG / "dispatch.json", PKG / "dev-plan.md", PKG / "fpga-design-guide.md",
        PKG / "handoff.md",
    ],
    "inputs_b7_evidence": [
        B7 / "board/captures_retry/com8_150s.bin",
        B7 / "board/captures_retry/status_v2.json",
        B7 / "board/parse_status_v2.py",
        B7.parent / "result-r0diag.md",
        B7.parent / "lessons-r0diag.md",    ],
    "inputs_production_rtl": [
        ROOT / "fpga/csi2/src/a1/a1_raw_crop.v",
        ROOT / "fpga/csi2/src/a1/camera_a1_uart_top.v",
        B7 / "changed-src/camera_a1_uart_top.v",
        B7 / "changed-src/a1_uart_export.v",
        B7 / "changed-src/cam_diag_mailbox.v",
        B7 / "changed-src/a1_deflate_core.v",
        ROOT / "fpga/csi2/prj/camera_peer/uisrc/03_ip/mipi_csi_2/csi_rx_packet_handler.v",
        ROOT / "fpga/csi2/prj/camera_peer/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack.v",
    ],
    "changed_rtl": [
        R0 / "changed-src/a1_raw_crop.v",
        R0 / "changed-src/camera_a1_uart_top.v",
        R0 / "changed-src/a1_uart_export.v",
        R0 / "changed-src/cam_diag_mailbox.v",
        R0 / "changed-src/a1_deflate_core.v",
        R0 / "rtl-diff-r0.patch",
        PKG / "result-r0.md",
        PKG / "lessons-r0.md",
        R0 / "geometry-derivation.md",
        R0 / "caveats.json",
    ],
    "sim": [
        R0 / "sim/tb_crop_geom_real.v", R0 / "sim/tb_crop_pipe_real.v",
        R0 / "sim/tb_crop_neg.v", R0 / "sim/tb_p1_chain.v",
        R0 / "sim/tb_status_pkt_v2.v", R0 / "sim/a1_ddr_model.v",
        R0 / "sim/make_ref_geom.py", R0 / "sim/run_sims.py",
        R0 / "sim/sim-results-b8.json",
        R0 / "sim/caps/roi_real.bin", R0 / "sim/caps/roi_real.ref.bin",
        R0 / "sim/caps/roi_real.stats",
        R0 / "sim/caps/micro8x2.dec", R0 / "sim/caps/mid64x8.dec",
        R0 / "sim/caps/full_grad.dec",
        R0 / "sim/caps/micro8x2.stats", R0 / "sim/caps/mid64x8.stats",
        R0 / "sim/caps/full_grad.stats",
        R0 / "sim/caps/status_v2_bytes.txt",
        R0 / "sim/logs/sim_geom_real.log", R0 / "sim/logs/sim_pipe_real.log",
        R0 / "sim/logs/sim_crop_neg.log", R0 / "sim/logs/sim_status_v2.log",
        R0 / "sim/logs/sim_p1_micro8x2.log", R0 / "sim/logs/sim_p1_mid64x8.log",
        R0 / "sim/logs/sim_p1_full_grad.log",
        R0 / "sim/logs/sim_pipe_vendor_unpack.log",
    ],
    "td_inputs": [
        R0 / "td/01_build.tcl", R0 / "td/02_bitgen.tcl", R0 / "td/03_cwc.tcl",
        R0 / "td/p2_board.sdc", R0 / "td/board_p2.adc", R0 / "td/src/p2_a1_board_top.v",
        R0 / "td/src/f9p_camera_display_core.v",
        R0 / "td/src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_packet_integrity.v",
        R0 / "td/src/camera/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack_checked.v",
    ],
    "td_outputs": [
        R0 / "td/build_console_b8.log", R0 / "td/routed_timing_status.rpt",
        R0 / "td/routed_qor.rpt", R0 / "td/routed_check_timing.rpt",
        R0 / "td/routed_area.rpt", R0 / "td/route_flow.status",
        R0 / "td/place_flow.status", R0 / "td/a1_board.bit",
        R0 / "td/a1_board.cwc", R0 / "td/a1_board_inst.bid",
        R0 / "td/cw/compiled.bit", R0 / "td/cw/compiled.cwc",
        R0 / "td/bitgen_console_b8.log", R0 / "td/cwc_console_b8.log",
    ],
    "board": [
        R0 / "board/ping_cable.tcl", R0 / "board/download_sram_b8.tcl",
        R0 / "board/download_sram_b8.log", R0 / "board/ping_cable_b8.log",
        R0 / "board/capture_com8.py", R0 / "board/parse_status_v2.py",
        R0 / "board/decode_frame.py", R0 / "board/derive_geometry.py",
        R0 / "board/captures/com8_90s.bin", R0 / "board/captures/com8_90s.stats",
        R0 / "board/captures/status_v2_90s.txt",
        R0 / "board/captures/com8_90s_predownload_b7bit.bin",
        R0 / "board/captures/status_v2_predownload_b7bit.txt",
    ],
}


def readlog(p):
    b = pathlib.Path(p).read_bytes()
    if b.count(b"\x00") > len(b) // 8:
        return b.decode("utf-16", errors="replace")
    return b.decode("utf-8", errors="replace")
    

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    hashes = {}
    lines = []
    missing = []
    for g, files in GROUPS.items():
        for f in files:
            if not f.exists():
                missing.append(str(f))
                continue
            hp = sha(f)
            rel = str(f).replace(str(ROOT) + "\\", "").replace("\\", "/")
            hashes[rel] = {"bytes": f.stat().st_size, "sha256": hp, "group": g}
            lines.append("%s  %10d  %s" % (hp, f.stat().st_size, rel))
    (R0 / "artifact-hashes.txt").write_text("\n".join(sorted(lines)) + "\n")

    # gate numbers pulled from the frozen reports (never invented)
    def grab(path, pat):
        try:
            m = re.search(pat, pathlib.Path(path).read_text(errors="replace"))
            return m.group(1) if m else None
        except OSError:
            return None

    sim = json.loads((R0 / "sim/sim-results-b8.json").read_text())
    build = readlog(R0 / "td/build_console_b8.log")
    m = re.search(r"P2_ROUTED_SWNS=(\S+) P2_ROUTED_STNS=(\S+) P2_ROUTED_HWNS=(\S+) "
                  r"P2_ROUTED_HTNS=(\S+) P2_ROUTED_VIOL_EP=(\S+) P2_ROUTED_TOTAL_EP=(\S+)", build)
    routed = dict(zip(["swns", "stns", "hwns", "htns", "viol_ep", "total_ep"],
                      m.groups())) if m else None
    m2 = re.search(r"P2_SYN_SWNS=(\S+) P2_SYN_STNS=(\S+) P2_SYN_SLICE=(\S+) "
                   r"P2_SYN_ERAM=(\S+) P2_SYN_REG=(\S+)", build)
    syn = dict(zip(["swns", "stns", "slice", "eram", "reg"], m2.groups())) if m2 else None

    man = {
        "task_ids": ["T10.b8-crop-geom"],
        "run_id": "20261020-0209_singleA_aplus_closedloop",
        "candidate": "b8-crop-geom-r0",
        "geometry": {"CAM_W": 3864, "CAM_H": 2192, "ROI_X": 972, "ROI_Y": 556,
                     "W": 1920, "H": 1080, "CG": 966, "OG": 480, "GX": 243,
                     "NGRP": 518400},
        "changed_files": ["r0/changed-src/a1_raw_crop.v (defaults + parameter contract)",
                          "r0/changed-src/camera_a1_uart_top.v (4 default parameters)",
                          "r0/td/01_build.tcl (5 path lines)"],
        "unchanged_by_design": ["a1_uart_export.v", "cam_diag_mailbox.v",
                                "a1_deflate_core.v", "p2_board.sdc", "a1_small_top.sdc",
                                "board_p2.adc", "UART_DIV", "I2C/MIPI tables",
                                "status packet v2 layout", "frame header/CRC", "DDR layout"],
        "sim": {
            "geom_real": {k: v for k, v in sim.get("geom", {}).items() if k != "stats"},
            "pipe_real": sim.get("pipe"),
            "neg": sim.get("neg"),
            "status_v2": sim.get("status"),
            "p1": {k: sim.get(k) for k in ("micro8x2", "mid64x8", "full_grad")},
        },
        "syn": syn, "routed": routed,
        "bitgen_ok": "P2_CANDIDATE_BIT_GENERATED" in readlog(R0 / "td/bitgen_console_b8.log")
        if (R0 / "td/bitgen_console_b8.log").exists() else None,
        "cwc_ok": "P2_MATCHING_CWC_EXPORTED" in readlog(R0 / "td/cwc_console_b8.log")
        if (R0 / "td/cwc_console_b8.log").exists() else None,
        "bit_cwc_identical_to_compiled": None,
        "system_gate": "G4 NOT MET (no camera payload; 1 SRAM download used, no retry)",
        "artifacts": hashes,
        "missing": missing,
        "caveats": json.loads((R0 / "caveats.json").read_text())
        if (R0 / "caveats.json").exists() else [],
        "budget": {"dev_minutes": None, "td_sessions": 1, "synth": 1, "route": 1,
                   "bitgen": 1, "cwc": 1, "download": 1, "flash": 0},
    }
    (PKG / "CANDIDATE-MANIFEST-b8-crop-geom-r0.json").write_text(json.dumps(man, indent=2))
    print("hashed=%d missing=%d" % (len(hashes), len(missing)))
    for f in missing:
        print("MISSING", f)
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
