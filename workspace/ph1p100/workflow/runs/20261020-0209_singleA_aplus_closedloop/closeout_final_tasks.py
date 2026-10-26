import json, io, shutil

root = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
tasks_path = root + r"\workflow\tasks.json"
backup_path = root + r"\workflow\tasks.json.before-20261022-finalclose.json"

shutil.copyfile(tasks_path, backup_path)

with io.open(tasks_path, encoding="utf-8") as f:
    j = json.load(f)

run = "workflow/runs/20261020-0209_singleA_aplus_closedloop"
t10 = next(t for t in j["tasks"] if t.get("id") == "T10")

final_note = (
    " | 2026-10-22 final run closeout (final-combo failed, no further packages/rounds): "
    "T10 = 3/4 PASS + 1 warning; state stays blocked/not done. "
    "G0/G1 hold (33/33 bit-identical; 0 mismatch/0 X; comp 355,261 cycles; 1080p 81,707 B; 81.067 MB/s >= 77.76). "
    "G2 not closed: best routed = qor-retime group 1 (-0.039 ns / 45 endpoints; retiming+phys_opt; RTL 35ea7364); "
    "best synth = adler-smem 611ad704 (+0.233 ns); no routed zero-violation PASS, no bit/CWC, no board. "
    "final-combo r0 (s1_ok_r micro-fix + reused group-1 strategy): functional 33/33, comp 355,261, 1080p 81,707 B; "
    "Routed -0.091 / 12 endpoints; gate not met; TD 1/2 sessions, synth 1/1, route 1/1; worktree reverted to 35ea7364; "
    "no bitgen/.bit/download. Demand 2: offline profile audit + export contract only; real RAW not obtained. "
    "Demand 3: not started. Candidate lineage: r2 0b084317 (synth -0.017, routed -0.436; rollback), "
    "bm-prefetch df6124d4, bm-addr 35ea7364 (routed -0.087/27), adler-smem 611ad704 (best synth +0.233), "
    "qor-retime group 1 (best routed -0.039/45), final-combo (-0.091/12). frame 18d51b1b, SDC 227dd39e. "
    "Budget: ~32 rounds; TD 48 sessions, 43 synth, 10 route attempts (1 capacity fail + 9 Routed setup<0). "
    "No QoR seed sweep/clock change/false path/multicycle/bitgen/download/Flash. "
    "Remaining themes: (a) structural pipelining / deeper microarchitecture; (b) larger device / deeper QoR (needs user authorization); "
    "(c) demand 2/3 board prerequisites (board window, real RAW, non-PCIe export, download authorization)."
)
t10["status_note"] = (t10.get("status_note", "") + final_note)
t10["blocker"] = (
    "G2 timing not closed: best routed qor-retime group 1 = -0.039 ns / 45 endpoints (retiming+phys_opt, RTL 35ea7364); "
    "best synth adler-smem 611ad704 = +0.233 ns; final-combo -0.091/12; no routed zero-violation PASS, no bit/CWC, no board. "
    "T10 closed as 3/4 PASS + 1 warning; not done."
)

new_evidence = [
    run + "/final-summary.md",
    run + "/handoff.md",
    run + "/user-summary.md",
    run + "/T10.a1-qor-retime/r0/result-r0.md",
    run + "/T10.a1-qor-retime/r0/td/g1/routed_timing_summary.rpt",
    run + "/T10.a1-qor-retime/CANDIDATE-MANIFEST-qor-retime-r0.json",
    run + "/T10.a1-final-combo/r0/result-r0.md",
    run + "/T10.a1-final-combo/r0/td/routed_timing_summary.rpt",
    run + "/T10.a1-final-combo/CANDIDATE-MANIFEST-final-combo-r0.json",
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
