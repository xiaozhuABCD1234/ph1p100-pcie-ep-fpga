#!/usr/bin/env python3
"""mk_manifest_b10_r1.py -- freeze the T10.b10-b9-fix r1 candidate.

Derived from r0/mk_manifest_b10.py. Same hashing rules, but:
  * round = "r1", previous_manifest + its SHA256 are recorded
  * the r0 manifest is NEVER rewritten (only CANDIDATE-MANIFEST-...-r1.json)
  * the r1 build/bitgen/CWC logs, the single download log and the COM8 captures
    are bound as evidence
  * board.download_count comes from r0/board/log-r1/download_state.json when the
    download has already happened (run this script before and after the board run)

No RTL/parameter/SDC/pin/port file is edited by this script; it only reads and
hashes. Running it twice is intentional: pass 1 proves the eight frozen sources
still match the r0 manifest before the download, pass 2 binds the board evidence.
"""
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
PKG = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix"
R0 = PKG / "r0"
R0_MANIFEST = PKG / "CANDIDATE-MANIFEST-b10-b9-fix-r0.json"
OUT_MANIFEST = PKG / "CANDIDATE-MANIFEST-b10-b9-fix-r1.json"
STATE = R0 / "board/log-r1/download_state.json"

# frozen in the r0 manifest; r1 must not change any of them
R0_SOURCE_SHA = {
    "changed-src/a1_uart_export.v": "ff0ce16d6892c5339d806fbfff23a26e373e5d3f3ddf8a6156488f8479f0a7e1",
    "changed-src/camera_a1_uart_top.v": "612d42a59cb1c304cd5446991ee3fe001402a1bcfbbf3b800584997d0590b22f",
    "changed-src/a1_ddr_slot_store.v": "86d626465dc8d0643a7bb62e952e79ee89215c2e0c02719fc348a04c4363ed84",
    "changed-src/a1_raw_crop.v": "33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d",
    "changed-src/cam_diag_mailbox.v": "352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278",
    "changed-src/a1_deflate_core.v": "6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb",
    "td/src/p2_ddr_bridge.v": "b9e83481e3d3450b4d2a9d03812cbb1f14189fe80749e0f712aa8585cddfd5f4",
    "td/src/p2_a1_board_top.v": "98d6c446bcee4fedb483792e229f4a672bd78e3b36f6bfa91f08f1c9c423441f",
}


def sha(p):
    p = pathlib.Path(p)
    if not p.exists():
        return "MISSING"
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def group(paths, base):
    out = {}
    for p in paths:
        p = pathlib.Path(p)
        out[str(p.relative_to(base)).replace("\\", "/")] = sha(p)
    return out


