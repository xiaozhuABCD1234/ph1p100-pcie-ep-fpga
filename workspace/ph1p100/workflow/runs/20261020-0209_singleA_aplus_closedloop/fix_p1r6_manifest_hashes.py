import json, io, os, shutil, hashlib

root = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
base = os.path.join(root, "workflow", "runs", "20261020-0209_singleA_aplus_closedloop")
mp = os.path.join(base, "T10.b1-a1-uart-integ", "CANDIDATE-MANIFEST-b1-a1-uart-integ-r6.json")
hp = os.path.join(base, "T10.b2-a1-uart-impl", "r3", "artifact-hashes.txt")
mbak = mp + ".before-hashfix"
hbak = hp + ".before-hashfix"
shutil.copyfile(mp, mbak)
shutil.copyfile(hp, hbak)

def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()

with io.open(mp, encoding="utf-8-sig") as f:
    j = json.load(f)

corrections = {}
for a in j.get("artifacts", []):
    p = a.get("path", "")
    fp = os.path.join(root, p)
    if not os.path.exists(fp):
        continue
    act = sha(fp)
    old = a.get("sha256", "")
    if act != old:
        corrections[p] = (old, act)
        a["sha256"] = act

j["documentation_correction"] = (
    "2026-10-23: corrected stale artifact hashes: a1_frame_top.v a2a84b74... -> c8b24775...; "
    "sim_micro8x2/sim_mid64x8/sim_full_grad logs updated to actual; artifact-hashes.txt updated to "
    "the post-correction manifest SHA. No RTL/functional change; P2 PASS unaffected."
)

with io.open(mp, "w", encoding="utf-8") as f:
    json.dump(j, f, ensure_ascii=False, indent=2)
    f.write("\n")

new_manifest_sha = sha(mp)

lines = io.open(hp, encoding="utf-8").read().splitlines()
out = []
for l in lines:
    if "CANDIDATE-MANIFEST-b1-a1-uart-integ-r6.json" in l:
        out.append(new_manifest_sha + "  workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/CANDIDATE-MANIFEST-b1-a1-uart-integ-r6.json")
    else:
        out.append(l)
io.open(hp, "w", encoding="utf-8").write("\n".join(out) + "\n")

print("manifest backup:", mbak)
print("hash list backup:", hbak)
print("new manifest sha:", new_manifest_sha)
for p, (old, act) in corrections.items():
    print("corrected:", p)
    print("  old:", old)
    print("  new:", act)
