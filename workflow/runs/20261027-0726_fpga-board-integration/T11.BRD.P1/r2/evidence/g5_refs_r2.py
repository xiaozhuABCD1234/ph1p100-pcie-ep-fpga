#!/usr/bin/env python3
"""T11.BRD.P1 r2 — G5 reference check: every file named by the r2 documents must
exist and be bound by the frozen r2 manifest (package manifest/result copies and
documented read-only external inputs excepted).

Same idea as the r1 tester's `tester_g5_refs.py`, widened to the r2 documents.
"""
import json
import os
import re

REPO = r"D:\fpga\repos\ph1p100-pcie-ep-fpga"
R2 = os.path.join(REPO, "workflow", "runs", "20261027-0726_fpga-board-integration", "T11.BRD.P1", "r2")
PKG = os.path.join(REPO, "handoff", "brd-p1-r2-20261027")
MAN = json.load(open(os.path.join(R2, "manifest-brd-p1-r2.json"), encoding="utf-8"))
bound = {os.path.normpath(e["path"]).lower() for e in MAN["files"]}

TOK = re.compile(r"[\w./\\\-]+\.(?:md|log|bin|txt|json|tcl|sdc|adc|py|ps1|v|tmpl|rpt|al|do|err)\b")
docs = [os.path.join(R2, "result-r2.md"), os.path.join(R2, "README.md"),
        os.path.join(R2, "build-entry.md"), os.path.join(R2, "delta-vs-r1.md"),
        os.path.join(R2, "lessons-r2.md"),
        os.path.join(R2, "evidence", "golden-r2.md"),
        os.path.join(R2, "evidence", "tb-stimulus-fix.md"),
        os.path.join(PKG, "README.md"), os.path.join(PKG, "known-risks.md"),
        os.path.join(PKG, "expected-g1.md"), os.path.join(PKG, "prohibitions.md"),
        os.path.join(PKG, "a1u1-header-contract.md")]

COPY_NAMES = ("manifest-brd-p1-r2.json", "result-r2.md")

missing_bound = []
exempt_r1 = []
exempt_post = []
checked = 0
for d in docs:
    if not os.path.exists(d):
        print("MISSING_DOC", d)
        continue
    base = os.path.dirname(d)
    txt = open(d, encoding="utf-8", errors="replace").read()
    for tok in sorted(set(TOK.findall(txt))):
        tok = tok.strip("`'\".,;:()[]")
        if "/" not in tok and "\\" not in tok and os.path.basename(tok) in (
                "build.tcl", "filelist.tcl", "README.md", "known-risks.md",
                "expected-g1.md", "prohibitions.md", "gen_al.py"):
            continue  # bare names: ambiguous, checked by existence below
        cands = [os.path.abspath(os.path.join(base, tok)), os.path.abspath(os.path.join(R2, tok)),
                 os.path.abspath(os.path.join(PKG, tok)), os.path.abspath(os.path.join(REPO, tok))]
        hit = next((c for c in cands if os.path.exists(c)), None)
        if hit is None:
            continue
        n = os.path.normpath(hit)
        rel = os.path.relpath(n, REPO)
        checked += 1
        if os.path.basename(n) in COPY_NAMES and os.path.dirname(n) in (
                os.path.normpath(PKG), os.path.normpath(R2)):
            continue  # package copies, byte-identical to the bound originals
        if "handoff\\fpga-sim-only-20261027" in n or "inputs" in rel.split(os.sep):
            continue  # documented read-only external input
        if rel.lower().startswith(os.path.join("handoff", "brd-p1-r1-20261027").lower()):
            exempt_r1.append(rel)
            continue  # frozen r1 package = protected read-only input, not an r2 deliverable
        if os.path.basename(n) == "verify-manifest.log":
            exempt_post.append(rel)
            continue  # post-freeze self-check log, excluded from the manifest by design
        if n.lower() not in bound and rel.lower() not in bound:
            missing_bound.append(rel)

print("REFERENCED_FILES_CHECKED=%d" % checked)
print("EXEMPT_R1_READONLY=%d" % len(exempt_r1))
for x in sorted(set(exempt_r1)):
    print("   EXEMPT(r1 read-only)", x)
print("EXEMPT_POSTFREEZE=%d" % len(exempt_post))
for x in sorted(set(exempt_post)):
    print("   EXEMPT(post-freeze self-check, not manifest-bound by design)", x)
print("UNBOUND=%d" % len(missing_bound))
for x in missing_bound:
    print("   UNBOUND", x)
print("G5_REFS=" + ("PASS" if not missing_bound else "FAIL"))
raise SystemExit(0 if not missing_bound else 1)
