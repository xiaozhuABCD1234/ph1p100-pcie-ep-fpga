"""Independent tester recomputation for T10.ss-g0-prod-coregap r0.

Nothing here is imported from the developer's model.  Inputs are the frozen
raw logs / counters (dev probe logs, tester-owned probe log, P1 r1 evt files)
and the frozen comp anchor quoted in dev-plan section 2.
"""
import json, re, sys
from pathlib import Path

RUN = Path(r"D:/fpga/ph1p100/workflow/runs/20261026-143924_fpga-1080p30-g0-production")
P2 = RUN / "T10.ss-g0-prod-coregap/r0"
P1 = RUN / "T10.ss-g0-prod-content/r0"
EV = RUN / "test-reports/T10.ss-g0-prod-coregap"
B = 2_592_000
BLK = 4800
G0 = 6_250_000.0
CPB = G0 / B

out = {"target_cycles_per_byte": CPB}

# ---------- 1. own parser ---------------------------------------------------
def parse_core_stage(log):
    txt = Path(log).read_text(errors="replace")
    m = None
    for line in txt.splitlines():
        if "CORE_STAGE" in line:
            m = dict(re.findall(r"(\w+)=(-?\d+)", line))
    if not m:
        return None
    ev = {}
    for line in txt.splitlines():
        if "SS_EVT" in line and "kind=" in line:
            kind = re.search(r"kind=(\w+)", line).group(1)
            fr = int(re.search(r"frame=(\d+)", line).group(1))
            ev.setdefault(kind, {})[fr] = int(re.search(r"\bt=(\d+)", line).group(1))
    return {
        "t_core_stage": int(m["t"]), "blocks": int(m["blocks"]), "fixed": int(m["fixed"]),
        "stored": int(m["stored"]), "literals": int(m["literals"]), "matches": int(m["matches"]),
        "cand_aborts": int(m["cand_aborts"]), "stall": int(m["stall"]),
        "max_match": int(m["max_match"]), "max_dist": int(m["max_dist"]),
        "t_pub1": int(m["t_pub1"]), "t_enc1": int(m["t_enc1"]),
        "core_interval": int(m["core_interval"]),
        "check_interval": int(m["t_enc1"]) - int(m["t_pub1"]),
        "exp_bytes": int(m["exp_bytes"]),
        "raw_match_ok": "SS_RAW_MATCH bad=0 checked=518400" in txt,
        "errors_0": "Errors: 0," in txt,
        "stall_marker": ("SS_STALL" in txt) or ("SS_STALL_COLD" in txt),
        "timeout": "B11_FULL_TIMEOUT" in txt,
        "exp_bytes_evt": int(ev.get("exp", {}).get("1", -1)) if "exp" in ev else None,
        "bytes_exp": None,
    }

def exp_bytes(log):
    for line in Path(log).read_text(errors="replace").splitlines():
        if "kind=exp" in line and "bytes=" in line:
            return int(re.search(r"bytes=(\d+)", line).group(1))
    return None

probes = {}
for name, log in (("N", P2 / "sim/logs/n-probe.log"), ("L", P2 / "sim/logs/l-probe.log"),
                  ("N_tester", EV / "tester-n-probe.log")):
    p = parse_core_stage(log)
    assert p, f"no CORE_STAGE in {log}"
    p["bytes_exp"] = exp_bytes(log)
    p["frame_bytes"] = B
    probes[name] = p
out["probes"] = probes

# ---------- 2. P1 r1 frame-1 reference (independent parse) ------------------
def parse_evt(evt):
    d = {}
    for line in Path(evt).read_text().splitlines():
        if "SS_EVT" in line and "kind=" in line:
            kind = re.search(r"kind=(\w+)", line).group(1)
            fr = re.search(r"frame=(\d+)", line).group(1)
            d.setdefault(kind, {})[fr] = int(re.search(r"\bt=(\d+)", line).group(1))
    return d

p1 = {c: parse_evt(P1 / f"sim/caps/{c}-r1.evt") for c in ("n", "l")}
ref = {}
for c, key in (("n", "N"), ("l", "L")):
    e = p1[c]
    ref[key] = {
        "frame1_core_interval": e["enc"]["1"] - e["pub"]["1"],
        "t_pub1": e["pub"]["1"], "t_enc1": e["enc"]["1"],
        "exp": [e["exp"][k] for k in ("1", "2", "3", "4")],
    }
