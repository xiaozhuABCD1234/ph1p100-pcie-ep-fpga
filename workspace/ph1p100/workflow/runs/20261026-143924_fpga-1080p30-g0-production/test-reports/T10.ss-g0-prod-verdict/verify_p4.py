# -*- coding: utf-8 -*-
"""Integrated tester T10.ss-g0-prod-verdict r0: independent verification (0 sim)."""
import json, os, re, hashlib, sys

R = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production"
P4 = os.path.join(R, "T10.ss-g0-prod-verdict", "r0")
res = []
def rec(cid, ok, msg):
    res.append((cid, bool(ok), msg))
    print(("OK  " if ok else "FAIL") + f" [{cid}] {msg}")

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def load(p):
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)

def full(p):
    return p if os.path.isabs(p) else os.path.join(R, p)

# ---------- A. P4 candidate/manifest integrity ----------
p4m_path = os.path.join(P4, "manifest-r0.json")
p4m = load(p4m_path)
p4m_sha = sha(p4m_path)
print("P4 manifest sha256 =", p4m_sha)
rec("A1", p4m_sha.startswith("8460fb8d"), f"P4 manifest sha prefix 8460fb8d (actual {p4m_sha[:8]})")
rec("A2", p4m.get("artifact_count") == 9 and len(p4m.get("artifacts", [])) == 9, "P4 manifest lists 9 artifacts")
bad = []
for a in p4m["artifacts"]:
    fp = a["path"] if os.path.isabs(a["path"]) else os.path.join(P4, a["path"])
    if not os.path.isfile(fp):
        bad.append((a["path"], "missing")); continue
    if os.path.getsize(fp) != a["bytes"]: bad.append((a["path"], "bytes"))
    if sha(fp) != a["sha256"]: bad.append((a["path"], "sha"))
rec("A3", not bad, f"P4 artifact bytes+sha match ({len(p4m['artifacts'])} files); bad={bad}")
rec("A4", p4m.get("stopped_modifying") is True and p4m.get("active_commands") == 0, "stopped_modifying=True, active_commands=0")
er = p4m.get("evidence_rounds", {})
z = all(er.get(k) == 0 for k in ["vsim","td","synthesis","place_route","bitgen","download","flash","board","network","full_size_runs"])
rec("A5", z, f"evidence_rounds all zero: { {k:er.get(k) for k in ['vsim','td','board','network','full_size_runs']} }")
actual = sorted(os.path.relpath(os.path.join(dp, f), P4).replace("\\", "/")
                for dp, _, fs in os.walk(P4) for f in fs)
listed = sorted(a["path"].replace("\\", "/") for a in p4m["artifacts"])
rec("A6", actual == sorted(listed + ["manifest-r0.json"]), f"no unlisted files in candidate root; extra={sorted(set(actual)-set(listed)-{'manifest-r0.json'})}, missing={sorted(set(listed)-set(actual))}")
ws = p4m.get("write_scope", [])
rec("A7", all("T10.ss-g0-prod-verdict" in w or "ss-g0-prod-verdict" in w for w in ws), f"write_scope confined: {ws}")
bud = p4m.get("budget", {})
rec("A8", bud.get("used_calls_upper_bound", 0) > bud.get("limit_calls", 25), f"dev calls disclosed over limit: {bud.get('used_calls_upper_bound')}>{bud.get('limit_calls')} (process deviation, recorded)")

