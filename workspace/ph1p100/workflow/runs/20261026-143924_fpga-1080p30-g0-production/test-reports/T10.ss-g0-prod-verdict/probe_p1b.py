import json, os
R = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production"
d = json.load(open(os.path.join(R, "T10.ss-g0-prod-content/r0/out/content-verdict-r1.json"), encoding="utf-8"))["content_classes"]
for k in ("N","L"):
    pf = d[k]["per_frame"]
    print(k, "per_frame keys:", list(pf.keys()))
    print(k, "frame2:", json.dumps(pf["2"], ensure_ascii=False)[:900])
    print(k, "counters:", json.dumps(d[k]["counters"], ensure_ascii=False)[:500])
    print(k, "self_check:", json.dumps(d[k]["self_check"], ensure_ascii=False)[:300], "| drops:", json.dumps(d[k]["drops"], ensure_ascii=False)[:300])
