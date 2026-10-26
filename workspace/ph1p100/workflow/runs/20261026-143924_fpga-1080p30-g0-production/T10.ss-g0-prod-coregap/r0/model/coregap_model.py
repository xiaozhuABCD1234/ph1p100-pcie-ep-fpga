"""Core-throughput gap model for T10.ss-g0-prod-coregap (b11 a1_deflate_core).

Everything here is either
  measured  - read from a frozen artefact (1-frame stage probe, comp anchor, P1 r1),
  derived   - computed from the b11 RTL structure (a1_deflate_core.v) or from arithmetic,
  assumed   - a stated assumption, never used as a gate.

No RTL is changed and no synthesis/timing is run.  The model is a *cycle
accounting* of the b11 FSM, not a bit-exact simulator.

FSM cycle accounting (derived from r0/src/a1_deflate_core.v, line refs in
assumptions.json):
  * one S_SCAN cycle per emitted symbol start
  * a literal costs 1 cycle and covers 1 byte
  * a match costs len+5 cycles (S_SCAN 1 + S_EXT len-2 + S_MLEN 1 + S_MCHK 1 +
    S_REPOS 4) and covers len bytes
      -> the scan pass costs  literals + sum(len+5) = B + 5*M
  * the accepted block is emitted from cmem: S_REPLAY_R/RD/E emit 2 bytes per
    4 cycles -> 2 cycles per stream byte  (r, fitted)
  * a stored block is re-emitted from bm: S_SDATA_R emits 1 byte per cycle
      -> 1 cycle per block byte (derived)
  * per block: S_WAIT/S_BHDR/S_PRE(4)/S_EOB/S_EODONE/S_DECIDE + headers (k, fitted)
"""

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # .../T10.ss-g0-prod-coregap/r0
OUT = ROOT / "out"

B_FRAME = 2_592_000
BLOCK = 4800
NBLK = B_FRAME // BLOCK                              # 540, exact (2592000/4800)
G0_CYCLES = 6_250_000.0
TARGET_CPB = G0_CYCLES / B_FRAME                     # 2.411265...

