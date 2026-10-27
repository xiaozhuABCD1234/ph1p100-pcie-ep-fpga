#!/usr/bin/env python3
"""Build CANDIDATE-MANIFEST-b14-cam-b-r1.json from the real r1 artifacts.

Every hash below is computed from the files on disk at run time; the numeric
timing/board values are the ones printed by TD and by the v5 parser for this
round (r1 build 2026-10-26 17:21-17:43, board run 17:44-17:48).
"""
import hashlib
import json
import pathlib

PKG = pathlib.Path(__file__).resolve().parents[1]      # .../T10.b14-cam-b
R1 = PKG / "r1"
TD = R1 / "td"
BRD = R1 / "board"
CAP = BRD / "captures"


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel(p):
    return str(pathlib.Path(p)).replace("\\", "/")


def entry(p):
    p = pathlib.Path(p)
    return {"path": rel(p), "bytes": p.stat().st_size, "sha256": sha(p)}


inputs = []
for name in ("a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_ddr_arb2.v",
             "a1_uart_export.v", "camera_a1_uart_top.v", "cam_diag_mailbox.v",
             "a1_frame_top.v", "a1_deflate_core.v", "p2_a1_board_top.v",
             "p2_ddr_bridge.v", "f9p_camera_display_core.v"):
    inputs.append(entry(PKG / "r0" / "changed-src" / name))
inputs.append(entry(TD / "p2_board.sdc"))
inputs.append(entry(TD / "board_p2.adc"))
inputs.append(entry(TD / "01_build.tcl"))
inputs.append(entry(TD / "02_bitgen.tcl"))
inputs.append(entry(TD / "03_cwc.tcl"))
inputs.append(entry(BRD / "parse_status_v5.py"))
inputs.append(entry(BRD / "check_b14_board.py"))
inputs.append(entry(BRD / "capture_com8.py"))
inputs.append(entry(BRD / "dl_b14_r1.tcl"))

artifacts = []
for p in (TD / "a1_board.bit", TD / "a1_board.cwc", TD / "a1_board_inst.bid",
          TD / "routed_netlist.v", TD / "routed_timing_summary.rpt",
          TD / "routed_area.rpt", TD / "routed_qor.rpt",
          TD / "a1_board_Runs" / "syn_1" / "a1_board.prj",
          TD / "a1_board_Runs" / "phy_1" / "a1_board_pr.timing",
          TD / "build_console_r1.log", TD / "bitgen_console_r1.log",
          TD / "cwc_console_r1.log", TD / "run_build_r1.ps1",
          TD / "run_bitgen_cwc_r1.ps1",
          CAP / "com8_150s.bin", CAP / "com8_150s.stats",
          CAP / "status_v5.txt", CAP / "status_v5.json",
          CAP / "board_gate.json", CAP / "board_gate.txt",
          BRD / "log" / "download_r1.log", BRD / "log" / "capture_com8.out",
          R1 / "CAM_SEL-bit-index-finding.md"):
    if p.exists():
        artifacts.append(entry(p))

gate = json.loads((CAP / "board_gate.json").read_text())
delta = gate["delta"]

