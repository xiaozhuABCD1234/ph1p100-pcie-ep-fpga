import json, io, shutil

root = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
tasks_path = root + r"\workflow\tasks.json"
backup_path = root + r"\workflow\tasks.json.before-20261023-p1p2.json"

shutil.copyfile(tasks_path, backup_path)

with io.open(tasks_path, encoding="utf-8-sig") as f:
    j = json.load(f)

t10 = next(t for t in j["tasks"] if t.get("id") == "T10")

note = (
    " | 2026-10-23: P1 T10.b1-a1-uart-integ accepted as core PASS-with-boundary "
    "(8x2/64x8/full 1920x1080 0 mismatch, header/stream/xform/raw CRCs true, dup=0, read_words=129,600). "
    "Boundary: MODE=2 bad-frame/overflow counters not exercised (geom=0/raw_drop=0; reset clears counters), "
    "reset mid-write at FRAME_CYC/2 times out, MODE=3/4, store-only 2,594,706 B, MODE=1 shortened, W=8,H=3 tail not run "
    "because shell permission TOOL_UNAVAILABLE. P2 T10.b2-a1-uart-impl is ready (full constraints/187.5 MHz/CDC/STA + "
    "1 bitgen + 1 CWC; no download; TD <=3 sessions/150 min, synth <=3, route <=2). P3 remains awaiting_user: shell-restored "
    "missing tests + Q1-Q6 + one-SRAM-download authorization with frozen bit SHA. T10 parent remains blocked/not done."
)
t10["status_note"] = (t10.get("status_note", "") + note)
t10["board_chain"] = {
    "p1_core": "done_with_boundary",
    "p1_core_evidence": [
        "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r3/result-r3.md",
        "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r3/CANDIDATE-MANIFEST-b1-a1-uart-integ-r3.json",
        "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r4/result-r4.md",
    ],
    "p1_boundary": [
        "MODE=2 bad-frame/overflow counters not exercised (geom=0/raw_drop=0; reset clears counters)",
        "reset mid-write at FRAME_CYC/2 times out; recovery path to be localized before P3",
        "MODE=3/4, store-only 2,594,706 B, MODE=1 shortened, W=8,H=3 tail not run (shell TOOL_UNAVAILABLE)",
    ],
    "p2": "ready",
    "p2_package": "T10.b2-a1-uart-impl",
    "p2_budget": "dev 120/60; TD <=3 sessions/150 min; synth <=3; route <=2; bitgen 1; CWC 1; download 0",
    "p3": "awaiting_user",
    "p3_prerequisites": [
        "shell restored: MODE=3/4, store-only 2,594,706 B max-length, MODE=1 shortened, W=8,H=3 tail, mid-write reset recovery",
        "P1 evidence re-bound to P2 candidate hash",
        "P2 routed/CDC/resources pass; bit/CWC hashes frozen",
        "Q1-Q6: board window/presence; camera A/B/BANK13; lens/exposure; one SRAM download authorization with bit SHA; UART COM/baud/host; ROI/Bayer; scope confirmation",
    ],
    "question": "workflow/runs/20261020-0209_singleA_aplus_closedloop/question-board-chain.md",
}
t10["blocker"] = (
    "G2 small-top done; P1 core PASS-with-boundary (fault/max-length/mode1/tail/mid-write reset pending); "
    "P2 T10.b2-a1-uart-impl ready (implementation + 1 bitgen + 1 CWC, no download); "
    "P3 awaiting_user for shell-restored missing tests + Q1-Q6 + one-SRAM-download authorization. T10 not done."
)

new_evidence = [
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r4/result-r4.md",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r4/CANDIDATE-MANIFEST-b1-a1-uart-integ-r4.json",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/dispatch-b2.json",
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
print("board_chain:", t10["board_chain"]["p1_core"], t10["board_chain"]["p2"], t10["board_chain"]["p3"])
print("evidence count:", len(t10["latest_evidence"]))
