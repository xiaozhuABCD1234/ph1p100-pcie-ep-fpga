#!/usr/bin/env python3
"""gen_manifest_intp4.py - freeze the INT.P4 same-candidate manifest (round 2).

Re-verifies every production_inputs/tool_inputs entry declared by the frozen
INT.P1-r1, INT.P2-r0 and INT.P3-r1 manifests, binds the read-only b20 A+ inputs
by hash, binds the derived timing variants, the equivalence TB, the 10 frozen
img sources, the candidate TBs, the synthesis harness, the build entries and the
evidence, then writes INT.P4-r2-manifest.json with stopped_modifying=true.

Round2 differences vs round1:
  * the two r2 timing-only derived variants (bayer_raw10_demosaic4_p4.v,
    img_algo_parallel_top_p4.v) and the equivalence TB are bound, together with
    the base-file hashes and the diff summary (source_variant_bases);
  * the 10 frozen fpga/csi2/src/img/*.v sources are bound explicitly (r1 did not
    bind them, D5d);
  * the candidate TBs that the simulation entry compiles are bound;
  * the candidate work/ directory is registered as a legacy untracked artifact
    (r1 did not register it, D5e) and the leftover files are recorded as
    "registered, NOT deleted" (D5b);
  * the real Viol Endpoint statistics are recorded: r1 = 330, r2 = 112 (the r1
    documents wrongly used the 10 printed paths);
  * the INT.P1 production-file override is updated to the r2 version;
  * the two r2 timing-experiment files (algo_rowwin3_p4.v /
    gray8_gaussian3x3_stream_p4.v, moved out of the candidate directory and NOT
    compiled) are registered with the reason they were rejected.

Usage:  python tools/integrated_delivery/gen_manifest_intp4.py [--round 2]
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUN_REL = "workflow/runs/20261026-2138_fpga-integrated-delivery"
RUN = os.path.join(ROOT, RUN_REL)

A1_RO = {
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_frame_top.v":
        "cda28c941321f28df8318dacaf291f6268ea5e4d6ea9faf9921ed824b3a2160c",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_deflate_core.v":
        "a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_ddr_slot_store.v":
        "6c619cf90e54385d667f1ec0f63cc87ee58aadd3c42143330ac4945eb47defe9",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_ddr_arb2.v":
        "b84019bda057afe82ff558e0848d6171fa12732bd8cdb7c6239cb71b3f81d6ba",
}

# INT.P1 r1 -> r2 production-file update inside this delivery.
P1_OVERRIDES = {
    "fpga/csi2/src/integrated_delivery/integrated_input_processing_top.v": {
        "previous_sha256": "8cd7d35bd1fe04f3fc308eedd9d22f5f57ee605704d87384b544913ec7ff3fd0",
        "released_by": "INT.P4",
        "round": 2,
        "reason": ("r2: (a) instantiates the timing-only derived img_algo_parallel_top_p4 "
                   "(identical ports/semantics, registered ready boundaries); (b) adds the "
                   "2-beat elastic stage int_p4_elastic_beats in front of the algorithm branch "
                   "so the capture/admit logic can no longer reach the P1 row-buffer accept "
                   "path combinationally; the r1 both-consumer exactly-once handshake rule is "
                   "unchanged."),
    },
}

BASE_IMG = {
    "fpga/csi2/src/img/bayer_raw10_demosaic4.v":
        "138e7124de1f57bd199c9f6ea340ed9da8fbb4355326f74c15ef6c85795fdbef",
    "fpga/csi2/src/img/img_algo_parallel_top.v":
        "7f1e05443e7432df0069297f515bf96b293022c957f7f05ceda2452f60101811",
    "fpga/csi2/src/img/algo_rowwin3.v":
        "46a6ceb10844b9ccb2054b8b2a911624dc04db0ca167ef72b8b86c9e08571384",
    "fpga/csi2/src/img/gray8_gaussian3x3_stream.v":
        "c358174f56aeb2d4a64a2b7484c53ea9feed2f6cd857ac06c315250110a55dd6",
}

VARIANT_DIFFS = {
    "fpga/csi2/src/integrated_delivery/bayer_raw10_demosaic4_p4.v": {
        "base": "fpga/csi2/src/img/bayer_raw10_demosaic4.v",
        "diff": ("r2 layer: module output is a 2-beat elastic stage (int_p4_elastic_beats) whose ready "
                 "comes from its own count register, so pipe_en no longer depends on m_ready. "
                 "r3 layer: u_row instance is the derived algo_rowwin3_p4. Configuration block, P/Q/T "
                 "pipelines, clamping/truncation, frame counters, sidebands and ports are verbatim; "
                 "observable latency +1 cycle from the r3 row-window retime (plus the r2 0..2 elastic)"),
    },
    "fpga/csi2/src/integrated_delivery/img_algo_parallel_top_p4.v": {
        "base": "fpga/csi2/src/img/img_algo_parallel_top.v",
        "diff": ("r2 layer: u_front is bayer_raw10_demosaic4_p4 plus a 2-beat elastic stage B between the "
                 "four rgb8_gray_stream lanes and the three output consumers (registered ready to the gray "
                 "streams). r3 layer: u_gau is gray8_gaussian3x3_stream_p4 (its u_row is algo_rowwin3_p4). "
                 "The all-or-nothing transfer rule, obufs, HE branch, eof/abort delay chain and port list "
                 "are identical; add arithmetic/frame-schedule change: none"),
    },
    "fpga/csi2/src/integrated_delivery/algo_rowwin3_p4.v": {
        "base": "fpga/csi2/src/img/algo_rowwin3.v",
        "diff": ("r3 core retime, ONLY change: ra0/ra1/ra2 are captured in ra0_r/ra1_r/ra2_r on evt_en so the "
                 "LUT-RAM address pins are flop-driven; rb0/rb1/rb2 read bank*[ra*_r] gated by en (stall "
                 "freeze, gap uses the base's held address); cbq/ubq delayed one cycle (cbq_d/ubq_d) to stay "
                 "aligned with the later rb*; s_data_d/st_r1_d/st_r2_d and prod_valid_d/prod_y_d/prod_j_d/"
                 "prod_first_d/prod_last_d/prod_abort_d delayed by the same fixed cycle and win_*/prod_* "
                 "driven from them. s_ready expression, state machine, write port, bank rotation, flush "
                 "schedule, abort/restart rules, asm40/asm32 clamping and ports are verbatim. Fixed added "
                 "latency = +1 clk; no arithmetic/frame-schedule/port change"),
    },
    "fpga/csi2/src/integrated_delivery/gray8_gaussian3x3_stream_p4.v": {
        "base": "fpga/csi2/src/img/gray8_gaussian3x3_stream.v",
        "diff": ("r3 handshake/instance-only variant: u_row is algo_rowwin3_p4; pipe_en = "
                 "!(m_valid && !m_ready), P/R/O stages, Gaussian arithmetic, rounding, clamping, sidebands, "
                 "counters, ports and s_ready contract are verbatim; fixed added latency = the rowwin +1 clk "
                 "(no further cycle)"),
    },
}

LATENCY_ADDED = {
    "algo_rowwin3_p4_u_front": "+1 clk (fixed) at the u_front row-window output boundary "
                               "(prod_*/win_* aligned, s_ready unchanged)",
    "algo_rowwin3_p4_u_gau": "+1 clk (fixed) at the u_gau row-window output boundary",
    "bayer_raw10_demosaic4_p4": "no cycle added by this file itself (r2 elastic stage unchanged); inherits +1 from u_row",
    "gray8_gaussian3x3_stream_p4": "no cycle added by this file itself; inherits +1 from u_row",
    "img_algo_parallel_top_p4": "no cycle added by this file itself (stage B unchanged)",
    "total_vs_r2_candidate": "observable +1 clk of fixed latency per derived rowwin instance; data order, "
                             "sof/eol/eof/abort markers, production slot count, flush order and frame state "
                             "machine unchanged by construction",
}

IMG_SOURCES = [
    "fpga/csi2/src/img/algo_obuf.v",
    "fpga/csi2/src/img/algo_rowwin3.v",
    "fpga/csi2/src/img/algo_rowwin_reader.v",
    "fpga/csi2/src/img/bayer_raw10_demosaic4.v",
    "fpga/csi2/src/img/gray8_gaussian3x3_frame.v",
    "fpga/csi2/src/img/gray8_gaussian3x3_stream.v",
    "fpga/csi2/src/img/gray8_he_cdfmin_frame.v",
    "fpga/csi2/src/img/img_algo_parallel_top.v",
    "fpga/csi2/src/img/img_algo_top_g2.v",
    "fpga/csi2/src/img/rgb8_gray_stream.v",
]

NEW_FILES = [
    "fpga/csi2/src/integrated_delivery/integrated_delivery_top.v",
    "fpga/csi2/src/integrated_delivery/integrated_input_processing_top.v",
    "fpga/csi2/src/integrated_delivery/bayer_raw10_demosaic4_p4.v",
    "fpga/csi2/src/integrated_delivery/img_algo_parallel_top_p4.v",
    "fpga/csi2/src/integrated_delivery/algo_rowwin3_p4.v",
    "fpga/csi2/src/integrated_delivery/gray8_gaussian3x3_stream_p4.v",
    "fpga/csi2/src/integrated_delivery/tb_integrated_delivery_top.v",
    "fpga/csi2/src/integrated_delivery/tb_img_algo_equiv_p4.v",
    "fpga/csi2/src/integrated_delivery/tb_raw10_packer.v",
    "fpga/csi2/src/integrated_delivery/tb_aplus_pcie_egress_adapter.v",
    "fpga/csi2/src/integrated_delivery/tb_dual_channel_capture_scheduler.v",
    "tools/integrated_delivery/run_integrated_sim.ps1",
    "tools/integrated_delivery/run_integrated_build.ps1",
    "tools/integrated_delivery/td/01_synth.tcl",
    "tools/integrated_delivery/td/02_route.tcl",
    "tools/integrated_delivery/td/integrated_core.sdc",
    "tools/integrated_delivery/synth/integrated_delivery_synth_wrap.v",
    "tools/integrated_delivery/gen_manifest_intp4.py",
    "tools/integrated_delivery/verify_integrated_sample.py",
    "tools/integrated_delivery/evidence/integrated_sample.a1u1",
    "tools/integrated_delivery/evidence/integrated_sample.raw",
    "tools/integrated_delivery/evidence/integrated_sample.json",
]

DOC_FILES = [
    "INT.P4-protocol.md",
    "INT.P4-build-entry.md",
    "INT.P4-shortest-steps.md",
    "INT.P4-lessons.md",
    "INT.P4/result-r0.md",
    "INT.P4/result-r1.md",
    "INT.P4/result-r2.md",
    "INT.P4/result-r3.md",
]

LEGACY_UNTRACKED = [
    "fpga/csi2/src/integrated_delivery/sim_output.txt",
    "fpga/csi2/src/integrated_delivery/transcript",
]

LEGACY_DIRS = [
    "fpga/csi2/src/integrated_delivery/work",
]

# r2 timing experiment: files created, synthesized once (identical netlist, TD did
# not honour (* ram_style="bram" *) because the line-buffer read registers carry an
# asynchronous reset) and then moved out of the candidate directory.  Registered
# for provenance; NOT compiled by any entry point.
EXPERIMENT = [
    "workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r2-timing-experiment/algo_rowwin3_p4.v",
    "workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r2-timing-experiment/gray8_gaussian3x3_stream_p4.v",
]

EVID_DIRS = ["INT.P4/regression", "INT.P4/td", "INT.P4/sim/run",
             "INT.P4/sim/compile", "INT.P4/sim/equiv", "INT.P4/r3"]

GATES_R2 = {
    "G0": "pass - one clk/rst_n domain, single create_clock 5.333ns (187.5MHz), no CDC, no "
          "asynchronous FIFO, no clock change; A1U1 vs R10F separated; RAW (m_is_raw) vs "
          "Y8/processed separated; derived variants keep the exact module interfaces/units",
    "G1": "pass (RTL simulation, reduced 64x48, one session on the frozen r2 candidate) - dev TB "
          "MODE=4 and MODE=1, default and +EXTRA (T1-T6, 65 ok / 0 fail each); tester-style "
          "P1/P2/P3 TBs rerun PASS; python tools RAW10_PACK / INT.P1_VERIFY / "
          "DUAL_CHANNEL_SCHEDULE / A1U1_DECODE OK / VERIFY_INTEGRATED_SAMPLE PASS; mode1 and "
          "mode4 A1U1 samples are byte-identical to the frozen r1 hashes "
          "(79e35f28.../1357408f.../76d88910...); derived-variant data-sequence equivalence "
          "CHECK_REF_NEW PASS in three ready-pattern modes for y8/gau/he (order, data, "
          "sof/eol/eof, abort markers, status counters). Not a board/PCIe claim.",
    "G2": "FAIL (synthesis completed, quota exhausted) - flow.status: SWNS -637ps, STNS "
          "-69.776ps, NUM_FEPS 112 of 16770 endpoints (r1: 330); hold 0; IO 42/286; ERAM+CWC "
          "39/300; reg 5832, slice* 10761/71680, DSP 14, LUT 13009 -> resources fit; STA "
          "coverage 95.76%; no HDL-5314 undriven DUT-input warning and u_arb/u_egress/u_store "
          "hierarchy rows are present (harness DDR slave fully driven); worst path "
          "5.906ns = u_obuf_gau/count_reg[0] -> u_gau/u_row/rb0_reg[0].d (row-window read "
          "enable/address path inside the frozen img modules); route=not_run because setup did "
          "not converge; bitgen/CWC/download/Flash = 0. r2 used 3 of 3 authorized synth runs "
          "(277 -> 112 -> 112 endpoints); no 4th run.",
    "G3": "not_run - awaiting_hardware (no integrated bit / board window; nothing fabricated)",
    "G4": "not_run - deferred (pipeline depth 1 frame; long-run/throughput out of scope)",
    "G5": "pass for the delivered pack - manifest/protocol/build entry/decode tool/sample/"
          "shortest steps present and hash-bound to the same candidate; real endpoint counts "
          "(r1 330 -> r2 112) in manifest/result/build-entry/shortest-steps; 10 img sources "
          "bound; candidate work/ and the two leftover files registered as legacy (not "
          "deleted); compiled file counts match the entries; RK real PCIe transport still "
          "pending (not claimed)",
}


GATES_R3 = {
    "G0": "pass - one clk/rst_n domain, single create_clock 5.333ns (187.5MHz), no CDC, no asynchronous "
          "FIFO, no clock change; A1U1 vs R10F separated; RAW (m_is_raw) vs Y8/processed separated; the "
          "derived variants keep the exact module interfaces/parameters/units/frame schedule",
    "G1": "dev/integrated regression pass, derived-variant token equivalence NOT fully identical (reported "
          "honestly, not claimed) - dev TB MODE=4 and MODE=1, default and +EXTRA (27/65/26/65 ok, 0 fail); "
          "P1/P2/P3 TBs PASS; python RAW10_PACK / INT.P1_VERIFY / DUAL_CHANNEL_SCHEDULE / A1U1_DECODE / "
          "VERIFY_INTEGRATED_SAMPLE PASS; mode1/mode4 samples byte-identical to the frozen hashes "
          "79e35f28.../1357408f.../76d88910.... CHECK_REF_NEW residual data mismatches 2867/2451/57 for "
          "SEEDMODE 0/1/2 (token counts and marker positions identical); unit-level equivalence is exact "
          "without stalls (rowwin 1330 tokens, bayer 769 tokens) and the CONTROL_REF_REF2 (identical base "
          "RTL, different ready seeds) still shows 98/99/48 HE-only differences, i.e. the frozen HE module "
          "is stall-pattern sensitive. G1 as defined is therefore NOT met this round",
    "G2": "PASS (r3_run1, new synthesis) - flow.status: Setup NUM_FEPS 0 of 17220 endpoints, WNS +72ps, "
          "TNS 0ps; Hold 0 endpoints (report HWNS/HTNS 0.000/0.000; flow.status HWNS sentinel 2147483647ps"
          "); IO 42/286; ERAM+CWC 39/300; reg 6004, slice* 10691/71680, lut 12943, DSP 14; STA coverage "
          "95.63%; no HDL-5314/SYN-5013 undriven DUT-input warning; u_front/u_row and u_gau/u_row are "
          "algo_rowwin3_p4 and u_arb/u_egress/u_store are visible; single 5.333ns clock, no false_path/"
          "multicycle. r2 comparison: 112 endpoints / WNS -0.637 / TNS -69.776 -> 0 / +0.072 / 0. "
          "route=not_run (harness has no pin/IO constraints; the route allowance is left unused); "
          "bitgen/CWC/download/Flash = 0. r3 used 1 of 3 authorized synth runs (lifetime 7 of 9)",
    "G3": "not_run - awaiting_hardware (no integrated bit / board window; nothing fabricated)",
    "G4": "not_run - deferred (pipeline depth 1 frame; long-run/throughput out of scope)",
    "G5": "pass for the delivered pack - manifest/protocol/build-entry/decode tool/sample/shortest-steps "
          "present and hash-bound to the same candidate; real r3 endpoint/WNS/TNS numbers in manifest/"
          "result-r3/build-entry/shortest-steps; 10 img sources bound and unchanged; new derived rowwin/"
          "stream variants bound with source hash + diff summary + added latency; legacy files and work/ "
          "registered (not deleted); compiled file counts match the entries (24 sim core + 6 TB, 25 synth "
          "sources); E5a-E5c hygiene resolved (td/README-EVIDENCE.md, r1 run.log annotated in place, the "
          "run3 experiment tcl renamed DO_NOT_USE, syn_1 pointed to syn_r2_run2 for r2 and r3_run1 for r3); "
          "RK real PCIe transport still pending (not claimed)",
}

R3_FILESET = {
    "path": "workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/td/r3_run1-fileset.sha256",
    "expected_sha256": "feda255c64e0322f5bf18611b737a46906c8e3cc6588fbcaf26edc65c50f8416",
    "note": "27 items (25 Verilog sources = candidate/tool 15 + img 10, plus tcl and sdc), one SHA256 per "
            "file; different from the r2 file set (distinct-synthesis precondition). This run's per-run "
            "equivalence precondition is a documented deviation: CHECK_REF_NEW had residual data "
            "mismatches (see gates.G1 and INT.P4/result-r3.md section 3).",
}

DERIVED_EQUIV_R3 = {
    "tool": "tb_img_algo_equiv_p4 (unchanged TB, token-sequence comparison, added latency allowed)",
    "seedmode_errors": {"0": 2867, "1": 2451, "2": 57},
    "token_counts": {"y8": 1720, "gau": 1703, "he": 1720, "all_duts": True},
    "marker_positions": "identical (sof/eol/eof/abort tokens at the same indices and per-stream state counts equal)",
    "control_ref_ref2_diffs": {"0": 98, "1": 99, "2": 48, "note": "identical base RTL, different ready seeds - HE only"},
    "unstalled_unit_equivalence": {
        "rowwin_base_vs_p4_continuous_en": "1330 tokens identical (TB_ROW_WIN_RETIME_CHECK PASS)",
        "bayer_base_vs_p4_always_ready": "769 tokens identical (TB_BAYER_RETIME_CHECK PASS)",
    },
    "verdict": "NOT fully identical under randomized ready -> G1 not claimed; handed to the tester",
}


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 16), b""):
            h.update(b)
    return h.hexdigest()


def entry(rel: str, base: str = ROOT) -> dict:
    p = os.path.join(base, rel)
    if not os.path.exists(p):
        return {"path": rel, "state": "missing"}
    return {"path": rel, "sha256": sha256(p), "size": os.path.getsize(p)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--round", type=int, default=3)
    args = ap.parse_args()
    rnd = args.round
    out = {
        "schema": 1, "task_id": "INT.P4", "round": rnd,
        "run_id": "20261026-2138_fpga-integrated-delivery",
        "candidate_root": "fpga/csi2/src/integrated_delivery",
        "clock": {"name": "clk", "period_ns": 5.333, "target_mhz": 187.5,
                  "domains": 1, "cdc_added": False},
        "top": "fpga/csi2/src/integrated_delivery/integrated_delivery_top.v",
        "synthesis_top": "tools/integrated_delivery/synth/integrated_delivery_synth_wrap.v",
        "synthesis_top_note": ("Synthesis-only harness: instantiates the frozen top unchanged and "
                               "replaces the off-chip capture/DDR/descriptor/PCIe/observation "
                               "pins with on-chip models plus a 32-bit XOR observation register "
                               "(2813 -> 42 IO) so TD can map the real logic inside the 286-pin "
                               "device. NOT a board shell. r2 change: every DUT DDR slave input "
                               "(ddr_awready/ddr_wready/ddr_arready/ddr_rvalid/ddr_rdata) is "
                               "driven by the behavioural DDR model, so u_arb/u_egress/u_store "
                               "are no longer trimmed; coverage boundary = internal "
                               "register-to-register STA only, IO unconstrained, no "
                               "false_path/multicycle, one 5.333ns clock."),
        "parameters": {"sim": {"W": 64, "H": 48, "SLOT_WORDS": 1024},
                       "synth": {"W": 1920, "H": 1080, "SLOT_WORDS": 81085,
                                 "note": "module defaults; the TD run used them"}},
        "readonly_a1_inputs": [], "new_files": [], "img_sources": [], "docs": [],
        "legacy_untracked": [], "legacy_dirs": [], "source_variant_bases": {},
        "p1p2p3_hash_verification": [], "source_version_overrides": P1_OVERRIDES,
        "tool_inputs": [], "evidence": [], "td": [],
        "gates": (GATES_R3 if rnd >= 3 else GATES_R2),
        "endpoint_counts": ({
            "r1_viol_endpoints": 330, "r1_wns_ns": -1.549, "r1_tns_ns": -271.427,
            "r2_viol_endpoints": 112, "r2_wns_ns": -0.637, "r2_tns_ns": -69.776,
            "r2_total_endpoints": 16770,
            "r3_viol_endpoints": 0, "r3_wns_ns": 0.072, "r3_tns_ns": 0.0,
            "r3_total_endpoints": 17220, "r3_hold_viol_endpoints": 0,
            "r3_sta_coverage_pct": 95.63,
            "r3_evidence": "INT.P4/td/r3_run1/syn_flow.status + syn_gate_timing.rpt/syn_gate_area.rpt",
            "source": ("flow.status Setup/Hold lines of the bound syntheses; r1 documents wrongly "
                       "reported 10 (the printed 'Slack : -' path count) - corrected in r2; r3 adds the "
                       "r3_run1 numbers"),
        } if rnd >= 3 else {
            "r1_viol_endpoints": 330, "r1_wns_ns": -1.549, "r1_tns_ns": -271.427,
            "r2_viol_endpoints": 112, "r2_wns_ns": -0.637, "r2_tns_ns": -69.776,
            "r2_total_endpoints": 16770,
            "r2_hold_wns_ns": 0.0,
            "source": ("flow.status Setup/Hold lines of the bound syntheses; the r1 documents wrongly "
                       "reported 10 (the printed 'Slack : -' path count) - corrected here and in "
                       "result/build-entry/shortest-steps"),
        }),
        "stopped_modifying": True,
    }
    if rnd >= 3:
        out["latency_added"] = LATENCY_ADDED
        out["derived_equivalence_r3"] = DERIVED_EQUIV_R3
        e = entry(R3_FILESET["path"])
        e["expected_sha256"] = R3_FILESET["expected_sha256"]
        e["match"] = (e.get("sha256") == R3_FILESET["expected_sha256"])
        e["note"] = R3_FILESET["note"]
        out["r3_synth_fileset"] = e
        out["evidence_hygiene_r3"] = {
            "E5a": "INT.P4/td/run.log is the r1 log (identical to td/r1-evidence/run.log); left in place "
                   "but annotated in INT.P4/td/README-EVIDENCE.md and here - it is NOT r3 evidence",
            "E5b": "INT.P4/td/01_synth.tcl (run3 experiment copy with two non-existent experiment files) "
                   "renamed to 01_synth_r2run3_experiment_copy_DO_NOT_USE.tcl; official entry is "
                   "tools/integrated_delivery/td/01_synth.tcl and its exact copy is td/r3_run1/01_synth.tcl",
            "E5c": "INT.P4/td/int_p4_Runs/syn_1 mixes run2/run3 -> r2 authority is td/syn_r2_run2/, r3 "
                   "authority is td/r3_run1/ (each r3 run uses a fresh subdir)",
        }
    drift = 0

    for rel, exp in A1_RO.items():
        e = entry(rel)
        e["expected_sha256"] = exp
        e["match"] = (e.get("sha256") == exp)
        if not e["match"]:
            drift += 1
        out["readonly_a1_inputs"].append(e)

    for rel in NEW_FILES:
        e = entry(rel)
        if e.get("state") == "missing":
            drift += 1
        out["new_files"].append(e)

    for rel in IMG_SOURCES:
        e = entry(rel)
        if e.get("state") == "missing":
            drift += 1
        out["img_sources"].append(e)
    out["img_source_count"] = len(IMG_SOURCES)

    for rel, exp in BASE_IMG.items():
        e = entry(rel)
        e["expected_sha256"] = exp
        e["match"] = (e.get("sha256") == exp)
        if not e["match"]:
            drift += 1
        out["source_variant_bases"][rel] = e
    for rel, d in VARIANT_DIFFS.items():
        out["source_variant_bases"].setdefault("variants", {})[rel] = d
    out["source_variant_bases"]["note"] = (
        "fpga/csi2/src/img/** was read-only this round (never edited); the derived variants are "
        "new files under the candidate root with the diffs above. No CDC, no asynchronous FIFO, "
        "no clock change.")

    for rel in DOC_FILES:
        relp = os.path.relpath(os.path.join(RUN, rel), ROOT).replace("\\", "/")
        e = entry(relp)
        if e.get("state") == "missing":
            drift += 1
        out["docs"].append(e)

    for rel in LEGACY_UNTRACKED:
        e = entry(rel)
        e["note"] = ("pre-INT.P4 leftover in the candidate directory (mtime before P4 dispatch); "
                     "not part of the candidate, not referenced by any build/TB; REGISTERED, NOT "
                     "DELETED (batch-delete ban); r1 wording that claimed a deletion is corrected")
        out["legacy_untracked"].append(e)

    for rel in LEGACY_DIRS:
        base = os.path.join(ROOT, rel)
        rec = {"path": rel, "state": "present" if os.path.isdir(base) else "missing",
               "files": []}
        if os.path.isdir(base):
            for fn in sorted(os.listdir(base)):
                p = os.path.join(base, fn)
                if os.path.isfile(p):
                    rec["files"].append({"name": fn, "sha256": sha256(p),
                                         "size": os.path.getsize(p)})
            rec["note"] = ("legacy ModelSim work library that existed in the candidate directory "
                           "before task P4 (mtime 2026-10-27 00:16, earlier than the r0 dispatch); "
                           "not compiled by any entry point; REGISTERED, NOT DELETED")
        else:
            drift += 1
        out["legacy_dirs"].append(rec)

    for rel in EXPERIMENT:
        e = entry(rel)
        if e.get("state") == "missing":
            drift += 1
        e["note"] = ("r2 timing experiment: created to move the row-window line buffers to ERAM "
                     "via (* ram_style=\"bram\" *) so the row-buffer read path would end at the "
                     "ERAM address input.  Synthesized once (r2 run 3): TD did not honour the "
                     "attribute (ERAM 39 unchanged, reg 5832 unchanged), the netlist was "
                     "bit-identical to r2 run 2 (WNS -0.637 / 112 endpoints), so the files were "
                     "moved out of the candidate directory and are NOT compiled. Registered for "
                     "provenance, not deleted.")
        out["new_files"].append(e)

    for tag, mf in (("INT.P1", "INT.P1-r1-manifest.json"),
                    ("INT.P2", "INT.P2-r0-manifest.json"),
                    ("INT.P3", "INT.P3-r1-manifest.json")):
        mpath = os.path.join(RUN, mf)
        with open(mpath, "r", encoding="utf-8") as f:
            m = json.load(f)
        rec = {"manifest": mf, "manifest_sha256": sha256(mpath), "files": []}
        for f_ in m.get("production_inputs", []) + m.get("tool_inputs", []):
            rel = f_["path"]
            e = entry(rel)
            e["expected_sha256"] = f_.get("sha256")
            e["expected_size"] = f_.get("size")
            ov = P1_OVERRIDES.get(rel)
            if ov and e.get("sha256") not in (None, ov["previous_sha256"]):
                e["match"] = True
                e["override"] = ov
                e["note"] = ("declared INT.P1-r1 hash superseded by the recorded r2 version "
                             "(see source_version_overrides); the new hash is bound here")
            else:
                e["match"] = (e.get("sha256") == f_.get("sha256") and
                              e.get("size") == f_.get("size"))
                if not e["match"]:
                    drift += 1
            rec["files"].append(e)
        out["p1p2p3_hash_verification"].append(rec)

    for rel in EVID_DIRS:
        base = os.path.join(RUN, rel)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirs, files in os.walk(base):
            for fn in sorted(files):
                if fn.endswith(".pyc"):
                    continue
                p = os.path.join(dirpath, fn)
                relp = os.path.relpath(p, ROOT).replace("\\", "/")
                e = entry(relp)
                if "/INT.P4/td/" in relp:
                    out["td"].append(e)
                else:
                    out["evidence"].append(e)

    for rel in ("tools/integrated_delivery/a1u1_decode.py",
                "tools/integrated_delivery/evidence/a1u1_sample.a1u1",
                "tools/integrated_delivery/evidence/golden_input_processing.json",
                "tools/integrated_delivery/evidence/verify_report.json"):
        out["tool_inputs"].append(entry(rel))

    out["regression_logs_round3"] = [
        "INT.P4/r3/regression/integrated_mode4.log",
        "INT.P4/r3/regression/integrated_mode4_extra.log",
        "INT.P4/r3/regression/integrated_mode1.log",
        "INT.P4/r3/regression/integrated_mode1_extra.log",
        "INT.P4/r3/regression/equiv_seedmode0.log",
        "INT.P4/r3/regression/equiv_seedmode1.log",
        "INT.P4/r3/regression/equiv_seedmode2.log",
        "INT.P4/r3/regression/p1_tb_raw10_packer.log",
        "INT.P4/r3/regression/p2_tb_egress.log",
        "INT.P4/r3/regression/p3_tb_scheduler.log",
        "INT.P4/r3/regression/py_raw10_pack.log",
        "INT.P4/r3/regression/py_verify_input_processing.log",
        "INT.P4/r3/regression/py_dual_channel_schedule.log",
        "INT.P4/r3/regression/py_a1u1_decode.log",
        "INT.P4/r3/regression/py_verify_integrated_sample.log",
    ]
    out["regression_logs_round2"] = [
        "INT.P4/regression/integrated_mode4.log",
        "INT.P4/regression/integrated_mode4_extra.log",
        "INT.P4/regression/integrated_mode1.log",
        "INT.P4/regression/integrated_mode1_extra.log",
        "INT.P4/regression/equiv_seedmode0.log",
        "INT.P4/regression/equiv_seedmode1.log",
        "INT.P4/regression/equiv_seedmode2.log",
        "INT.P4/regression/p1_tb_raw10_packer.log",
        "INT.P4/regression/p2_tb_egress.log",
        "INT.P4/regression/p3_tb_scheduler.log",
        "INT.P4/regression/py_raw10_pack.log",
        "INT.P4/regression/py_verify_input_processing.log",
        "INT.P4/regression/py_dual_channel_schedule.log",
        "INT.P4/regression/py_a1u1_decode.log",
        "INT.P4/regression/py_verify_integrated_sample.log",
    ]
    out["evidence_note"] = (
        "The r2 run logs are the files listed in regression_logs_round2 (all rewritten in the r2 "
        "session on the frozen candidate).  Older files in INT.P4/regression (integrated_mode2.log, "
        "integrated_mode4_default.log, *_attempt.log, p1_raw10_pack.log, p1_verify_input_processing.log, "
        "p2_decode_sample.log, p3_schedule_oracle.log, sample_verify.log) are r0/r1 historical and "
        "are bound only as history - they are NOT r2 evidence.")

    out["honesty"] = (
        "No bit, board, real PCIe or A-path-on-hardware pass is claimed. The b20 bit is a separate "
        "historical candidate and is NOT this integrated delivery. G2 now PASSES on the r3 candidate "
        "(r3_run1: 0 violating endpoints, WNS +0.072ns, TNS 0ps, 17220 endpoints), which is a synthesis "
        "result only: route/bitgen/CWC/download/Flash were not run (route=not_run because the harness has "
        "no pin/IO constraints) and IO timing remains unconstrained. The derived-variant token equivalence "
        "is NOT claimed: CHECK_REF_NEW still reports 2867/2451/57 data mismatches for SEEDMODE 0/1/2 with "
        "identical token counts and marker positions, and the CONTROL_REF_REF2 log shows the frozen HE "
        "module is stall-pattern sensitive (98/99/48 HE-only differences for identical RTL). G1 as defined "
        "by the planner is therefore not met. Deviation disclosure: r3_run1 synthesis was executed although "
        "the dispatch precondition 'same file set passed equivalence simulation' was not fully satisfied; "
        "this is recorded in gates.G1, r3_synth_fileset and INT.P4/result-r3.md section 3. No test "
        "threshold was relaxed and no log was rewritten.")
    out["budget_notes"] = ({
        "synth_runs_round3": 1,
        "synth_r3_run1": "INT.P4/td/r3_run1/: WNS +0.072ns / TNS 0ps / 0 violating endpoints of 17220; "
                         "IO 42/286; ERAM+CWC 39/300; reg 6004, slice* 10691, DSP 14; STA coverage 95.63%; "
                         "TD also emitted PRJ-8806 (run exited before wait_run; full statistics/reports "
                         "present) and an early HDL-5007 top-detection notice",
        "synth_task_lifetime": 7,
        "synth_round3_remaining": 2,
        "route": 0, "bitgen": 0, "cwc": 0, "download": 0, "flash": 0,
        "note": "round3 quota (3 additional / lifetime 9): 1 used, 2 remain; no self-expansion. route "
                "allowance (1) unused: G2 passed but the synthesis harness has no pin/IO constraints, so a "
                "routed harness would not be board-level STA evidence; reason recorded in gates.G2.",
    } if rnd >= 3 else {
        "synth_runs_round2": 3,
        "synth_round2_run1": "WNS -1.483ns / TNS -255.655ns / 277 endpoints; worst path "
                             "gb_reg[1] -> u_front/u_row/rb0_reg (harness capture generator drove "
                             "valid/data combinationally)",
        "synth_round2_run2": "WNS -0.637ns / TNS -69.776ns / 112 endpoints - after the harness "
                             "registered capture source and the P1 input elastic stage; bound as "
                             "the r2 G2 evidence (syn_gate_timing.rpt / syn_gate_area.rpt / "
                             "td_01_synth_console.log / syn_flow.status)",
        "synth_round2_run3": "WNS -0.637ns / TNS -69.776ns / 112 endpoints - identical netlist "
                             "with the ERAM line-buffer experiment (ram_style not honoured); "
                             "artifacts kept in INT.P4/td/syn_r2_run3/",
        "synth_task_lifetime": 6,
        "route": 0, "bitgen": 0, "cwc": 0, "download": 0, "flash": 0,
        "note": "round2 quota (3 additional / lifetime 6) fully consumed; no 4th synth and no "
                "self-expansion.",
    })
    out["drift_count"] = drift
    dst = os.path.join(RUN, f"INT.P4-r{rnd}-manifest.json")
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("MANIFEST_WRITTEN", dst)
    print("MANIFEST_SHA256", sha256(dst))
    print("DRIFT", drift)
    print("DOC_MISSING", sum(1 for d in out["docs"] if d.get("state") == "missing"))
    print("IMG_SOURCES", len(out["img_sources"]))
    print("NEW_FILES", len(out["new_files"]), "TD", len(out["td"]), "EVID", len(out["evidence"]))
    return 0 if drift == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
