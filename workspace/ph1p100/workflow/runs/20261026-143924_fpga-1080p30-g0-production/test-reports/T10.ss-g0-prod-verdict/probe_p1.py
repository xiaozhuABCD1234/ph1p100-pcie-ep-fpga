import json, os
R = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production"
c = json.load(open(os.path.join(R, "T10.ss-g0-prod-content/r0/out/content-verdict-r1.json"), encoding="utf-8"))["content_classes"]
for k in ("N","L"):
    d = c[k]
    for f in ("t_exp","t_enc","L_cold","L_cold_raw_t_exp1","export_tail_mean","export_tail_per_frame","tail_frac","tail_frac_pct","busy_pct" if "busy_pct" in d else "sink_limited","G0","labels","dup_words"):
        print(k, f, "=", d.get(f))
print("N G0_why:", c["N"].get("G0_why"))
print("L G0_why:", c["L"].get("G0_why"))
print("headline:", json.load(open(os.path.join(R, "T10.ss-g0-prod-content/r0/out/content-verdict-r1.json"), encoding="utf-8")).get("headline"))