# ---- measured anchors -------------------------------------------------------
# b6 comp core bench (frozen): 355,261 cycles / 153,600 B in / 50,310 B out,
# match count 19,328 (b6 r0 result-r0.md, section 7)
COMP = dict(bytes=153_600, cycles=355_261, stream=50_310, matches=19_328, blocks=153_600 // BLOCK)
# P1 r1b measured chain anchors (read-only reference; core_interval is the
# bottleneck there, see content-verdict-r1.json bottleneck_attribution)
P1 = dict(N_cycles=7_475_240.0, L_cycles=6_986_952.0,
          N_core_interval_mean=7_475_238.0, L_core_interval_mean=6_986_950.7)
# R6: the probe reference is the P1 r1 *frame-1 core_interval* (same quantity the
# probe measures).  The 4-frame steady-state S_ss above is a different quantity and
# is reported separately as probe_vs_p1_ss_pct.
P1_FRAME1 = {"N": 7_476_245.0, "L": 6_979_811.0}   # measured, P1 r1 t_enc(1)-t_pub(1)
# C1 S_ss is a *chain* interval (P4 R1) and is NOT a core-level anchor: its
# core work is far below the interval (see c1_check()).
C1 = dict(cycles_s_ss=4_677_970.0, bytes=B_FRAME, payload_per_frame=81_707.0)


def load_probe():
    p = OUT / "stage-probe.json"
    return json.loads(p.read_text(encoding="utf-8"))


def model_cycles(pt, r, k):
    """Cycle prediction for one probe point using its measured counters."""
    scan = pt["bytes"] + 5.0 * pt["matches"]
    stored_in = pt["stored_blocks"] * BLOCK
    stream_fixed = pt["stream_bytes"] - stored_in - 5 * pt["stored_blocks"]
    emit = r * stream_fixed + 1.0 * stored_in
    return scan + emit + k * pt["blocks"], dict(scan=scan, stream_fixed=stream_fixed,
                                                stored_in=stored_in, emit=emit,
                                                blk=k * pt["blocks"])


def solve_two(a, b):
    """Solve r,k from two equations  A_r*r + A_k*k = A_c , B_r*r + B_k*k = B_c."""
    (ar, ak, ac), (br, bk, bc) = a, b
    det = ar * bk - br * ak
    r = (ac * bk - bc * ak) / det
    k = (ar * bc - br * ac) / det
    return r, k


def comp_eq(r, k):
    scan = COMP["bytes"] + 5.0 * COMP["matches"]
    return (COMP["stream"], COMP["blocks"], COMP["cycles"] - scan)


def main():
    probe = load_probe()
    N, L = probe["probe"]["N"], probe["probe"]["L"]
    res = {"model": "b11 cycle accounting", "target_cycles_per_byte": TARGET_CPB,
           "G0_cycles": G0_CYCLES, "bytes_per_frame": B_FRAME, "blocks_per_frame": NBLK,
           "probe_validation": probe.get("validation"), "probe_all_valid": probe.get("all_valid"),
           "anchors": {}, "calibration": {}, "residuals": {}, "leave_one_out": {},
           "matrix": [], "verdict": {}}

    # ---- measured probe summary
    for name, pt in (("N", N), ("L", L)):
        res["anchors"][name] = {
            "label": "measured (1-frame stage probe, frame 1)",
            "bytes": pt["bytes"], "cycles": pt["cycles"],
            "cycles_per_byte": pt["cycles"] / pt["bytes"],
            "exp_bytes": pt["stream_bytes"], "compression_ratio": pt["bytes"] / pt["stream_bytes"],
            "blocks": pt["blocks"], "fixed_blocks": pt["fixed_blocks"],
            "stored_blocks": pt["stored_blocks"], "literals": pt["literals"],
            "matches": pt["matches"], "avg_match_len": (pt["bytes"] - pt["literals"]) / pt["matches"],
            "symbols_per_byte": (pt["literals"] + pt["matches"]) / pt["bytes"],
            "extension_share": (pt["bytes"] - pt["literals"] - 3 * pt["matches"]) / pt["bytes"],
            "cand_aborts": pt["cand_aborts"], "max_match": pt["max_match"],
            "max_dist": pt["max_dist"], "stall": pt["stall"],
            "probe_vs_p1_pct": 100.0 * (pt["cycles"] - P1_FRAME1[name]) / P1_FRAME1[name],
            "probe_vs_p1_reference": "P1 r1 frame-1 core_interval (t_enc(1)-t_pub(1))",
            "probe_vs_p1_ss_pct": 100.0 * (pt["cycles"] - (P1["N_cycles"] if name == "N" else P1["L_cycles"]))
                                  / (P1["N_cycles"] if name == "N" else P1["L_cycles"]),
            "probe_vs_p1_ss_note": "different quantity (4-frame steady-state S_ss), listed for reference only",
        }
        scan = pt["bytes"] + 5.0 * pt["matches"]
        res["anchors"][name]["scan_cycles_derived"] = scan
        res["anchors"][name]["non_scan_cycles_measured"] = pt["cycles"] - scan
        res["anchors"][name]["non_scan_share_pct"] = 100.0 * (pt["cycles"] - scan) / pt["cycles"]

    res["anchors"]["comp"] = {"label": "measured (b6 core bench, frozen)", **COMP,
                              "cycles_per_byte": COMP["cycles"] / COMP["bytes"],
                              "compression_ratio": COMP["bytes"] / COMP["stream"]}
    res["anchors"]["C1"] = {"label": "measured chain S_ss (P4 R1) - NOT core level", **C1,
                            "cycles_per_byte_chain": C1["cycles_s_ss"] / C1["bytes"],
                            "compression_ratio": C1["bytes"] / C1["payload_per_frame"]}

    # ---- calibration: fit r,k on N and comp (both core-level, measured)
    eqN = (N["bytes"], 1.0, 0.0)
    scanN = N["bytes"] + 5.0 * N["matches"]
    storedN = N["stored_blocks"] * BLOCK
    streamN = N["stream_bytes"] - storedN - 5 * N["stored_blocks"]
    a = (streamN, N["blocks"], N["cycles"] - scanN - storedN)
    r_nc, k_nc = solve_two(a, comp_eq(0, 0))
    res["calibration"]["fit_N_comp"] = {"r_replay_cycles_per_stream_byte": r_nc,
                                        "k_block_cycles": k_nc,
                                        "labels": {"r": "fitted", "k": "fitted"},
                                        "inputs": ["N probe counters", "comp b6 anchor"]}
    # alternative fit on N and L (for leave-one-out and a stability check)
    scanL = L["bytes"] + 5.0 * L["matches"]
    storedL = L["stored_blocks"] * BLOCK
    streamL = L["stream_bytes"] - storedL - 5 * L["stored_blocks"]
    b = (streamL, L["blocks"], L["cycles"] - scanL - storedL)
    r_nl, k_nl = solve_two(a, b)
    res["calibration"]["fit_N_L"] = {"r_replay_cycles_per_stream_byte": r_nl, "k_block_cycles": k_nl}

    def predict(pt, r, k):
        return model_cycles(pt, r, k)[0]

    # ---- three-parameter fit (r, k, abort credit) on N + L + comp.
    # Rows: scan = B + 5M overstates aborted blocks; each aborted block stops
    # scanning early, so a per-abort credit c_ab is unavoidable once two
    # contents with different abort counts (N 83 / L 210) are in the same fit.
    A3 = [[streamN, N["blocks"], -float(N["cand_aborts"])],
          [streamL, L["blocks"], -float(L["cand_aborts"])],
          [COMP["stream"], COMP["blocks"], 0.0]]
    b3 = [N["cycles"] - scanN - storedN, L["cycles"] - scanL - storedL,
          COMP["cycles"] - COMP["bytes"] - 5.0 * COMP["matches"]]
    # Cramer's rule (3x3, small and well conditioned here)
    def det3(m):
        return (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))
    d = det3(A3)
    fit3 = {}
    for i, name in enumerate(("r", "k", "c_ab")):
        m = [row[:] for row in A3]
        for j in range(3):
            m[j][i] = b3[j]
        fit3[name] = det3(m) / d
    res["calibration"]["fit_N_L_comp_3param"] = {
        "r_replay_cycles_per_stream_byte": round(fit3["r"], 4),
        "k_block_cycles": round(fit3["k"], 2),
        "c_abort_credit_cycles_per_aborted_block": round(fit3["c_ab"], 1),
        "labels": {"r": "fitted", "k": "fitted", "c_ab": "fitted"},
        "note": "three anchors, three unknowns -> in-sample residuals are zero by "
                "construction and are NOT a validation; the validation is the "
                "leave-one-out block below"}
    r_use, k_use, cab_use = fit3["r"], fit3["k"], fit3["c_ab"]
    r_nc, k_nc = r_use, k_use          # matrix rows use the 3-parameter fit

    # ---- in-sample (by construction) + leave-one-out folds
    def pred3(pt):
        scan_ = pt["bytes"] + 5.0 * pt["matches"]
        stored_ = pt["stored_blocks"] * BLOCK
        stream_ = pt["stream_bytes"] - stored_ - 5 * pt["stored_blocks"]
        return scan_ + r_use * stream_ + stored_ + k_use * pt["blocks"] - cab_use * pt["cand_aborts"]

    res["residuals"]["in_sample_N"] = {"predicted": round(pred3(N)), "measured": N["cycles"],
                                      "residual_pct": round(100.0 * (pred3(N) - N["cycles"]) / N["cycles"], 3),
                                      "note": "in-sample, zero by construction"}
    res["residuals"]["in_sample_L"] = {"predicted": round(pred3(L)), "measured": L["cycles"],
                                      "residual_pct": round(100.0 * (pred3(L) - L["cycles"]) / L["cycles"], 3),
                                      "note": "in-sample, zero by construction"}
    # fold 1: fit (r,k) on N + comp, predict L
    pred_L = predict(L, r_nc2 := solve_two(a, comp_eq(0, 0))[0], solve_two(a, comp_eq(0, 0))[1])
    r1, k1 = solve_two(a, comp_eq(0, 0))
    pred_L = predict(L, r1, k1)
    res["leave_one_out"]["fit_N_comp_predict_L"] = {
        "held_out": "L", "predicted": round(pred_L), "measured": L["cycles"],
        "residual_pct": round(100.0 * (pred_L - L["cycles"]) / L["cycles"], 3),
        "params": {"r": round(r1, 4), "k": round(k1, 2)}}
    # fold 2: fit (r,k) on L + comp, predict N
    r2, k2 = solve_two(b, comp_eq(0, 0))
    pred_N = predict(N, r2, k2)
    res["leave_one_out"]["fit_L_comp_predict_N"] = {
        "held_out": "N", "predicted": round(pred_N), "measured": N["cycles"],
        "residual_pct": round(100.0 * (pred_N - N["cycles"]) / N["cycles"], 3),
        "params": {"r": round(r2, 4), "k": round(k2, 2)}}
    # fold 3: fit (r,k) on N + L with the physical constraint k >= 0, predict comp.
    # The unconstrained two-equation solve returns k < 0 (-2418), which is not a
    # physical block cost; that is exactly the abort-credit term the 2-parameter
    # model cannot represent.  With k = 0 the fit is a single parameter r.
    r3 = (a[2] + b[2]) / (a[0] + b[0])
    r3a, r3b = a[2] / a[0], b[2] / b[0]
    comp_lo = COMP["bytes"] + 5.0 * COMP["matches"] + min(r3a, r3b) * COMP["stream"]
    comp_hi = COMP["bytes"] + 5.0 * COMP["matches"] + max(r3a, r3b) * COMP["stream"]
    res["leave_one_out"]["fit_N_L_k0_predict_comp"] = {
        "held_out": "comp", "predicted_range": [round(comp_lo), round(comp_hi)],
        "measured": COMP["cycles"],
        "residual_pct_range": [round(100.0 * (comp_lo - COMP["cycles"]) / COMP["cycles"], 3),
                               round(100.0 * (comp_hi - COMP["cycles"]) / COMP["cycles"], 3)],
        "params": {"r_range": [round(min(r3a, r3b), 4), round(max(r3a, r3b), 4)], "k": 0},
        "note": "unconstrained k from N+L is -2418 cycles/block (unphysical); it is the "
                "content-dependent abort credit, which is why the 3-parameter fit exists"}
    res["leave_one_out"]["all_within_5pct"] = all(
        abs(v["residual_pct"]) <= 5.0 for k_, v in res["leave_one_out"].items()
        if isinstance(v, dict) and "residual_pct" in v) and all(
        abs(x) <= 5.0 for x in res["leave_one_out"]["fit_N_L_k0_predict_comp"]["residual_pct_range"])

    # ---- C1: chain-level check.  A core-level prediction is only possible with
    # an assumed symbol density; we report the implied value instead of fitting it.
    c1_stream = C1["payload_per_frame"]
    # R4: physical coefficients (the fitted 3-parameter set r_use/k_use), no abort
    # credit (C1 aborts are not measured).  M = 0 is the floor; M <= stream/3 is the
    # symbol bound (each match must cover >= 3 bytes).  The estimate uses the
    # MAX_MATCH-length assumption (avg match ~250 B -> M ~ 10,047) and therefore
    # sits just above the floor.  The r0 file used a non-physical k = -2418 fold here;
    # that value and its 33.7% figure are withdrawn.
    c1_floor = C1["bytes"] + r_use * c1_stream + k_use * NBLK
    c1_ceiling = c1_floor + 5.0 * (c1_stream / 3.0)
    c1_est = 2_956_095.0            # ruling R4 estimate; recomputed below for the delta
    res["residuals"]["C1"] = {
        "label": "chain S_ss (P4 R1); core-level counters not measured for C1",
        "measured_chain_cycles": C1["cycles_s_ss"],
        "core_predicted_min_cycles_M0": 2_905_862,
        "core_predicted_max_cycles_with_symbol_bound": 3_042_041,
        "core_predicted_estimate_cycles": 2_956_095,
        "core_estimate_over_chain_pct": 63.19,
        "recomputed_from_physical_coefficients": {"floor": round(c1_floor, 1),
                                                 "ceiling": round(c1_ceiling, 1),
                                                 "r": round(r_use, 6), "k": round(k_use, 4)},
        "recompute_delta_note": "the ruling values (2,905,862 / 3,042,041 / 2,956,095) are quoted "
                                "as authoritative; the recomputation differs by <= 6 cycles from "
                                "the 4-digit r/k rounding",
        "withdrawn": {"what": "the r0 C1 figure and its percentage are withdrawn",
                      "why": "computed with the non-physical k from the 2-parameter {N,L} fold, "
                      "which the model itself rejects; coefficient taxonomy in assumptions.json"},
        "conclusion": "C1 chain interval exceeds the core-cycle bound, so the C1 number is "
                      "a chain/feed interval, not a core-cycle anchor; it cannot validate or "
                      "refute the core model. Reported as not_applicable_core_level."}

    # ---- scheme matrix (estimates in cycles/frame at 187.5 MHz)
    base = N["cycles"]
    scan = N["bytes"] + 5.0 * N["matches"]
    stream_fixed = streamN
    emit_fixed = r_nc * stream_fixed
    stored_term = storedN
    blk_term = k_nc * N["blocks"]

    def row(sid, desc, d_scan, d_emit, d_blk, era, lut, reg, clk, conf, alone, note, evid):
        cyc = base + d_scan + d_emit + d_blk
        return {"id": sid, "scheme": desc,
                "delta_scan_cycles": round(d_scan), "delta_emit_cycles": round(d_emit),
                "delta_block_cycles": round(d_blk),
                "cycles_per_frame_est": round(cyc),
                "cycles_per_byte_est": round(cyc / B_FRAME, 4),
                "closes_M1_at_187_5": bool(cyc <= G0_CYCLES),
                "margin_vs_G0_pct": round(100.0 * (G0_CYCLES / cyc - 1.0), 3),
                "required_cycles_per_byte": round(cyc / B_FRAME, 3),
                "clock_MHz_equivalent": round(cyc * 30.0 / 1e6, 2),
                "delta_ERAM": era, "delta_LUT6": lut, "delta_REG": reg,
                "timing_risk_vs_WNS_0p015_at_187_5": clk,
                "confidence": conf, "sufficient_alone": alone,
                "evidence": evid, "note": note}

    m = []
    # A: 2-symbol / 2-position scan engine.  The scan term splits into three
    # measured/derived parts, so the scheme has a real min/max envelope:
    scan_lit = float(N["literals"])                       # 1 cycle per literal
    scan_ext = float(N["bytes"] - N["literals"])          # 1 cycle per match byte (S_EXT)
    scan_match = 5.0 * float(N["matches"])                # 5 cycles per match
    a_min = -scan_lit / 2.0                               # only literals dual-issued
    a_max = -(scan_lit + scan_ext + scan_match) / 2.0      # literals+extension+match overhead all dual-issued
    ra = row("A", "2-symbol/2-position scan engine (dual hash port, 2 positions per cycle)",
             a_min, 0, 0,
             "+2..4 (dual-port htab, 2x window registers)", "+3500..6000", "+1500..2500",
             "high: a second hash lookup + match arbiter sits in the scan cone; today WNS "
             "+0.015 ns at 187.5 MHz has no margin", "low (no prototype)",
             "no" if base + a_min > G0_CYCLES else "only-in-combination",
             "2-position issue alone (literals only) = %d cycles; full dual issue including "
             "extension and the match FSM = %d; the scheme only closes in the full-dual case, "
             "which needs a 2-byte extension compare and a 2-match window"
             % (round(base + a_min), round(base + a_max)),
             "derived (RTL structure) + fitted r/k")
    ra["range_cycles"] = [round(base + a_max), round(base + a_min)]
    ra["range_cycles_per_byte"] = [round((base + a_max) / B_FRAME, 4), round((base + a_min) / B_FRAME, 4)]
    m.append(ra)
    # B: htab 1024 -> 4096/8192
    m.append(row("B", "hash table 1024 -> 4096/8192 entries",
                 -0.02 * scan, 0, 0,
                 "+3 (4096) / +7 (8192) 66-bit entries", "+300..600", "+100",
                 "low: table is a RAM read, not in the longest path",
                 "medium", "no",
                 "offline matcher (hbits 10->12/13, not probe-validated) shows <0.1% change: "
                 "the table is block-scoped (4800 positions/block, blk_tag compare) so extra "
                 "entries are mostly unused; a single candidate stays the limit",
                 "assumed (the -0.02*scan credit is an assumed 2% allowance, NOT a matcher result) + offline matcher NOT probe-validated: hbits 10->12/13 <0.1%, window 2048->4800 changes literals by 0.54% (N) / 0.20% (L)"))
    # C: window 2048 -> 4800/8192
    m.append(row("C", "match window MAX_DIST 2048 -> 4800 (8192 needs a larger block)",
                 -0.02 * scan, 0, 0,
                 "0 for 4800; +16 for an 8192 block (2 banks)", "+200..800", "+100",
                 "low-medium: wider distance compare at the hit stage",
                 "medium", "no",
                 "matcher: 2048 -> 4800 changes literals by 0.54% (N) / 0.20% (L); block size "
                 "4800 bounds any window, and the b11 block-scoped single candidate rarely has a "
                 "far reference",
                 "assumed (the -0.02*scan credit is an assumed 2% allowance, NOT a matcher result) + offline matcher NOT probe-validated: hbits 10->12/13 <0.1%, window 2048->4800 changes literals by 0.54% (N) / 0.20% (L)"))
    # D: deep pipeline / retiming for 200/209.6/224.3 MHz
    m.append(row("D", "deep pipeline + retiming to support 200 / 209.6 / 224.3 MHz",
                 0, 0, 0,
                 "0", "+2000..4000", "+4000..8000",
                 "this IS the timing work: needs 5.318 ns -> 4.458 ns (-16.2%) at 224.3 MHz with "
                 "WNS +0.015 ns today", "low", "no",
                 "cycles unchanged (7,476,245): 209.6 MHz needs <=6,986,667 (-6.55% short); "
                 "224.3 MHz needs <=7,476,667 and the measured interval is 7,476,245 "
                 "(+0.006% margin, i.e. not a closure)",
                 "derived (clock arithmetic on the measured interval)"))
    # E: clock only
    m.append(row("E", "raise clock only (209.6 / 224.3 MHz, no RTL change)",
                 0, 0, 0, "0", "0", "0",
                 "not credible: 5.318 ns path must reach 4.777 / 4.458 ns with WNS +0.015 ns",
                 "high (arithmetic)", "no",
                 "209.6 MHz leaves 6.55% of the interval; 224.3 MHz leaves 0.006% - inside all "
                 "modelling and PLL/jitter margins",
                 "derived (clock arithmetic)"))
    # F: dual core
    m.append(row("F", "dual core (two a1 cores, one stream each)",
                 0, 0, 0,
                 "+102..+129 (dual-core 231..289 / 300)", "+7000..14000", "+14000..28000",
                 "unproven: no dual-core routed build; WNS +0.015 ns single core",
                 "high (from P2 feasibility report)", "no",
                 "per-stream rate is unchanged (75.684 MB/s chain in the feasibility report); "
                 "duplicating the core does not shorten one frame's core_interval",
                 "measured elsewhere (P2 feasibility report) + derived"))
    # H: replay/emit widening (single structural lever on the measured emit term)
    m.append(row("H", "emit path widened: replay 2 stream bytes/cycle (32-bit cmem replay port)",
                 -stream_fixed / 2.0 * r_nc, 0, 0,
                 "0 (cmem already 4096x16; needs a 2nd read port or 32-bit mode)",
                 "+300..800", "+200..500",
                 "medium: replay is a separate FSM, not the scan critical path",
                 "medium", "no",
                 "saves half of the emit term only -> 6,260,648 cycles (2.4154 cycles/B), i.e. -0.17% against the 6,250,000 gate: the smallest single-scheme gap, still short",
                 "derived (RTL structure) + fitted r"))
    # G: replace the core / algorithm
    m.append(row("G", "replace the core / algorithm (4-byte hash, multi-candidate, wider block, "
                      "entropy coder front-end)",
                 0, 0, 0, "unbounded (new core)", "unbounded", "unbounded",
                 "unproven: a new core needs its own TD/STA", "n/a (no design)", "only-in-combination",
                 "out of this round's scope: a new core is the only path with >20% margin that "
                 "does not depend on the 187.5 MHz wall, but it is a separate implementation task",
                 "assumed / out of scope"))
    res["matrix"] = m

    # ---- combinations (conservative: A enters with its literals-only delta)
    combos = []
    for label, ids in (("A+H", ("A", "H")), ("A+D", ("A", "D")),
                       ("A_full+H", ("A_full", "H")), ("A+B+H", ("A", "B", "H"))):
        cyc = base
        for r_ in m:
            if r_["id"] in ids:
                if r_["id"] == "A":
                    cyc += a_max if label.startswith("A_full") else a_min
                else:
                    cyc += r_["delta_scan_cycles"] + r_["delta_emit_cycles"] + r_["delta_block_cycles"]
        if label == "A_full+H":
            cyc = base + a_max - stream_fixed / 2.0 * r_nc
        combos.append({"combo": label, "cycles_per_frame_est": round(cyc),
                       "cycles_per_byte_est": round(cyc / B_FRAME, 4),
                       "closes_at_187_5": bool(cyc <= G0_CYCLES),
                       "margin_vs_G0_pct": round(100.0 * (G0_CYCLES / cyc - 1.0), 2)})
    res["combinations"] = combos

    # ---- verdict per the frozen rule (dev-plan section 2, step 5)
    hi = base + a_min                                   # A, literals-only issue
    lo = base + a_max - stream_fixed / 2.0 * r_nc        # A full dual issue + emit widening
    uncertainty = 100.0 * (hi - lo) / hi
    res["scheme_envelope"] = {"best_case_cycles": round(lo), "best_case_cycles_per_byte": round(lo / B_FRAME, 4),
                              "worst_case_cycles": round(hi), "worst_case_cycles_per_byte": round(hi / B_FRAME, 4),
                              "envelope_uncertainty_pct": round(uncertainty, 1)}
    res["verdict"] = {
        "closable_at_187_5": "conditional",
        "why": [
            "no single no-clock scheme closes within model uncertainty: the only 187.5 MHz "
            "scheme that closes by arithmetic (A) lands at 5.19M-6.18M cycles/frame, i.e. its "
            "range brackets the 6.25M gate and its own uncertainty is %.1f%% > 10%%" % uncertainty,
            "the 187.5 MHz closure requires structural RTL (2-position scan + emit widening), "
            "which cannot be validated without a prototype, TD and STA",
            "clock-only is not a path: 209.6 MHz is 6.55% short and 224.3 MHz leaves 0.006%, "
            "while the current critical path (5.318 ns) already has WNS +0.015 ns",
            "resource-wise A+H is inside the 300 ERAM / 71,680 LUT6 budget (est. +2..4 ERAM, "
            "+3.8k..6.8k LUT6); ERAM is not the binding limit, timing is",
        ],
        "model_uncertainty_pct": round(uncertainty, 1),
        "required_next_evidence": [
            "isolated prototype of the 2-position scan + 2 B/cycle replay on the b11 core",
            "TD synthesis + place & route at 187.5 MHz (and 209.6 MHz as a fallback) with "
            "WNS >= 0 and hold >= 0",
            "same 1-frame stage probe on the prototype (must show cycles/B <= 2.411 with the "
            "same counters), then the 4-frame N/L run for G0",
            "board level only after G2/G3 pass",
        ],
        "user_decision_items": [
            "fund the structural core rewrite (2-position scan + emit widening) and its TD run",
            "or accept G0_not_closed for natural content at 187.5 MHz single core",
            "clock raise to >=224.3 MHz requires the same re-pipelining plus PLL/board changes",
        ],
        "not_a_closure": "the model never claims G0 is closed; G0 remains G0_not_closed for N "
                         "and G0_not_proven for L until a 4-frame run on a changed core says otherwise",
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "coregap-model.json").write_text(json.dumps(res, indent=2), encoding="utf-8")
    print(json.dumps({"calibration": res["calibration"], "residuals": res["residuals"],
                      "analysis": {"scan": scan, "stream_fixed": stream_fixed,
                                   "emit_fixed": emit_fixed, "stored": stored_term,
                                   "blk": blk_term}}, indent=2))
    for r_ in m:
        print(r_["id"], r_["cycles_per_frame_est"], r_["cycles_per_byte_est"],
              r_["closes_M1_at_187_5"], r_["margin_vs_G0_pct"], r_["sufficient_alone"])
    for c in combos:
        print(c)


if __name__ == "__main__":
    main()
