import hashlib, json, os, re

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
PKG = os.path.join(ROOT, "workflow", "runs", "20261020-0209_singleA_aplus_closedloop", "T10.a1-pipe-split", "r0")


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def rel(p):
    return os.path.relpath(p, PKG).replace("\\", "/")


def read(p):
    with open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


core = os.path.join(ROOT, "upstream", "ph1p100-pcie-ep-fpga", "rtl", "ep_side", "codec", "a1_deflate_core.v")
core_archive = os.path.join(PKG, "candidate-pipe-split.a1_deflate_core.v")
core_baseline = os.path.join(PKG, "baseline-core-35ea7364.v")
frame = os.path.join(ROOT, "upstream", "ph1p100-pcie-ep-fpga", "rtl", "ep_side", "codec", "a1_frame_top.v")
sdc_td = os.path.join(PKG, "td", "a1_small_top.sdc")
bench = os.path.join(PKG, "td", "a1_eng_top.v")

CORE_SHA = sha(core)
CORE_ARCHIVE_SHA = sha(core_archive)
FRAME_SHA = sha(frame)
SDC_SHA = sha(sdc_td)
BENCH_SHA = sha(bench)

# ---- parse TD routed summary (independent of console markers) ----------------
td = os.path.join(PKG, "td")
routed_summary = os.path.join(td, "routed_timing_summary.rpt")
routed = {}
if os.path.exists(routed_summary):
    t = read(routed_summary)
    m = re.search(r"SWNS:\s*(-?[0-9.]+)ns,\s*STNS:\s*(-?[0-9.]+)ns", t)
    h = re.search(r"HWNS:\s*(-?[0-9.]+)ns,\s*HTNS:\s*(-?[0-9.]+)ns", t)
    v = re.search(r"SWNS\s+(-?[0-9.]+)ns,\s+STNS\s+(-?[0-9.]+)ns,\s+([0-9]+) Viol Endpoints,\s+([0-9]+) Total Endpoints", t)
    conf = re.search(r"Confidence\s*:\s*(\S+)", t)
    cov = re.search(r"STA coverage\s*:\s*([0-9.]+)%", t)
    clk = re.search(r"clk0:\s+([0-9.]+)\s+([0-9]+)\s+clk", t)
    if m:
        routed["sw_ns"] = float(m.group(1)); routed["st_ns"] = float(m.group(2))
    if h:
        routed["hw_ns"] = float(h.group(1)); routed["ht_ns"] = float(h.group(2))
    if v:
        routed["viol_ep"] = int(v.group(3)); routed["total_ep"] = int(v.group(4))
    if conf:
        routed["confidence"] = conf.group(1)
    if cov:
        routed["coverage"] = float(cov.group(1))
    if clk:
        routed["clk_mhz"] = float(clk.group(1)); routed["clk_fanout"] = int(clk.group(2))
    for line in t.splitlines():
        s = line.split()
        if len(s) >= 9 and s[0] == "clk0" and s[1] == "Inferred":
            try:
                routed["r_period_ns"] = float(s[7]); routed["fmax_mhz"] = float(s[8])
            except ValueError:
                pass
            break

routed_area = {}
ap = os.path.join(td, "routed_area.rpt")
if os.path.exists(ap):
    at = read(ap)
    for k, pat in [("slice", r"#slice\s{3,}([0-9]+)"), ("lut6", r"#lut6\s+([0-9]+)"),
                   ("reg", r"#reg\s+([0-9]+)"), ("eram", r"#eram\s+([0-9]+)"),
                   ("dsp", r"#dsp\s+([0-9]+)"), ("io", r"#IO\s+([0-9]+)")]:
        mm = re.search(pat, at)
        if mm:
            routed_area[k] = int(mm.group(1))

