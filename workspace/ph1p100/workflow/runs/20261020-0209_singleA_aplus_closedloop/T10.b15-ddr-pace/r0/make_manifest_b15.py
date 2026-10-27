#!/usr/bin/env python3
"""make_manifest_b15.py -- freeze the T10.b15-ddr-pace r0 candidate.

Writes:
  <task>/CANDIDATE-MANIFEST-b15-ddr-pace-r0.json
  <task>/r0/artifact-hashes.txt

The manifest is the single input list for the integrated tester: the 11
changed-src RTL files (10 byte-identical to b13 r1, 1 edited), the build
scripts/constraints, the bit/CWC/BID/compiled hashes, the sim harness and the
board scripts.  Missing artefacts are recorded as MISSING instead of being
silently skipped.
"""
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
TASK = ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b15-ddr-pace"
R0 = TASK / "r0"
TD = R0 / "td"
SIM = R0 / "sim"
BOARD = R0 / "board"

B13_FROZEN = {
    "a1_ddr_arb2.v": "b84019bda057afe82ff558e0848d6171fa12732bd8cdb7c6239cb71b3f81d6ba",
    "a1_ddr_slot_store.v": "6c619cf90e54385d667f1ec0f63cc87ee58aadd3c42143330ac4945eb47defe9",
    "a1_deflate_core.v": "a91c2ed82fbef654c4e065b64ae1cc268ca232feaa26fdd313c58d8740f81b3e",
    "a1_frame_top.v": "0064607aceb20ae3ef14133f0aaf5f8b3f489943011a66a1ddc005350dba7109",
    "a1_raw_crop.v": "33a6fee77fd1aa67a31cacf26dd5530e5e2ea474ee655cbd5f1d98d887c5d72d",
    "a1_uart_export.v": "f8f9e4e354b5bdbcce56321cacb22981f1283565ec6c40479a90d0625ce76b61",
    "camera_a1_uart_top.v": "acc1eff329aa295d01b16123581fee48ef49d444efdce3b7fe62214555517405",
    "cam_diag_mailbox.v": "352af7c85094ea99b575e99da952af8d33871352140e4c6efddff9e6c2407278",
    "f9p_camera_display_core.v": "c9de0d9c176e830df35833eff7e91b811d954fb5480bc13e1fb122ef23305089",
    "p2_a1_board_top.v": "48881d574352fd2c61f7587d3687f215bb11ea18d5b5d0b4772820a938de561b",
}
B13_BRIDGE_SHA = "bff1a3589bd254aa2aaef1050804411095c41c03b6d43fa2a31b6f4e72d49731"


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "MISSING"