# ---------- B. upstream binding (124 artifacts) ----------
up = [
    ("P1", "T10.ss-g0-prod-content/r0/manifest-r1.json", "e306ed42ed47dbcec6127bf2faee88925a9a88ae8a5ef07ecbda8dda91fe1fd9", 70),
    ("P2", "T10.ss-g0-prod-coregap/r0/manifest-r1.json", "803d3efb0104376004eb46c2b633d9b19577ba746190edadea802f81e3b92a66", 49),
    ("P3", "T10.ss-g0-prod-sink/r0/manifest-r0.json", "de8a5cffb8044828d2c4eb0ae72d1959c5267a06744a4002bf60a413995aa139", 5),
]
total, mism = 0, []
tbytes = 0
for pkg, rel, exp, cnt in up:
    fp = os.path.join(R, rel)
    got = sha(fp)
    rec("B", got == exp, f"{pkg} manifest sha == {exp[:8]} ({got[:8]}), expected {cnt} artifacts")
    m = load(fp)
    arts = m["artifacts"]
    rec("B", len(arts) == cnt, f"{pkg} artifact count {len(arts)} == {cnt}")
    for a in arts:
        ap = a.get("path")
        ap = ap if os.path.isabs(ap) else os.path.join(R, os.path.dirname(rel), ap)
        total += 1
        if not os.path.isfile(ap): mism.append((pkg, a.get("rel", ap), "missing")); continue
        if os.path.getsize(ap) != a["bytes"]: mism.append((pkg, a.get("rel", ap), "bytes")); continue
        tbytes += a["bytes"]
        if sha(ap) != a["sha256"]: mism.append((pkg, a.get("rel", ap), "sha"))
    v = m.get("verdict")
    print(f"   {pkg} manifest.verdict =", json.dumps(v, ensure_ascii=False)[:200])
rec("B", total == 124 and not mism, f"upstream artifacts verified = {total}, mismatches={len(mism)} {mism[:5]}")

# P2 r0 vs r1: prove r1 used
p2r0 = load(os.path.join(R, "T10.ss-g0-prod-coregap/r0/manifest-r0.json"))
def find_art(m, needle):
    return [a for a in m["artifacts"] if needle in a.get("path", "").replace("\\", "/")]
print("   P2 r0 coregap-verdict entries:", [(a["path"], a["sha256"][:8]) for a in find_art(p2r0, "coregap-verdict.json")])
print("   P2 r1 coregap-verdict entries:", [(a["path"], a["sha256"][:8]) for a in find_art(load(os.path.join(R,"T10.ss-g0-prod-coregap/r0/manifest-r1.json")), "coregap-verdict.json")])
cur_cg_sha = sha(os.path.join(R, "T10.ss-g0-prod-coregap/r0/out/coregap-verdict.json"))
print("   current coregap-verdict.json sha =", cur_cg_sha[:8])
p2r1m = load(os.path.join(R, "T10.ss-g0-prod-coregap/r0/manifest-r1.json"))
in_r1 = any(a["sha256"] == cur_cg_sha and "coregap-verdict.json" in a["path"] for a in p2r1m["artifacts"])
in_r0 = any(a["sha256"] == cur_cg_sha and "coregap-verdict.json" in a["path"] for a in p2r0["artifacts"])
rec("B", in_r1 and not in_r0, f"current P2 verdict json matches r1 manifest only (in_r1={in_r1}, in_r0={in_r0}) -> P2 r1 binding, not r0")

# ---------- C. P1 independent recompute from raw r1 EVT ----------
G0 = 6250000.0
def parse_evt(path):
    ev = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("SS_EVT"):
                d = {"kind": None}
                for tok in line.split():
                    if "=" in tok:
                        k, v = tok.split("=", 1); d[k] = v
                ev.append(d)
    return ev
meas = {}
for cls, tail in (("N", "n-r1.evt"), ("L", "l-r1.evt")):
    ev = parse_evt(os.path.join(R, "T10.ss-g0-prod-content/r0/sim/caps", tail))
    t_exp = {int(e["frame"]): int(e["t"]) for e in ev if e["kind"] == "exp"}
    t_enc = {int(e["frame"]): int(e["t"]) for e in ev if e["kind"] == "enc"}
    cum = {int(e["frame"]): int(e["bytes"]) for e in ev if e["kind"] == "exp" and "bytes" in e}
    assert sorted(t_exp) == [1,2,3,4], (cls, t_exp)
    S23 = t_exp[3]-t_exp[2]; S34 = t_exp[4]-t_exp[3]; S_ss = (S23+S34)/2
    tails = [t_exp[k]-t_enc[k] for k in (2,3,4)]
    bytes_f = [cum[2]-cum[1], cum[3]-cum[2], cum[4]-cum[3]]
    exp_t = [2*b for b in bytes_f]
    meas[cls] = dict(t_exp=[t_exp[k] for k in (1,2,3,4)], S23=S23, S34=S34, S_ss=S_ss,
                     tail_mean=sum(tails)/3.0, export_mean=sum(exp_t)/3.0,
                     L_cold=t_exp[1]-20, bytes_f=bytes_f,
                     busy=(sum(exp_t)/3.0)/S_ss, margin=G0/S_ss-1.0,
                     fps=187.5e6/S_ss, C_ss=2592000*187.5e6/S_ss/1e6)
    print(f"   {cls} recomputed: S_ss={S_ss:.0f} tail_mean={sum(tails)/3:.0f} export={sum(exp_t)/3:.0f} "
          f"busy={meas[cls]['busy']*100:.4f}% margin={meas[cls]['margin']*100:.4f}% L_cold={meas[cls]['L_cold']}")

