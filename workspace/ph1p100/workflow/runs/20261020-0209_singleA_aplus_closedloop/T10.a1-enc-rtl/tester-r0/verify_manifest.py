import json, hashlib, os, sys

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
RUN = os.path.join(ROOT, r"workflow\runs\20261020-0209_singleA_aplus_closedloop")
P2 = os.path.join(RUN, r"T10.a1-enc-rtl\p2")
man_path = os.path.join(P2, "CANDIDATE-MANIFEST.json")
m = json.load(open(man_path, encoding="utf-8"))
print("declared candidate", m.get("candidate_id"), "file_count", m.get("file_count"), "hash_mismatches", m.get("hash_mismatches"))
files = m["files"]
print("actual entries", len(files))
bad = []
missing = []
for f in files:
    p = f["path"]
    if not os.path.exists(p):
        missing.append(p); continue
    b = open(p, "rb").read()
    h = hashlib.sha256(b).hexdigest()
    if h != f["sha256"] or len(b) != f["bytes"]:
        bad.append((p, h, len(b), f["sha256"], f["bytes"]))
print("missing", len(missing))
for p in missing[:10]: print("  MISSING", p)
print("mismatch", len(bad))
for x in bad[:10]: print("  BAD", x)
# recompute candidate id same way? just report.
# index consistency
idx = json.load(open(os.path.join(P2, "cases", "index.json"), encoding="utf-8"))
print("index cases", len(idx["cases"]))
idx_err = []
for c in idx["cases"]:
    for k in ("hex", "meta", "xform"):
        p = c[k]
        if not os.path.exists(p): idx_err.append((c["name"], k, "missing"))
    # hex content must equal xform bytes
    hx = open(c["hex"], "rb").read()
    xf = open(c["xform"], "rb").read()
    try:
        hb = bytes(int(x, 16) for x in hx.split())
    except Exception as e:
        hb = b""
        idx_err.append((c["name"], "hexparse", str(e)))
    if hb != xf:
        idx_err.append((c["name"], "hex!=xform", (len(hb), len(xf))))
    mta = [int(x, 16) for x in open(c["meta"]).read().split()]
    if mta[0] != c["nblocks"] or mta[1:] != c["blocks"] or sum(c["blocks"]) != c["total_bytes"]:
        idx_err.append((c["name"], "meta mismatch", mta))
    # input binding to P1 vectors for p1 cases
    if c["kind"].startswith("p1_"):
        if not os.path.exists(c["raw"]):
            idx_err.append((c["name"], "raw missing", c["raw"]))
        else:
            raw = open(c["raw"], "rb").read()
            if c["prep_en"] == 0:
                if raw != xf:
                    idx_err.append((c["name"], "prep0 raw!=xform", (len(raw), len(xf))))
            # W/H sanity
            stride = c["w"] * 5 // 4
            if len(raw) != stride * c["h"]:
                idx_err.append((c["name"], "raw len != stride*h", (len(raw), stride*c["h"])))
        # P1 vector path must exist and hash match index source sha? none provided; check file exists
        if not os.path.exists(c["source"]):
            idx_err.append((c["name"], "source missing", c["source"]))
        else:
            src = open(c["source"], "rb").read()
            if src != xf:
                idx_err.append((c["name"], "source!=xform", (len(src), len(xf))))
print("index_errors", len(idx_err))
for e in idx_err: print("  IDX", e)
# manifest covers every file under p2 (excluding manifest itself)? report extra
man_set = {os.path.normcase(f["path"]) for f in files}
extra = []
for dp, dn, fn in os.walk(P2):
    for n in fn:
        p = os.path.normcase(os.path.join(dp, n))
        if p not in man_set and not p.endswith("candidate-manifest.json"):
            extra.append(p)
print("files_under_p2_not_in_manifest", len(extra))
for p in extra[:20]: print("  EXTRA", p)
print("VERDICT", "PASS" if not missing and not bad and not idx_err else "FAIL")
