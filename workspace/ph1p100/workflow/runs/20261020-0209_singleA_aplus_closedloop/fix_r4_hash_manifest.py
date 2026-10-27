import json, io, shutil

p = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b1-a1-uart-integ\r4\CANDIDATE-MANIFEST-b1-a1-uart-integ-r4.json"
bak = p + ".before-hashfix"
shutil.copyfile(p, bak)

with io.open(p, encoding="utf-8-sig") as f:
    j = json.load(f)

h = j.get("rtl_hashes_r3_verified_in_r4", {})
h["a1_ddr_slot_store.v"] = "8bab440d528a"
h["camera_a1_uart_top.v"] = "873cb98c7c79"
h["correction"] = (
    "2026-10-23: corrected stale prefixes 5196c07aed52 (a1_ddr_slot_store.v) and "
    "e88de0910ff0 (camera_a1_uart_top.v). Those digests do not exist; actual measured "
    "SHA256 prefixes are 8bab440d528a and 873cb98c7c79, matching the r3 full digests. "
    "This is a documentation conflict, not RTL drift."
)
j["rtl_hashes_r3_verified_in_r4"] = h

with io.open(p, "w", encoding="utf-8") as f:
    json.dump(j, f, ensure_ascii=False, indent=2)
    f.write("\n")

print("backup:", bak)
print(json.dumps(j["rtl_hashes_r3_verified_in_r4"], ensure_ascii=False, indent=2))