def main():
    src = group(sorted((R0 / "changed-src").glob("*.v")), R0)
    td_src = group(sorted((R0 / "td").glob("0*.tcl")) +
                   sorted((R0 / "td/src").glob("*.v")) +
                   [R0 / "td/p2_board.sdc", R0 / "td/board_p2.adc"],
                   R0)
    sim = group(sorted((R0 / "sim").glob("*.v")) + sorted((R0 / "sim").glob("*.sv")) +
                sorted((R0 / "sim").glob("*.py")), R0)
    board_scripts = sorted((R0 / "board").glob("*.py")) + [
        R0 / "board/download_sram_b10.tcl", R0 / "board/run_board_b10.ps1"]
    board = group(board_scripts, R0)

    # r1 hard check: every frozen source must still hash-match the r0 manifest
    have = dict(src)
    have.update(td_src)
    drift = {k: {"r0": v, "r1": have.get(k, "MISSING")}
             for k, v in R0_SOURCE_SHA.items() if have.get(k) != v}
    if drift:
        print("SOURCE_DRIFT", json.dumps(drift, indent=2))
        return 5

    bit = R0 / "td/a1_board.bit"
    cwc = R0 / "td/a1_board.cwc"
    bid = R0 / "td/a1_board_inst.bid"

    dl = {}
    if STATE.exists():
        dl = json.loads(STATE.read_text(encoding="utf-8-sig"))

    cap = R0 / "board/captures_r1"
    cap_bin = cap / "com8_180s.bin"
    cap_stats = cap / "com8_180s.stats"
    cap_json = cap / "status_v3.json"
    dec_txt = cap / "decoded/decode.txt"

    man = {
        "task_id": "T10.b10-b9-fix",
        "run_id": "20261020-0209_singleA_aplus_closedloop",
        "parent_task": "T10 (NOT marked done by this package)",
        "round": "r1",
        "date": "2026-10-25",
        "candidate_root": str(R0),
        "previous_manifest": {
            "path": str(R0_MANIFEST),
            "sha256": sha(R0_MANIFEST),
            "note": "r0 manifest is kept byte-identical; r1 only adds this file",
        },
        "baseline": {
            "root": "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b9-rawstore/r0",
            "exporter_sha256_b9": "dae0d47fc791fcc8993ccc7efc97c10dfef139cc684404e7a073689372561312",
            "bit_sha256_b9": "950b6e4a867cf1aa87d11c4f084607f4254a82d335f5ed10891dcf74b66a5a06",
            "cwc_sha256_b9": "b9515f79*",
            "bid_sha256_b9": "67c289a8*",
        },
        "changes": {
            "a1_uart_export.v": "unchanged vs r0: B9-01 frame-boundary status/frame arbitration; B9-02 1-bit wrap pointers + single-point dq_cnt + full/same-cycle policy",
            "camera_a1_uart_top.v": ("unchanged vs r0. FUNCTIONAL DELTA vs b9 is ONLY B9-03: "
                                     "CMP_BASE 131072 -> 262144 plus four-slot capacity/layout "
                                     "assertions. The `// T10.b10 R1:` comment blocks in this file "
                                     "are HISTORICAL: they describe the r0 attempts that were "
                                     "reverted, and this candidate contains NO R1 functional fix. "
                                     "They were deliberately not edited because editing them would "
                                     "break the source hash bound by the r0 manifest."),
            "p2_ddr_bridge.v": "unchanged vs r0: R2 (no repeated FIFO word) + R3 (drop an R with no outstanding AR)",
            "p2_a1_board_top.v": "unchanged vs r0: no functional change (hierarchical CWC probes rejected -> cwc_hier_not_available)",
            "a1_ddr_slot_store.v": "unchanged (hash frozen)",
            "a1_raw_crop.v / cam_diag_mailbox.v / a1_deflate_core.v": "unchanged (hash frozen)",
            "r1_vs_r0": ("no RTL/parameter/SDC/pin/port change at all. r1 rebuilt the candidate "
                         "from the same eight frozen sources (8/8 hash-match) and re-ran the "
                         "board round; the r0 attempts that were built from the 1-bit crop_pix "
                         "source produced no valid bit."),
        },
        "source_freeze": {
            "rule": "r1 must not change RTL, parameters, SDC, pins or ports",
            "manifest_r0": str(R0_MANIFEST),
            "sha256": R0_SOURCE_SHA,
            "verified_in_r1": "8/8 identical (this script exits 5 on any drift)",
            "crop_pix": "camera_a1_uart_top.v L156 is `wire [39:0] crop_pix;` (40 bit)",
        },
        "sources": {"changed_src": src, "td": td_src},
        "tests": {"sim": sim, "board": board},
        "run_outputs": {
            "td/params_after.tcl": {
                "sha256": sha(R0 / "td/params_after.tcl"),
                "note": ("generated by the r1 build (report_param); the r0 value "
                         "114cddea... was the s3 run output, archived at "
                         "r0/td/r0-build-evidence/s3/params_after.tcl"),
            },
        },
        "td_build": {
            "session": 1,
            "synthesis": 1,
            "route": 1,
            "bitgen": 1,
            "cwc": 1,
            "logs": {
                "build": "r0/td/build_console_b10_r1.log",
                "bitgen": "r0/td/bitgen_console_b10_r1.log",
                "cwc": "r0/td/cwc_console_b10_r1.log",
            },
            "routed": {
                "sw_ns": 0.103, "st_ns": 0.000, "hw_ns": 0.020, "ht_ns": 0.000,
                "period_w_ns": 2.200, "viol_endpoints": 0, "total_endpoints": 24665,
            },
            "synth": {"sw_ns": 0.273, "st_ns": 0.000},
            "archive": "r0/td/r0-build-evidence/ (s2/s3 copies) + a1_board_Runs_r0s3/ + a1_board_r0.al",
        },
        "artifacts": {
            "bit": {"path": str(bit), "sha256": sha(bit)},
            "cwc": {"path": str(cwc), "sha256": sha(cwc)},
            "bid": {"path": str(bid), "sha256": sha(bid)},
            "cw_compiled_bit": {"path": str(R0 / "td/cw/compiled.bit"),
                                "sha256": sha(R0 / "td/cw/compiled.bit"),
                                "equals_a1_board_bit": sha(R0 / "td/cw/compiled.bit") == sha(bit)},
        },
        "evidence": {
            "sim_results": "r0/sim/sim-results-b10.json",
            "sim_logs": "r0/sim/logs/",
            "board_download_log": "r0/board/log-r1/download_sram_r1.log",
            "board_status": "r0/board/captures_r1/status_v3.json",
            "board_capture": "r0/board/captures_r1/com8_180s.bin",
            "board_decode": "r0/board/captures_r1/decoded/decode.txt",
            "td_build_reports": "r0/td/{syn_gate_*,routed_*,phy_*,routed_netlist.v}",
            "r0_archive": "r0/td/r0-build-evidence/",
            "result": "result-r1.md",
            "lessons": "lessons-r1.md",
        },
        "board": {
            "download_count": dl.get("download_count", None),
            "download_count_cumulative": dl.get("download_count_cumulative", None),
            "download_limit_cumulative": 2,
            "flash_count": 0,
            "device": dl.get("device", None),
            "order": "download (COM8 closed) -> release FTDI -> open COM8 180 s capture",
            "capture": {
                "path": str(cap_bin),
                "sha256": sha(cap_bin),
                "stats_sha256": sha(cap_stats),
                "bytes": (cap_bin.stat().st_size if cap_bin.exists() else None),
            },
            "parse": {"path": str(cap_json), "sha256": sha(cap_json)},
            "decode": {"path": str(dec_txt), "sha256": sha(dec_txt)},
        },
        "hash_notes": {
            "td_src_glob": "r0/td/0*.tcl + r0/td/src/*.v + p2_board.sdc + board_p2.adc",
            "params_after_tcl": "run output, see run_outputs (r0 114cddea... is archived s3 output)",
            "board_scripts": "r0/board/*.py + download_sram_b10.tcl + run_board_b10.ps1",
            "r0_only_vs_r1": ("r0 listed td/download_sram_b9.tcl (b9-era script, never used by this "
                              "package) and td/params_after.tcl; r1 globs r0/td/0*.tcl only and "
                              "records params_after.tcl under run_outputs. Every file present in "
                              "both manifests has the same sha256."),
        },
    }
    OUT_MANIFEST.write_text(json.dumps(man, indent=2))

    lines = []
    lines.append("# T10.b10-b9-fix r1 artifact hashes (sha256)")
    lines.append("# manifest: %s" % OUT_MANIFEST)
    lines.append("# previous manifest sha256: %s" % man["previous_manifest"]["sha256"])
    for sec in ("changed_src", "td"):
        for k, v in man["sources"][sec].items():
            lines.append("%s  %s" % (v, k))
    for sec in ("sim", "board"):
        for k, v in man["tests"][sec].items():
            lines.append("%s  %s" % (v, k))
    lines.append("%s  td/params_after.tcl (run output)" % man["run_outputs"]["td/params_after.tcl"]["sha256"])
    for k in ("bit", "cwc", "bid"):
        lines.append("%s  %s" % (man["artifacts"][k]["sha256"], man["artifacts"][k]["path"]))
    lines.append("%s  r0/td/cw/compiled.bit (must equal a1_board.bit: %s)"
                 % (man["artifacts"]["cw_compiled_bit"]["sha256"],
                    man["artifacts"]["cw_compiled_bit"]["equals_a1_board_bit"]))
    if man["board"]["capture"]["sha256"] != "MISSING":
        lines.append("%s  r0/board/captures_r1/com8_180s.bin" % man["board"]["capture"]["sha256"])
        lines.append("%s  r0/board/captures_r1/status_v3.json" % man["board"]["parse"]["sha256"])
        lines.append("%s  r0/board/captures_r1/decoded/decode.txt" % man["board"]["decode"]["sha256"])
    (R0 / "artifact-hashes-r1.txt").write_text("\n".join(lines) + "\n")

    print("manifest", OUT_MANIFEST)
    print("SOURCES_MATCH_R0 8/8")
    print("bit", man["artifacts"]["bit"]["sha256"])
    print("cwc", man["artifacts"]["cwc"]["sha256"])
    print("bid", man["artifacts"]["bid"]["sha256"])
    print("cw/compiled.bit == a1_board.bit:", man["artifacts"]["cw_compiled_bit"]["equals_a1_board_bit"])
    print("download_count", man["board"]["download_count"])
    print("capture", man["board"]["capture"]["sha256"], man["board"]["capture"]["bytes"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
