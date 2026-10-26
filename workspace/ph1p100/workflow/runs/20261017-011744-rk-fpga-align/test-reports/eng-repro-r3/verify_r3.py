#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T07 r3 engineering (same tester instance): reuse-condition verification.
- 232-entry recompute on new manifest 68F9F4D0...
- mtime invariance vs r2 freeze time (06:04:56) and vs r3 manifest mtime
- BOM-only proof for run_sim.ps1 / run_td.ps1: strip BOM -> must equal r2 SHAs
- critical-file hash cross-check vs r2-recorded values (from my r2 report/evidence)
"""
import hashlib, json, os, datetime, sys

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
RUN  = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align")
MF   = os.path.join(RUN, "backend", "candidate-manifest.json")
R2_FREEZE = datetime.datetime(2026, 10, 17, 6, 4, 56).timestamp()   # r2 manifest mtime
R3_FREEZE = datetime.datetime(2026, 10, 17, 7, 14, 0).timestamp()    # r3 manifest mtime

def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def ts(t):
    return datetime.datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M:%S")

mf = json.load(open(MF, encoding="utf-8"))
print("manifest round=%s schema=%s notes=%s" % (mf["round"], mf["schema"], json.dumps(mf.get("notes", []), ensure_ascii=False)))
print("volatile_excluded=%s" % json.dumps(mf.get("volatile_excluded", {}), ensure_ascii=False))
print("manifest mtime=%s" % ts(os.path.getmtime(MF)))

groups = [("production_inputs", ROOT), ("build_scripts", ROOT), ("test_inputs", ROOT),
          ("rk_patch_inputs", RUN), ("build_artifacts", RUN)]
total = ok = miss = mism = size_mism = 0
problems, covered = [], []
for g, base in groups:
    for e in mf.get(g, []):
        p = os.path.normpath(os.path.join(base, e["path"]))
        total += 1
        if not os.path.exists(p):
            miss += 1; problems.append("MISSING %s %s" % (g, e["path"])); continue
        covered.append((p, g, e["path"], e["sha256"]))
        h = sha256(p)
        if h != e["sha256"]:
            mism += 1; problems.append("HASH %s %s got=%s want=%s" % (g, e["path"], h, e["sha256"]))
        else:
            ok += 1
        if "size" in e and os.path.getsize(p) != e["size"]:
            size_mism += 1; problems.append("SIZE %s %s" % (g, e["path"]))
print("TOTAL=%d OK=%d MISSING=%d MISMATCH=%d SIZE_MISMATCH=%d" % (total, ok, miss, mism, size_mism))
for pr in problems: print(" ", pr)

# coverage diff
def walk(rel, exclude_parts=()):
    res = set()
    for dp, dn, fn in os.walk(os.path.join(ROOT, rel)):
        for f in fn:
            rp = os.path.relpath(os.path.join(dp, f), ROOT).replace("\\", "/")
            if any(x in rp.split("/") for x in exclude_parts): continue
            res.add(rp)
    return res
prod_keep = set(e["path"] for e in mf["production_inputs"])
prod_tree = walk("fpga/csi2/pcie_integration", exclude_parts=("sim", "peer-ref-2a4b253"))
prod_tree.discard("fpga/csi2/pcie_integration/README.md")
print("prod tree=%d manifest=%d extra=%s missing=%s" % (len(prod_tree), len(prod_keep), sorted(prod_tree-prod_keep)[:8], sorted(prod_keep-prod_tree)[:8]))
sim_tree = walk("fpga/csi2/pcie_integration/sim")
test_keep = set(e["path"] for e in mf["test_inputs"])
print("sim tree=%d manifest=%d extra=%s missing=%s" % (len(sim_tree), len(test_keep), sorted(sim_tree-test_keep)[:8], sorted(test_keep-sim_tree)[:8]))
tool_tree = walk("tools/pcie_integration")
script_keep = set(e["path"] for e in mf["build_scripts"])
print("tools tree=%d manifest=%d extra=%s missing=%s" % (len(tool_tree), len(script_keep), sorted(tool_tree-script_keep)[:8], sorted(script_keep-tool_tree)[:8]))

# mtime invariance
new_after_r2 = [(ts(os.path.getmtime(p)), g, rp) for p, g, rp, _ in covered if os.path.getmtime(p) > R2_FREEZE]
new_after_r3 = [(ts(os.path.getmtime(p)), g, rp) for p, g, rp, _ in covered if os.path.getmtime(p) > R3_FREEZE]
print("covered files with mtime > r2_freeze(06:04:56): %d" % len(new_after_r2))
for t, g, rp in sorted(new_after_r2): print("   %s  %s %s" % (t, g, rp))
print("covered files with mtime > r3_freeze(07:14:00): %d" % len(new_after_r3))
for t, g, rp in sorted(new_after_r3): print("   %s  %s %s" % (t, g, rp))

scan_dirs = ["fpga/csi2/pcie_integration", "tools/pcie_integration", "workflow/runs/20261017-011744-rk-fpga-align/backend/candidate"]
newer_any = []
for base in scan_dirs:
    for dp, dn, fn in os.walk(os.path.join(ROOT, base)):
        for f in fn:
            p = os.path.join(dp, f)
            mt = os.path.getmtime(p)
            if mt > R2_FREEZE:
                newer_any.append((mt, os.path.relpath(p, ROOT)))
print("files under scanned trees newer than r2_freeze: %d" % len(newer_any))
for mt, rp in sorted(newer_any): print("   %s  %s" % (ts(mt), rp))

# BOM-only proof for the two scripts
print("== script BOM check ==")
for rel, r2sha, exp_size in [
    ("tools/pcie_integration/run_sim.ps1", "33399210c389818a8601b2710ff08fc1b46312976b35d6fb9a0de1b50674229e", 6439),
    ("tools/pcie_integration/run_td.ps1",  "760c5524c3dddf1627d32d0d323a3a48cd727740d87091d173253c75a77fed0f", 3449),
]:
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    bom = raw[:3] == b"\xef\xbb\xbf"
    stripped = raw[3:] if bom else raw
    h = hashlib.sha256(stripped).hexdigest()
    print(" %s size=%d (expect %d) BOM=%s strip_bom_sha=%s == r2sha? %s" %
          (rel, len(raw), exp_size, bom, h[:16], h == r2sha))
    # manifest value + recorded mtime
    mval = [e for e in mf["build_scripts"] if e["path"] == rel][0]["sha256"]
    print("   manifest_sha=%s full_file_sha=%s mtime=%s" % (mval[:16], sha256(p)[:16], ts(os.path.getmtime(p))))

# r2-recorded critical values (from MY r2 report + r2 evidence logs)
print("== critical hash cross-check vs r2-recorded ==")
CHECKS = [
    ("workflow/runs/20261017-011744-rk-fpga-align/backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit",
     "0943cb36feeb873decc6ea5aae1c2777b3ab4881ebe2954b43bee040ceb38b0a", 32),
    ("workflow/runs/20261017-011744-rk-fpga-align/backend/candidate/prj/ph1p_pcie_integration_Runs/best_result/ph1p_pcie_integration.bit",
     "0943cb36feeb873decc6ea5aae1c2777b3ab4881ebe2954b43bee040ceb38b0a", 32),
    ("fpga/csi2/pcie_integration/constraints/ph1p_pcie_case_ep.sdc", "3f999c447abbb8908e0c830c1b2bf0313dc8a30b3f50a2ed899f3793bfa4c13a", 32),
    ("fpga/csi2/pcie_integration/constraints/ph1p_pcie_case_ep.adc", "67831295aef0f5afbec9f2dfbf062922b793a6586e56c074ace21787b6365c98", 32),
    ("fpga/csi2/pcie_integration/rtl/checked/csi_rx_packet_integrity.v", "50b4c77be684f078bdf6dca93848e9298e3cbd8010e45eab4b0ecfb2debdc6c0", 32),
    ("fpga/csi2/pcie_integration/rtl/checked/crc16_upd4.v", "20520d044773247bdd6469c3fd04efcf1ea4c31366abf41f7fde3ea27e98841f", 32),
    ("fpga/csi2/pcie_integration/sim/tb/csi_rx_packet_integrity_ref.v", "4489a8338f31cd06d8c42046cc37f0fa5292df1cbdec6d0da416d3949df48f2b", 32),
    ("fpga/csi2/pcie_integration/sim/tb/tb_csi_integrity_diff.v", "f78b3d83ae08a24774a7f334347ac9362ba1faedb07aed5cce31dc4f6f551285", 32),
    ("fpga/csi2/pcie_integration/sim/compile_checked.f", "c075ccab6b4cc5861c17da22cf1410894f2c9929493b8c1b6a87eb803db5100c", 32),
    ("tools/pcie_integration/gen_crc16_flat.py", "1cefad275bb10db63d31e3788e49f11923355e28f7dae3b6fc682aec0053617d", 32),
    ("workflow/runs/20261017-011744-rk-fpga-align/backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/final_timing.rpt", "ada43e46", 8),
    ("workflow/runs/20261017-011744-rk-fpga-align/backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/run.log", "bad1f0ad", 8),
    ("workflow/runs/20261017-011744-rk-fpga-align/backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_place.db", "510b5187", 8),
    ("workflow/runs/20261017-011744-rk-fpga-align/backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_pr.db", "692791c6", 8),
]
for rel, want, n in CHECKS:
    p = os.path.join(ROOT, rel) if not rel.startswith("workflow") else os.path.join(ROOT, rel)
    h = sha256(p)
    good = h[:n] == want[:n]
    print(" %s  %s  %s" % ("OK " if good else "REVIEW", rel.split("/")[-1], h[:32]))
    if not good: print("    want prefix=%s" % want)

# build_artifacts inventory
print("== build_artifacts summary ==")
arts = mf["build_artifacts"]
mt = [os.path.getmtime(os.path.join(RUN, e["path"])) for e in arts]
print(" count=%d mtime range %s .. %s" % (len(arts), ts(min(mt)), ts(max(mt))))
bits = [e for e in arts if e["path"].endswith(".bit")]
print(" bit entries=%s" % json.dumps(bits, ensure_ascii=False))
