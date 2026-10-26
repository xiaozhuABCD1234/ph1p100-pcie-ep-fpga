import json, io, shutil

root = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
tasks_path = root + r"\workflow\tasks.json"
backup_path = root + r"\workflow\tasks.json.before-20261024-p3auth.json"

shutil.copyfile(tasks_path, backup_path)

with io.open(tasks_path, encoding="utf-8-sig") as f:
    j = json.load(f)

t10 = next(t for t in j["tasks"] if t.get("id") == "T10")
bc = t10.setdefault("board_chain", {})

note = (
    " | 2026-10-24: P3 authorized by user quote '该给的权限我给，该上电的我都上了，剩余按默认或者你做好判断...开始执行吧' "
    "with Q1-Q10 defaults confirmed. P3 ready: one SRAM download of bit d1ac8726...c142, CWC 37b60854...b25c, BID 3de68e68...f213; "
    "P3 workdir default D:\\fpga_work\\20261020-0209_singleA_aplus_closedloop\\P3 with fallback; path-move probe/switch/frozen-copy rule. "
    "Technical boundaries: frozen bit UART=115.172 kbaud (use 115200; 921600 unsupported); TPG-into-A+ not available (HDMI TPG only), "
    "record tpg_a_plus=not_available boundary; real A frame is primary. Board 90 min, 1 download, no Flash; P4 tester 60/40 after P3. "
    "T10 remains blocked/not done."
)
t10["status_note"] = (t10.get("status_note", "") + note)

bc["p3"] = "ready_authorized"
bc["p3_package"] = "T10.b3-board-bringup"
bc["p3_authorization_date"] = "2026-10-24"
bc["p3_authorization_quote"] = "该给的权限我给，该上电的我都上了，剩余按默认或者你做好判断，我也基本都是符合的，开始执行吧"
bc["p3_bit"] = "d1ac8726e84f6584d49979dd223d6e8c484e559bf2a3ad3b2302972c58efc142"
bc["p3_cwc"] = "37b608540f7924f60a09db5ba2b543334db1259ef69f2a1c982cf161cbc8b25c"
bc["p3_bid"] = "3de68e68...f213"
bc["p3_workdir"] = "D:\\fpga_work\\20261020-0209_singleA_aplus_closedloop\\P3"
bc["p3_uart"] = "115200 8N1 (frozen bit 115.172 kbaud; 921600 unsupported)"
bc["p3_tpg"] = "tpg_a_plus=not_available (HDMI TPG only; boundary); real A frame primary"
bc["p3_budget"] = "board 90 min; 1 SRAM download; no Flash; dev 90/50; P4 60/40"
bc["p3_prerequisites"] = [
    "Q1-Q10 default confirmed 2026-10-24; boundary accepted",
    "one SRAM download authorization with bit SHA d1ac8726...c142; no Flash; no second download",
    "P3 workdir D: or fallback recorded; path-move probe/switch/frozen-copy rule",
]
bc["p4"] = "planned after P3 (independent tester 60/40; no TD/download)"

t10["blocker"] = (
    "G2 small-top done; P1 core PASS-with-boundary; P2 done with thin +0.012 caveat; "
    "P3 ready_authorized (one SRAM download, board not yet run; TPG-into-A+ boundary; UART 115200). "
    "T10 parent not done; demands 2/3 incomplete."
)

new_evidence = [
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/dispatch-b3.json",
    "workflow/runs/20261020-0209_singleA_aplus_closedloop/question-board-chain.md",
    "test-reports/T10.b2-a1-uart-impl-r3-integrated.md",
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
print("p3 bit:", bc.get("p3_bit"))
print("evidence count:", len(t10["latest_evidence"]))