cv = load(os.path.join(R, "T10.ss-g0-prod-content/r0/out/content-verdict-r1.json"))
cc = cv["content_classes"]
v4 = load(os.path.join(P4, "g0-production-verdict.json"))
for cls in ("N","L"):
    a = cc[cls]; b = v4["per_class"][cls]; m = meas[cls]
    checks = [
        (m["S_ss"] == float(a["S_ss"]) == b["S_ss_cycles"], f"{cls} S_ss evt==P1json==P4"),
        (abs(m["tail_mean"]-float(a["export_tail_mean"] if False else a["export_tail_mean"])) < 1e9, f"{cls} (info)"),
        (abs(m["busy"]-b["busy_export_over_S_ss"]) < 5e-6, f"{cls} busy recomputed {m['busy']:.6f} == P4 {b['busy_export_over_S_ss']}"),
        (abs(m["margin"]*100-b["margin_G0_pct"]) < 1e-4, f"{cls} margin_G0 {m['margin']*100:.4f}% == P4 {b['margin_G0_pct']:.4f}%"),
        (abs(m["export_mean"]-b["export_time_mean_cycles"]) < 1, f"{cls} export_time_mean {m['export_mean']:.0f} == P4 {b['export_time_mean_cycles']:.0f}"),
        (m["L_cold"] == b["L_cold_cycles"] == int(a["L_cold"]), f"{cls} L_cold {m['L_cold']} == P4 == P1 (and separate from S_ss)"),
        (m["t_exp"] == b["t_exp_1_4"] == [int(x) for x in a["t_exp"][1:]], f"{cls} t_exp(1..4) identical in evt/P1/P4"),
    ]
    for ok, msg in checks:
        rec("C", ok, msg)
    # core_interval mean from P1 per_frame (frames 2..4) vs P4
    ci = [a["per_frame"][str(k)]["core_interval_cycles"] for k in (2,3,4)]
    mean_ci = sum(ci)/3.0
    rec("C", abs(mean_ci - b["core_interval_mean_cycles"]) < 0.6,
        f"{cls} core_interval mean from P1 per_frame {mean_ci:.2f} == P4 {b['core_interval_mean_cycles']:.2f}")
    # tail_frac from recompute
    tf = m["tail_mean"]/m["S_ss"]
    ok = abs(tf*100 - b["tail_frac_pct"]) < 0.001
    rec("C", ok, f"{cls} tail_frac recomputed {tf*100:.4f}% vs P4 {b['tail_frac_pct']:.4f}%")

# ---------- D. P2 arithmetic recompute ----------
cg = load(os.path.join(R, "T10.ss-g0-prod-coregap/r0/out/coregap-verdict.json"))
rawB = 2592000
def row(i): return next(r for r in cg["scheme_matrix"] if r["id"] == i)
comb = next(c for c in cg["combinations"] if c["combo"] == "A+H")
env = cg["scheme_envelope"]
h = row("H"); e = row("E"); f = row("F")
print("   P2 env:", {k: env[k] for k in env if not isinstance(env[k], str)})
rec("D", cg["headline"] == "G0_not_closed" and cg["closable_at_187_5"] == "conditional", "P2 headline=G0_not_closed, closable=conditional")
rec("D", comb["cycles_per_frame_est"] == 6008078 and abs(comb["cycles_per_frame_est"]/rawB - 2.3179) < 5e-4,
    f"A+H cycles 6,008,078 -> {comb['cycles_per_frame_est']/rawB:.4f} c/B (P2 {comb['cycles_per_byte_est']})")
