import json, os, re
RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
RUNROOT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production"

cv = json.load(open(os.path.join(RUN, "out", "content-verdict-r1.json")))
print("headline:", cv.get("headline"))
print("P1_answer:", str(cv.get("P1_answer"))[:900])
for cls in ("N", "L"):
    j = cv["content_classes"][cls]
    print(cls, {k: j.get(k) for k in ("A3_complete", "frames_exported", "S_ss", "S_23", "S_34",
                                      "export_tail_mean", "tail_frac", "sink_limited", "L_cold",
                                      "L_cold_raw_t_exp1", "margin_G0_pct", "capacity_MBps", "fps",
                                      "G0", "bottleneck_attribution")})
    print(cls, "per_frame_exp_bytes:", {k: v.get("exp_bytes") for k, v in j.get("per_frame", {}).items()})
print("dup_semantics:", json.dumps(cv.get("dup_semantics"), indent=1)[:1600])
print("controls:", json.dumps(cv.get("negative_controls") or cv.get("controls"), indent=1)[:1200])
print("== run-status-r1 ==")
print(json.dumps(json.load(open(os.path.join(RUN, "out", "run-status-r1.json"))), indent=1)[:1500])
print("== r1-verify (dev self-check) ==")
print(json.dumps(json.load(open(os.path.join(RUN, "out", "r1-verify.json"))), indent=1)[:1200])
print("== commands-r1.jsonl ==")
for i, ln in enumerate(open(os.path.join(RUN, "sim", "commands-r1.jsonl"), encoding="utf-8")):
    j = json.loads(ln)
    print(i, j.get("tag") or j.get("note"), "rc=", j.get("rc"), "s=", j.get("seconds"),
          "timeout=", j.get("timed_out"), "argv0=", os.path.basename(str(j.get("argv", ["?"])[0])),
          "tail=", str(j.get("argv"))[-90:])
print("== guide section 3 raw band ==")
g = open(os.path.join(RUNROOT, "fpga-design-guide.md"), encoding="utf-8").read()
for ln in g.splitlines():
    if "4,687,500" in ln or "5,000,000" in ln or "103.79" in ln or "WD_LIMIT" in ln:
        print("  ", ln.strip()[:220])
print("== result-r1 supersede / A3 statements ==")
r = open(os.path.join(RUN, "result-r1.md"), encoding="utf-8").read()
for ln in r.splitlines():
    if any(k in ln for k in ("supersede", "取代", "dup", "A3", "G0", "L_cold", "not_closed", "not_proven")):
        print("  ", ln.strip()[:200])
print("== fpga/ modified today ==")
import time
cut = time.mktime(time.strptime("2026-10-26 00:00", "%Y-%m-%d %H:%M"))
hits = []
for dp, dn, fn in os.walk(r"D:\fpga\ph1p100\fpga"):
    for f in fn:
        p = os.path.join(dp, f)
        try:
            if os.stat(p).st_mtime > cut:
                hits.append(p)
        except OSError:
            pass
print("count:", len(hits), hits[:5])