syn = {}
stp = os.path.join(td, "syn_gate_timing_ps.rpt")
if os.path.exists(stp):
    t = read(stp)
    m = re.search(r"SWNS:\s*(-?[0-9.]+)ns,\s*STNS:\s*(-?[0-9.]+)ns", t)
    if m:
        syn["sw_ns"] = float(m.group(1)); syn["st_ns"] = float(m.group(2))
sap = os.path.join(td, "syn_gate_area_ps.rpt")
if os.path.exists(sap):
    at = read(sap)
    for k, pat in [("slice", r"#slice\*\s+([0-9]+)"), ("reg", r"#reg\s+([0-9]+)"),
                   ("eram", r"#eram\s+([0-9]+)"), ("dram_lut", r"#dram lut\s+([0-9]+)")]:
        mm = re.search(pat, at)
        if mm:
            syn[k] = int(mm.group(1))

gate_pass = bool(routed.get("viol_ep", 1) == 0 and routed.get("sw_ns", -99) >= 0.2 and routed.get("hw_ns", -99) >= 0)
status = "ready_for_test" if gate_pass else "blocked_at_routed_gate"

# ---- functional results ------------------------------------------------------
p2 = json.load(open(os.path.join(PKG, "p2", "result.json"), encoding="utf-8")) if os.path.exists(os.path.join(PKG, "p2", "result.json")) else {}
p3 = json.load(open(os.path.join(PKG, "p3", "result.json"), encoding="utf-8")) if os.path.exists(os.path.join(PKG, "p3", "result.json")) else {}
p2_cases = p2.get("cases", [])
p2_ok = sum(1 for c in p2_cases if c.get("pass"))
p3_cases = p3.get("cases", [])
p3_ok = sum(1 for c in p3_cases if not c.get("problems"))
p2_comp = None
for c in p2_cases:
    if "comp" in c.get("name", ""):
        p2_comp = c.get("stats", {}).get("run_cycles")
p3_1080 = None
for c in p3_cases:
    if c.get("name") == "f1080p_p1d1":
        p3_1080 = c.get("cycles")

files = []


def add(path, kind, note=""):
    if os.path.exists(path):
        files.append({"path": rel(path), "abs_path": os.path.abspath(path), "sha256": sha(path),
                      "bytes": os.path.getsize(path), "kind": kind, "note": note})
    else:
        files.append({"path": rel(path), "abs_path": os.path.abspath(path), "sha256": None,
                      "bytes": None, "kind": kind, "note": "MISSING"})


add(core, "frozen_input_rtl", "core working tree = tested candidate (rng1_r/s1_ok_r/s1_last_r stage-1 registration)")
add(core_archive, "candidate_archive", "tested RTL candidate (core %s)" % CORE_ARCHIVE_SHA[:8])
add(core_baseline, "baseline_archive", "pre-change baseline 35ea7364 (used for patch.diff)")
add(frame, "frozen_input_rtl", "unchanged 18d51b1b")
add(sdc_td, "frozen_input_sdc", "unchanged 227dd39e")
add(bench, "frozen_input_bench", "a1_eng_top.v unchanged 544cecfc")
add(os.path.join(PKG, "patch.diff"), "candidate_diff", "baseline 35ea7364 -> candidate %s" % CORE_ARCHIVE_SHA[:8])
add(os.path.join(PKG, "run_p2_pipe_split.ps1"), "script")
add(os.path.join(PKG, "run_p3_pipe_split.ps1"), "script")
add(os.path.join(PKG, "analysis", "scan_netlists.py"), "static_scan_script")
add(os.path.join(PKG, "analysis", "netlist_scan.txt"), "static_scan_result")
add(os.path.join(PKG, "freeze_manifest.py"), "manifest_generator")
add(os.path.join(PKG, "result-r0.md"), "result")
add(os.path.join(PKG, "lessons-r0.md"), "lessons")
add(os.path.join(td, "01_syn_ps.tcl"), "syn_tcl")
add(os.path.join(td, "02_syn_route_ps.tcl"), "route_tcl")
for p, k in [
    (os.path.join(PKG, "p2", "result.json"), "p2_result"),
    (os.path.join(PKG, "p2", "logs", "vlog.log"), "p2_vlog"),
    (os.path.join(PKG, "p2", "logs", "exitcodes.txt"), "p2_exitcodes"),
    (os.path.join(PKG, "p3", "result.json"), "p3_result"),
    (os.path.join(PKG, "p3", "logs", "vlog.log"), "p3_vlog"),
    (os.path.join(PKG, "p3", "logs", "vlog-lint.log"), "p3_vlog_lint"),
    (os.path.join(PKG, "p3", "logs", "exitcodes.txt"), "p3_exitcodes"),
    (os.path.join(PKG, "p3", "logs", "verify_first_run_FAIL.log"), "p3_contaminated_first_attempt_log"),
    (os.path.join(PKG, "p3", "logs", "f1080p_p1d0_first_run_stats.txt"), "p3_contaminated_first_attempt_stats"),
]:
    add(p, k)
