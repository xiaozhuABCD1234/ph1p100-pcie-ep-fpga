#!/usr/bin/env python3
"""Freeze the T11.BRD.P1 r2 manifest (local sim/static candidate).

Bindings:
  * the 78 guarded sources from handoff/brd-p1-r2-20261027/build/filelist-sha256.json
    (repository-relative paths, N2-fixed)
  * every r2 work-root artefact (docs, rtl, constraints, sim sources/scripts,
    per-scenario dumps + logs, evidence)
  * every handoff-package file except the manifest and result copies (added
    after freezing, byte-identical to the originals)

`parent_manifest_sha256` = the frozen r1 manifest (304A2FF0...).
"""
import hashlib
import json
from datetime import datetime, timezone, timedelta
from pathlib import Path

R2 = Path(__file__).resolve().parent
REPO = R2.parents[4]
PKG = REPO / "handoff" / "brd-p1-r2-20261027"
PARENT = "304A2FF08DA88B6F129577D710A5B077B9FCF0A71F205E72BFB03412616CCC05"

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

# 2) r2 work-root documents
for name in ("README.md", "delta-vs-r1.md", "build-entry.md", "cdc-list.md",
             "result-r2.md", "lessons-r2.md", "gen_manifest_r2.py", "filelist.tcl"):
    add(R2 / name)

# 3) rtl + constraints
for p in (R2 / "rtl").rglob("*.v"):
    add(p)
for p in (R2 / "constraints").rglob("*"):
    add(p)

# 4) sim sources/scripts/run files (never the `work` library or its junction)
for pat in ("*.v", "*.ps1", "*.do", "*.log", "*.err", "transcript"):
    for p in (R2 / "sim").glob(pat):
        add(p)
SCEN_DUMPS = ("slot_dump.bin", "slotbase0_dump.bin", "pk_bytes.bin",
              "a1u1_frame.bin", "sim_meta.txt", "tb_probe_r2.txt")
for scen in ("scen0", "scen1", "scen2", "scen3", "scen4", "prep", "arb"):
    for name in SCEN_DUMPS:
        add(R2 / "sim" / scen / name)

# 5) evidence (the manifest-generation log is written after this script starts)
for p in (R2 / "evidence").rglob("*"):
    if p.name in ("manifest-gen.log", "verify_manifest.log", "verify-manifest.log"):
        continue
    add(p)

# 6) handoff package (manifest/result copies are added after freezing)
for p in PKG.rglob("*"):
    if p.is_file() and p.name not in ("manifest-brd-p1-r2.json", "result-r2.md"):
        add(p)

files = dict(sorted(files.items()))
ts = datetime.now(timezone(timedelta(hours=8))).replace(microsecond=0).isoformat()

