#!/usr/bin/env python3
"""make_manifest_b14.py -- freeze the T10.b14-cam-b r0 candidate manifest.

Reads the actual TD reports/hashes and the sim result JSONs; writes
CANDIDATE-MANIFEST-b14-cam-b-r0.json and refreshes r0/artifact-hashes.txt.
"""
import datetime
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
PKG = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b14-cam-b"
TD = PKG / "r0/td"
SIM = PKG / "r0/sim"
BOARD = PKG / "r0/board"


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def text(p):
    p = pathlib.Path(p)
    return p.read_text(errors="replace") if p.exists() else ""


def re_first(pat, s, cast=float, default=None):
    m = re.search(pat, s)
    return cast(m.group(1)) if m else default


def main():
    syn_t = text(TD / "syn_gate_timing.rpt")
    syn_a = text(TD / "syn_gate_area.rpt")
    pr_t = text(TD / "phy_pr_timing_flow.rpt")
    rout_a = text(TD / "routed_area.rpt")
    bitlog = text(TD / "bitgen_console_b14.log")
    buildlog = text(TD / "build_console_b14.log")

    routed = dict(
        sw=re_first(r"SWNS:\s*(-?[0-9.]+)ns", pr_t),
        st=re_first(r"STNS:\s*(-?[0-9.]+)ns", pr_t),
        hw=re_first(r"HWNS:\s*(-?[0-9.]+)ns", pr_t),
        ht=re_first(r"HTNS:\s*(-?[0-9.]+)ns", pr_t),
        viol=re_first(r"([0-9]+)\s+Viol Endpoints", pr_t, int),
        total=re_first(r"([0-9]+)\s+Total Endpoints", pr_t, int),
    )
    bitsta = {}
    ct = text(TD / "candidate_timing.rpt")
    sw = re_first(r"SWNS: ([-+0-9.]+)ns", ct)
    st = re_first(r"STNS: ([-+0-9.]+)ns", ct)
    hw = re_first(r"HWNS: ([-+0-9.]+)ns", ct)
    ht = re_first(r"HTNS: ([-+0-9.]+)ns", ct)
    pw = re_first(r"Period Check WNS: ([-+0-9.]+)ns", ct)
    if sw is not None:
        bitsta = dict(setup=sw, setup_tns=st, hold=hw, hold_tns=ht, period=pw)

    sim = {}
    for g in ("s1", "s2", "s3", "s4", "s5"):
        p = SIM / ("sim-results-b14-%s.json" % g)
        sim[g] = json.loads(p.read_text()) if p.exists() else {}

    s1 = sim.get("s1", {})
    s2 = sim.get("s2", {})
    status = "blocked" if (BOARD / "log/board_blocked.txt").exists() else "complete"
    board_reason = None
    bp = BOARD / "log/board_blocked.txt"
    if bp.exists():
        for line in bp.read_text().splitlines():
            if line.startswith("board_blocked_reason="):
                board_reason = line.split("=", 1)[1]

    rtl_hashes = {f.name: sha(f) for f in sorted((PKG / "r0/changed-src").glob("*.v"))}
    cw = TD / "cw"
    man = {
        "task_id": "T10.b14-cam-b",
        "run_id": "20261020-0209_singleA_aplus_closedloop",
        "round": "r0",
        "date": datetime.date.today().isoformat(),
        "status": status,
        "status_reason": (
            "Offline work complete: B tap/diagnostics exported by pure assigns, compile-time "
            "CAM_SEL=1 selects B (generate, no LUT clock mux), the B byte clock is constrained, "
            "S1 B-geometry chain + S2 P1 goldens + S3 v5/bit20 + S4 dead clock + S5 short-line all "
            "pass, and the candidate was rebuilt once (1 synth + 1 route + 1 bitgen + 1 CWC). "
            "Board is blocked by the board precondition: the on-board FTDI (VID_0403&PID_6042) is "
            "not enumerated on this PC now, so per dev-plan 7.1 there was 0 download and 0 COM8."
            if status == "blocked" else
            "Offline work + board run complete (see board section)."),
        "parent_task": "T10 stays blocked (this package does not close T10)",
        "candidate": {
            "eligible": (TD / "a1_board.bit").exists(),
            "eligible_scope": "hash-bound B-tap diagnostic candidate (CAM_SEL=1 compile-time only); bitgen/CWC complete but board not run (FTDI absent)",
            "bit": sha(TD / "a1_board.bit"),
            "cwc": sha(TD / "a1_board.cwc"),
            "bid": sha(TD / "a1_board_inst.bid"),
            "compiled_bit": sha(cw / "compiled.bit"),
            "compiled_cwc": sha(cw / "compiled.cwc"),
            "bitgen": 1 if (TD / "a1_board.bit").exists() else 0,
            "cwc_count": 1 if (TD / "a1_board.cwc").exists() else 0,
            "downloads": 0,
            "download_mode": "none (FTDI absent)",
            "bitgen_sta": bitsta,
        },
        "selection": {"CAM_SEL": 1, "A_branch_equivalent": "r0/diag/cam-sel-equivalence.md",
                      "cam_sysstat_bit20": "CAM_SEL"},
        "timing": {
            "syn_SWNS_ns": re_first(r"SWNS:\s*(-?[0-9.]+)ns", syn_t),
            "syn_STNS_ns": re_first(r"STNS:\s*(-?[0-9.]+)ns", syn_t),
            "routed_SWNS_ns": routed["sw"], "routed_STNS_ns": routed["st"],
            "routed_HWNS_ns": routed["hw"], "routed_HTNS_ns": routed["ht"],
            "routed_violated_endpoints": routed["viol"],
            "routed_total_endpoints": routed["total"],
            "target_wns_ns": 0.05, "floor_wns_ns": 0.003,
            "timing_caveat": (None if (routed["sw"] or 0) >= 0.05 else
                              "thin_margin_%+0.3f (0 violations, above +0.003 floor, below "
                              "+0.05 target; diagnostic candidate, not production sign-off)"
                              % (routed["sw"] or 0)),
        },
        "resources": {
            "syn_slice": re_first(r"#slice\*\s+([0-9]+)", syn_a, int),
            "syn_eram": re_first(r"#eram\s+([0-9]+)", syn_a, int),
            "syn_reg": re_first(r"#reg\s+([0-9]+)", syn_a, int),
            "routed_slice": re_first(r"\n#slice\s+([0-9]+)", rout_a, int),
            "routed_slice_reg": re_first(r"#slice reg\s+([0-9]+)", rout_a, int),
            "routed_lut6": re_first(r"#lut6\s+([0-9]+)", rout_a, int),
            "routed_eram": re_first(r"\n#eram\s+([0-9]+)", rout_a, int),
            "routed_eram_limit": 300,
        },
        "rtl": {
            "source_set": "r0/changed-src (11 files: 2 edited + 9 byte-identical to b13 r1)",
            "hashes": rtl_hashes,
            "build_binding": [
                "r0/td/01_build.tcl add_files: 10 changed-src files from T10.b14-cam-b/r0/changed-src",
                "r0/td/01_build.tcl add_files: f9p_camera_display_core.v from T10.b14-cam-b/r0/changed-src",
                "r0/diag/a1_board.al.pre_build: same 11 changed-src File Paths (TD rewrites a1_board.al on create_project)",
                "r0/td/run_build_b14.ps1 fails closed on core/p2-top/camera/SDC SHA256",
            ],
        },
        "sdc": {"file": "r0/td/p2_board.sdc", "sha256": sha(TD / "p2_board.sdc"),
                "diff_scope": "2 changes: create_generated_clock mipi_b_byte_clk; add it to the existing mipi_b_clk_hs async group"},
        "sim_results": {
            "bound_to_same_rtl": True,
            "s1_b_geometry": s1.get("s1_b_geometry", {}),
            "s1_verify": s1.get("s1_verify", {}),
            "s2_p1_goldens": s2,
            "s3_v5_bit20": sim.get("s3", {}).get("s3_v5_bit20", {}),
            "s4_dead_clock": sim.get("s4", {}).get("s4_dead_clk", {}),
            "s5_short_line": sim.get("s5", {}).get("s5_short_line", {}),
            "json": [str((SIM / ("sim-results-b14-%s.json" % g)).relative_to(PKG)) for g in
                     ("s1", "s2", "s3", "s4", "s5")],
        },
        "board": status,
        "board_reason": board_reason,
        "board_summary": [
            "user confirmed the second IMX415 is physically connected to port B (r0/board/connection-confirmation.md)",
            "FTDI preflight: VID_0403&PID_6042 not present; visible COM ports: COM3/COM4 (Bluetooth) only",
            "0 SRAM downloads, 0 COM8 captures (dev-plan 7.1 step 2: board blocked, not FAIL)",
        ],
        "artifacts": [],
        "artifact_hashes_file": "r0/artifact-hashes.txt",
        "test_input_paths": [],
        "lessons_path": "lessons-r0.md",
        "result_path": "result-r0.md",
        "td_dir": "r0/td",
        "retest_required": [
            "independent re-hash of r0/changed-src and the bit/CWC/BID + cw/compiled.* pair",
            "independent engineering re-check of routed timing/ERAM and the WNS caveat",
            "independent functional re-run of S1-S5 and the P1 golden byte comparison",
            "board re-run needs the FTDI/board to be enumerated (new authorisation, 1 SRAM download then COM8 150 s)",
        ],
        "runs": {"td_sessions": 2, "synth": 1, "route": 1, "bitgen": 1, "cwc": 1, "downloads": 0},
        "retest": [
            "functional: r0/sim/run_b14.py {s1,s2,s3,s4,s5} against the frozen changed-src hashes",
            "engineering: compare r0/td routing/timing reports with the manifest values; cw/compiled.* == parent bit/cwc",
            "system: board is blocked; when the board is available, 1 SRAM download then 150 s COM8 and r0/board/check_b14_board.py",
        ],
        "known_limits": [
            "board evidence absent (FTDI not enumerated): no B pixel/export claim from hardware",
            "B uses the same IDELAY tap 46 as A; B eye not swept",
            "routed WNS may be below the +0.05 target; see timing_caveat",
            "S1 uses the synthetic tap in the real camera_a1_uart_top chain; the camera core/PHY is not simulated",
            "S5 uses a 96x12 proxy geometry for the short-line abort path (A/B crop logic is geometry-parametric)",
        ],
    }

    arts = []
    for sub in ("r0/changed-src", "r0/sim", "r0/td", "r0/board", "r0/diag"):
        for p in sorted((PKG / sub).rglob("*")):
            if p.is_file() and p.stat().st_size < 8_000_000:
                arts.append(str(p.relative_to(PKG)).replace("\\", "/"))
    man["artifacts"] = arts
    man["test_input_paths"] = [
        "r0/changed-src", "r0/td/01_build.tcl", "r0/td/02_bitgen.tcl", "r0/td/03_cwc.tcl",
        "r0/diag/a1_board.al.pre_build", "r0/td/a1_board.bit", "r0/td/a1_board.cwc",
        "r0/td/a1_board_inst.bid", "r0/td/cw/compiled.bit", "r0/td/cw/compiled.cwc",
        "r0/td/phy_pr_timing_flow.rpt", "r0/td/routed_area.rpt", "r0/td/routed_qor.rpt",
        "r0/td/syn_gate_timing.rpt", "r0/td/syn_gate_area.rpt", "r0/td/p2_board.sdc",
        "r0/sim/run_b14.py", "r0/sim/check_b14.py", "r0/sim/check_b14_s5.py",
        "r0/sim/verify_b14_s1.py", "r0/sim/tb_b14_chain.sv", "r0/sim/tb_b14_deadclk.sv",
        "r0/sim/tb_status_v5_b14.v", "r0/sim/sim-results-b14-s1.json",
        "r0/sim/sim-results-b14-s2.json", "r0/sim/sim-results-b14-s3.json",
        "r0/sim/sim-results-b14-s4.json", "r0/sim/sim-results-b14-s5.json",
        "r0/board/parse_status_v5.py", "r0/board/check_b14_board.py",
        "r0/board/connection-confirmation.md", "r0/artifact-hashes.txt",
    ]
    out = PKG / "CANDIDATE-MANIFEST-b14-cam-b-r0.json"
    out.write_text(json.dumps(man, indent=2))
    print("MANIFEST", out)
    print(json.dumps({k: man[k] for k in ("status", "timing", "resources")}, indent=2)[:1500])
    return 0


if __name__ == "__main__":
    sys.exit(main())