for name, k in [
    ("console_syn1.log", "td_console_syn1_literal_form"),
    ("console_syn2.log", "td_console_syn2_threshold_form"),
    ("console_route.log", "td_console_route"),
    ("syn1_gate_timing_literal_form.rpt", "syn1_gate_timing"),
    ("syn1_gate_area_literal_form.rpt", "syn1_gate_area"),
    ("syn2_gate_timing_threshold_form.rpt", "syn2_gate_timing"),
    ("syn2_gate_area_threshold_form.rpt", "syn2_gate_area"),
    ("syn_gate_timing_ps.rpt", "syn3_gate_timing_final"),
    ("syn_gate_area_ps.rpt", "syn3_gate_area_final"),
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
    ("ps_gate_netlist.v", "gate_netlist"),
    ("ps_routed_netlist.v", "routed_netlist"),
    ("ps_elab_netlist.v", "elab_netlist"),
    ("params_ps_after.tcl", "params_after"),
    ("a1_ps.al", "td_project_al"),
]:
    add(os.path.join(td, name), k)
for name, k in [
    (os.path.join("a1_ps_Runs", "syn_1", "run.log"), "syn_runlog"),
    (os.path.join("a1_ps_Runs", "phy_1", "run.log"), "phy_runlog"),
]:
    add(os.path.join(td, name), k)