manifest = {
    "schema": 1,
    "task_id": "T11.BRD.P1",
    "run_id": "20261027-0726_fpga-board-integration",
    "round": 2,
    "created_at": ts,
    "work_root": "D:/fpga/repos/ph1p100-pcie-ep-fpga",
    "work_dir": str(R2.relative_to(REPO)).replace("\\", "/"),
    "handoff_package": str(PKG.relative_to(REPO)).replace("\\", "/"),
    "parent_manifest_sha256": PARENT,
    "parent_manifest": "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/manifest-brd-p1-r1.json",
    "local_boundary": ("RTL simulation / software+byte checks / static checks / evidence only. "
                       "No TD synthesis, route, STA, bitgen, CWC, JTAG/COM, download or Flash was "
                       "run locally (2026-10-27 AGENTS 'sim only, teammate holds the board')."),
    "stopped_modifying": True,
    "drift_count": 0,
    "status": "ready_for_test",
    "round2_delta": {
        "rtl_delta": 0,
        "constraints_delta": 0,
        "filelist_delta": 0,
        "dut_modified_to_fit_golden": False,
        "criteria_weakened": False,
        "changed_scope": ["sim/tb_brd_g1_r2.v", "sim/run_sim_r2.ps1", "sim/** dumps+logs",
                          "evidence/**", "docs", "manifest", "handoff/brd-p1-r2-20261027/**"],
        "evidence": "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/r1-r2-sha-diff.md",
    },
    "round1_inherited": {
        "verdict": "FAIL (integrated r1)",
        "blocking_problem_id": "T11.BRD.P1:TB_CAM_STIMULUS_WIDTH",
        "root_cause": ("r1 TB camera stimulus `{4{(line*32+grp) & 10'h3FF}}` replicated a 32-bit "
                       "expression and truncated to 40 bits, so the four 10-bit lanes were "
                       "(v,0,0,v[7:0]<<2); `raw == pk_bytes` was a self-comparison"),
        "r1_manifest_sha256": PARENT,
        "rule": "r1 files are byte-identical and were not rewritten (static_checks_r2.py)",
    },
    "independent_model": {
        "generator": "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/gen_expected_raw.py",
        "reads_dut_output": False,
        "expected_raw_sha256": "FBA49D330DB9196A9BD9B8F29419A5603CEF600FE7D08F73708674F4C3C5111E",
        "expected_raw_len": 3840,
        "expected_raw_adler32": "392578F9",
        "expected_raw_crc32": "7269454A",
        "first5": "8282828200",
        "contract": "rows 16..63, groups 8..23, v=(r*32+g)&0x3FF, 4 identical pixels, byte0..3=v[9:2], byte4={v[1:0] x4}",
    },
    "golden": {
        "doc": "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/golden-r2.md",
        "json": "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/golden-r2.json",
        "candidate_bound": {
            "note": "measured on the frozen r2 TB; equality is a repeatability check, not an independent derivation",
            "stream_len": 2470, "frame_bytes": 4096, "hcrc": "5436BF73", "stream_crc": "9909B919",
            "prep_stream_len": 538, "prep_hcrc": "981E85CF", "prep_xform_crc": "7883ABAF",
        },
        "reference_encoder": {"compressor": "CPython 3.11.5 zlib.compress default level", "stream_len": 723,
                              "note": "reference only; the DUT deflate is a different RFC1950 encoder"},
        "not_a_criterion": "compressed byte equality with Python zlib (proved by r1: 1391 B vs DUT 3137 B, same Adler)",
    },
    "gates": {
        "G0_ports_clocks_resets_cdc": {
            "result": "pass_static_local",
            "detail": ("43 top ports identical to ph1p_pcie_ep_top; R14 once on pcie_power_on_rst; six SDC "
                       "one-clock groups with clk_core alone; only R14/user_int_trigger false paths; no "
                       "multicycle/internal false path; C8/C9 2FF instances; F2 offsets present; no STA/CDC "
                       "engine run. N1 (second derive_clocks, line ~68) unchanged - teammate STA item."),
            "evidence": ["workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/static-checks.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/sdc-groups.md",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/cdc-static.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/cdc-list.md"],
        },
        "G1_scaled_top_simulation": {
            "result": "pass_local_sim",
            "positive": ("SCEN0 (late ARM) / SCEN3 (early ARM, doubled) / SCEN4 (duplicate ARM): exported=1, "
                         "32 MWr x 128B = 4096 B = frame_bytes, doorbell=1 payload=held_seq=1, slot 0x1_0000 "
                         "starts 78 9c, legacy base 0 unused, 0 TLP mismatch, 0 X, correct ACK -> release+1"),
            "independent_byte_criterion": ("decompressed raw == expected_raw.bin byte-for-byte in 3/3 bypass "
                                           "scenarios (SHA256 FBA49D33..., Adler 392578F9, xform_crc 7269454A)"),
            "stimulus_probe": "STIM_PROBE=PASS in all four top runs (lane_bad=0, chain_bad=0, first_v=520, pk_first=0082828282)",
            "negative_missing_eof": "PASS: last ROI row absent -> committed=0 published=0 exported=0, 0 TLP, 0 doorbell, aborted+released",
            "negative_wrong_ack": "PASS: held_seq^1 keeps HELD and does not release; correct held_seq releases +1",
            "negative_duplicate_arm": "PASS: repeated ARM ignored/counted, one export",
            "read_arbiter": "PASS 6/6 (no mid-burst handover, bridge single beat, late beat counted once/not rerouted, o_switch_err=0)",
            "prep_pred": ("PREP=1/PRED=1 PASS: standard zlib decodes 3840 B, Adler 5F1669E1, header raw_crc "
                          "7269454A (raw domain still the contract raw), xform_crc 7883ABAF != raw_crc; "
                          "transform domain not byte-compared to expected_raw (different domain, documented)"),
            "evidence": ["workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/verify_slot_r2.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/gen_expected_raw.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/tb-stimulus-fix.md",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/run_scen0_r2.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/run_scen3_r2.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/run_scen4_r2.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/run_scen1_r2.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/run_scen2_r2.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/run_prep_r2.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/run_arb_r2.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/scen0/**"],
        },
        "G2p_real_top_sta": {
            "result": "not_run",
            "status": "teammate_required",
            "historical_reference_only": {
                "source": "r0 td/brd_board_Runs/syn_1/flow.status + gate.qor",
                "clk_core_mhz": 150.0, "setup_wns_ns": -2.273, "setup_tns_ns": -31.547,
                "violated_endpoints": 79, "hold": "basic mode 0 endpoints, unverified",
                "125mhz": "not_run", "route_bitgen_cwc": "0/0/0",
                "note": "r0 numbers; r2 RTL/constraints are byte-identical to r1 and different from r0 - the teammate must re-measure (or reuse an r1 run with the same input hash)",
            },
            "required_teammate_evidence": ["real synth+route WNS/TNS/endpoints on this filelist", "hold",
                                           "unconstrained IO list", "resource/clock interaction/comb loops/undriven inputs",
                                           "CDC report incl. N1 second derive_clocks", "bit/CWC SHA + candidate binding"],
        },
        "G5_build_entry": {
            "result": "pass_local_static",
            "source_count": 78,
            "filelist": "handoff/brd-p1-r2-20261027/filelist.tcl",
            "filelist_sha256": "41A61493335B84FA8AAFB1FF41FB99C2F8AC71D5E73F018187F567BA277A84A3",
            "guards": "0 missing, 0 duplicate modules, 0 r3 paths/SHAs, 0 stale/src-src/peer-ref, 0 .bit/.cwc",
            "n2_fixed": "build/filelist-sha256.json paths are repository-relative",
            "n3_fixed": "no pre-generated brd_board.al in the package; gen_al.py expands @REPO_ROOT@ (must be run first)",
            "n1": "second derive_clocks in brd_board.sdc kept unchanged; restated in known-risks.md for the teammate STA",
            "r1_integrity": "r1 manifest 218/218 files unchanged; r0 manifest files unchanged",
            "handoff_package": "handoff/brd-p1-r2-20261027",
            "evidence": ["workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/filelist-check.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/static-checks.log",
                         "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/g5-refs.log",
                         "handoff/brd-p1-r2-20261027/build/filelist-sha256.json"],
        },
        "G3_G4": {"result": "not_run", "status": "awaiting_hardware",
                  "note": "no bit, no download, no real PCIe/RK, no A path, no 1080p30/long-run"},
    },
    "d7_adler": {
        "decision": "accept_no_delta_closure",
        "facts": ["r0 'tail 4 bytes zero' did not reproduce in this harness",
                  "standard zlib.decompress + independently written Adler-32 both pass",
                  "rtl/a1_core_fix01/* is byte-identical to the b20 originals (no behavioural variant)"],
        "closure_conditions_r2": {"C1_standard_zlib": True, "C2_len_eq_xform_len": True,
                                  "C3_raw_eq_independent_model": True, "C4_tail_eq_independent_adler": True,
                                  "C5_slot_is_zlib_only_header_is_host": True,
                                  "C6_zero_tail_mutation_detected": "r1 evidence (mutation_zero_adler_reproduces_r0_f3)"},
        "wording": "the current candidate slot stream is a legal RFC1950 member and D7 is closed by independent evidence",
        "forbidden_wording": ["r0 Adler defect fixed", "adler-fix01 effective"],
        "reopen_condition": ("board or real RK host observes an invalid tail / zlib decode failure / raw mismatch -> "
                             "separate task that first reproduces the r0 condition"),
    },
    "a1_core_fix01": {"alias_of_b20": True, "behavioral_variant": False, "filelist_included": False,
                      "note": "carried for byte-identity with r1; the filelist compiles the b20 originals"},
    "source_count": 78,
    "r3_rejected": [
        {"path": "fpga/csi2/src/integrated_delivery/algo_rowwin3_p4.v", "sha256": "863932B3D42FBB4F97AD2A6A9397E477A012B61B534CD4DBEAD1997AF73A44BC"},
        {"path": "fpga/csi2/src/integrated_delivery/gray8_gaussian3x3_stream_p4.v", "sha256": "B8096430C060BE77BE408B1D4103DE87F543193F94E78DE418189EA32C412B64"},
    ],
    "bits": {"local_bit": None, "local_cwc": None, "b20_bit": None,
             "note": "no bit/CWC exists locally or in the package"},
    "simulation_budget": {
        "top_level_g1_runs_max": 10, "top_level_g1_runs_used": 6,
        "top_level_g1_scenarios": ["scen0", "scen3", "scen4", "scen1", "scen2", "prep"],
        "arb_runs_max": 6, "arb_runs_used": 1,
        "harness_startup_failures": 2,
        "note": ("2 additional vsim invocations failed at startup (cd while a design is loaded / work library "
                 "not found) and advanced no simulation time; they are harness iterations, not scenario runs"),
        "per_run_timeout_min": 20,
    },
    "files": list(files.values()),
    "file_count": len(files),
    "test_input_paths": [
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/manifest-brd-p1-r2.json",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/result-r2.md",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/golden-r2.md",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/gen_expected_raw.py",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/expected_raw.bin",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/verify_slot_r2.py",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/verify_slot_r2.log",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/static_checks_r2.py",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/static-checks.log",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/r1-r2-sha-diff.md",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/evidence/tb-stimulus-fix.md",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/tb_brd_g1_r2.v",
        "workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r2/sim/run_sim_r2.ps1",
        "handoff/brd-p1-r2-20261027/README.md",
        "handoff/brd-p1-r2-20261027/filelist.tcl",
        "handoff/brd-p1-r2-20261027/build/filelist-sha256.json",
        "handoff/brd-p1-r2-20261027/expected-g1.md",
    ],
    "notes": [
        "P4 remains warning; r2/r3 evidence is never spliced",
        "G2p/bit/board are not local pass or fail: teammate_required/awaiting_hardware/not_run",
        "r2 RTL/constraints/filelist are byte-identical to r1; only TB/golden/evidence/manifest/handoff changed",
        "the DUT was not modified to fit the golden and no criterion was weakened (raw==pk demoted to additional)",
        "r0 640KiB slot text is an arithmetic error; SLOT_WORDS=81920 x 32B = 2.5 MiB/slot",
        "A1U1 header is host-owned (D6); the DUT slot stores only zlib",
        "D2 BAR 0x130..0x13C / CTRL[9..11] is rejected; host cannot read P4 status yet",
        "the manifest copies in the handoff package are byte-identical to this file; the manifest excludes itself and its copy",
    ],
}

out = R2 / "manifest-brd-p1-r2.json"
out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"MANIFEST={out}")
print(f"FILE_COUNT={len(files)} SOURCE_COUNT={fl['source_count']}")
print("MANIFEST_SHA256=" + hashlib.sha256(out.read_bytes()).hexdigest().upper())