def main():
    src = {n: sha(R0 / "changed-src" / n) for n in
           list(B13_FROZEN) + ["p2_ddr_bridge.v"]}
    byte_identical = {n: (src[n] == h) for n, h in B13_FROZEN.items()}
    bridge = {"path": (R0 / "changed-src/p2_ddr_bridge.v").as_posix(),
              "sha256": src["p2_ddr_bridge.v"],
              "b13_baseline_sha256": B13_BRIDGE_SHA,
              "changed": src["p2_ddr_bridge.v"] != B13_BRIDGE_SHA}

    build = {n: sha(TD / n) for n in
             ("01_build.tcl", "02_bitgen.tcl", "03_cwc.tcl", "a1_board.al",
              "board_p2.adc", "p2_board.sdc", "run_build_b15.ps1",
              "run_bitgen_cwc_b15.ps1", "dl_b15.tcl")}
    build["src/p2_ddrmc_shell.v"] = sha(TD / "src/p2_ddrmc_shell.v")
    build["src/p2_a1_pll.v"] = sha(TD / "src/p2_a1_pll.v")
    build["src/cam_preview_capture.v"] = sha(TD / "src/cam_preview_capture.v")
    build["src/vendor/ip/ddrmc_x32/ddrmc_x32.xml"] = sha(TD / "src/vendor/ip/ddrmc_x32/ddrmc_x32.xml")

    art = {n: sha(TD / n) for n in
           ("a1_board.bit", "a1_board.cwc", "a1_board_inst.bid",
            "cw/compiled.bit", "cw/compiled.cwc", "routed_timing_status.rpt",
            "phy_pr_timing_flow.rpt", "routed_area.rpt", "routed_qor.rpt",
            "params_after.tcl", "build_driver_r0.log", "bitgen_console_r0.log",
            "cwc_console_r0.log")}

    harness = {p.relative_to(TASK).as_posix(): sha(p) for p in
               [SIM / n for n in ("p2_paxi_model_b15.v", "tb_b15_chain.sv",
                                  "run_b15.py", "check_b15.py", "make_b15_sim.py",
                                  "p2_paxi_model_b13.v", "tb_b13_chain.sv",
                                  "check_b13.py", "run_b12.py",
                                  "tb_status_v5.v", "tb_b13_store_retry.v")]
               + [BOARD / n for n in ("parse_status_v5.py", "capture_com8.py",
                                      "check_b15_board.py", "run_board_b15.ps1",
                                      "dl_b15.tcl")]
               + [R0 / "diag/paxi-read-facts.md", R0 / "diag/read-serialization.md"]}

    simres = {p.name: sha(p) for p in sorted(SIM.glob("sim-results-b15-*.json"))}
    board_art = {p.relative_to(TASK).as_posix(): sha(p) for p in
                 [BOARD / "captures/com8_150s.bin", BOARD / "captures/status_v5.json",
                  BOARD / "captures/board_gate.json", BOARD / "captures/status_v5.txt",
                  BOARD / "log/download_b15.log", BOARD / "log/board_run_r0.log",
                  BOARD / "H4_UNRESOLVED.md"]}
    bitgen_ok = art["a1_board.bit"] != "MISSING" and art["a1_board.cwc"] != "MISSING"

    man = {
        "manifest_id": "CANDIDATE-MANIFEST-b15-ddr-pace-r0",
        "task_id": "T10.b15-ddr-pace",
        "run_id": "20261020-0209_singleA_aplus_closedloop",
        "round": "r0",
        "parent_task": "T10 (stays blocked; this package does not close T10)",
        "scope": ("read engine of p2_ddr_bridge.v only: R1 strict single AR "
                  "(ar_busy closes on rlast), R2 AR issued only into an empty "
                  "read-data path (MAX_OS=1), R3 paxi_rready constant 1, "
                  "R4 every owned beat pushed, R5 b13 timeout/retry/purge/guard "
                  "kept verbatim"),
        "changed_rtl": bridge,
        "rtl_byte_identical_to_b13": byte_identical,
        "rtl_all_identical_ok": all(byte_identical.values()),
        "changed_src_sha256": src,
        "status_packet": {"version": 5, "length_bytes": 241, "fields": 59,
                          "xor_over": "bytes 0..239", "new_fields": 0},
        "L_max": 1,
        "RF": {"width": 256, "addr_bits": 4, "depth": 16, "deepened": False},
        "MAX_OS": 1,
        "build": build,
        "artifacts": art,
        "bitgen_cwc_present": bitgen_ok,
        "harness": harness,
        "sim_results": simres,
        "board_artifacts": board_art,
        "board_verdict": "H4_UNRESOLVED (see r0/board/H4_UNRESOLVED.md)",
        "sdc_unchanged_vs_b13": sha(TD / "p2_board.sdc") == sha(
            ROOT / "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b13-ddr-retry/r1/td/p2_board.sdc"),
        "board": {"script": (BOARD / "run_board_b15.ps1").as_posix(),
                  "downloads_allowed": 1, "capture_seconds": 150},
        "stop_rules": ["no second bitstream", "no second download",
                       "no Flash", "no RTL change outside p2_ddr_bridge.v"],
    }
    (TASK / "CANDIDATE-MANIFEST-b15-ddr-pace-r0.json").write_text(json.dumps(man, indent=2))

    lines = ["# T10.b15-ddr-pace r0 artifact hashes (sha256)", ""]
    for grp, d in (("changed-src", src), ("bridge", {"p2_ddr_bridge.v": src["p2_ddr_bridge.v"]}),
                   ("build", build), ("artifacts", art), ("harness", harness),
                   ("sim-results", simres), ("board", board_art)):
        lines.append("## %s" % grp)
        for k in sorted(d):
            lines.append("%s  %s" % (d[k], k))
        lines.append("")
    lines.append("## flags")
    lines.append("rtl_all_identical_ok=%s" % man["rtl_all_identical_ok"])
    lines.append("bridge_changed=%s" % bridge["changed"])
    lines.append("bitgen_cwc_present=%s" % bitgen_ok)
    lines.append("sdc_unchanged_vs_b13=%s" % man["sdc_unchanged_vs_b13"])
    (R0 / "artifact-hashes.txt").write_text("\n".join(lines) + "\n")
    print("RTL_IDENTICAL_OK=%s BRIDGE_CHANGED=%s BIT_CWC=%s SDC_SAME=%s"
          % (man["rtl_all_identical_ok"], bridge["changed"], bitgen_ok,
             man["sdc_unchanged_vs_b13"]))
    print("MANIFEST_WRITTEN", (TASK / "CANDIDATE-MANIFEST-b15-ddr-pace-r0.json").as_posix())
    return 0


if __name__ == "__main__":
    sys.exit(main())
