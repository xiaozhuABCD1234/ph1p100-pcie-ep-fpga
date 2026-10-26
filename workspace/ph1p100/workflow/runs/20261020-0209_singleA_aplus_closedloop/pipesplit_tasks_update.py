import json, io, shutil

root = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
tasks_path = root + r"\workflow\tasks.json"
backup_path = root + r"\workflow\tasks.json.before-20261022-pipesplit.json"

shutil.copyfile(tasks_path, backup_path)

with io.open(tasks_path, encoding="utf-8") as f:
    j = json.load(f)

t10 = next(t for t in j["tasks"] if t.get("id") == "T10")

note = (
    " | 2026-10-22: user authorized structural pipeline split attempt "
    "('进行结构性分拍尝试'); package T10.a1-pipe-split active under the same run/T10; state stays blocked/not done. "
    "Cycle rule: cycle-neutral preferred (target P2 comp 355,261); extra cycles must be quantified and P2 comp <= 370,370 "
    "(<= 15,109 extra); anything > 370,370 requires the user to refresh the acceptance basis. "
    "Plan: register rng1_r at stage 1 (old stage-1 range-test form) and make stage-2 hit2 all-flop; optional bounded p3p1_r "
    "address precompute and one extra stage-1 predicate registration (e.g. s1_blkn_r); full 33-case regression; reuse "
    "retiming+phys_opt; up to 3 synth + 1 route; gate Routed zero violations and setup >= +0.2 ns; failure closes T10 as 3/4 + 1 warning. "
    "Budget: dev 120 min/60 calls; TD 3 sessions/150 min, synth <= 3, route <= 1; tester 45 min/30 calls if pass. "
    "SDC 227dd39e unchanged; protocol/port/frame semantics/CRC/length/abort/Bayer unchanged; no seed sweep/clock change/false path/multicycle/bitgen/download."
)
t10["status_note"] = (t10.get("status_note", "") + note)

new_evidence = [
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/dispatch-pipe-split.json",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-qor-retime/r0/td/g1/routed_timing_summary.rpt",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-final-combo/r0/result-r0.md",
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
print("evidence count:", len(t10["latest_evidence"]))