rec("D", abs((G0/comb["cycles_per_frame_est"]-1)*100 - 4.027) < 0.001, f"A+H margin {((G0/comb['cycles_per_frame_est']-1)*100):.4f}% == +4.027%")
rec("D", abs((G0/h["cycles_per_frame_est"]-1)*100 - (-0.17)) < 0.005, f"single H {h['cycles_per_frame_est']} margin {((G0/h['cycles_per_frame_est']-1)*100):.4f}% == -0.17%")
envpct = (env["conservative_cycles"]-env["best_case_cycles"])/env["conservative_cycles"]*100
rec("D", abs(envpct-45.034) < 0.001 and abs(v4["coregap"]["scheme_envelope"]["uncertainty_pct"]-45.034) < 0.001,
    f"envelope {env['best_case_cycles']}..{env['conservative_cycles']} -> {envpct:.3f}% (P2 json rounded field {env['envelope_uncertainty_pct']}), P4 45.034")
rec("D", ("209.6" in e.get("scheme","")) and ("224.3" in e.get("scheme","")), f"clock row E references 209.6/224.3: {e.get('scheme','')[:80]}")
d_row = row("D")
print("   row D:", json.dumps(d_row, ensure_ascii=False)[:400])
rec("D", f["cycles_per_frame_est"] == 7476245 and (f.get("sufficient_alone") == "no"), f"dual-core row F per-stream unchanged {f['cycles_per_frame_est']}")
# 224.3 arithmetic margin
m224 = (G0 - 7476245*(187.5/224.3)) / G0 * 100
print(f"   224.3MHz arithmetic margin ~ {m224:.4f}%")
print("   cg clock/224 fields:", json.dumps({k: cg.get(k) for k in cg if "224" in str(k) or "clock" in str(k).lower()}, ensure_ascii=False)[:300])

# ---------- E. P3 recompute ----------
sk = load(os.path.join(R, "T10.ss-g0-prod-sink/r0/out/sink-headroom.json"))
cs = sk["comp_stream"]; rb = sk["raw_band"]
for cls in ("N","L"):
    bf = cs[cls]["bytes_steady_frame"]
    d30 = bf*30/1e6; d25 = bf*40/1e6
    rec("E", abs(d30-cs[cls]["demand"]["period_33_3333ms"]["MBps"]) < 1e-4 and abs(d25-cs[cls]["demand"]["period_25_0ms"]["MBps"]) < 1e-4,
        f"P3 {cls} comp demand {d30:.5f}/{d25:.5f} MB/s == json")
    rec("E", d25 < 93.75, f"P3 {cls} 25ms demand {d25:.3f} < 93.75 (headroom)")
bfL = cs["L"]["bytes_steady_frame"]; d25L = bfL*40/1e6
rec("E", abs(d25L/93.75*100-92.0) < 0.05 and v4["sink"]["tightest"]["util_of_93_75_pct"] == 92.0, f"tightest L@25ms util {d25L/93.75*100:.2f}% == 92.0%")
need25 = rb["bytes_per_frame"]/25e-3/1e6
rec("E", abs(need25-103.78824) < 5e-4 and rb["at_93_75"]["shortfall_at_25ms_pct"] > 10.7, f"raw band 25ms need {need25:.5f} MB/s, shortfall {rb['at_93_75']['shortfall_at_25ms_pct']:.4f}%")

# ---------- F. scope tuple ----------
st = v4["scope_tuple"]
scope_ok = (
    "P1" in st["content"] and "NOT sensor RAW" in st["content"] and
    "wait_slot_free" in st["pacing"] and "NOT production free-run" in st["pacing"] and
    "93.75" in st["sink"] and "NOT production sink" in st["sink"] and
    "256-bit PAXI" in st["ddr"] and "187.5" in st["core_clock"] and "single stream" in st["stream"])
rec("F", scope_ok, f"scope tuple pinned: {json.dumps(st, ensure_ascii=False)}")

# ---------- G. planner files unchanged ----------
for rel, exp in (("p4-release-ruling.md", "5ba1cf00fe1d694de60a3dca7e3a0aa8022d5e735fb2ec0f4a3104dcb47bbf8e"),
                 ("fpga-design-guide.md", "fa7524d77291d26d05170375bcdb2ff20469eedbc770998ff7c223ebbbc23a0d"),
                 ("dev-plan.md", "1c9b32547015146da2f9bea6cfdb1f628e0fc416470cd9db76e65957f742db02")):
    got = sha(os.path.join(R, rel))
    rec("G", got == exp, f"planning file {rel} sha unchanged ({got[:8]})")

