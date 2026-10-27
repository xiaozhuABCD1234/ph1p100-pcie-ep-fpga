import json, io, shutil

root = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
tasks_path = root + r"\workflow\tasks.json"
backup_path = root + r"\workflow\tasks.json.before-20261022.json"

shutil.copyfile(tasks_path, backup_path)

with io.open(tasks_path, encoding="utf-8") as f:
    j = json.load(f)

run = "workflow/runs/20261020-0209_singleA_aplus_closedloop"
t10 = next(t for t in j["tasks"] if t.get("id") == "T10")

final_note = (
    " | 2026-10-22 final closeout: T10 = 3/4 PASS + 1 warning, state stays blocked/not done. "
    "G0/G1 hold (33/33 bit-identical; 0 mismatch/0 X; comp 355,261 cycles; 1080p 81,707 B; 81.067 MB/s >= 77.76). "
    "G2 not closed: best routed bm-addr 35ea7364 = -0.087 ns / 27 endpoints; best synth adler-smem 611ad704 = +0.233 ns; "
    "no routed zero-violation PASS, no bit/CWC, no board. Demand 2: offline profile audit + export contract only; real RAW not obtained. "
    "Demand 3: not started. Candidate lineage: r2 0b084317 (synth -0.017, routed -0.436), bm-prefetch df6124d4, "
    "bm-addr 35ea7364 (best routed -0.087), adler-smem 611ad704 (best synth +0.233); frame 18d51b1b, SDC 227dd39e. "
    "Remaining themes: deeper microarchitecture (ERAM output -> address/CE chain re-pipeline), larger device/QoR (needs user authorization), "
    "demand 2/3 board prerequisites (board window, real RAW, download authorization). "
    "No QoR strategy/clock change/false path/multicycle/seed sweep/bitgen/download/Flash in this closeout."
)
t10["status_note"] = (t10.get("status_note", "") + final_note)
t10["blocker"] = (
    "G2 timing not closed: best routed bm-addr 35ea7364 = -0.087 ns / 27 endpoints; best synth adler-smem 611ad704 = +0.233 ns; "
    "no routed zero-violation PASS, no bit/CWC, no board. T10 closed as 3/4 PASS + 1 warning; not done."
)

new_evidence = [
    run + "/final-summary.md",
    run + "/handoff.md",
    run + "/user-summary.md",
    run + "/T10.a1-bm-prefetch/r2/result-r2.md",
    run + "/T10.a1-bm-prefetch/CANDIDATE-MANIFEST-bm-prefetch-r2.json",
    run + "/T10.a1-bm-addr/r0/result-r0.md",
    run + "/T10.a1-bm-addr/r0-route/route.qor",
    run + "/T10.a1-bm-addr/CANDIDATE-MANIFEST-bm-addr-r0.json",
    run + "/T10.a1-adler-smem/r0/result-r0.md",
    run + "/T10.a1-adler-smem/r0/td/syn_gate_timing_a1.rpt",
    run + "/T10.a1-adler-smem/CANDIDATE-MANIFEST-adler-smem-r0.json",
    run + "/test-reports/T10.a1-hit-pipe-r1-integrated.md",
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
