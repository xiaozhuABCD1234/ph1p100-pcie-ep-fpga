#!/usr/bin/env python3
"""make_manifest_b20.py -- freeze T10.b20-a-timing r0 into one manifest.

Run only after the developer stopped modifying the package.  Every group records
the actual file hash; missing artifacts are listed in hashes_missing instead of
being silently skipped.  The candidate is the b19 A chain with the single
a1_frame_top.v abort_d change (see r0/diag/abort-path-fix.md).
"""
import hashlib
import json
import pathlib
import re
import sys
import time

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop"
PKG = RUN / "T10.b20-a-timing"
R0 = PKG / "r0"
B19 = RUN / "T10.b19-cam-a"
B18 = RUN / "T10.b18-b17-b"
B17 = RUN / "T10.b17-paxi-native"

STATUS = sys.argv[1] if len(sys.argv) > 1 else "pending"


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def rec(p):
    p = pathlib.Path(p)
    return {"path": str(p), "sha256": sha(p),
            "bytes": p.stat().st_size if p.exists() else None}


def txt(p):
    p = pathlib.Path(p)
    return p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""


inputs = {}
for n in ("a1_raw_crop.v", "a1_ddr_slot_store.v", "a1_ddr_arb2.v", "a1_uart_export.v",
          "camera_a1_uart_top.v", "cam_diag_mailbox.v", "a1_frame_top.v",
          "a1_deflate_core.v", "p2_ddr_bridge.v", "p2_a1_board_top.v",
          "f9p_camera_display_core.v"):
    inputs["b19_changed_src/" + n] = rec(B19 / "r0/changed-src" / n)
inputs["b19_sdc"] = rec(B19 / "r0/td/p2_board.sdc")
inputs["b19_adc"] = rec(B19 / "r0/td/board_p2.adc")
inputs["b19_bit_reference_only"] = rec(B19 / "r0/td/a1_board.bit")
inputs["b18_board_capture_negative_control"] = rec(
    B18 / "r0/board/captures_full/com8_300s.bin")
inputs["b17_sdc"] = rec(B17 / "r0/td/p2_board.sdc")
for n in ("tb_b17_chain.sv", "tb_b17_paxi_native.sv", "tb_p1_chain.v",
          "p2_paxi_model_b17.v", "a1_ddr_model.v", "check_b17.py",
          "check_b17_core.py", "check_b19.py"):
    inputs["b19_sim/" + n] = rec(B19 / "r0/sim" / n)
for p in sorted((B19 / "r0/sim/caps").glob("*.dec")):
    inputs["b19_sim/caps/" + p.name] = rec(p)

cand = {}
for p in sorted((R0 / "changed-src").glob("*.v")):
    cand[p.name] = rec(p)
cand["td/p2_board.sdc"] = rec(R0 / "td/p2_board.sdc")
cand["td/board_p2.adc"] = rec(R0 / "td/board_p2.adc")

scripts = {}
for pat in ("check_merge_b20.py", "make_manifest_b20.py", "cone_check_b20.py"):
    scripts[pat] = rec(R0 / pat)
for p in (sorted((R0 / "sim").glob("*.py")) + sorted((R0 / "sim").glob("tb_*.v")) +
          sorted((R0 / "sim").glob("tb_*.sv")) +
          sorted((R0 / "board").glob("*.py")) + sorted((R0 / "board").glob("*.ps1")) +
          sorted((R0 / "board").glob("*.tcl")) + sorted((R0 / "td").glob("*.tcl")) +
          sorted((R0 / "td").glob("*.ps1"))):
    scripts[str(p.relative_to(R0)).replace("\\", "/")] = rec(p)

simres = {}
for p in sorted((R0 / "sim").glob("sim-results-b20-*.json")):
    simres[p.name] = rec(p)

tdart = {}
for rel in ("build_console_r0.log", "run_build_b20.out", "syn_gate_timing.rpt",
            "syn_gate_area.rpt", "a1_board.al", "a1_board_Runs/syn_1/a1_board.prj",
            "routed_qor.rpt", "routed_timing_status.rpt", "routed_timing_summary.rpt",
            "routed_timing.rpt", "routed_area.rpt", "route_flow.status",
            "place_flow.status", "routed_netlist.v", "p2_board.sdc",
            "a1_board_Runs/phy_1/a1_board_pr.db", "bitgen_console_r0.log",
            "cwc_console_r0.log", "candidate_timing.rpt", "candidate_hashes_r0.txt",
            "a1_board.bit", "a1_board.cwc", "a1_board_inst.bid", "cw/compiled.bit",
            "cw/compiled.cwc"):
    tdart[rel] = rec(R0 / "td" / rel)

