import hashlib, json, os, sys

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
PKG = os.path.join(ROOT, "workflow", "runs", "20261020-0209_singleA_aplus_closedloop", "T10.a1-final-combo", "r0")

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def rel(p):
    return os.path.relpath(p, PKG).replace("\\", "/")

core = os.path.join(ROOT, "upstream", "ph1p100-pcie-ep-fpga", "rtl", "ep_side", "codec", "a1_deflate_core.v")
core_archive = os.path.join(PKG, "candidate-final-combo.a1_deflate_core.v")
frame = os.path.join(ROOT, "upstream", "ph1p100-pcie-ep-fpga", "rtl", "ep_side", "codec", "a1_frame_top.v")
sdc_td = os.path.join(PKG, "td", "a1_small_top.sdc")
bench = os.path.join(PKG, "td", "a1_eng_top.v")

files = []
def add(path, kind, note=""):
    if os.path.exists(path):
        files.append({"path": rel(path), "sha256": sha(path), "bytes": os.path.getsize(path), "kind": kind, "note": note})
    else:
        files.append({"path": rel(path), "sha256": None, "bytes": None, "kind": kind, "note": "MISSING"})

# frozen inputs (recorded in place)
add(core, "frozen_input_rtl", "core: single s1_ok_r micro-fix on bm-addr 35ea7364 lineage")
add(frame, "frozen_input_rtl", "unchanged 18d51b1b")
add(sdc_td, "frozen_input_sdc", "unchanged 227dd39e")
add(bench, "frozen_input_bench", "a1_eng_top.v unchanged 544cecfc")

# scripts
add(os.path.join(PKG, "run_p2_final_combo.ps1"), "script")
add(os.path.join(PKG, "run_p3_final_combo.ps1"), "script")
add(os.path.join(PKG, "td", "01_syn_route_final_combo.tcl"), "strategy_tcl")

# candidate archive (working tree was restored to the bm-addr baseline after FAIL)
add(os.path.join(PKG, "candidate-final-combo.a1_deflate_core.v"), "candidate_archive", "tested RTL candidate (core c676ba0b)")
add(os.path.join(PKG, "patch.diff"), "candidate_diff", "baseline 35ea7364 -> candidate c676ba0b")

# simulation evidence
for p, k in [
    (os.path.join(PKG, "p2", "result.json"), "p2_result"),
    (os.path.join(PKG, "p2", "logs", "vlog.log"), "p2_vlog"),
    (os.path.join(PKG, "p2", "logs", "exitcodes.txt"), "p2_exitcodes"),
    (os.path.join(PKG, "p3", "result.json"), "p3_result"),
    (os.path.join(PKG, "p3", "logs", "vlog.log"), "p3_vlog"),
    (os.path.join(PKG, "p3", "logs", "vlog-lint.log"), "p3_vlog_lint"),
    (os.path.join(PKG, "p3", "logs", "exitcodes.txt"), "p3_exitcodes"),
]:
    add(p, k)

# TD evidence
td = os.path.join(PKG, "td")
for name, k in [
    ("console_fc.log", "td_console"),
    ("syn_gate_timing_fc.rpt", "syn_gate_timing"),
    ("syn_gate_area_fc.rpt", "syn_gate_area"),
    ("routed_timing_summary.rpt", "routed_timing_summary"),
    ("routed_timing_status.rpt", "routed_timing_status"),
    ("routed_area.rpt", "routed_area"),
    ("routed_timing.rpt", "routed_timing"),
    ("routed_qor.rpt", "routed_qor"),
    ("routed_check_timing.rpt", "routed_check_timing"),
    ("routed_clock_utilization.rpt", "routed_clock_utilization"),
    ("phy_pr_timing_flow.rpt", "phy_pr_timing_flow"),
    ("phy_area_run.rpt", "phy_area"),
    ("route_flow.status", "route_flow_status"),
    ("place_flow.status", "place_flow_status"),
    ("fc_gate_netlist.v", "gate_netlist"),
    ("fc_routed_netlist.v", "routed_netlist"),
    ("fc_elab_netlist.v", "elab_netlist"),
    ("params_fc_after.tcl", "params_after"),
    ("a1_fc.al", "td_project_al"),
]:
    add(os.path.join(td, name), k)

