import json, io, shutil

root = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
tasks_path = root + r"\workflow\tasks.json"
backup_path = root + r"\workflow\tasks.json.before-20261023-p2done.json"

shutil.copyfile(tasks_path, backup_path)

with io.open(tasks_path, encoding="utf-8-sig") as f:
    j = json.load(f)

t10 = next(t for t in j["tasks"] if t.get("id") == "T10")

note = (
    " | 2026-10-23: P2 T10.b2-a1-uart-impl done with thin-margin caveat (independent tester PASS): "
    "Routed 0/19,754 violations, SWNS +0.012, hold +0.020, R-Freq 187.935, 17 clocks CC no/no, 0 comb loops, "
    "LUT6 18,698 / reg 25,200 / ERAM 102/300 / DSP 0 / IO 110; functional 8x2/64x8/full 1080p 0 mismatch/four CRCs/dup=0; "
    "bit d1ac8726...c142, CWC 37b60854...b25c, BID 3de68e68...f213; no download/Flash. System partial: board download/reset/stability/throughput "
    "awaiting_hardware. P1 r6 artifact hashes corrected (frame a2a84b74->c8b24775; 3 sim logs; artifact-hashes updated to post-correction manifest "
    "33754463; .before backups kept). P3 T10.b3-board-bringup is awaiting_user: Q1-Q10 + frozen sampling plan + P1 boundary tests "
    "(MODE=3/4, store-only 2,594,706 B, MODE=1 shortened, W=8,H=3, mid-write reset) + one SRAM download authorization with bit SHA. "
    "T10 parent remains blocked/not done; demand 2/3 remain incomplete."
)
t10["status_note"] = (t10.get("status_note", "") + note)

bc = t10.setdefault("board_chain", {})
bc["p1_core"] = "done_with_boundary"
bc["p1_manifest"] = "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/CANDIDATE-MANIFEST-b1-a1-uart-integ-r6.json"
bc["p2"] = "done_with_caveat"
bc["p2_package"] = "T10.b2-a1-uart-impl"
bc["p2_bit"] = "d1ac8726e84f6584d49979dd223d6e8c484e559bf2a3ad3b2302972c58efc142"
bc["p2_cwc"] = "37b608540f7924f60a09db5ba2b543334db1259ef69f2a1c982cf161cbc8b25c"
bc["p2_bid"] = "3de68e68...f213"
bc["p2_tester_report"] = "test-reports/T10.b2-a1-uart-impl-r3-integrated.md"
bc["p2_manifest"] = "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b2-a1-uart-impl/r3/CANDIDATE-MANIFEST-b2-a1-uart-impl-r3.json"
bc["p2_caveat"] = "SWNS +0.012 only; +0.2 target not met; offline only; no download/board signoff"
bc["p3"] = "awaiting_user"
bc["p3_package"] = "T10.b3-board-bringup"
bc["p3_question"] = "workflow/runs/20261020-0209_singleA_aplus_closedloop/question-board-chain.md"
bc["p3_budget"] = "board 90 min; 1 SRAM download; no Flash"
bc["p3_prerequisites"] = [
    "Q1-Q10 answered and sampling plan frozen",
    "one SRAM download authorization with bit SHA d1ac8726...c142; no Flash; no second download",
    "P1 boundary tests run/recorded: MODE=3/4, store-only 2,594,706 B, MODE=1 shortened, W=8,H=3, mid-write reset; or explicit user acceptance",
    "UART COM/baud/host/save path; ROI/Bayer; TPG first, real frame second",
]
bc["p4"] = "planned (independent verification 60 min/40 calls)"

t10["blocker"] = (
    "G2 small-top done; P1 core PASS-with-boundary; P2 done with thin +0.012 caveat; P3 awaiting_user "
    "(Q1-Q10 + P1 boundary tests + one SRAM download authorization). T10 parent not done; demands 2/3 incomplete."
)

new_evidence = [
    "test-reports/T10.b2-a1-uart-impl-r3-integrated.md",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b2-a1-uart-impl/r3/CANDIDATE-MANIFEST-b2-a1-uart-impl-r3.json",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/CANDIDATE-MANIFEST-b1-a1-uart-integ-r6.json",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/dispatch-b3.json",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/question-board-chain.md",
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
print("p1/p2/p3:", bc.get("p1_core"), bc.get("p2"), bc.get("p3"))
print("evidence count:", len(t10["latest_evidence"]))
