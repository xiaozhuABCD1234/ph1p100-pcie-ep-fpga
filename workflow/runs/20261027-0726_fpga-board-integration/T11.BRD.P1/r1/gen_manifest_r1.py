#!/usr/bin/env python3
"""Freeze the T11.BRD.P1 r1 manifest (local sim/static candidate)."""
import hashlib
import json
from datetime import datetime, timezone, timedelta
from pathlib import Path

R1 = Path(__file__).resolve().parent
REPO = R1.parents[4]
PKG = REPO / "handoff" / "brd-p1-r1-20261027"
OLD = Path(r"D:/fpga/ph1p100")

def row(p: Path):
    return {
        "path": str(p.relative_to(REPO)).replace("\\", "/"),
        "sha256": hashlib.sha256(p.read_bytes()).hexdigest().upper(),
        "size": p.stat().st_size,
    }

files = {}
def add(p: Path):
    if p.is_file():
        r = row(p)
        files[r["path"]] = r

# 1) the 78 guarded sources (authoritative filelist)
fl = json.loads((PKG / "build" / "filelist-sha256.json").read_text())
for r in fl["files"]:
    files[r["path"]] = r

# 2) r1 work products
for p in [R1 / "README.md", R1 / "cdc-list.md", R1 / "build-entry.md",
          R1 / "result-r1.md", R1 / "lessons-r1.md"]:
    add(p)
for p in (R1 / "constraints").rglob("*"):
    add(p)
for p in (R1 / "rtl").rglob("*.v"):
    add(p)
for p in (R1 / "sim").glob("*.v"):
    add(p)
for p in (R1 / "sim").glob("*.ps1"):
    add(p)
for p in (R1 / "evidence").rglob("*"):
    if p.name in ("manifest-gen.log", "verify_manifest.log"):
        continue
    add(p)

# 3) the handoff package (manifest/result copies are added after freezing)
for p in PKG.rglob("*"):
    if p.is_file() and p.name not in ("manifest-brd-p1-r1.json", "result-r1.md"):
        add(p)

files = dict(sorted(files.items()))
ts = datetime.now(timezone(timedelta(hours=8))).replace(microsecond=0).isoformat()

