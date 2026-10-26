#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""T09.rk-align-algo round1 integrated tester: input-integrity verification.

Read-only over all frozen inputs.  Writes nothing except (a) a test-owned copy
of tools/algo/run_g1.py and tools/algo/run_td_algo.ps1 under
test-reports/evidence/T09.rk-align-algo-r1/scripts/ with ONLY the output root
changed, so that all tester evidence stays inside test-reports/.
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import subprocess

ROOT = pathlib.Path(r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道")
RUN = ROOT / "workflow" / "runs" / "20261017-011744-rk-fpga-align"
EV = RUN / "test-reports" / "evidence" / "T09.rk-align-algo-r1"
(EV / "scripts").mkdir(parents=True, exist_ok=True)


def sha(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


print("== 1. manifest integrity ==")
m = RUN / "algo" / "candidate-manifest.json"
print("manifest_sha256:", sha(m))
data = json.loads(m.read_text(encoding="utf-8"))
ok = miss = bad = 0
for e in data["entries"]:
    p = ROOT / e["path"]
    if not p.exists():
        miss += 1
        print("  MISSING", e["path"])
        continue
    s = sha(p)
    if s != e["sha256"].upper():
        bad += 1
        print("  MISMATCH", e["path"], "got", s, "exp", e["sha256"])
    else:
        ok += 1
print("entries:", len(data["entries"]), "ok:", ok, "missing:", miss, "mismatch:", bad)

print("== 2. manifest selfcheck file ==")
sc = RUN / "algo" / "manifest-selfcheck.json"
if sc.exists():
    d = json.loads(sc.read_text(encoding="utf-8"))
    print({k: d.get(k) for k in ("manifest_sha256", "ok", "entries", "missing", "mismatch")})
else:
    print("manifest-selfcheck.json MISSING")

print("== 3. worktree provenance (read-only recheck) ==")
wt = pathlib.Path(r"C:\Users\czz\.codex\worktrees\bayer-codec-reference\FPGA创新设计赛道")
prov = json.loads((RUN / "algo" / "source-provenance.json").read_text(encoding="utf-8"))
for it in prov["introduced"]:
    wp = wt / it["worktree_path"]
    if wp.exists():
        s = sha(wp)
        print(" ", it["worktree_path"], s, "source_match:", s == it["source_sha256"].upper())
    else:
        print("  wt MISSING", it["worktree_path"])

print("== 4. tools present ==")
for t in (r"D:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe",
          r"D:\intelFPGA\18.1\modelsim_ase\win32aloem\vlog.exe",
          r"D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe",
          r"C:\Program Files\Python311\python.exe"):
    print(" ", t, os.path.exists(t))
print(" python:", subprocess.run([r"C:\Program Files\Python311\python.exe", "--version"],
                                capture_output=True, text=True).stdout.strip())

print("== 5. drive letters in use ==")
out = subprocess.run(["powershell", "-Command",
                      "(Get-PSDrive -PSProvider FileSystem).Name -join ','"],
                     capture_output=True, text=True)
print(" ", out.stdout.strip())

print("== 6. dev G2 smalltop-r1b artifact hashes (claimed in dev-result) ==")
g2 = RUN / "algo" / "g2" / "smalltop-r1b" / "ph1p_algo_smalltop_Runs" / "phy_1"
for name in ("ph1p_algo_smalltop.bit", "final_timing.rpt", "ph1p_algo_smalltop_phy.area"):
    p = g2 / name
    print(" ", name, sha(p) if p.exists() else "MISSING")

print("== 7. freeze-time sanity (files under algo/ newer than manifest) ==")
mt = m.stat().st_mtime
newer = []
for p in (RUN / "algo").rglob("*"):
    if p.is_file() and p.stat().st_mtime > mt + 1:
        newer.append(str(p.relative_to(RUN / "algo")))
print("manifest mtime:", mt, "files newer than manifest:", len(newer))
for x in newer[:20]:
    print("  newer:", x)

print("== 8. test-owned runner copies (output root redirected) ==")
src = ROOT / "tools" / "algo" / "run_g1.py"
txt = src.read_text(encoding="utf-8")
old_root = 'ROOT = Path(__file__).resolve().parents[2]'
new_root = 'ROOT = Path(r"%s")' % str(ROOT)
old_out = 'OUTROOT = RUN / "algo" / "g1" / "msim"'
new_out = 'OUTROOT = RUN / "test-reports" / "evidence" / "T09.rk-align-algo-r1" / "g1"'
assert txt.count(old_root) == 1 and txt.count(old_out) == 1
txt = txt.replace(old_root, new_root).replace(old_out, new_out)
dst = EV / "scripts" / "run_g1.py"
dst.write_text(txt, encoding="utf-8")
print(" wrote", dst)

ps = ROOT / "tools" / "algo" / "run_td_algo.ps1"
pt = ps.read_text(encoding="utf-8")
old_o = '$outDirF = Join-Path $root ("workflow\\runs\\20261017-011744-rk-fpga-align\\algo\\g2\\" + $Name)'
new_o = '$outDirF = Join-Path $root ("workflow\\runs\\20261017-011744-rk-fpga-align\\test-reports\\evidence\\T09.rk-align-algo-r1\\td\\" + $Name)'
assert pt.count(old_o) == 1, f"anchor count {pt.count(old_o)}"
pt = pt.replace(old_o, new_o)
dst2 = EV / "scripts" / "run_td_algo.ps1"
dst2.write_text(pt, encoding="utf-8")
print(" wrote", dst2)
print("copy_sha run_g1.py:", sha(dst))
print("copy_sha run_td_algo.ps1:", sha(dst2))
print("DONE")