manifest = {
    "task_id": "T10.b14-cam-b",
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "round": "r1",
    "date": "2026-10-26",
    "parent_task": "T10.b14-cam-b (build-engineering repair round; RTL frozen from r0)",
    "status": "fail",
    "status_reason": (
        "Build repaired and re-run cleanly (file list guard: one copy each from "
        "changed-src). CAM_SEL=1 is really in the bit and on the board "
        "(cam_sysstat=0x00001F1D, bit12=1 in every packet). Camera B is LIVE: "
        "4470 frames/150 s, pix_beats 875,164,816, line_rises 9,798,239, "
        "roi_frames 4470, crop_groups 2,358,720,000, geom_err 0. But the A+ "
        "store/encode/export path drops every frame (timeout 13410, retry 8940, "
        "giveup 4470, enc=0, exported=0, zero A1U1 frames). The same failure "
        "exists with camera A in T10.b15-ddr-pace r0, so it is camera-independent "
        "and belongs to the b13/b15 DDR retry work; r1 was not allowed to edit RTL."),
    "candidate": {
        "bit": sha(TD / "a1_board.bit"),
        "cwc": sha(TD / "a1_board.cwc"),
        "bid": sha(TD / "a1_board_inst.bid"),
        "bit_bytes": (TD / "a1_board.bit").stat().st_size,
        "cwc_bytes": (TD / "a1_board.cwc").stat().st_size,
        "cw_compiled_bit_identical": sha(TD / "a1_board.bit") == sha(TD / "cw" / "compiled.bit"),
        "cw_compiled_cwc_identical": sha(TD / "a1_board.cwc") == sha(TD / "cw" / "compiled.cwc"),
        "bitgen_sta": "SETUP 0.110/0.000 HOLD 0.020/0.000 PERIOD 2.200",
        "td_dir": rel(TD),
    },
    "selection": {
        "CAM_SEL": 1,
        "bit": 12,
        "note": ("p2_a1_board_top.v packs {19'd0,CAM_SEL,lane_sticky,3'd0,...} "
                 "so CAM_SEL is bit 12. The r0 comment/manifest said bit20; "
                 "hardware shows 0x1F1D = b13 0x0F1D | 0x1000. Host parser fixed, "
                 "RTL untouched. See r1/CAM_SEL-bit-index-finding.md."),
    },
    "timing": {
        "syn_sws_ns": 0.218, "syn_sts_ns": 0.000,
        "routed_sws_ns": 0.110, "routed_sts_ns": 0.000,
        "routed_hws_ns": 0.020, "routed_hts_ns": 0.000,
        "violated_endpoints": 0, "total_endpoints": 26354,
        "period_check_wns_ns": 2.200,
        "target": ">= +0.05 ns (met, no caveat)",
        "synth_runs": 1, "route_runs": 1, "bitgen": 1, "cwc": 1,
    },
    "resources": {
        "slice": 25783, "slice_pct": 35.97, "lut6": 20769, "reg": 30094,
        "eram": 103, "eram_total": 300, "dsp": 0,
    },
    "filelist": {
        "guard": "syn_1/a1_board.prj parsed after synthesis; fail closed on != 1",
        "f9p_camera_display_core_v_count": 1,
        "p2_a1_board_top_v_count": 1,
        "old_src_reference": False,
        "src_src_reference": False,
        "duplicate_module_warnings": 0,
        "prj_sha256": sha(TD / "a1_board_Runs" / "syn_1" / "a1_board.prj"),
        "stale_files_left_on_disk_but_not_compiled": [
            "r1/td/src/f9p_camera_display_core.v",
            "r1/td/src/p2_a1_board_top.v",
            "r1/td/src/src/**",
        ],
    },
    "rtl": {"source": "r0/changed-src (unchanged in r1)", "hash_bound": True,
            "input_hashes": inputs},
    "sdc": {"path": rel(TD / "p2_board.sdc"), "sha256": sha(TD / "p2_board.sdc"),
            "changed_from_b13": "2 B-clock lines only (r0)"},
    "board": "ran",
    "board_reason": "1 SRAM download OK (B14_R1_DL_OK), then 150 s COM8",
    "board_summary": [
        "status_packets=150 bad_xor=0",
        "CAM sel=1 (bit12) sysstat=0x00001F1D in every packet",
        "pix_beats=875164816 line_rises=9798239 frame_rises=4470 frame_falls=4470",
        "roi_frames=4470 crop_groups=2358720000 crop_geom_err=0",
        "cap=4470 raw_pub=4470 enc=0 exported=0",
        "timeout=13410 retry=8940 giveup=4470 cmp_drop=13650",
        "A1U1 frames with four CRCs + strict zlib = 0",
    ],
    "board_delta": delta,
    "board_gate": gate["status"],
    "board_capture": entry(CAP / "com8_150s.bin"),
    "artifacts": artifacts,
    "test_input_paths": [e["path"] for e in inputs],
    "lessons_path": rel(R1 / "lessons-r1.md"),
    "result_path": rel(R1 / "result-r1.md"),
    "retest_required": ["enc/exported path (shared with A, b15)", "board re-run after RTL fix"],
    "retest": [
        "Do not rebuild/redownload this candidate for the B question: B is proven live.",
        "Next RTL fix must target a1_ddr_slot_store/a1_ddr_arb2 giveup-per-frame, then re-run the same 150 s gate.",
    ],
    "known_limits": [
        "B eye/IDELAY tap not swept (tap 46 used for both cameras).",
        "B lane_sticky=0x1 while A was 0xF; frames are complete so 2-lane data still arrives, but the sticky bit deserves a look.",
        "r1 bit hash differs from r0 (fb9eb3e8...) while CWC is byte-identical (2e624fab...); both builds are STA-identical.",
        "No A-side counters are visible with CAM_SEL=1; A core still runs.",
    ],
}

out = PKG / "CANDIDATE-MANIFEST-b14-cam-b-r1.json"
out.write_text(json.dumps(manifest, indent=2))
print("MANIFEST", out)
print("bit", manifest["candidate"]["bit"])
print("cwc", manifest["candidate"]["cwc"])
print("artifacts", len(artifacts))
