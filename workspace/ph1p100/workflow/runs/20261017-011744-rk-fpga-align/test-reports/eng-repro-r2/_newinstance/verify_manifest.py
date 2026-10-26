#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""New-instance engineering re-verification: manifest 232 entries + coverage + freeze scan."""
import hashlib, json, os, sys

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
RUN  = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align")
MF   = os.path.join(RUN, "backend", "candidate-manifest.json")

def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

mf = json.load(open(MF, encoding="utf-8"))
print("manifest task=%s round=%s schema=%s" % (mf["task_id"], mf["round"], mf["schema"]))

groups = [
    ("production_inputs", ROOT),
    ("build_scripts",     ROOT),
    ("test_inputs",       ROOT),
    ("rk_patch_inputs",   RUN),
    ("build_artifacts",   RUN),
]
total = ok = miss = mism = size_mism = 0
problems = []
covered = []
for g, base in groups:
    for e in mf.get(g, []):
        p = os.path.normpath(os.path.join(base, e["path"]))
        total += 1
        if not os.path.exists(p):
            miss += 1
            problems.append("MISSING %s %s" % (g, e["path"]))
            continue
        covered.append((p, g, e["path"]))
        h = sha256(p)
        if h != e["sha256"]:
            mism += 1
            problems.append("HASH %s %s got=%s want=%s" % (g, e["path"], h, e["sha256"]))
        else:
            ok += 1
        if "size" in e:
            sz = os.path.getsize(p)
            if sz != e["size"]:
                size_mism += 1
                problems.append("SIZE %s %s got=%d want=%d" % (g, e["path"], sz, e["size"]))

print("TOTAL=%d OK=%d MISSING=%d MISMATCH=%d SIZE_MISMATCH=%d" % (total, ok, miss, mism, size_mism))
for pr in problems:
    print(" ", pr)

# ---- coverage checks -------------------------------------------------------
def walk(rel, exclude_parts=()):
    res = set()
    base = os.path.join(ROOT, rel)
    for dp, dn, fn in os.walk(base):
        for f in fn:
            rp = os.path.relpath(os.path.join(dp, f), ROOT).replace("\\", "/")
            if any(x in rp.split("/") for x in exclude_parts):
                continue
            res.add(rp)
    return res

prod_keep = set(e["path"] for e in mf["production_inputs"])
prod_tree = walk("fpga/csi2/pcie_integration", exclude_parts=("sim", "peer-ref-2a4b253"))
prod_tree.discard("fpga/csi2/pcie_integration/README.md")
print("prod tree=%d manifest=%d extra=%s missing=%s" %
      (len(prod_tree), len(prod_keep), sorted(prod_tree - prod_keep)[:10], sorted(prod_keep - prod_tree)[:10]))

sim_tree  = walk("fpga/csi2/pcie_integration/sim")
test_keep = set(e["path"] for e in mf["test_inputs"])
print("sim tree=%d manifest=%d extra=%s missing=%s" %
      (len(sim_tree), len(test_keep), sorted(sim_tree - test_keep)[:10], sorted(test_keep - sim_tree)[:10]))

tool_tree   = walk("tools/pcie_integration")
script_keep = set(e["path"] for e in mf["build_scripts"])
print("tools tree=%d manifest=%d extra=%s missing=%s" %
      (len(tool_tree), len(script_keep), sorted(tool_tree - script_keep)[:10], sorted(script_keep - tool_tree)[:10]))

# ---- freeze scan: anything under covered trees newer than manifest? --------
mf_mtime = os.path.getmtime(MF)
print("manifest mtime = %s (epoch %.0f)" % (
    __import__("datetime").datetime.fromtimestamp(mf_mtime).strftime("%Y-%m-%d %H:%M:%S"), mf_mtime))

newer_covered = []
for p, g, e in covered:
    try:
        mt = os.path.getmtime(p)
    except OSError:
        continue
    if mt > mf_mtime:
        newer_covered.append((mt, g, e))
print("covered files newer than manifest: %d" % len(newer_covered))
for mt, g, e in sorted(newer_covered):
    print("  %s  %s %s" % (__import__("datetime").datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M:%S"), g, e))

scan_dirs = [
    os.path.join(ROOT, "fpga", "csi2", "pcie_integration"),
    os.path.join(ROOT, "tools", "pcie_integration"),
    os.path.join(RUN, "backend", "candidate"),
]
newer_any = []
for base in scan_dirs:
    for dp, dn, fn in os.walk(base):
        for f in fn:
            p = os.path.join(dp, f)
            try:
                mt = os.path.getmtime(p)
            except OSError:
                continue
            if mt > mf_mtime:
                newer_any.append((mt, os.path.relpath(p, ROOT)))
print("files under scanned trees newer than manifest: %d" % len(newer_any))
for mt, rp in sorted(newer_any):
    print("  %s  %s" % (__import__("datetime").datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M:%S"), rp))

# ---- volatile_excluded sanity ----------------------------------------------
print("volatile_excluded names=%s patterns=%s" % (mf.get("volatile_excluded", {}).get("names"), mf.get("volatile_excluded", {}).get("patterns")))
cmdlog = os.path.join(RUN, "backend", "candidate", "prj", "commands.log")
if os.path.exists(cmdlog):
    print("commands.log size=%d mtime=%s excluded_from_manifest=%s" % (
        os.path.getsize(cmdlog),
        __import__("datetime").datetime.fromtimestamp(os.path.getmtime(cmdlog)).strftime("%Y-%m-%d %H:%M:%S"),
        "commands.log" in mf.get("volatile_excluded", {}).get("names", [])))
