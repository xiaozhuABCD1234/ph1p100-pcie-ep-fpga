import json, io, shutil

root = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
tasks_path = root + r"\workflow\tasks.json"
backup_path = root + r"\workflow\tasks.json.before-20261023-milestone.json"

shutil.copyfile(tasks_path, backup_path)

with io.open(tasks_path, encoding="utf-8") as f:
    j = json.load(f)

t10 = next(t for t in j["tasks"] if t.get("id") == "T10")

note = (
    " | 2026-10-23 milestone: independent integrated tester PASS (G2 small-top, with caveat). "
    "Functional: 33 cases (P3 19/20 only because multi1080p keeps a single-frame stream file, not a failure), "
    "0 mismatch/0 X, comp 355,261, 1080p 81,707 B, third-party zlib 17/17. "
    "Engineering: SWNS +0.047 ns, STNS 0, 0/4,649 violations, hold +0.021/0, Fmax 189.179, slice 3,032/4.23%, "
    "ERAM 26, DSP 0, single clock, CC no/no, 0 comb loops, bitgen not_run. "
    "Caveats: 47 ps margin, offline small-top not board signoff, no post-route phys_opt, IO unconstrained 47/73, "
    "STA coverage 96.40%, no gate-level/formal equivalence, multi1080p single-frame artifact gap. "
    "G2 small-top marked done; T10 parent remains blocked; demands 2/3 remain blocked. "
    "Boundary: offline small-top only, no bit/CWC, no production integration; re-run STA and keep margin before bitgen/board."
)
t10["status_note"] = (t10.get("status_note", "") + note)
t10["g2_small_top"] = (
    "done (2026-10-23 independent tester PASS: Routed zero violations +0.047 ns, 0/4,649, hold +0.021/0, "
    "Fmax 189.179; thin-margin/offline/no-bit caveat)"
)
t10["g2_tester_report"] = "workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.a1-pipe-split-final-r0-integrated.md"
t10["blocker"] = (
    "G2 small-top PASS (tester, 2026-10-23; caveat: 47 ps thin margin, offline small-top, not board signoff, "
    "no bit/CWC, no post-route phys_opt, IO 47/73 unconstrained, STA coverage 96.40%). "
    "Demand 2 (real RAW/params) and demand 3 (board end-to-end) remain blocked; T10 parent not done."
)

new_evidence = [
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.a1-pipe-split-final-r0-integrated.md",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-pipe-split/r0/td/routed_timing_summary.rpt",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-pipe-split/r0/td/route.qor",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-pipe-split/CANDIDATE-MANIFEST-pipe-split-r0.json",
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
print("g2_small_top:", t10["g2_small_top"][:80])
print("tester report:", t10["g2_tester_report"])
print("evidence count:", len(t10["latest_evidence"]))