for key, c in (("N", "n"), ("L", "l")):
    e = p1[c]["exp"]
    s23, s34 = e["3"] - e["2"], e["4"] - e["3"]
    ref[key]["S_23"], ref[key]["S_34"] = s23, s34
    ref[key]["S_ss"] = (s23 + s34) / 2.0
    ref[key]["G0_margin_pct"] = 100 * (G0 / ref[key]["S_ss"] - 1)
out["p1_r1_reference"] = ref
for key in ("N", "L"):
    r = ref[key]
    for who in (key, f"{key}_tester" if f"{key}_tester" in probes else None):
        if who and who in probes:
            probes[who]["p1_frame1_ref"] = r["frame1_core_interval"]
            probes[who]["dev_pct"] = 100.0 * (probes[who]["core_interval"] / r["frame1_core_interval"] - 1)
# cross-check tester vs dev
probes["N_tester"]["dev_probe_pct"] = 100.0 * (probes["N_tester"]["core_interval"] / probes["N"]["core_interval"] - 1)

# ---------- 3. model refit (own linear algebra) -----------------------------
COMP = dict(bytes=153_600, cycles=355_261, stream=50_310, matches=19_328, blocks=153_600 // BLK)
COMP["blocks"] = 32

def non_scan_terms(p):
    scan = p["frame_bytes"] + 5.0 * p["matches"]
    stored = p["stored"] * BLK
    stream_fixed = p["bytes_exp"] - stored - 5 * p["stored"]
    return scan, stored, stream_fixed

def solve(mat, rhs):
    n = len(rhs)
    a = [row[:] + [rhs[i]] for i, row in enumerate(mat)]
    for i in range(n):
        piv = max(range(i, n), key=lambda r: abs(a[r][i]))
        a[i], a[piv] = a[piv], a[i]
        d = a[i][i]
        a[i] = [v / d for v in a[i]]
        for r in range(n):
            if r != i and a[r][i] != 0:
                f = a[r][i]
                a[r] = [vr - f * vi for vr, vi in zip(a[r], a[i])]
    return [a[i][n] for i in range(n)]

N, L = probes["N"], probes["L"]
scanN, storedN, sfN = non_scan_terms(N)
scanL, storedL, sfL = non_scan_terms(L)
scanC = COMP["bytes"] + 5.0 * COMP["matches"]
rhsN = N["core_interval"] - scanN - storedN
rhsL = L["core_interval"] - scanL - storedL
rhsC = COMP["cycles"] - scanC

# 3-parameter fit (r, k, c_ab)
A = [[sfN, N["blocks"], -N["cand_aborts"]],
     [sfL, L["blocks"], -L["cand_aborts"]],
     [COMP["stream"], COMP["blocks"], -0.0]]
r, k, cab = solve(A, [rhsN, rhsL, rhsC])

def predict(p, r_, k_, cab_, use_abort=True):
    scan, stored, sf = non_scan_terms(p)
    v = scan + r_ * sf + stored + k_ * p["blocks"]
    if use_abort:
        v -= cab_ * p.get("cand_aborts", 0)
    return v

res = {}
for name in ("N", "L"):
    pred = predict(probes[name], r, k, cab)
    res[name] = dict(predicted=pred, measured=probes[name]["core_interval"],
                     residual_pct=100 * (pred / probes[name]["core_interval"] - 1))
COMPp = dict(frame_bytes=COMP["bytes"], matches=COMP["matches"], stored=0,
             bytes_exp=COMP["stream"], blocks=COMP["blocks"], cand_aborts=0,
             core_interval=COMP["cycles"])
pred = predict(COMPp, r, k, cab)
res["comp"] = dict(predicted=pred, measured=COMP["cycles"],
                   residual_pct=100 * (pred / COMP["cycles"] - 1))

# 2-parameter fits for leave-one-out
def fit2(pairs):
    (p1_, b1), (p2_, b2) = pairs
    s1, st1, f1 = non_scan_terms(p1_); s2, st2, f2 = non_scan_terms(p2_)
    return solve([[f1, p1_["blocks"]], [f2, p2_["blocks"]]],
                 [p1_["core_interval"] - s1 - st1, p2_["core_interval"] - s2 - st2])

r_NC, k_NC = fit2([(N, 0), (COMPp, 0)])
r_LC, k_LC = fit2([(L, 0), (COMPp, 0)])
r_NL, k_NL = fit2([(N, 0), (L, 0)])
loo = {}
p = predict(L, r_NC, k_NC, 0, use_abort=False)
loo["fit_N_comp_predict_L"] = dict(predicted=p, measured=L["core_interval"],
                                   residual_pct=100 * (p / L["core_interval"] - 1))
p = predict(N, r_LC, k_LC, 0, use_abort=False)
loo["fit_L_comp_predict_N"] = dict(predicted=p, measured=N["core_interval"],
                                   residual_pct=100 * (p / N["core_interval"] - 1))
r3a = rhsN / sfN
r3b = rhsL / sfL
lo = scanC + min(r3a, r3b) * COMP["stream"]
hi = scanC + max(r3a, r3b) * COMP["stream"]
loo["fit_N_L_k0_predict_comp"] = dict(predicted_range=[lo, hi], measured=COMP["cycles"],
                                      residual_pct_range=[100 * (lo / COMP["cycles"] - 1),
                                                           100 * (hi / COMP["cycles"] - 1)],
                                      r_range=[min(r3a, r3b), max(r3a, r3b)])
out["model_refit"] = dict(r=r, k=k, c_ab=cab,
                          r2par_NC=[r_NC, k_NC], r2par_LC=[r_LC, k_LC], r2par_NL=[r_NL, k_NL],
                          residuals_3par=res, leave_one_out=loo,
                          all_loo_within_5pct=all(abs(v) <= 5 for v in
                              [loo["fit_N_comp_predict_L"]["residual_pct"],
                               loo["fit_L_comp_predict_N"]["residual_pct"]] +
                              loo["fit_N_L_k0_predict_comp"]["residual_pct_range"]),
                          max_abs_residual_3par=max(abs(v["residual_pct"]) for v in res.values()))

# ---------- 4. C1 chain-vs-core (physical coefficients) ---------------------
c1_stream, c1_chain, c1_bytes = 81_707.0, 4_677_970.0, B
# a) physical bound with the 3-parameter fit, M assumed 0 (hard floor) and with
#    the symbol count implied by a 3-byte-minimum coding of the payload
m_lo = 0.0
m_hi = c1_stream / 3.0
core_floor = c1_bytes + r * c1_stream + k * NBLK if False else c1_bytes + r * c1_stream + k * (c1_bytes / BLK)
core_ceiling = c1_bytes + 5.0 * m_hi + r * c1_stream + k * (c1_bytes / BLK)
# b) tighter estimate: max_match=258 -> matches needed to cover the frame
m_est = c1_bytes / 258.0
core_est = c1_bytes + 5.0 * m_est + r * c1_stream + k * (c1_bytes / BLK)
# c) the developer's exhibit (uses the unphysical negative k from the N+L 2-par fit)
dev_floor = c1_bytes + r_NL * c1_stream + k_NL * (c1_bytes / BLK)
out["c1_analysis"] = dict(
    chain_S_ss=c1_chain, physical_core_floor=core_floor, physical_core_ceiling=core_ceiling,
    physical_core_estimate=m_est and core_est,
    physical_estimate_over_chain_pct=100 * core_est / c1_chain,
    dev_exhibit_uses_k_NL=k_NL, dev_exhibit_floor=dev_floor,
    dev_exhibit_over_chain_pct=100 * dev_floor / c1_chain,
    conclusion="chain interval exceeds any core bound => C1 chain S_ss is not a core-cycle anchor; "
               "the dev's 33.7% exhibit is produced with the unphysical k=-2418 and must be replaced "
               "by the physical ~62% figure; the exclusion conclusion itself survives")

# ---------- 5. scheme matrix recomputation ---------------------------------
base = N["core_interval"]
scan = scanN
scan_lit = float(N["literals"])
scan_rest = scan - scan_lit
a_min = -scan_lit / 2.0
a_max = -scan / 2.0
emit_fixed = r * sfN
rows = {}
rows["A"] = base + a_min
rows["A_full"] = base + a_max
rows["B"] = base - 0.02 * scan
rows["C"] = base - 0.02 * scan
rows["D"] = base
rows["E"] = base
rows["F"] = base
rows["H"] = base - emit_fixed / 2.0
rows["G"] = base
combos = {"A+H": base + a_min - emit_fixed / 2.0,
          "A+B+H": base + a_min - 0.02 * scan - emit_fixed / 2.0,
          "A+D": base + a_min,
          "A_full+H": base + a_max - emit_fixed / 2.0}
env_hi, env_lo = base + a_min, base + a_max - emit_fixed / 2.0
out["matrix_recompute"] = dict(
    rows={k_: dict(cycles=v, cpb=v / B, margin_pct=100 * (G0 / v - 1), closes=bool(v <= G0))
          for k_, v in rows.items()},
    combos={k_: dict(cycles=v, cpb=v / B, margin_pct=100 * (G0 / v - 1), closes=bool(v <= G0))
            for k_, v in combos.items()},
    envelope=dict(hi=env_hi, lo=env_lo, uncertainty_pct=100 * (env_hi - env_lo) / env_hi),
    decomposition=dict(scan=scan, emit_fixed=emit_fixed, stored=storedN, blk=k * N["blocks"],
                       abort=-cab * N["cand_aborts"],
                       total=scan + emit_fixed + storedN + k * N["blocks"] - cab * N["cand_aborts"],
                       measured=base),
    clock_checks=dict(
        mhz_209_6_allowed=G0 * 209.6 / 187.5, mhz_209_6_deficit_pct=100 * (G0 * 209.6 / 187.5 / base - 1),
        mhz_224_3_allowed=G0 * 224.3 / 187.5, mhz_224_3_margin_pct=100 * (G0 * 224.3 / 187.5 / base - 1)),
    comp_anchor=dict(cpb=COMP["cycles"] / COMP["bytes"],
                     mbps=COMP["bytes"] / COMP["cycles"] * 187.5),
)

# ---------- 6. compare with frozen json ------------------------------------
fz = json.loads((P2 / "out/coregap-model.json").read_text(encoding="utf-8"))
fzv = json.loads((P2 / "out/coregap-verdict.json").read_text(encoding="utf-8"))
fzrow = {row["id"]: row["cycles_per_frame_est"] for row in fz["matrix"]}
cmp_rows = {}
for key, frozen_id in (("A", "A"), ("B", "B"), ("C", "C"), ("D", "D"), ("E", "E"),
                       ("F", "F"), ("H", "H"), ("G", "G")):
    cmp_rows[key] = dict(tester=round(rows[key]), frozen=fzrow[frozen_id],
                         delta=round(rows[key]) - fzrow[frozen_id])
cmp_combos = {c["combo"]: c["cycles_per_frame_est"] for c in fz["combinations"]}
cmp_combo = {}
for k_ in combos:
    frozen = cmp_combos.get("A_full_dual_issue+H" if k_ == "A_full+H" else k_)
    cmp_combo[k_] = dict(tester=round(combos[k_]), frozen=frozen,
                         delta=(round(combos[k_]) - frozen) if frozen is not None else None)
out["frozen_compare"] = dict(rows=cmp_rows, combos=cmp_combo,
                             frozen_verdict=fzv["closable_at_187_5"],
                             frozen_headline=fzv["headline"],
                             frozen_envelope=fz["scheme_envelope"]["envelope_uncertainty_pct"],
                             frozen_r=fz["calibration"]["fit_N_L_comp_3param"]["r_replay_cycles_per_stream_byte"],
                             frozen_k=fz["calibration"]["fit_N_L_comp_3param"]["k_block_cycles"],
                             frozen_cab=fz["calibration"]["fit_N_L_comp_3param"]["c_abort_credit_cycles_per_aborted_block"])

(EV / "tester-recompute.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
print(json.dumps({k: out[k] for k in ("probes", "p1_r1_reference", "model_refit",
                                      "c1_analysis", "matrix_recompute", "frozen_compare")},
                 indent=1)[:6000])
print("\nwrote", EV / "tester-recompute.json")
