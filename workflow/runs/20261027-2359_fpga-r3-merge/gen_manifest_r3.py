#!/usr/bin/env python3
"""Freeze the T11.BRD.P1 r3 manifest (local sim/static candidate).

Bindings:
  * the 78 guarded sources from handoff/brd-p1-r3-20261027/build/filelist-sha256.json
    (repository-relative paths)
  * every r3 work-root artefact (docs, rtl, constraints, tb, sim sources/scripts,
    per-scenario dumps + logs, evidence)
  * every handoff-package file except the manifest and result copies (added
    after freezing, byte-identical to the originals)

`parent_manifest_sha256` = the frozen r2 manifest (BD2B983F...).
The r3 manifest excludes itself and its handoff copy.
"""
import hashlib
import json
from datetime import datetime, timezone, timedelta
from pathlib import Path

R3 = Path(__file__).resolve().parent
REPO = R3.parents[2]
PKG = REPO / "handoff" / "brd-p1-r3-20261027"
PARENT = "BD2B983F4734DA06211FF973B4165E043FD94A09D023A896E4846821AC037B4B"

files = {}


def row(p: Path) -> dict:
    return {
        "path": str(p.relative_to(REPO)).replace("\\", "/"),
        "sha256": hashlib.sha256(p.read_bytes()).hexdigest().upper(),
        "size": p.stat().st_size,
    }


def add(p: Path) -> None:
    if p.is_file():
        r = row(p)
        files[r["path"]] = r


# 1) the 78 guarded sources (authoritative filelist)
fl = json.loads((PKG / "build" / "filelist-sha256.json").read_text(encoding="utf-8"))
for r in fl["files"]:
    files[r["path"]] = {"path": r["path"], "sha256": r["sha256"].upper(), "size": r["size"]}

# 2) r3 work-root documents
for name in ("README.md", "result-r3.md", "lessons.md", "gen_manifest_r3.py", "filelist.tcl"):
    add(R3 / name)
# 2b) the user-decision page that this run implements
add(REPO / "docs" / "DECISION_r0g_20261027.md")

# 3) rtl + constraints
for p in (R3 / "rtl").rglob("*.v"):
    add(p)
for p in (R3 / "constraints").rglob("*"):
    add(p)

# 4) tb
for p in (R3 / "tb").rglob("*.v"):
    add(p)

# 5) sim sources/scripts/run files (never the `work` library or its junctions)
for pat in ("*.v", "*.ps1", "*.do", "*.log", "*.err", "*.txt"):
    for p in (R3 / "sim").glob(pat):
        add(p)
SCEN_DUMPS = ("slot_dump.bin", "slotbase0_dump.bin", "pk_bytes.bin",
              "a1u1_frame.bin", "sim_meta.txt", "tb_probe_r2.txt")
for scen in ("scen0", "scen1", "scen2", "scen3", "scen4", "prep", "arb"):
    for name in SCEN_DUMPS:
        add(R3 / "sim" / scen / name)
for name in ("t03_store_read.bin", "t03_host_A.bin", "t03_host_B.bin", "t03_host_C.bin",
             "t03_map.txt", "t03_stream.mem", "rtl-slot-read.bin"):
    add(R3 / "sim" / "t03map" / name)
for p in (R3 / "sim" / "t03map").glob("t03_*.log"):
    add(p)

# 6) evidence (the manifest-generation log is written after this script starts)
for p in (R3 / "evidence").rglob("*"):
    if p.name in ("manifest-gen.log", "verify_manifest.log", "verify-manifest.log"):
        continue
    add(p)

# 7) handoff package (manifest/result copies are added after freezing)
for p in PKG.rglob("*"):
    if p.is_file() and p.name not in ("manifest-r3.json", "result-r3.md"):
        add(p)

files = dict(sorted(files.items()))
ts = datetime.now(timezone(timedelta(hours=8))).replace(microsecond=0).isoformat()

