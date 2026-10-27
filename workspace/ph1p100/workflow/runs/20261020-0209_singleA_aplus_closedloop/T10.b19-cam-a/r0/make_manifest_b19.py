#!/usr/bin/env python3
"""make_manifest_b19.py -- freeze T10.b19-cam-a r0 into one manifest.

Run only after the developer stopped modifying the package.  This candidate is a
blocked build (see r0/diag/build-constraint-finding.md): no bit/CWC and no board
capture exist, so those groups are recorded empty and hashes_missing only covers
frozen inputs/candidate/scripts.
"""
import hashlib
import json
import pathlib
import time

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
PKG = RUN / "T10.b19-cam-a"
R0 = PKG / "r0"
B18 = RUN / "T10.b18-b17-b"
B13 = RUN / "T10.b13-ddr-retry"
B17 = RUN / "T10.b17-paxi-native"


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def rec(p):
    p = pathlib.Path(p)
    return {"path": str(p), "sha256": sha(p),
            "bytes": p.stat().st_size if p.exists() else None}


inputs = {}
for n in ("a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_ddr_arb2.v", "a1_uart_export.v",
          "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
          "a1_deflate_core.v", "p2_ddr_bridge.v", "p2_a1_board_top.v",
          "f9p_camera_display_core.v"):
    inputs["b18_changed_src/" + n] = rec(B18 / "r0/changed-src" / n)
inputs["b18_sdc"] = rec(B18 / "r0/td/p2_board.sdc")
inputs["b18_adc"] = rec(B18 / "r0/td/board_p2.adc")
inputs["b18_bit_reference_only"] = rec(B18 / "r0/td/a1_board.bit")
inputs["b18_cwc_reference_only"] = rec(B18 / "r0/td/a1_board.cwc")
inputs["b13_a_wiring_top"] = rec(B13 / "r0/changed-src/p2_a1_board_top.v")
inputs["b17_sdc"] = rec(B17 / "r0/td/p2_board.sdc")
for n in ("tb_b17_chain.sv", "tb_b17_paxi_native.sv", "tb_p1_chain.v",
          "tb_status_v6.v", "tb_b18_camsel.sv", "gen_stubs.py", "check_b18.py",
          "p2_paxi_model_b17.v", "a1_ddr_model.v", "run_b18.py"):
    inputs["b18_sim/" + n] = rec(B18 / "r0/sim" / n)

cand = {}
for p in sorted((R0 / "changed-src").glob("*.v")):
    cand[p.name] = rec(p)
cand["td/p2_board.sdc"] = rec(R0 / "td/p2_board.sdc")
cand["td/board_p2.adc"] = rec(R0 / "td/board_p2.adc")

scripts = {}
for pat in ("check_merge_b19.py", "make_manifest_b19.py"):
    scripts[pat] = rec(R0 / pat)
for p in (sorted((R0 / "sim").glob("*.py")) + sorted((R0 / "sim").glob("tb_*.v")) +
          sorted((R0 / "sim").glob("tb_*.sv")) + sorted((R0 / "sim").glob("*.sv")) +
          sorted((R0 / "board").glob("*.py")) + sorted((R0 / "board").glob("*.ps1")) +
          sorted((R0 / "board").glob("*.tcl")) + sorted((R0 / "td").glob("*.tcl")) +
          sorted((R0 / "td").glob("*.ps1"))):
    scripts[str(p.relative_to(R0)).replace("\\", "/")] = rec(p)

simres = {}
for p in sorted((R0 / "sim").glob("sim-results-b19-*.json")):
    simres[p.name] = rec(p)

tdart = {}
for rel in ("build_console_r0.log", "run_build_b19.out", "syn_gate_timing.rpt",
            "syn_gate_area.rpt", "a1_board.al", "a1_board_Runs/syn_1/a1_board.prj",
            "routed_qor.rpt", "routed_timing_status.rpt", "routed_timing_summary.rpt",
            "routed_area.rpt", "route_flow.status", "place_flow.status",
            "p2_board.sdc", "p2_board-b19.diff.txt", "sdc-hashes.txt",
            "a1_board_Runs/phy_1/a1_board_pr.db",
            "attempt1/run_build_b19.out", "attempt1/build_console_r0.log",
            "attempt1/syn_gate_timing.rpt", "attempt1/syn_gate_area.rpt"):
    tdart[rel] = rec(R0 / "td" / rel)

boardart = {}
for p in (sorted((R0 / "board").glob("log/*")) + sorted((R0 / "board").glob("captures_a/*")) +
          [R0 / "board/gate-selftest-b18/board_gate.txt",
           R0 / "board/gate-selftest-b18/board_gate.json"]):
    p = pathlib.Path(p)
    if p.exists():
        boardart[str(p.relative_to(R0)).replace("\\", "/")] = rec(p)

docs = {}
for rel in ("merge-conformance-r0.txt", "diag/build-constraint-finding.md",
            "result-r0.md", "lessons-r0.md"):
    docs[rel] = rec(R0 / rel)

man = {
    "package": "T10.b19-cam-a",
    "round": "r0",
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
    "stopped_modifying": True,
    "status": "fail_route_timing",
    "candidate": "b18-proven chain, p2_a1_board_top.v line 97 CAM_SEL 1'b1 -> 1'b0, "
                 "SDC approved diff (B clock group removed)",
    "device": "PH1P100SBG484 speed 3, Routed database only (no bitgen)",
    "build": {
        "attempt1_syn_sws": -3.055,
        "attempt1_cause": "frozen set_clock_groups referenced the trimmed "
                          "mipi_b_byte_clk; async groups dropped",
        "sdc_approved_diff": "r0/td/p2_board-b19.diff.txt",
        "sdc_sha_b18": "3fe1641270eb0cd90a25a3d4724617f7f81103d83f8d364bb954cd41329cf2ed",
        "sdc_sha_b19": "0888b6a705a039a6cbabebacf323244a36257b5f29fb51bab7d81ef003220f5e",
        "syn_sws": 0.127, "syn_wns": 0.127,
        "routed_sws": -0.098, "routed_tns": -0.518,
        "routed_hws": 0.020, "routed_viol_ep": 10, "routed_total_ep": 26649,
        "period_check_wns": 2.200,
        "worst_path": "u_a1/a1_abort_reg -> u_a1/u_a1/smem.addrb[10] (clk_a1 self)",
        "gate": "WNS < +0.003 with violations -> stop, no bitgen",
        "bit": None, "cwc": None, "downloads": 0,
    },
    "inputs": inputs,
    "candidate_files": cand,
    "scripts": scripts,
    "sim_results": simres,
    "td_artifacts": tdart,
    "board_artifacts": boardart,
    "documents": docs,
    "hashes_missing": sorted([k for grp in (inputs, cand, scripts, simres, tdart, docs)
                              for k, v in grp.items() if v["sha256"] == "MISSING"]),
}
out = PKG / "CANDIDATE-MANIFEST-b19-cam-a-r0.json"
out.write_text(json.dumps(man, indent=2))
print("MANIFEST_OK %s entries=%d missing=%d" %
      (out, len(inputs) + len(cand) + len(scripts) + len(simres) + len(tdart) + len(docs),
       len(man["hashes_missing"])))
print(json.dumps(man["hashes_missing"], indent=2))
