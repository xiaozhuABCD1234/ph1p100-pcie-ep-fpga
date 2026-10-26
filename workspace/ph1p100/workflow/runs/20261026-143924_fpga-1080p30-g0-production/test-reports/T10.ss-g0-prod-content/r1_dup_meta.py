import json, os, re
RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
buf = []

cv = json.load(open(os.path.join(RUN, "out", "content-verdict-r1.json")))
buf.append("TOP-LEVEL KEYS: " + ", ".join(cv.keys()))
buf.append("dup-related keys: " + str([k for k in cv.keys() if "dup" in k.lower()]))
buf.append("control-related keys: " + str([k for k in cv.keys() if any(w in k.lower() for w in ("control", "neg", "gate"))]))
for k in cv.keys():
    if "dup" in k.lower():
        buf.append(f"[{k}] " + json.dumps(cv[k], ensure_ascii=False, indent=1))
    if "control" in k.lower() or "neg" in k.lower():
        buf.append(f"[{k}] " + json.dumps(cv[k], ensure_ascii=False, indent=1)[:2500])

mod = open(os.path.join(RUN, "src", "a1_ddr_slot_store.v"), encoding="utf-8").read().splitlines()
buf.append("== a1_ddr_slot_store.v read-path port/reg declarations ==")
for i, l in enumerate(mod):
    if re.search(r"(input|output|reg)\b.*(rdata|rd_data|rd_prev|dup)", l) or "st_dup" in l:
        buf.append(f"{i+1}: {l.rstrip()}")

r = open(os.path.join(RUN, "result-r1.md"), encoding="utf-8").read()
buf.append("== result-r1.md : dup / negative-control sections ==")
keep = False
for ln in r.splitlines():
    if re.match(r"^#+ ", ln):
        keep = bool(re.search(r"dup|负对照|负控制|控制", ln, re.I))
    if keep or re.search(r"NEG-|TB_SLOTFREE|93_75_SINK|SYNTHETIC|3FRAMES|G25_AS_G0|MODEL_AS_RTL|AGGREGATE", ln):
        buf.append(ln.rstrip()[:300])

open(os.path.join(OUT, "r1-notes.txt"), "w", encoding="utf-8").write("\n".join(buf))
print("written", len(buf), "lines")