manifest = {
    "schema": 1,
    "task_id": "T11.BRD.P1",
    "run_id": "20261027-2359_fpga-r3-merge",
    "round": 3,
    "created_at": ts,
    "work_root": "D:/fpga/repos/ph1p100-pcie-ep-fpga",
    "work_dir": str(R3.relative_to(REPO)).replace("\\", "/"),
    "handoff_package": str(PKG.relative_to(REPO)).replace("\\", "/"),
    "parent_manifest_sha256": PARENT,
    "parent_manifest": "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/manifest-brd-p1-r2.json",
    "local_boundary": ("RTL simulation / software+byte checks / static checks / evidence only. "
                       "No TD synthesis, route, STA, bitgen, CWC, JTAG/COM, download or Flash was "
                       "run locally (2026-10-27 AGENTS 'sim only, teammate holds the board')."),
    "stopped_modifying": True,
    "drift_count": 0,
    "status": "ready_for_test",
    "user_decisions_r0g": {
        "slot_byte_order": "LSB-first (low address first) inside the 256-bit DDR beat; T03 70 B oracle starts 78 9c; a1_ddr_slot_store unchanged",
        "address_unit": "one 256-bit word = 32 bytes total: r2 p2_ddr_bridge x8 + board x4 = x32; the export working copy's x32 + board x4 = x128 is rejected; no third multiplier",
        "pusher_mapping": ("re-tested, not guessed: the unchanged bswap256 gives BYTE_DIFF=0 / FIRST8=78 9c; "
                           "'remove bswap' gives 69/70 mismatches (02 c2 ...); 'DW-order only' gives 67/70 "
                           "(40 02 ...).  The pusher is therefore NOT changed; r0g's reversed payload came "
                           "from a TB payload decode that was lane0-first + LSB-first, inconsistent with its "
                           "own header decode and with the three project TBs"),
        "doc": "docs/DECISION_r0g_20261027.md",
    },
    "r3_delta": {
        "rtl_changed_files": [
            "workflow/runs/20261027-2359_fpga-r3-merge/rtl/brd_cdc_mailboxes.v",
            "workflow/runs/20261027-2359_fpga-r3-merge/rtl/brd_board_datapath.v",
            "workflow/runs/20261027-2359_fpga-r3-merge/rtl/ref/ep_side/ddr/ddr_frame_pusher.v",
        ],
        "rtl_semantic_changes": [
            "brd_cdc_mailboxes.v brd_ack_xing: o_ack_seq <= out_bus[63:32]; o_ack_session <= out_bus[31:0] (r0d ACK-slice fix)",
            "brd_board_datapath.v: a_seq/b_seq reset to 32'd1 (r0d capture identity starts at 1)",
        ],
        "comment_only": [
            "rtl/ref/ep_side/ddr/ddr_frame_pusher.v: comment above data_beat documenting the T03 map experiment; bswap256 unchanged",
        ],
        "kept_from_r2": [
            "C8/C9 2FF (mps_code/link_up into clk_core)",
            "F2 +SLOT_BASE_WORD on both P4 write and read word addresses",
            "slot byte base = word x32; pusher BASE0/BASE1 = SLOT_BASE_WORD x32",
            "p2_ddr_bridge x8 ({wf_rdata[279:256],3'b000} / {af_rdata[23:0],3'b000})",
            "brd_export_seq F1 sequencer (ARM aligned to a published descriptor, one source event per ARM)",
            "release polarity rel_camera_id=0 -> A, 1 -> B (already correct in r2)",
        ],
        "not_adopted_from_export_copy": [
            "BASE_WORD=SLOT_BASE_WORD (double offset)",
            "pusher base x128",
            "p2_ddr_bridge x32",
            "internal utx_sel grant (would double-drive the EP engine in brd_integrated_top)",
            "removal of brd_export_seq",
        ],
        "unchanged_scope": [
            "a1_ddr_slot_store.v", "a1_deflate_core.v", "a1_frame_top.v", "a1_ddr_arb2.v",
            "P4 RTL", "brd_integrated_top.v", "brd_cam_fe.v", "brd_ddr_rd_arb.v",
            "brd_a1_core_pll.v", "brd_export_seq.v", "a1_raw_crop.v", "p2_ddr_bridge.v",
            "constraints/**", "filelist source set (78)",
        ],
        "rtl_delta_check": "evidence/static-checks.log (64 checks, 0 fails; comment-stripped diffs)",
        "dut_modified_to_fit_golden": False,
        "criteria_weakened": False,
    },
    "independent_model": {
        "generator": "workflow/runs/20261027-2359_fpga-r3-merge/evidence/gen_expected_raw.py",
        "reads_dut_output": False,
        "expected_raw_sha256": "FBA49D330DB9196A9BD9B8F29419A5603CEF600FE7D08F73708674F4C3C5111E",
        "expected_raw_len": 3840,
        "expected_raw_adler32": "392578F9",
        "expected_raw_crc32": "7269454A",
        "first5": "8282828200",
        "contract": "rows 16..63, groups 8..23, v=(r*32+g)&0x3FF, 4 identical pixels, byte0..3=v[9:2], byte4={v[1:0] x4}",
    },
    "golden": {
        "doc": "workflow/runs/20261027-2359_fpga-r3-merge/evidence/golden-r3.json",
        "json": "workflow/runs/20261027-2359_fpga-r3-merge/evidence/golden-r3.json",
        "candidate_bound": {
            "note": "measured on the frozen r3 runs; equality is a repeatability check, not an independent derivation",
            "stream_len": 2470, "frame_bytes": 4096, "hcrc": "A5ECBAD9", "stream_crc": "9909B919",
            "prep_stream_len": 538, "prep_hcrc": "69C48065", "prep_xform_crc": "7883ABAF",
        },
        "hcrc_change_reason": ("r3 starts the capture identity at 1 (r0d), so the A1U1 header frame_id changes "
                               "0 -> 1 and hcrc 5436BF73 -> A5ECBAD9 (bypass), 981E85CF -> 69C48065 (PREP). "
                               "The compressed slot stream is unchanged (2470 B / 9909B919)."),
        "reference_encoder": {"compressor": "CPython 3.11.5 zlib.compress default level", "stream_len": 723,
                              "note": "reference only; the DUT deflate is a different RFC1950 encoder"},
        "not_a_criterion": "compressed byte equality with Python zlib (proved by r1: 1391 B vs DUT 3137 B, same Adler)",
    },
    "gates": {
        "G0_ports_clocks_resets_cdc": {
            "result": "pass_static_local",
            "detail": ("43 top ports identical to ph1p_pcie_ep_top; R14 once on pcie_power_on_rst; six SDC "
                       "one-clock groups with clk_core alone; only R14/user_int_trigger false paths; no "
                       "multicycle/internal false path; C8/C9 2FF instances; F2 offsets present; ACK slice, "
                       "x32 base, x8 bridge and seq=1 asserted; no STA/CDC engine run. N1 (second derive_clocks) "
                       "unchanged - teammate STA item."),
            "evidence": ["workflow/runs/20261027-2359_fpga-r3-merge/evidence/static-checks.log",
                         "workflow/runs/20261027-2359_fpga-r3-merge/evidence/sdc-groups.md",
                         "workflow/runs/20261027-2359_fpga-r3-merge/rtl/brd_board_datapath.v",
                         "workflow/runs/20261027-2359_fpga-r3-merge/rtl/brd_cdc_mailboxes.v"],
        },
        "G1_t03_oracle_store_pusher": {
            "result": "pass_local_sim",
            "detail": ("tb_t03_pusher_map: store writes 70 B at word 2048 (byte 0x10000), store read-back == "
                       "rtl-slot-read.bin, pusher AR=0x10000, 32 MWr + 1 doorbell, documented host decode == "
                       "rtl-slot-read.bin.  PRODUCED_LEN=70 BYTE_DIFF=0 FIRST8=78 9c 62 48 4a 4a 5a 01.  "
                       "Map experiment: A (bswap256) 0 mismatches, B (no bswap) 69/70, C (DW-order only) 67/70."),
            "evidence": ["workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify-t03.log",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/t03map/**"],
        },
        "G1_scaled_top_simulation": {
            "result": "pass_local_sim",
            "detail": ("r2 six-scenario G1 re-run on r3: SCEN0/3/4 pass (exported=1, 32 MWr x 128 B = 4096 B, "
                       "doorbell=1 payload=held_seq, slot 0x1_0000 starts 78 9c, base 0 unused, 0 TLP mismatch, "
                       "0 X, correct ACK -> release+1), SCEN1 missing-EOF negative pass, SCEN2 wrong-ACK pass, "
                       "PREP=1/PRED=1 pass (zlib decodes 3840 B, Adler 5F1669E1, raw_crc 7269454A), arb 6/6."),
            "independent_byte_criterion": "zlib.decompress(slot) == expected_raw.bin byte-for-byte in 3/3 bypass scenarios",
            "verifier": "workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify_slot_r3.py",
            "checks": "CHECKS=150 FAILS=0 VERIFY_R3=PASS",
            "evidence": ["workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify-slot-r3.log",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/scen0/**",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/scen3/**",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/scen4/**",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/prep/**"],
        },
        "G1_export_two_frame_backpressure_ack": {
            "result": "pass_local_sim",
            "detail": ("tb_brd_export_r3: SCEN0/SCEN2/SCEN3 with NF=2; both frames byte-exact against the "
                       "store write-side capture (mismatch=0), one doorbell each, wrong ACK holds the slot, "
                       "correct ACK releases (+1), x_cnt=0, no watchdog.  The same TB in legacy host mode "
                       "reproduces r0g (mismatch=3830/3845) - proving the r0g reversal was a TB decode artifact."),
            "verifier": "workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify_export_r3.py",
            "checks": "CHECKS=48 FAILS=0 EXPORT_REGRESSION=PASS",
            "evidence": ["workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify-export-r3.log",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/sim_export_s0_h0_*.log",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/sim_export_s3_h0_*.log",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/sim_export_s2_h0_*.log",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/logs_export_legacy.txt",
                         "workflow/runs/20261027-2359_fpga-r3-merge/sim/logs_export_neg.txt"],
        },
        "G2p_real_top_sta": {
            "result": "not_run",
            "status": "teammate_required",
            "note": ("r3 changes 3 RTL files vs r2; the teammate must run synth/route/STA/CDC on this filelist. "
                     "r0's -2.273 ns / 79 endpoints and r3's +0.072 ns are not this candidate's numbers."),
            "required_teammate_evidence": ["real synth+route WNS/TNS/endpoints on this filelist", "hold",
                                           "unconstrained IO list", "resource/clock interaction/comb loops/undriven inputs",
                                           "CDC report incl. N1 second derive_clocks", "bit/CWC SHA + candidate binding"],
        },
        "G5_build_entry": {
            "result": "pass_local_static",
            "source_count": 78,
            "filelist": "handoff/brd-p1-r3-20261027/filelist.tcl",
            "filelist_sha256": hashlib.sha256((PKG / "filelist.tcl").read_bytes()).hexdigest().upper(),
            "guards": "0 missing, 0 duplicate modules, 0 rejected r3-era paths/SHAs, 0 stale/src-src/peer-ref, 0 .bit/.cwc",
            "n2": "build/filelist-sha256.json paths are repository-relative",
            "n3": "no pre-generated brd_board.al; gen_al.py expands @REPO_ROOT@ (run first)",
            "n1": "second derive_clocks in brd_board.sdc kept unchanged; restated in known-risks.md",
            "handoff_package": "handoff/brd-p1-r3-20261027",
            "evidence": ["workflow/runs/20261027-2359_fpga-r3-merge/evidence/filelist-check.log",
                         "workflow/runs/20261027-2359_fpga-r3-merge/evidence/static-checks.log",
                         "handoff/brd-p1-r3-20261027/build/filelist-sha256.json"],
        },
        "G3_G4": {"result": "not_run", "status": "awaiting_hardware",
                  "note": "no bit, no download, no real PCIe/RK, no A path, no 1080p30/long-run"},
    },
    "d7_adler": {
        "decision": "accept_no_delta_closure (inherited from r2)",
        "facts": ["standard zlib.decompress + independently written Adler-32 both pass",
                  "rtl/a1_core_fix01/* is byte-identical to the b20 originals"],
        "wording": "the current candidate slot stream is a legal RFC1950 member and D7 is closed by independent evidence",
        "forbidden_wording": ["r0 Adler defect fixed", "adler-fix01 effective"],
        "reopen_condition": ("board or real RK host observes an invalid tail / zlib decode failure / raw mismatch -> "
                             "separate task that first reproduces the r0 condition"),
    },
    "a1_core_fix01": {"alias_of_b20": True, "behavioral_variant": False,
                      "note": "byte-identical to the b20 originals and to r1/r2; filelist includes this copy"},
    "source_count": 78,
    "bits": {"local_bit": None, "local_cwc": None, "note": "no bit/CWC exists locally or in the package"},
    "simulation_budget": {
        "t03_map_runs": 1,
        "top_level_g1_runs": 6,
        "export_positive_runs": 3,
        "export_legacy_diagnostic_runs": 1,
        "export_negative_runs": 1,
        "per_run_timeout_min": 20,
        "note": "all runs completed in seconds; no TD/hardware action",
    },
    "files": list(files.values()),
    "file_count": len(files),
    "test_input_paths": [
        "workflow/runs/20261027-2359_fpga-r3-merge/manifest-r3.json",
        "workflow/runs/20261027-2359_fpga-r3-merge/result-r3.md",
        "workflow/runs/20261027-2359_fpga-r3-merge/evidence/golden-r3.json",
        "workflow/runs/20261027-2359_fpga-r3-merge/evidence/gen_expected_raw.py",
        "workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify_slot_r3.py",
        "workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify_t03_r3.py",
        "workflow/runs/20261027-2359_fpga-r3-merge/evidence/verify_export_r3.py",
        "workflow/runs/20261027-2359_fpga-r3-merge/evidence/static_checks_r3.py",
        "workflow/runs/20261027-2359_fpga-r3-merge/tb/tb_brd_g1_r3.v",
        "workflow/runs/20261027-2359_fpga-r3-merge/tb/tb_brd_export_r3.v",
        "workflow/runs/20261027-2359_fpga-r3-merge/tb/tb_t03_pusher_map.v",
        "handoff/brd-p1-r3-20261027/README.md",
        "handoff/brd-p1-r3-20261027/filelist.tcl",
        "handoff/brd-p1-r3-20261027/build/filelist-sha256.json",
        "handoff/brd-p1-r3-20261027/expected-g1.md",
        "docs/DECISION_r0g_20261027.md",
    ],
    "notes": [
        "r3 is the first package that merges the r0d ACK-slice fix and the r2 F1 sequencer; the r0g blocked verdict is not overwritten",
        "the pusher data-beat mapping is unchanged because the T03 experiment selects the existing bswap256 (A=0, B=69/70, C=67/70)",
        "the r0g export TB's payload decode was corrected for r3 (lane 7 first, MSB first in DW); a legacy switch reproduces the r0g failure",
        "the r2 export TB's 'arming frame is consumed' expectation belongs to the r0g wiring; with the r2 F1 sequencer frame 0 is exported",
        "no TD/synthesis/route/STA/bitgen/CWC/download/Flash was run; G2p/G3/G4 stay not_run/teammate_required/awaiting_hardware",
        "r0 640KiB slot text is an arithmetic error; SLOT_WORDS=81920 x 32B = 2.5 MiB/slot",
        "A1U1 header is host-owned (D6); the DUT slot stores only zlib",
        "D2 BAR 0x130..0x13C / CTRL[9..11] is rejected; host cannot read P4 status yet",
        "the manifest copies in the handoff package are byte-identical to this file; the manifest excludes itself and its copy",
    ],
}

out = R3 / "manifest-r3.json"
out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"MANIFEST={out}")
print(f"FILE_COUNT={len(files)} SOURCE_COUNT={fl['source_count']}")
print("MANIFEST_SHA256=" + hashlib.sha256(out.read_bytes()).hexdigest().upper())