manifest = {
    "task_id": "T10.a1-pipe-split",
    "run_id": "20261020-0209_singleA_aplus_closedloop",
    "revision": "r0",
    "date": "2026-10-22/23",
    "status": status,
    "ready_for_test": gate_pass,
    "tester": None,
    "package_type": ("cycle-neutral structural pipeline split (rng1_r/s1_ok_r stage-1 registration + flop-only stage-2 hit2, "
                     "plus one bounded registered pos/blk_n predicate) under T10; same run; retiming reused; 3 synth + 1 route; "
                     "no seed sweep, no clock change, no false path/multicycle"),
    "status_reason": ("G1 PASS: 33/33 bit-identical (P2 13/13, P3 20/20, 0 mismatch, 0 X, vlog 0/0; P2 comp exactly 355,261 = cycle-neutral; "
                      "f1080p_p1d1 81,707 B / 4,677,945 cycles; SDC 227dd39e and frame 18d51b1b unchanged). "
                      "G2 partially met: Routed SWNS +0.047 / STNS 0.000 / HWNS +0.021 / 0 violating endpoints of 4,649 / Fmax 189.179 MHz, "
                      "resources within device (3,032 slices, 26 ERAM, 0 DSP), single clock, bitgen not_run. "
                      "The dispatch gate requires setup >= +0.2 ns; +0.047 < +0.2 -> BLOCKED, planner/user to adjudicate acceptance. "
                      "The split removed the old worst cone (pos_reg[3] -> bm_a.addrb, -0.039/45 in qor-retime); the new limiter is the "
                      "extension-compare ERAM clk2q cone (bm_a/b clk2q 1.846 ns -> ext_mis_r compare -> add41, 5.003 ns, +0.047), "
                      "outside this package's authorized scope."),
    "authorization": {
        "source": "workflow/runs/20261020-0209_singleA_aplus_closedloop/dispatch-pipe-split.json",
        "user_quote": "进行结构性分拍尝试 (2026-10-22)",
        "cycle_rule": "cycle-neutral preferred (target P2 comp 355,261); any added cycles must be quantified and total P2 comp <= 370,370; > 370,370 forbidden without user refresh",
        "limits": ["no protocol/port/frame semantics/CRC/length/abort/Bayer changes", "SDC 227dd39e unchanged",
                   "no random seed sweep", "no clock change / false path / multicycle",
                   "no bitgen / .bit / download / Flash", "no cross-clock or cross-reset retiming moves",
                   "no third pipeline stage anywhere"],
    },
    "tool": "Tang Dynasty Release_2026.2 (V6.2.3.210850), device PH1P100SBG484 speed 3, SDC 187.5 MHz (5.333 ns); ModelSim ASE 18.1",
    "frozen_inputs": {
        "core": {"path": "candidate-pipe-split.a1_deflate_core.v (tested candidate; working tree holds the same file)",
                 "abs_path": os.path.abspath(core_archive), "sha256": CORE_ARCHIVE_SHA,
                 "working_tree_sha256": CORE_SHA,
                 "baseline_sha256": "35ea736415c5fbfd28fabcf85b78e33275fb2507f8d30a070a95a17a41760942",
                 "change": "bounded steps 1-2 + one step-4 predicate: stage-1 rng1_r (precomputed s1_lo/s1_hi bounds, dual hent-source compare, 1-bit select), s1_ok_r, s1_last_r, flop-only hit2 = s1_vld_r && hb_r && rng1_r && s1_ok_r; rng2 wire removed; reset/abort clears added. Step 3 (p3p1_r) not applied. See patch.diff."},
        "frame": {"path": "upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v",
                  "abs_path": os.path.abspath(frame), "sha256": FRAME_SHA,
                  "expected": "18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe",
                  "match": FRAME_SHA == "18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe"},
        "sdc": {"path": "td/a1_small_top.sdc (copy used by TD)", "abs_path": os.path.abspath(sdc_td), "sha256": SDC_SHA,
                "expected": "227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311",
                "match": SDC_SHA == "227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311"},
        "eng_top": {"path": "td/a1_eng_top.v", "abs_path": os.path.abspath(bench), "sha256": BENCH_SHA,
                    "expected": "544cecfc2eb34a3ab5c03ebf3965730b4ce60b2ff73ac4c2ec2d87772faaf9aa",
                    "match": BENCH_SHA == "544cecfc2eb34a3ab5c03ebf3965730b4ce60b2ff73ac4c2ec2d87772faaf9aa"},
        "note": "Only a1_deflate_core.v differs from the qor-retime baseline; frame/SDC/bench bit-identical.",
    },
    "strategy": {
        "no_random_seed": True,
        "syn": "set_param -run syn_1 rtl retiming on (PRJ-1105 confirmed; SYN-3005 backward retimed adler_fold_b_reg[8..13] etc.)",
        "route": "set_param -run phy_1 route post_route_opt ultra (PRJ-1105 confirmed; param table ultra (*)). EVIDENCE DEVIATION: the phy flow ran place 40 s / route 29 s / fix_hold 1 s and NO post-route phys_opt stage; the +47 ps result is from retiming + place/route + hold fix only.",
        "postrt_params": "postrt_opt_loc 20 / postrt_opt_extra_round 4 accepted via set_param (no PRJ-1105 confirmation line; not claimed effective)",
        "synth_iterations": 3,
        "route_attempts": 1,
    },
    "gates": {
        "gate": "Routed zero violations AND setup >= +0.2 ns; hold >= 0; resources within device; static single-clock CDC + reset structure; reports direct -file; bitgen not_run",
        "functional": {
            "result": "PASS" if (p2.get("verdict") == "PASS" and p3.get("verdict") == "PASS") else "FAIL",
            "detail": "P2 %d/%d, P3 %d/%d; P2 comp run_cycles=%s; f1080p_p1d1 cycles=%s; vlog 0/0; all per-case stream SHA/len/cycles bit-identical to the final-combo/bm-addr baseline" % (
                p2_ok, len(p2_cases), p3_ok, len(p3_cases), p2_comp, p3_1080),
        },
        "synth": syn,
        "routed": routed,
        "routed_area": routed_area,
        "bitgen": "not_run; stop marker set when opt_route begins; no .bit (NO_BIT_FILE), no download",
        "baseline_qor_retime_g1": "synth +0.113 / routed -0.039 / 45 endpoints",
        "baseline_final_combo": "synth +0.021 / routed -0.091 / 12 endpoints",
        "synth_iteration_notes": "synth #1 literal form -0.055 (htab ERAM clk2q -> rng1_r 5.324 ns); #2 precomputed bounds -0.007; #3 final +0.275 / 0 violations",
    },
    "functional": {
        "rtl_changed": True,
        "regression_rerun": "full 33-case P2/P3 regression re-run on the final RTL (P2 43 s, P3 491 s clean single run); prior evidence used only as the bit-identical comparison baseline",
        "equivalence": "all 13 P2 cases and all 20 P3 cases bit-identical to the final-combo (= bm-addr) baseline (stream SHA256/len/run_cycles and stats); P2 comp %s" % p2_comp,
        "evidence_paths": ["p2/result.json", "p2/logs/vlog.log", "p2/logs/exitcodes.txt",
                           "p3/result.json", "p3/logs/vlog.log", "p3/logs/vlog-lint.log", "p3/logs/exitcodes.txt"],
        "incident": "first P3 attempt was invalidated by two overlapping P3 runs on the same directory/work library (operator error); the clean single re-run is authoritative; contaminated evidence preserved under p3/logs/.",
    },
    "static_check": {
        "report_cdc": "TD Release_2026.2 has no report_cdc (console RPT_CDC_UNAVAILABLE); no cdc report file created",
        "single_clock": "routed timing summary: single clk 187.512 MHz, CC-From=no, CC-To=no; report_clock_utilization: GCLK 1 / SCLK 4 (gclk_0 fanout 1,290)",
        "check_timing": "executed: 0 combinational loops, 1 dummy node (PH1P_PHY_LSLICE), 0 unconnected generated clocks",
        "gate_netlist_scan": "analysis/netlist_scan.txt: 1,689 AL_MAP_SEQ, 100% clocked by clk_dup_1; sr nets rst_n_dup_1567 (756), fifo_mem_i1_syn_2 (443), unconnected (245); retiming same-domain only",
        "routed_netlist": "routed netlist packs flops into LSLICE/MSLICE (no AL_MAP_SEQ primitives); STA/clock reports used for the routed-level statement",
    },
    "artifacts": {
        "hash_file": "artifact-hashes.txt",
        "files": files,
        "result": "result-r0.md",
        "lessons": "lessons-r0.md",
    },
    "fallback": {
        "best_routed_this_package": "Routed SWNS +0.047 / 0 violating endpoints / hold +0.021 / Fmax 189.179 MHz (best WNS and only zero-violation route of T10, but below the +0.2 ns gate)",
        "previous_best_routed": "T10.a1-qor-retime group 1: -0.039 / 45 endpoints (no run has met the +0.2 ns gate)",
        "best_synth_overall": "this package final: synth +0.275 / 0 violations; T10.a1-adler-smem core 611ad704: synth +0.233",
        "working_tree_after_package": "a1_deflate_core.v = tested candidate bf6af390 (NOT reverted, per this round's instruction); baseline 35ea7364 archived as baseline-core-35ea7364.v",
        "rollback": "restore a1_deflate_core.v from baseline-core-35ea7364.v (or T10.a1-bm-addr/r0/td/a1_deflate_core.v); older manifests read-only",
    },
    "blocked": {
        "reason_code": "LIMIT_REACHED",
        "detail": "Routed zero violations achieved, but setup WNS +0.047 ns < the dispatch threshold +0.2 ns. Per dispatch stop conditions no second route and no extra RTL fix round; T10 stays 3/4 PASS + 1 warning.",
        "last_evidence": "td/routed_timing_summary.rpt (SWNS +0.047, 0/4,649), td/a1_ps_Runs/phy_1/route.qor (Setup 47 ps, 0 violated S-EP), td/console_route.log (PS_ROUTED_SWNS=0.047 ...)",
        "minimal_next_step": "Planner/user adjudication: accept +47 ps (requires refreshing the +0.2 ns acceptance basis) or close T10 as 3/4 + 1 warning. Any further RTL/route work needs a new explicit authorization.",
    },
    "retest": {
        "tester_required": False,
        "note": "Routed gate (+0.2 ns) not met -> per dispatch no PASS tester is spawned; the planner decides acceptance. If an independent review is wanted, it must keep the threshold judgment explicit (+47 ps < +200 ps) and not silently relax it.",
        "required_dimensions": ["integrated", "functional", "engineering", "system"],
        "required_checks": [
            "independent parse of routed_timing_summary.rpt / routed_timing_status.rpt (SWNS/STNS/HWNS/HTNS, violating endpoints) and a1_ps_Runs/phy_1/route.qor",
            "independent re-run of the 33-case P2/P3 regression on core bf6af390 (expected bit-identical: comp 355,261; 1080p 81,707 B / b769cc66)",
            "frame/SDC/bench hashes unchanged; no bitgen/.bit/download",
            "static single-clock CDC + reset structure (analysis/netlist_scan.txt); resources within device",
        ],
        "input_status": "changed (core RTL), frame/SDC/bench same",
    },
}

