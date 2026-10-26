import json, os
R = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production"
for rel in ("T10.ss-g0-prod-content/r0/manifest-r1.json","T10.ss-g0-prod-coregap/r0/manifest-r1.json","T10.ss-g0-prod-sink/r0/manifest-r0.json"):
    m = json.load(open(os.path.join(R, rel), encoding="utf-8"))
    paths = [a.get("rel") or a.get("path") for a in m["artifacts"]]
    print("==", rel, len(paths))
    print("  ", [p.replace("\\","/") for p in paths][:60])
