# T10.b12-r1-last r1 -- freeze the diagnostic-candidate manifest.
# Bitgen + CWC were produced from the frozen r0 routed database; no RTL/SDC edit,
# no synthesis, no route, no download (board blocked: FTDI 0403:6042 absent).
import hashlib
import json
import os

ROOT = r"D:\fpga\ph1p100"
RUN = r"workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b12-r1-last"


def sha256(rel):
    p = os.path.join(ROOT, rel)
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest(), os.path.getsize(p)


def entry(rel):
    h, n = sha256(rel)
    return {"path": rel.replace("\\", "/"), "sha256": h, "bytes": n}


CHANGED = [
    "a1_raw_crop.v",
    "a1_ddr_slot_store.v",
    "a1_uart_export.v",
    "camera_a1_uart_top.v",
    "cam_diag_mailbox.v",
    "a1_frame_top.v",
    "a1_deflate_core.v",
    "p2_ddr_bridge.v",
    "p2_a1_board_top.v",
]
changed_src = [entry(f"{RUN}/r0/changed-src/{n}") for n in CHANGED]

repo_deps = [
    entry("fpga/csi2/src/a1/a1_ddr_arb2.v"),
    entry("fpga/csi2/src/mem/capture_async_fifo.v"),
]

td_inputs = [
    entry(f"{RUN}/r0/td/a1_board_Runs/phy_1/a1_board_pr.db"),
    entry(f"{RUN}/r0/td/p2_board.sdc"),
    entry(f"{RUN}/r0/td/board_p2.adc"),
    entry(f"{RUN}/r0/td/a1_eng_top.v"),
    entry(f"{RUN}/r0/td/a1_small_top.sdc"),
    entry(f"{RUN}/r1/td/02_bitgen.tcl"),
    entry(f"{RUN}/r1/td/03_cwc.tcl"),
    entry(f"{RUN}/r1/td/a1_board.al"),
    entry(f"{RUN}/r0/td/routed_timing_status.rpt"),
    entry(f"{RUN}/r0/td/routed_qor.rpt"),
]

td_outputs = [
    entry(f"{RUN}/r1/td/a1_board.bit"),
    entry(f"{RUN}/r1/td/a1_board_inst.bid"),
    entry(f"{RUN}/r1/td/a1_board.cwc"),
    entry(f"{RUN}/r1/td/cw/compiled.bit"),
    entry(f"{RUN}/r1/td/cw/compiled.cwc"),
    entry(f"{RUN}/r1/td/candidate_timing.rpt"),
    entry(f"{RUN}/r1/td/candidate_abnormal.rpt"),
    entry(f"{RUN}/r1/td/candidate_ignored.rpt"),
    entry(f"{RUN}/r1/td/candidate_skew.rpt"),
    entry(f"{RUN}/r1/td/bitgen_console_b12_r1.log"),
    entry(f"{RUN}/r1/td/cwc_console_b12_r1.log"),
]

evidence = [
    entry(f"{RUN}/r1/board/ftdi-preflight.log"),
    entry(f"{RUN}/r0/result-r0.md"),
    entry(f"{RUN}/r0/lessons-r0.md"),
    entry(f"{RUN}/r0/artifact-hashes.txt"),
    entry(f"{RUN}/CANDIDATE-MANIFEST-b12-r1-last-r0.json"),
    entry(f"{RUN}/r1/result-r1.md"),
    entry(f"{RUN}/r1/lessons-r1.md"),
    entry(f"{RUN}/r1/mk_manifest_b12_r1.py"),
]

by_name = {os.path.basename(e["path"]): e for e in td_outputs}
bit = by_name["a1_board.bit"]
cwc = by_name["a1_board.cwc"]
bid = by_name["a1_board_inst.bid"]
cbit = by_name["compiled.bit"]
ccwc = by_name["compiled.cwc"]

assert bit["sha256"] == cbit["sha256"], "compiled.bit differs from parent bit"
assert cwc["sha256"] == ccwc["sha256"], "compiled.cwc differs from parent cwc"

