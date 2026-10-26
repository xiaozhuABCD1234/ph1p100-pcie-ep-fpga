import json, os, glob
R = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production"
# extra files in upstream package roots vs manifests
for pkg, mrel in (("T10.ss-g0-prod-content","T10.ss-g0-prod-content/r0/manifest-r1.json"),
                  ("T10.ss-g0-prod-coregap","T10.ss-g0-prod-coregap/r0/manifest-r1.json"),
                  ("T10.ss-g0-prod-sink","T10.ss-g0-prod-sink/r0/manifest-r0.json")):
    m = json.load(open(os.path.join(R, mrel), encoding="utf-8"))
    root = os.path.join(R, pkg, "r0")
    listed = set()
    for a in m["artifacts"]:
        p = a["path"]
        if os.path.isabs(p):
            try: rel = os.path.relpath(p, root).replace("\\","/")
            except ValueError: rel = p
        else:
            rel = p.replace("\\","/")
        listed.add(rel)
    actual = set(os.path.relpath(os.path.join(dp,f), root).replace("\\","/")
                 for dp,_,fs in os.walk(root) for f in fs)
    print(pkg, "listed", len(listed), "actual", len(actual))
    print("  unlisted:", sorted(actual - listed)[:15])
    print("  listed-missing:", sorted(listed - actual)[:5])

# P2 rows
cg = json.load(open(os.path.join(R,"T10.ss-g0-prod-coregap/r0/out/coregap-verdict.json"), encoding="utf-8"))
for rid in ("D","E","F","H"):
    r = next(x for x in cg["scheme_matrix"] if x["id"]==rid)
    print("ROW", rid, json.dumps({k:r.get(k) for k in ("scheme","cycles_per_frame_est","margin_vs_G0_pct","sufficient_alone","confidence")}, ensure_ascii=False))
print("combos:", json.dumps(cg["combinations"], ensure_ascii=False))
print("closable:", cg["closable_at_187_5"], "| model:", json.dumps(cg.get("model"), ensure_ascii=False)[:400])
print("not_closure_evidence:", json.dumps(cg.get("not_closure_evidence"), ensure_ascii=False)[:600])
G0=6250000.0
scaled=7476245*187.5/224.3
print("224.3 scaled cycles:", scaled, "margin_pct", (G0-scaled)/G0*100)
scaled209=7476245*187.5/209.6
print("209.6 scaled cycles:", scaled209, "margin_pct", (G0-scaled209)/G0*100)
print("WNS implied MHz:", 1e3/(5.333333-0.015))