for name, k in [
    (os.path.join("a1_fc_Runs", "syn_1", "run.log"), "syn_runlog"),
    (os.path.join("a1_fc_Runs", "phy_1", "run.log"), "phy_runlog"),
]:
    add(os.path.join(td, name), k)

manifest = {
    "task_id": "T10.a1-final-combo",
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "revision": "r0",
    "date": "2026-10-22",
    "status": "blocked_at_routed_gate",
    "ready_for_test": False,
    "tester": None,
    "package_type": "final bounded combo under T10: ONE cycle-neutral RTL micro-fix (s1_ok_r) + reused qor-retime group-1 strategy (retiming + phys_opt); 1 synth + 1 route; no seed sweep, no second group.",
    "status_reason": ("Micro-fix applied and functionally proven bit-identical (P2 13/13, P3 20/20, 0 mismatch, 0 X, vlog 0/0; P2 comp exactly 355,261; f1080p_p1d1 81,707 B / b769cc66). "
                      "TD run completed: synth SWNS +0.021, Routed SWNS -0.091 / STNS -0.308 / 12 violating endpoints / 4651 total, hold +0.021/0, resources within device. "
                      "Routed gate requires zero violations AND setup >= +0.2 ns -> FAIL. The old (pos < lim2) comparator left the hit2 cone (worst launch moved from pos_reg[3] to hp_r_reg[4], endpoint still bm_a.addrb[3]), "
                      "but the remaining (hp_r < pos) comparator + hit2 -> bm_raddr mux -> ERAM address path is still 4.730 ns. Per dispatch stop conditions: no second RTL fix, no extra synth/route; T10 stays 3/4 PASS + 1 warning; best routed remains qor-retime group 1 (-0.039 / 45)."),
    "authorization": {
        "source": "workflow/runs/20261020-0209_singleA_aplus_closedloop/dispatch-final-combo.json",
        "user_quote_location": "dispatch-final-combo.json authorization.quote (user 2026-10-22: one final combo attempt; micro RTL fix + group-1 retiming/phys_opt; 1 synth + 1 route; Routed zero violations and setup >= +0.2 ns; fail closes)",
        "type": "explicit_user_authorization_for_one_final_combo_attempt",
        "limits": ["single RTL micro-fix only", "no seed sweep / no second strategy group", "no clock change / false path / multicycle", "no bitgen / .bit / download / Flash", "failure closes T10 as 3/4 PASS + 1 warning, no auto expansion"],
    },
    "tool": "Tang Dynasty Release_2026.2 (V6.2.3.210850, DB_VERSION=46207), device PH1P100SBG484 speed 3, SDC 187.5 MHz (5.333 ns)",
    "frozen_inputs": {
        "core": {"path": "candidate-final-combo.a1_deflate_core.v (tested candidate; upstream working tree restored to 35ea7364 after FAIL)", "sha256": sha(core_archive), "previous_bm_addr_sha256": "35ea736415c5fbfd28fabcf85b78e33275fb2507f8d30a070a95a17a41760942", "change": "ONE micro-fix: declare reg s1_ok_r; add s1_ok_r <= s1_ok in the stage-1 block next to s1_vld_r <= s1_en; rng2 uses s1_ok_r instead of (pos < lim2). No other RTL line changed (patch.diff)."},
        "frame": {"path": "upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v", "sha256": sha(frame), "expected": "18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe", "match": sha(frame) == "18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe"},
        "sdc": {"path": "td/a1_small_top.sdc (copy used by TD)", "sha256": sha(sdc_td), "expected": "227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311", "match": sha(sdc_td) == "227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311"},
        "eng_top": {"path": "td/a1_eng_top.v", "sha256": sha(bench), "expected": "544cecfc2eb34a3ab5c03ebf3965730b4ce60b2ff73ac4c2ec2d87772faaf9aa", "match": sha(bench) == "544cecfc2eb34a3ab5c03ebf3965730b4ce60b2ff73ac4c2ec2d87772faaf9aa"},
        "note": "Only a1_deflate_core.v differs from the qor-retime baseline; frame/SDC/bench bit-identical.",
    },
    "strategy": {
        "groups": 1,
        "no_random_seed": True,
        "reused_group_1": {
            "tcl": "td/01_syn_route_final_combo.tcl",
            "syn": "set_param -run syn_1 rtl retiming on (PRJ-1105 confirmed)",
            "route": "set_param -run phy_1 route post_route_opt ultra (PRJ-1105 confirmed; route step ran phys_opt -post_route -effort high, 261.8 s)",
            "postrt_params": "postrt_opt_loc 20 / postrt_opt_extra_round 4 accepted via set_param (no PRJ-1105 confirmation line, same as group 1; not claimed effective)",
            "retiming_evidence": "syn run.log SYN-3005 backward retimed (dval_r_reg[7..13], ext_zero_r_reg, adler_fold_b_reg[8..10], ...); synth #reg 1646 (bm-addr) -> 1692",
        },
    },
    "gates": {
        "gate": "Routed zero violations AND setup >= +0.2 ns; hold >= 0; resources within device; static single-clock CDC + reset structure (retiming not cross-domain); reports direct -file; bitgen not_run",
        "functional": {"result": "PASS", "detail": "P2 13/13, P3 20/20, 0 mismatch, 0 X, vlog 0/0; P2 comp exactly 355,261 cycles (81.067 MB/s); f1080p_p1d1 81,707 B / sha b769cc66...08ff; all per-case stream SHA/len/cycles bit-identical to bm-addr baseline"},
        "synth": {"SWNS": "+0.021", "STNS": "0.000", "slice": 3084, "eram": 26, "core_eram": 22, "reg": 1692, "dram_lut": 32},
        "routed": {"status": "Routed", "SWNS": "-0.091", "STNS": "-0.308", "HWNS": "+0.021", "HTNS": "0.000", "viol_endpoints": 12, "total_endpoints": 4651, "fmax_mhz": 184.366, "coverage_pct": 96.17, "result": "FAIL (requires 0 violations and setup >= +0.2 ns)"},
        "worst_path": {"begin": "u_dut/u_core/hp_r_reg[4]_syn_2 (clk)", "end": "u_dut/u_core/bm_a_syn_37.addrb[3] (ERAM address)", "slack": "-0.091 ns", "data_path": "4.730 ns (cell 2.210 / net 2.520)", "logic_levels": "6 (ADDER=2, LUT6=1, LUT5=1, LUT3=1, ERAM=1)", "rtl_refs": "hp_r(289) -> (hp_r<pos) comparator -> rng2(513) -> hit2 -> bm_raddr_a(720)"},
        "bitgen": "not_run; no .bit (BIT_COUNT=0); stop marker set before opt_route completion; no download",
        "baseline_bm_addr": "synth +0.113 / routed -0.087 / 27 endpoints",
        "baseline_qor_retime_g1": "synth +0.113 / routed -0.039 / 45 endpoints (still best routed)",
    },
    "static_check": {
        "report_cdc": "TD Release_2026.2 has no report_cdc (console: RPT_CDC_UNAVAILABLE invalid command name \"report_cdc\"); no cdc report file created",
        "single_clock": "routed timing summary: single clk 187.512 MHz, CC-From=no, CC-To=no; report_clock_utilization executed (GCLK 1, SCLK 4, fanout 1308)",
        "check_timing": "executed: 0 combinational loops, 1 dummy node (PH1P_PHY_LSLICE), 0 unconnected generated clocks",
        "retiming_cross_domain": "SYN-3005 retimed registers listed; gate netlist s1_ok_r_reg present; s1_ok_r itself not retimed; no new clock/reset nets expected (not claimed beyond gate-level evidence; no report_cdc in this tool version)",
        "reset_structure": "s1_ok_r intentionally has no reset (unconditional update; hit2 gated by s1_vld_r which resets to 0; lim2/s1_pos_r reset to 0 so s1_ok_r is defined at the first active edge) - documented in result-r0.md",
    },
    "functional": {
        "rtl_changed": True,
        "regression_rerun": "full 33-case P2/P3 regression re-run on the fixed RTL (new run dir); prior bm-addr evidence not reused as the gate evidence, only as the bit-identical comparison baseline",
        "equivalence": "all 13 P2 cases and all 20 P3 cases bit-identical to the bm-addr baseline (stream SHA256/len/run_cycles and stats); P2 comp 355,261 exactly",
        "evidence_paths": ["p2/result.json", "p2/logs/vlog.log", "p2/logs/exitcodes.txt", "p3/result.json", "p3/logs/vlog.log", "p3/logs/vlog-lint.log", "p3/logs/exitcodes.txt"],
    },
    "budget": {
        "td_sessions": 1,
        "td_total_minutes_approx": 7.8,
        "limit_sessions": 2,
        "limit_minutes": 90,
        "synth_attempts": 1,
        "synth_limit": 1,
        "route_attempts": 1,
        "route_limit": 1,
        "bitgen": 0,
        "seed_sweeps": 0,
        "downloads": 0,
        "flash": 0,
    },
    "artifacts": {
        "hash_file": "artifact-hashes.txt",
        "files": files,
        "result": "result-r0.md",
        "lessons": "lessons-r0.md",
    },
    "fallback": {
        "best_routed_overall": "T10.a1-qor-retime group 1: routed -0.039 / 45 endpoints (unchanged; still the best routed result of T10)",
        "best_synth_overall": "T10.a1-adler-smem core 611ad704: synth +0.233",
        "working_tree_after_package": "a1_deflate_core.v restored to the bm-addr baseline 35ea7364 (hash verified after restore); the tested candidate is archived as candidate-final-combo.a1_deflate_core.v (c676ba0b) with patch.diff",
        "rollback": "restore a1_deflate_core.v to bm-addr 35ea736415c5fbfd28fabcf85b78e33275fb2507f8d30a070a95a17a41760942 (frozen copy: T10.a1-bm-addr/r0/td/a1_deflate_core.v); delete T10.a1-final-combo/** and result-r0.md; older manifests read-only",
    },
    "blocked": {
        "reason_code": "LIMIT_REACHED",
        "detail": "Routed gate not met (12 violations, SWNS -0.091 < +0.2). Dispatch stop condition: FAIL -> close T10 as 3/4 PASS + 1 warning; no second RTL fix, no extra synth/route.",
        "last_evidence": "td/routed_timing_summary.rpt (SWNS -0.091, 12/4651 endpoints); td/console_fc.log (FC_ROUTED_SWNS=-0.091 ...)",
        "minimal_next_step": "None within this package. Future work would be a new user-authorized package (deeper microarchitecture re-pipeline of the hit/address cone, or larger device/QoR strategy) - not authorized here.",
    },
    "retest": {
        "tester_required": False,
        "note": "Routed gate FAILED -> per dispatch no tester is spawned for T10.a1-final-combo; T10 stays 3/4 PASS + 1 warning. If the planner still wants an independent FAIL-evidence review, the tester can independently parse routed_timing_summary.rpt/-status.rpt, syn_gate_*_fc.rpt, console_fc.log, the gate/routed netlists, and re-run P2/P3 on core c676ba0b.",
        "required_dimensions": ["engineering", "functional", "system"],
        "required_checks": ["independent parse of routed SWNS/STNS/HWNS/HTNS and endpoint counts", "independent re-run of P2/P3 on core c676ba0b (bit-identical expectation)", "no bitgen/.bit/download", "frame/SDC hashes unchanged"],
        "input_status": "changed (core RTL), frame/SDC/bench same",
    },
}

out = os.path.join(PKG, "CANDIDATE-MANIFEST-final-combo-r0.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=1, ensure_ascii=False)

hout = os.path.join(PKG, "artifact-hashes.txt")
with open(hout, "w", encoding="utf-8") as f:
    f.write("# T10.a1-final-combo r0 artifact hashes (SHA256)\n")
    f.write("# frozen inputs\n")
    f.write("%s  %s (tested candidate; working tree restored to 35ea7364)\n" % (sha(core_archive), core_archive.replace("\\", "/")))
    for p in (frame, sdc_td, bench):
        f.write("%s  %s\n" % (sha(p), p.replace("\\", "/")))
    f.write("# package artifacts\n")
    for e in files:
        f.write("%s  %s\n" % (e["sha256"], e["path"]))

missing = [e["path"] for e in files if e["sha256"] is None]
print("manifest:", out)
print("hashes:", hout)
print("files:", len(files), "missing:", missing)
print("core:", sha(core))
print("frame match:", sha(frame) == "18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe")
print("sdc match:", sha(sdc_td) == "227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311")