out = os.path.join(PKG, "CANDIDATE-MANIFEST-pipe-split-r0.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=1, ensure_ascii=False)

hout = os.path.join(PKG, "artifact-hashes.txt")
with open(hout, "w", encoding="utf-8") as f:
    f.write("# T10.a1-pipe-split r0 artifact hashes (SHA256)\n")
    f.write("# frozen inputs\n")
    f.write("%s  %s (tested candidate)\n" % (CORE_ARCHIVE_SHA, core_archive.replace("\\", "/")))
    f.write("%s  %s (working tree = candidate)\n" % (CORE_SHA, core.replace("\\", "/")))
    f.write("%s  %s (baseline)\n" % (sha(core_baseline), core_baseline.replace("\\", "/")))
    for p in (frame, sdc_td, bench):
        f.write("%s  %s\n" % (sha(p), p.replace("\\", "/")))
    f.write("# package artifacts (absolute paths)\n")
    for e in files:
        f.write("%s  %s\n" % (e["sha256"], e["abs_path"].replace("\\", "/")))

missing = [e["path"] for e in files if e["sha256"] is None]
print("manifest:", out)
print("hashes:", hout)
print("files:", len(files), "missing:", missing)
print("status:", status, "gate_pass:", gate_pass)
print("routed:", routed)
print("synth:", syn)
print("area:", routed_area)
print("p2:", p2_ok, "/", len(p2_cases), "comp:", p2_comp, "p3:", p3_ok, "/", len(p3_cases), "1080p:", p3_1080)
print("core:", CORE_SHA)
print("frame match:", FRAME_SHA == "18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe")
print("sdc match:", SDC_SHA == "227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311")
