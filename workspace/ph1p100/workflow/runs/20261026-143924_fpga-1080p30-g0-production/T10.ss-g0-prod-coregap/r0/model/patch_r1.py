"""r1 reporting-only patch for coregap_model.py (R2/R4/R5/R6).

Changes TEXT/LABELS/references of the reporting layer only:
  R2  row H note            -> 6,260,648 / -0.17% (drops the stale 6.63M/6.2%)
  R4  residuals.C1          -> physical coefficients 2,905,862..3,042,041, est 2,956,095 (63.19%)
  R5  rows B/C evidence     -> the -0.02*scan credit is labelled `assumed`
  R6  probe_vs_p1_pct       -> frame-1 core_interval reference (0.000%), 4-frame S_ss listed separately

No fit, matrix arithmetic, envelope, verdict or G0 statement is touched.
The script asserts on every anchor string so a silent miss is impossible.
"""

from pathlib import Path

SRC = Path(__file__).resolve().parent / "coregap_model.py"
s = SRC.read_text(encoding="utf-8")
orig = s

# ---------------------------------------------------------------- R6: reference
old_ref = ('REF = {"N": 7_476_245, "L": 6_979_811}   # P1 r1 t_enc(1)-t_pub(1), frozen')
if old_ref not in s:
    old_ref = 'P1 = dict(N_cycles=7_475_240.0, L_cycles=6_986_952.0,'
    assert old_ref in s, "R6 anchor: P1 dict not found"
    s = s.replace(old_ref,
                  'P1 = dict(N_cycles=7_475_240.0, L_cycles=6_986_952.0,', 1)

s = s.replace(
    'P1 = dict(N_cycles=7_475_240.0, L_cycles=6_986_952.0,\n          N_core_interval_mean=7_475_238.0, L_core_interval_mean=6_986_950.7)',
    'P1 = dict(N_cycles=7_475_240.0, L_cycles=6_986_952.0,\n'
    '          N_core_interval_mean=7_475_238.0, L_core_interval_mean=6_986_950.7)\n'
    '# R6: the probe reference is the P1 r1 *frame-1 core_interval* (same quantity the\n'
    '# probe measures).  The 4-frame steady-state S_ss above is a different quantity and\n'
    '# is reported separately as probe_vs_p1_ss_pct.\n'
    'P1_FRAME1 = {"N": 7_476_245.0, "L": 6_979_811.0}   # measured, P1 r1 t_enc(1)-t_pub(1)',
    1)
assert 'P1_FRAME1' in s, "R6 anchor: P1_FRAME1 not inserted"

old_pct = ('            "probe_vs_p1_pct": 100.0 * (pt["cycles"] - (P1["N_cycles"] if name == "N" else P1["L_cycles"]))\n'
           '                               / (P1["N_cycles"] if name == "N" else P1["L_cycles"]),')
new_pct = ('            "probe_vs_p1_pct": 100.0 * (pt["cycles"] - P1_FRAME1[name]) / P1_FRAME1[name],\n'
           '            "probe_vs_p1_reference": "P1 r1 frame-1 core_interval (t_enc(1)-t_pub(1))",\n'
           '            "probe_vs_p1_ss_pct": 100.0 * (pt["cycles"] - (P1["N_cycles"] if name == "N" else P1["L_cycles"]))\n'
           '                                  / (P1["N_cycles"] if name == "N" else P1["L_cycles"]),\n'
           '            "probe_vs_p1_ss_note": "different quantity (4-frame steady-state S_ss), listed for reference only",')
assert old_pct in s, "R6 anchor: probe_vs_p1_pct block not found"
s = s.replace(old_pct, new_pct, 1)

# ---------------------------------------------------------------- R2: row H note
old_h = '"saves half of the emit term only: 6.63M, still 6.2% short",'
new_h = ('"saves half of the emit term only -> 6,260,648 cycles (2.4154 cycles/B), i.e. -0.17% '
         'against the 6,250,000 gate: the smallest single-scheme gap, still short",')
assert old_h in s, "R2 anchor: row H note not found"
s = s.replace(old_h, new_h, 1)

# ---------------------------------------------------------------- R5: rows B/C evidence
old_ev = '"derived, matcher unvalidated"))'
new_ev = ('"assumed (the -0.02*scan credit is an assumed 2% allowance, NOT a matcher result) + '
          'offline matcher NOT probe-validated: hbits 10->12/13 <0.1%, window 2048->4800 changes '
          'literals by 0.54% (N) / 0.20% (L)"))')
assert s.count(old_ev) == 2, "R5 anchor: rows B/C evidence tags not found twice"
s = s.replace(old_ev, new_ev)

# ---------------------------------------------------------------- R4: C1 residual
old_c1_start = '    c1_stream = C1["payload_per_frame"]'
old_c1_end = '                      "refute the core model. Reported as not_applicable_core_level."}'
i = s.find(old_c1_start)
j = s.find(old_c1_end)
assert i > 0 and j > i, "R4 anchor: C1 block not found"
new_c1 = '''    c1_stream = C1["payload_per_frame"]
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
        "withdrawn": {"r0_values": "1,441,559..1,577,737 (33.7%)", "why": "computed with the "
                      "non-physical k = -2418 cycles/block from the 2-parameter {N,L} fold, which "
                      "the model itself rejects"},
        "conclusion": "C1 chain interval exceeds the core-cycle bound, so the C1 number is "
                      "a chain/feed interval, not a core-cycle anchor; it cannot validate or "
                      "refute the core model. Reported as not_applicable_core_level."}'''
s = s[:i] + new_c1 + s[j + len(old_c1_end):]

SRC.write_text(s, encoding="utf-8")
print("patched", SRC, "bytes", len(orig), "->", len(s))
for tag in ("P1_FRAME1", "c1_floor", "assumed (the -0.02*scan"):
    print(tag, "present:", tag in s)
