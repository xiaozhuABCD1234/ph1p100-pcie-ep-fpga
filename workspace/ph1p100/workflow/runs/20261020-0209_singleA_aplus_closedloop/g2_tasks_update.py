import json, io, shutil

root = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
tasks_path = root + r"\workflow\tasks.json"
backup_path = root + r"\workflow\tasks.json.before-20261023-g2.json"

shutil.copyfile(tasks_path, backup_path)

with io.open(tasks_path, encoding="utf-8") as f:
    j = json.load(f)

t10 = next(t for t in j["tasks"] if t.get("id") == "T10")

note = (
    " | 2026-10-23: pipe-split r0 accepted as G2 small-top PASS (Routed zero violations, SWNS +0.047 ns, "
    "0/4,649 violations, hold +0.021/0, Fmax 189.179 MHz, resources in device, single clock, no CDC/no comb loops; "
    "functional 33/33 bit-identical, comp 355,261, 1080p 81,707 B; no bitgen/.bit/download). "
    "Original G2 criterion was Routed zero violations + necessary STA/CDC/resource checks; the +0.2 ns target was a "
    "robustness goal and is NOT met (47 ps margin). G2 small-top marked done; demands 2 (real RAW/params) and 3 "
    "(board end-to-end) remain blocked; T10 is NOT done. New tester package T10.a1-pipe-split-final dispatched "
    "(45 min/30 calls, no TD rerun, no bitgen/download)."
)
t10["status_note"] = (t10.get("status_note", "") + note)
t10["g2_small_top"] = "done (2026-10-23: Routed zero violations, SWNS +0.047 ns, 0/4,649, hold +0.021/0, Fmax 189.179; thin-margin/offline/no-bit caveat)"
t10["g2_evidence"] = [
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-pipe-split/r0/result-r0.md",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-pipe-split/r0/td/routed_timing_summary.rpt",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-pipe-split/r0/td/route.qor",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-pipe-split/CANDIDATE-MANIFEST-pipe-split-r0.json",
]
t10["blocker"] = (
    "G2 small-top PASS accepted (Routed zero violations +0.047 ns; caveat: 47 ps thin margin, offline small-top, "
    "not board signoff, no bit/CWC). Demand 2 (real RAW/params) and demand 3 (board end-to-end) remain blocked; "
    "T10 not done."
)

new_evidence = [
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/dispatch-pipe-split-final.json",
]
ev = t10.get("latest_evidence", [])
for p in new_evidence:
    if p not in ev:
        ev.append(p)
t10["latest_evidence"] = ev

with io.open(tasks_path, "w", encoding="utf-8") as f:
    json.dump(j, f, ensure_ascii=False, indent=2)
    f.write("\n")

print("backup:", backup_path)
print("T10 state:", t10["state"])
print("g2_small_top:", t10["g2_small_top"])
print("evidence count:", len(t10["latest_evidence"]))