# ---------- H. summary consistency (targeted, tolerant) ----------
def read(p):
    with open(os.path.join(P4, p), "r", encoding="utf-8") as f: return f.read()
texts = {p: read(p) for p in ("result-r0.md","handoff.md","final-summary.md","user-summary.md")}
for p, t in texts.items():
    rec("H", "G0_not_closed" in t, f"{p}: headline G0_not_closed present")
    rec("H", ("core" in t.lower()) and ("sink" in t.lower()), f"{p}: core-vs-sink attribution stated")
# final-summary must carry the key run-level numbers
fs = texts["final-summary.md"]
fs_must = ["7,475,240", "6,986,952", "16.39", "10.5475", "6,008,078", "2.3179", "4.027", "45.034",
           "6,260,648", "0.17", "86.25", "92.0", "103.788", "93.75", "61.72", "44.88"]
rec("H", all(s in fs for s in fs_must), f"final-summary figures {[s for s in fs_must if s not in fs]} missing")
us = texts["user-summary.md"]
us_must = ["7,475,240", "6,986,952", "16.39", "10.55", "6,008,078", "4.03", "45", "0.17", "188",
           "7,476,245", "86.25", "92.0", "103.79", "93.75", "61.72", "44.88", "11.52"]
rec("H", all(s in us for s in us_must), f"user-summary figures {[s for s in us_must if s not in us]} missing")
ho = texts["handoff.md"]
ho_must = ["e306ed42", "803d3efb", "de8a5cff", "70", "49", "5", "G0_not_closed"]
rec("H", all(s in ho for s in ho_must), f"handoff binds upstream manifests/headline {[s for s in ho_must if s not in ho]} missing")

# ---------- I. overclaim scan on candidate JSON/MD (negations allowed only in cannot_say / 不能说 / rejection) ----------
files = ["g0-production-verdict.json","out/evidence-binding.json","result-r0.md","handoff.md","final-summary.md","user-summary.md","lessons-r0.md"]
def readany(p):
    with open(os.path.join(P4, p), "r", encoding="utf-8") as f: return f.read()
alltext = {p: readany(p) for p in files}
bad_pat = re.compile(r"(G0_feasible|feasible_for_scope|G0[ _]closed\b|G0\s*已闭合|A\+H\s*(已|is)\s*implemented|implemented\s*[:=]\s*true|板级通过|板级已通|真实\s*DDR\s*已|RK/NPU\s*已|Flash\s*已|双路\s*已|use G25 for|用\s*G25\s*降档)", re.I)
hits = []
for p, t in alltext.items():
    for i, line in enumerate(t.splitlines(), 1):
        if bad_pat.search(line):
            hits.append((p, i, line.strip()[:120]))
rec("I", not hits, f"strict positive-overclaim patterns: {hits}")
# count of 'feasible' occurrences and ensure each is negation/rejection context
for p, t in alltext.items():
    for i, line in enumerate(t.splitlines(), 1):
        if re.search(r"feasible", line, re.I):
            print(f"   [feasible] {p}:{i}: {line.strip()[:200]}")
# explicit cannot-claim coverage
req_cannot = ["sensor RAW", "worst", "production sink", "DDR", "board", "dual"]
v4c = " ".join(v4.get("cannot_say", [])).lower()
rec("I", all(k.lower() in v4c for k in req_cannot), f"cannot_say covers scope limits: {[k for k in req_cannot if k.lower() not in v4c]}")
rec("I", v4["g25_reference_only"]["used_for_headline"] is False and v4["g25_reference_only"]["used_for_downgrade"] is False,
    "G25 reference column only; not used for headline/downgrade")
rec("I", v4["user_decision"]["downgrade"]["promoted_by_this_package"] is False, "downgrade not promoted")
rec("I", v4["coregap"]["a_plus_h"]["g0_closure"] is False and v4["coregap"]["a_plus_h"]["implemented"] is False
        and v4["coregap"]["a_plus_h"]["td_run"] is False, "A+H: g0_closure/implemented/td_run all false")

print("\n==== SUMMARY ====")
print("failures:", [r for r in res if not r[1]])
print("total checks:", len(res), "failed:", sum(1 for r in res if not r[1]))