manifest = {
    "schema": 1,
    "task_id": "T11.BRD.P1",
    "run_id": "20261027-0726_fpga-board-integration",
    "round": 1,
    "created_at": ts,
    "work_root": "D:/fpga/repos/ph1p100-pcie-ep-fpga",
    "local_boundary": "RTL simulation / software+byte checks / static checks / evidence only. No TD synthesis, route, STA, bitgen, CWC, JTAG/COM, download or Flash was run locally (2026-10-27 AGENTS).",
    "stopped_modifying": True,
    "drift_count": 0,
    "status": "ready_for_test",
    "inherited_facts": {
        "p4_status": "warning",
        "p4_r2": "functional + system pass, G2 fail: 112 endpoints, WNS -0.637ns, TNS -69.776ns @187.5MHz (INT.P4-r2-manifest DFAB7F9D7FF7B7F8FB1D9B4401844F3D76102064C99FC4338192FB8A0C59B32E)",
        "p4_r3": "G2 pass (0 endpoints, +0.072ns) but derived-variant equivalence FAIL; never spliced, never compiled",
        "rule": "r2 and r3 evidence must not be spliced; every timing number in this manifest belongs to no run (G2p is not run locally)"
    },
    "r1_fixes": {
        "F2_slot_base": "SLOT_BASE_WORD=2048 word offset added to P4 write and drain read in brd_board_datapath; store/descriptor/pusher agree on byte 0x1_0000; P4 r2 sources unchanged",
        "F1_arm_event": "brd_export_seq latches host ARM, presents it only after a published descriptor, emits exactly one board-owned source event; repeats ignored/counted",
        "held_seq": "P4 egress adapter compares the ACK against the pusher done count (= doorbell/held_seq), not capture_seq",
        "desc_release": "descriptor active flag cleared for the matching camera id (r0 cleared the wrong one)",
        "pcie_err": "pusher error is a pulse on a NEW error code, not a sticky level",
        "C8_C9": "mps_code[2:0] and link_up enter clk_core only through 2FF (mps_s1/s2, lnk_s1/s2)",
        "SDC": "six one-clock asynchronous groups; clk_core no longer shares a group with tl_clk_user; only R14/user_int_trigger false paths",
        "TB": "EP utx_sel driven, TLP DW lane order, per-DW byte swap, ACK=held_seq, whole-ROI-row truncation, early/duplicate ARM, stable slot dump, host 44B A1U1 header"
    },
    "gates": {
        "G0_ports_clocks_resets_cdc": {
            "result": "pass_static_local",
            "detail": "43 top ports identical to ph1p_pcie_ep_top; R14 once on pcie_power_on_rst; six SDC groups one clock each; C8/C9 2FF instances; no multicycle/internal false path; no STA/CDC engine run",
            "evidence": ["workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/static-checks.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/sdc-groups.md",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/cdc-static.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/cdc-list.md"]
        },
        "G1_scaled_top_simulation": {
            "result": "pass_local_sim",
            "positive": "SCEN 0 (late ARM) and SCEN 3 (early ARM, doubled) and SCEN 4 (duplicate ARM): exported=1, 32 MWr / 4096 B = frame_bytes, doorbell=1 payload=held_seq=1, slot 0x10000 starts 78 9c, base 0 unused, 0 mismatch, 0 X, correct ACK -> release+1",
            "negative_missing_eof": "PASS: last ROI row absent -> committed=0 published=0 exported=0, 0 TLP, 0 doorbell, aborted+released",
            "negative_wrong_ack": "PASS: held_seq^1 keeps HELD and does not release; correct held_seq releases +1",
            "negative_duplicate_arm": "PASS: repeated ARM ignored/counted, one export",
            "read_arbiter": "PASS 6/6 (no mid-burst handover, bridge single beat, late beat counted once/not rerouted, o_switch_err=0)",
            "independent_decode": "standard Python zlib decompresses the slot; length=xform_len; raw=A+ input bytes (bypass); Adler correct; A1U1 header built by the TB host, CRC+payload OK",
            "evidence": ["workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/sim_scen0.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/sim_scen1.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/sim_scen2.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/sim_scen3.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/sim_scen4.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/sim_prep.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/verify_scen0.log"]
        },
        "F3_adler": {
            "result": "no_delta_needed",
            "detail": "core probe + frame probe + full path all emit a correct RFC1950 Adler; the r0 zero-tail did not reproduce in bypass or PREP=1/PRED=1 (stream_len=3966, zlib OK, Adler d5cadeeb); a1_core_fix01 holds byte-identical b20 closure (no behaviour change); no host-side Adler patch used as pass",
            "evidence": ["workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/adler-rootcause.md"]
        },
        "G2p_real_top_sta": {
            "result": "not_run",
            "status": "teammate_required",
            "historical_reference_only": {
                "source": "r0 td/brd_board_Runs/syn_1/flow.status + gate.qor",
                "clk_core_mhz": 150.0, "setup_wns_ns": -2.273, "setup_tns_ns": -31.547,
                "violated_endpoints": 79, "hold": "basic mode 0 endpoints, unverified",
                "125mhz": "not_run", "route_bitgen_cwc": "0/0/0",
                "note": "r1 source set changed; teammate must re-measure"
            },
            "required_teammate_evidence": ["real synth+route WNS/TNS/endpoints on this filelist", "hold", "unconstrained IO list", "resource/clock interaction/comb loops/undriven inputs", "CDC report", "bit/CWC SHA + candidate binding"]
        },
        "G5_build_entry": {
            "result": "pass_local_static",
            "source_count": fl["source_count"],
            "filelist": "handoff/brd-p1-r1-20261027/filelist.tcl",
            "guards": "0 missing, 0 duplicate modules, 0 r3 paths/SHAs, 0 stale/src-src/peer-ref, 0 .bit/.cwc",
            "handoff_package": "handoff/brd-p1-r1-20261027",
            "evidence": ["workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/filelist-check.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/static-checks.log",
                         "handoff/brd-p1-r1-20261027/build/filelist-sha256.json"]
        },
        "G3_G4": { "result": "not_run", "status": "awaiting_hardware", "note": "no bit, no download, no real PCIe/RK, no A path, no 1080p30/long-run" }
    },
    "source_count": fl["source_count"],
    "r3_rejected": [
        {"path": "fpga/csi2/src/integrated_delivery/algo_rowwin3_p4.v", "sha256": "863932B3D42FBB4F97AD2A6A9397E477A012B61B534CD4DBEAD1997AF73A44BC"},
        {"path": "fpga/csi2/src/integrated_delivery/gray8_gaussian3x3_stream_p4.v", "sha256": "B8096430C060BE77BE408B1D4103DE87F543193F94E78DE418189EA32C412B64"}
    ],
    "bits": {"local_bit": None, "local_cwc": None, "b20_bit": None, "note": "no bit/CWC exists locally or in the package"},
    "r0_historical_evidence": "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/historical-evidence-sha256.json",
    "files": list(files.values()),
    "file_count": len(files),
    "test_input_paths": [
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/manifest-brd-p1-r1.json",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/result-r1.md",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/static-checks.log",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/filelist-check.log",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/verify_scen0.log",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/evidence/sim_scen0.log",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/sim/tb_brd_g1_r1.v",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/sim/run_sim_r1.ps1",
        "handoff/brd-p1-r1-20261027/README.md",
        "handoff/brd-p1-r1-20261027/filelist.tcl",
        "handoff/brd-p1-r1-20261027/build/filelist-sha256.json"
    ],
    "notes": [
        "P4 remains warning; r2/r3 evidence is never spliced",
        "G2p/bit/board are not local pass or fail: teammate_required/awaiting_hardware/not_run",
        "r0 640KiB slot text is an arithmetic error; SLOT_WORDS=81920 x 32B = 2.5 MiB/slot",
        "A1U1 header is host-owned (D6); the DUT slot stores only zlib",
        "D2 BAR 0x130..0x13C / CTRL[9..11] is rejected in round1; host cannot read P4 status yet",
        "the manifest copies in the handoff package are byte-identical to this file; the manifest excludes itself and its copy"
    ]
}

out = R1 / "manifest-brd-p1-r1.json"
out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"MANIFEST={out}")
print(f"FILE_COUNT={len(files)} SOURCE_COUNT={fl['source_count']}")
print("MANIFEST_SHA256=" + hashlib.sha256(out.read_bytes()).hexdigest().upper())
