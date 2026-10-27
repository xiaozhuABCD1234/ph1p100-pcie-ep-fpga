#!/usr/bin/env python3
"""mk_manifest_b9.py -- artifact-hashes.txt + CANDIDATE-MANIFEST-b9-rawstore-r0.json.

Hashes every file under r0/ except TD run internals (a1_board_Runs, cw) and
Python caches, then binds the candidate (sources, bit, CWC, BID), the gate
evidence produced by the simulations and the board capture.
"""
import hashlib
import json
import pathlib
import re

PKG = pathlib.Path(r"D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b9-rawstore")
R0 = PKG / "r0"
SKIP_DIRS = {"a1_board_Runs", "cw", "__pycache__"}
SKIP_FILES = {"artifact-hashes.txt"}
EXCLUDE_JSON = {"CANDIDATE-MANIFEST-b9-rawstore-r0.json"}


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def walk():
    out = []
    for p in sorted(R0.rglob("*")):
        if p.is_dir():
            continue
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        if p.name in SKIP_FILES or p.name in EXCLUDE_JSON:
            continue
        out.append(p)
    return out


def load(p):
    p = pathlib.Path(p)
    return json.loads(p.read_text()) if p.exists() else None


def grab(pat, text, default=None):
    m = re.search(pat, text or "")
    return m.group(1) if m else default


def main():
    files = walk()
    lines = []
    for p in files:
        lines.append("%s  %s" % (sha(p), p.relative_to(PKG).as_posix()))
    (R0 / "artifact-hashes.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    sim = load(R0 / "sim/sim-results-b9.json") or {}
    status = load(R0 / "board/parse_status_v3.json") or {}
    build = (R0 / "td/build_console_b9.log").read_text(errors="replace") \
        if (R0 / "td/build_console_b9.log").exists() else ""
    timing_status = (R0 / "td/routed_timing_status.rpt").read_text(errors="replace") \
        if (R0 / "td/routed_timing_status.rpt").exists() else ""

    cand = {}
    for rel in ("changed-src/a1_raw_crop.v", "changed-src/camera_a1_uart_top.v",
                "changed-src/a1_uart_export.v", "changed-src/a1_ddr_slot_store.v",
                "changed-src/cam_diag_mailbox.v", "changed-src/a1_deflate_core.v",
                "td/src/p2_a1_board_top.v", "td/src/p2_ddr_bridge.v",
                "td/src/p2_a1_pll.v", "td/src/p2_ddrmc_shell.v",
                "td/01_build.tcl", "td/02_bitgen.tcl", "td/03_cwc.tcl",
                "td/p2_board.sdc", "td/board_p2.adc",
                "td/a1_board.bit", "td/a1_board.cwc", "td/a1_board_inst.bid"):
        p = R0 / rel
        cand[rel] = sha(p) if p.exists() else "MISSING"

    man = {
        "task_id": "T10.b9-rawstore",
        "run_id": "20261020-0209_singleA_aplus_closedloop",
        "round": "r0",
        "package": str(PKG),
        "base_candidate": "T10.b8-crop-geom/CANDIDATE-MANIFEST-b8-crop-geom-r0.json",
        "frozen_data_contract": {
            "crop": "3864x2192 ROI 972,556 -> 1920x1080",
            "groups_per_line": 480, "groups_per_frame": 518400,
            "words_per_frame": 129600, "bytes_per_frame": 2592000,
            "status_packet": "v3 177 B = 5 + 43*4, LEN=177 VER=3, XOR8 over 0..175",
        },
        "changed_rtl": {
            "a1_ddr_slot_store.v": "observation outputs only (17 new ports)",
            "camera_a1_uart_top.v": "F1 abort beat + abort_hold, F2 skip_frame whole-frame discard + fifo_ovf_cnt, F4 i_ddr_rdy, v3 20x32b bus",
            "a1_uart_export.v": "status packet v2 -> v3 (177 B, 43 fields, same single-edge snapshot)",
            "p2_ddr_bridge.v": "F3 AR issue/pop coupling with ddr_rdy + ar_pending",
            "p2_a1_board_top.v": "i_ddr_rdy = ddr_rdy_sync_a1[1]",
        },
        "sim": sim,
        "board": status,
        "build": {
            "syn_sw": grab(r"P2_SYN_SWNS=(\S+)", build),
            "syn_st": grab(r"P2_SYN_STNS=(\S+)", build),
            "syn_slice": grab(r"P2_SYN_SLICE=(\S+)", build),
            "syn_eram": grab(r"P2_SYN_ERAM=(\S+)", build),
            "syn_reg": grab(r"P2_SYN_REG=(\S+)", build),
            "routed_sw": grab(r"P2_ROUTED_SWNS=(\S+)", build),
            "routed_st": grab(r"P2_ROUTED_STNS=(\S+)", build),
            "routed_hw": grab(r"P2_ROUTED_HWNS=(\S+)", build),
            "routed_ht": grab(r"P2_ROUTED_HTNS=(\S+)", build),
            "viol_ep": grab(r"P2_ROUTED_VIOL_EP=(\S+)", build),
            "total_ep": grab(r"P2_ROUTED_TOTAL_EP=(\S+)", build),
            "timing_status": timing_status.strip()[:400],
        },
        "candidate_files": cand,
        "artifact_hashes": {"file": "r0/artifact-hashes.txt", "entries": len(lines)},
        "gates": {
            "G1_sim": "see sim block (all pass criteria in result-r0.md)",
            "G2_build": "see build block",
            "G3_board": (status or {}).get("verdict", "PENDING"),
        },
    }
    (PKG / "CANDIDATE-MANIFEST-b9-rawstore-r0.json").write_text(
        json.dumps(man, indent=2), encoding="utf-8")
    print("hashed %d files" % len(lines))
    print(json.dumps(man["build"], indent=1))
    print("board verdict:", man["gates"]["G3_board"])


if __name__ == "__main__":
    main()
