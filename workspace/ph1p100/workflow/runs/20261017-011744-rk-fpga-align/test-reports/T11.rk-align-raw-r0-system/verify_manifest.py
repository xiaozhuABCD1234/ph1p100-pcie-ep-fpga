# T11.rk-align-raw r0 / system tester — independent manifest self-check (no production writes)
# Verifies candidate-manifest.json SHA + every entry SHA with per-list path base,
# and cross-checks "unchanged vs T07" claims against the backend manifest.
import hashlib, json, os, sys

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
RUN = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align")

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

manifest_path = os.path.join(RUN, "raw", "candidate-manifest.json")
m_sha = sha256(manifest_path)
print("manifest sha256 =", m_sha)
print("expected         = aab0cc08ef0134d5fcb18b25e0b70c43e9af1d577513ca2996dc46f22de76975")
print("MATCH" if m_sha == "aab0cc08ef0134d5fcb18b25e0b70c43e9af1d577513ca2996dc46f22de76975" else "MISMATCH")

m = json.load(open(manifest_path, encoding="utf-8"))
bases = {
    "production_inputs": ROOT,
    "build_scripts": ROOT,
    "test_inputs": ROOT,
    "rk_patch_inputs": RUN,
    "build_artifacts": RUN,
}
total = ok = bad = missing = 0
mismatches = []
for key, base in bases.items():
    for e in m.get(key, []):
        total += 1
        p = os.path.join(base, e["path"])
        if not os.path.exists(p):
            missing += 1
            mismatches.append((key, e["path"], "MISSING", e["sha256"]))
            continue
        s = sha256(p)
        if s.lower() == e["sha256"].lower():
            ok += 1
        else:
            bad += 1
            mismatches.append((key, e["path"], s, e["sha256"]))
print(f"entries total={total} ok={ok} mismatch={bad} missing={missing}")

# T07 backend manifest cross-check for "zero change" claims
p7 = os.path.join(RUN, "backend", "candidate-manifest.json")
m7 = json.load(open(p7, encoding="utf-8"))
def index(mf):
    d = {}
    for key, base in bases.items():
        for e in mf.get(key, []):
            d[e["path"]] = e["sha256"].lower()
    return d
i11, i7 = index(m), index(m7)
unchanged_expect = [
    "fpga/csi2/pcie_integration/constraints/ph1p_pcie_case_ep.sdc",
    "fpga/csi2/pcie_integration/constraints/ph1p_pcie_case_ep.adc",
    "fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v",
    "fpga/csi2/pcie_integration/rtl/checked/csi_rx_10bit_unpack_checked.v",
    "fpga/csi2/pcie_integration/rtl/checked/crc16_upd4.v",
    "fpga/csi2/pcie_integration/rtl/ep_side/ddr/ddr_frame_pusher.v",
]
print("\n-- zero-change claims vs T07 manifest --")
for path in unchanged_expect:
    a, b = i11.get(path), i7.get(path)
    print(f"{path}: T11={a} T07={b} :: {'SAME' if a == b and a else 'DIFFER/ABSENT'}")

# what actually changed in the shared tree (production_inputs diff T07->T11)
changed = []
added = []
for k in ("production_inputs",):
    for e in m.get(k, []):
        p = e["path"]
        if p not in i7:
            added.append(p); continue
        if i7[p] != e["sha256"].lower():
            changed.append(p)
print("\nproduction_inputs changed vs T07:", changed)
print("production_inputs added vs T07:", added)

# samples vs contract artifacts byte-identity
print("\n-- samples vs contract artifacts --")
for name in ("r10f-1080p-synthetic.dma", "r10f-small-synthetic.dma"):
    a = os.path.join(RUN, "raw", "samples", name)
    b = os.path.join(RUN, "artifacts", name)
    if os.path.exists(a) and os.path.exists(b):
        sa, sb = sha256(a), sha256(b)
        print(f"{name}: sample={sa[:16]} artifact={sb[:16]} size={os.path.getsize(a)} :: {'SAME' if sa == sb else 'DIFFER'}")
    else:
        print(f"{name}: absent (sample={os.path.exists(a)}, artifact={os.path.exists(b)})")

sys.exit(0 if (m_sha == "aab0cc08ef0134d5fcb18b25e0b70c43e9af1d577513ca2996dc46f22de76975" and bad == 0 and missing == 0) else 1)
