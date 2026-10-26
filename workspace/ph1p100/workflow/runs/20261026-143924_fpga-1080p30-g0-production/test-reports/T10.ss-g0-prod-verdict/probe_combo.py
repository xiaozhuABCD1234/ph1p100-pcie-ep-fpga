import json, os
R = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production"
cg = json.load(open(os.path.join(R,"T10.ss-g0-prod-coregap/r0/out/coregap-verdict.json"), encoding="utf-8"))
for c in cg["combinations"]:
    print(json.dumps(c, ensure_ascii=False, indent=1))
print("--- keys per combo:", [list(c.keys()) for c in cg["combinations"]])
