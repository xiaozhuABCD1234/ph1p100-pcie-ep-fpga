#!/usr/bin/env python3
"""make_manifest_b18.py -- freeze T10.b18-b17-b r0 into one manifest.

Covers: frozen inputs (b17 base, b14 overlay, b14 r1 SDC, b17 r1 ADC),
the 11 candidate RTL files, TD/board scripts, simulation results, TD build
and bit artifacts, board capture.  Run only after the candidate is frozen.
"""
import hashlib
import json
import pathlib
import time

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
PKG = RUN / "T10.b18-b17-b"
R0 = PKG / "r0"
B17 = RUN / "T10.b17-paxi-native"
B14 = RUN / "T10.b14-cam-b"


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
    inputs["b17_changed_src/" + n] = rec(B17 / "r0/changed-src" / n)
inputs["b14_changed_src/f9p_camera_display_core.v"] = \
    rec(B14 / "r0/changed-src/f9p_camera_display_core.v")
inputs["b14_r1_sdc"] = rec(B14 / "r1/td/p2_board.sdc")
inputs["b17_r1_adc"] = rec(B17 / "r1/td/board_p2.adc")
for n in ("tb_b14_chain.sv", "run_b14.py", "check_b14.py"):
    inputs["b14_sim/" + n] = rec(B14 / "r0/sim" / n)
for n in ("tb_b17_chain.sv", "tb_b17_paxi_native.sv", "tb_p1_chain.v",
          "tb_status_v6.v", "p2_paxi_model_b17.v", "a1_ddr_model.v",
          "check_b17.py", "check_b17_core.py", "run_b17.py"):
    inputs["b17_sim/" + n] = rec(B17 / "r0/sim" / n)

cand = {}
for p in sorted((R0 / "changed-src").glob("*.v")):
    cand[p.name] = rec(p)
cand["td/p2_board.sdc"] = rec(R0 / "td/p2_board.sdc")
cand["td/board_p2.adc"] = rec(R0 / "td/board_p2.adc")

scripts = {}
for p in [R0 / "check_merge_b18.py"] + sorted((R0 / "sim").glob("*.py")) + \
        sorted((R0 / "sim").glob("tb_*.v")) + sorted((R0 / "sim").glob("tb_*.sv")) + \
        sorted((R0 / "sim").glob("p2_paxi_model_b17.v")) + \
        sorted((R0 / "sim").glob("a1_ddr_model.v")) + \
        sorted((R0 / "sim").glob("check_b17*.py")) + \
        sorted((R0 / "board").glob("*.py")) + sorted((R0 / "board").glob("*.ps1")) + \
        sorted((R0 / "board").glob("*.tcl")) + sorted((R0 / "td").glob("*.tcl")) + \
        sorted((R0 / "td").glob("*.ps1")):
    scripts[str(p.relative_to(R0)).replace("\\", "/")] = rec(p)

simres = {}
for p in sorted((R0 / "sim").glob("sim-results-b18-*.json")):
    simres[p.name] = rec(p)

tdart = {}
for rel in ("build_console_r0.log", "syn_gate_timing.rpt", "syn_gate_area.rpt",
            "routed_timing_status.rpt", "routed_qor.rpt", "routed_area.rpt",
            "route_flow.status", "place_flow.status", "bitgen_console_r0.log",
            "cwc_console_r0.log", "candidate_hashes_r0.txt",
            "candidate_timing.rpt", "candidate_abnormal.rpt", "a1_board.bit",
            "a1_board.cwc", "a1_board_inst.bid", "cw/compiled.bit", "cw/compiled.cwc",
            "params_after.tcl", "a1_board.al", "a1_board_Runs/phy_1/a1_board_pr.db",
            "a1_board_Runs/syn_1/a1_board.prj", "a1_board_Runs/syn_1/a1_board_gate.timing"):
    tdart[rel] = rec(R0 / "td" / rel)

boardart = {}
for p in sorted((R0 / "board").glob("captures/*")) + sorted((R0 / "board").glob("log/*")):
    boardart[str(p.relative_to(R0)).replace("\\", "/")] = rec(p)

docs = {}
for rel in ("merge-conformance-r0.txt", "diag/cam-sel-equivalence.md",
            "result-r0.md", "lessons-r0.md"):
    docs[rel] = rec(R0 / rel)

man = {
    "package": "T10.b18-b17-b",
    "round": "r0",
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
    "stopped_modifying": True,
    "merged_candidate": "b17 native-PAXI/v6/R1-retry base + b14 B tap / CAM_SEL=1",
    "device": "PH1P100SBG484 speed 3, Routed",
    "inputs": inputs,
    "candidate": cand,
    "scripts": scripts,
    "sim_results": simres,
    "td_artifacts": tdart,
    "board_artifacts": boardart,
    "documents": docs,
    "hashes_missing": sorted([k for grp in (inputs, cand, scripts, simres, tdart)
                              for k, v in grp.items() if v["sha256"] == "MISSING"]),
}
(PKG / "CANDIDATE-MANIFEST-b18-b17-b-r0.json").write_text(json.dumps(man, indent=2))
print("MANIFEST_OK entries=%d missing=%d" %
      (len(inputs) + len(cand) + len(scripts) + len(simres) + len(tdart),
       len(man["hashes_missing"])))
print(json.dumps(man["hashes_missing"], indent=2))