boardart = {}
for p in (sorted((R0 / "board").glob("log/*")) +
          sorted((R0 / "board").glob("captures_a/*")) +
          sorted((R0 / "board").glob("negative_b18/*"))):
    p = pathlib.Path(p)
    if p.exists():
        boardart[str(p.relative_to(R0)).replace("\\", "/")] = rec(p)

docs = {}
for rel in ("merge-conformance-r0.txt", "diag/abort-path-fix.md",
            "diag/a1_frame_top-b20.diff", "diag/cone-check-routed.txt",
            "result-r0.md", "lessons-r0.md"):
    docs[rel] = rec(R0 / rel)

# runtime numbers (missing -> None)
syn = txt(R0 / "td/syn_gate_timing.rpt")
rts = txt(R0 / "td/routed_timing_status.rpt")
rq = txt(R0 / "td/routed_qor.rpt")


def num(pat, s):
    m = re.search(pat, s)
    return float(m.group(1)) if m else None


candtxt = txt(R0 / "td/candidate_hashes_r0.txt")
bit = re.search(r"([0-9A-F]{64})\s+\d+\s+a1_board\.bit", candtxt)
cwc = re.search(r"([0-9A-F]{64})\s+\d+\s+a1_board\.cwc", candtxt)
bid = re.search(r"([0-9A-F]{64})\s+\d+\s+a1_board_inst\.bid", candtxt)

man = {
    "package": "T10.b20-a-timing",
    "round": "r0",
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "created": time.strftime("%Y-%m-%dT%H:%M:%S"),
    "stopped_modifying": True,
    "status": STATUS,
    "candidate": "b19 A chain (CAM_SEL=0, PAXI x8/mask=0, retry/R1, v6) with exactly one "
                 "RTL delta in a1_frame_top.v: registered abort_d for the drain-side "
                 "teardown (abort -> smem read-address cone broken, +0..1 cycle on "
                 "abort teardown only)",
    "device": "PH1P100SBG484 speed 3, clk_a1 187.5 MHz",
    "delta_vs_b19": {
        "a1_frame_top.v_b19": "0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109",
        "a1_frame_top.v_b20": sha(R0 / "changed-src/a1_frame_top.v"),
        "sdc_byte_identical_to_b19": sha(R0 / "td/p2_board.sdc") ==
        "0888b6a705a039a6cbabebacf323244a36257b5f29fb51bab7d81ef003220f5e",
        "adc_byte_identical_to_b17r1": sha(R0 / "td/board_p2.adc") ==
        "1cb30346fa17da6bb0e77802ca72c4b4bb4aecc1445711e19391cf4ee2271580",
        "diff": "r0/diag/a1_frame_top-b20.diff",
    },
    "build": {
        "syn_sws": num(r"SWNS:\s*(-?[0-9.]+)", syn),
        "syn_tns": num(r"STNS:\s*(-?[0-9.]+)", syn),
        "routed_sws": num(r"SWNS:\s*(-?[0-9.]+)ns", rts) or num(r"SWNS:\s*(-?[0-9.]+)ns", rq),
        "routed_tns": num(r"STNS:\s*(-?[0-9.]+)ns", rts),
        "routed_hws": num(r"HWNS:\s*(-?[0-9.]+)ns", rts),
        "routed_viol_ep": num(r"Num of violated S-EP\s*\|\s*([0-9]+)", rq),
        "routed_viol_ep_status": num(r"([0-9]+)\s+Viol Endpoints", rts),
        "bit": bit.group(1).lower() if bit else None,
        "cwc": cwc.group(1).lower() if cwc else None,
        "bid": bid.group(1).lower() if bid else None,
        "downloads": 1 if (R0 / "board/log/download_b20.log").exists() else 0,
    },
    "inputs": inputs,
    "candidate_files": cand,
    "scripts": scripts,
    "sim_results": simres,
    "td_artifacts": tdart,
    "board_artifacts": boardart,
    "documents": docs,
    "hashes_missing": sorted(set([k for grp in (cand, scripts, simres, tdart, docs)
                                  for k, v in grp.items() if v["sha256"] == "MISSING"] +
                                 [k for k, v in inputs.items() if v["sha256"] == "MISSING"])),
}
out = PKG / "CANDIDATE-MANIFEST-b20-a-timing-r0.json"
out.write_text(json.dumps(man, indent=2))
print("MANIFEST_OK %s entries=%d missing=%d" %
      (out, len(inputs) + len(cand) + len(scripts) + len(simres) + len(tdart) + len(docs),
       len(man["hashes_missing"])))
print(json.dumps(man["hashes_missing"], indent=2))