manifest = {
    "manifest": "CANDIDATE-MANIFEST-b12-r1-last-r1",
    "task_id": "T10.b12-r1-last",
    "round": "r1",
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "parent_task": "T10 (stays blocked)",
    "purpose": "One bitgen + one CWC from the frozen r0 routed database so the R1 fix has a "
               "downloadable diagnostic candidate; the r0 timing floor (+0.015 ns) was missed "
               "and the user accepted +0.003 ns / 0 violations as a diagnostic-only candidate.",
    "status": "diagnostic_candidate_bitgen_cwc_frozen_board_blocked",
    "acceptance": {
        "decision_owner": "user",
        "accepted": True,
        "accepted_wns_ns": 0.003,
        "violation_endpoints": 0,
        "scope": "diagnostic candidate only, NOT a production or board sign-off",
        "timing_caveat": "thin_margin_+0.003",
        "production_requirement": "final production build must add pipelining to the A+ core "
                                  "carry chain (u_a1/u_a1/u_core/len_r_reg -> add9) to regain margin "
                                  ">= +0.05 ns; this package does not do that",
        "dev_plan_floor_ns": 0.015,
        "floor_shortfall_ns": 0.012,
    },
    "timing": {
        "source": "r0 routed database re-checked inside 02_bitgen.tcl (update_timing -mode final)",
        "routed_swNs": 0.003,
        "routed_stNs": 0.0,
        "routed_hwNs": 0.02,
        "routed_htNs": 0.0,
        "period_check_wns_ns": 2.2,
        "violation_endpoints": 0,
        "total_endpoints": 25697,
        "route_runs": 2,
        "route_runs_identical": True,
        "syn_swNs": 0.121,
        "eram": 72,
        "slice": 18370,
        "reg": 19539,
        "worst_path": "u_a1/u_a1/u_core/len_r_reg[6]_syn_2.clk -> u_a1/u_a1/u_core/add9_syn_221.fci "
                      "(frozen A+ core carry chain, not vendor DDR PHY, not R1 logic)",
    },
    "bitstream": {
        "bitgen_calls": 1,
        "cwc_calls": 1,
        "bit": bit,
        "bid": bid,
        "cwc": cwc,
        "compiled_bit": cbit,
        "compiled_cwc": ccwc,
        "bit_equals_compiled_bit": True,
        "cwc_equals_compiled_cwc": True,
        "downloads": 0,
        "flash": 0,
        "note": "BID is a1_board_inst.bid exported by bitgen (export_bid inside 02_bitgen.tcl).",
    },
    "board": {
        "status": "blocked",
        "reason": "FTDI_0403:6042_absent",
        "ftdi_present": 0,
        "com8_present": 0,
        "downloads": 0,
        "com8_opened": 0,
        "flash": 0,
        "retry": 0,
        "evidence": f"{RUN}/r1/board/ftdi-preflight.log",
        "claim": "no board-level conclusion; the R1 fix is verified in simulation and routed, not on hardware",
    },
    "frozen_source_baseline": "T10.b11-aplus-read/r0 (v4 225 B + F_WAIT watchdog)",
    "unchanged_in_r1": [
        "RTL (no edit at all in r1; bitgen consumed r0 changed-src verbatim)",
        "p2_board.sdc",
        "board_p2.adc",
        "pins / clocks / UART_DIV / HB_DIV",
        "v4 225 B / 55 fields",
    ],
    "groups": {
        "changed_src": changed_src,
        "repo_deps": repo_deps,
        "td_inputs": td_inputs,
        "td_outputs": td_outputs,
        "evidence": evidence,
    },
}

run_dir = os.path.join(ROOT, RUN)
with open(os.path.join(run_dir, "CANDIDATE-MANIFEST-b12-r1-last-r1.json"), "w", encoding="utf-8", newline="\n") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")

lines = []
for grp in ("changed_src", "repo_deps", "td_inputs", "td_outputs", "evidence"):
    lines.append(f"## {grp}")
    for e in manifest["groups"][grp]:
        lines.append(f"{e['sha256']}  {e['bytes']:>9}  {e['path']}")
    lines.append("")
with open(os.path.join(run_dir, "r1", "artifact-hashes.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines))

print("BIT_SHA256=" + bit["sha256"])
print("BID_SHA256=" + bid["sha256"])
print("CWC_SHA256=" + cwc["sha256"])
print("COMPILED_BIT_SHA256=" + cbit["sha256"])
print("COMPILED_CWC_SHA256=" + ccwc["sha256"])
print("MANIFEST_OK")
